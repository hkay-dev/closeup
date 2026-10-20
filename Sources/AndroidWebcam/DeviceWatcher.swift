import Foundation

/// Follows `adb track-devices -l`, which sends the phone list each time it changes, so nothing polls.
/// The stream starts again when it ends, for example when the adb server restarts or adb gets installed.
final class DeviceWatcher {
    /// Called on main with each new list, or with the error that kept the stream from running.
    var onChange: (Result<[AndroidDevice], Error>) -> Void = { _ in }
    private let lock = NSLock()
    private var process: Process?
    private var stopped = false

    /// A plain thread, since it spends its life blocked in poll().
    func start() {
        let thread = Thread { [weak self] in self?.follow() }
        thread.name = "android-webcam.devices"
        thread.qualityOfService = .utility
        thread.start()
    }

    /// Ends this app's own adb client. The adb server keeps running.
    func stop() {
        lock.lock()
        stopped = true
        let running = process
        lock.unlock()
        running?.terminate()
    }

    private var isStopped: Bool {
        lock.lock(); defer { lock.unlock() }
        return stopped
    }

    private func follow() {
        var delay: TimeInterval = 1
        while !isStopped {
            let began = Date()
            do { try stream() } catch { report(.failure(error)) }
            // A stream that ran a while starts again at once; one that keeps failing backs off to 10 s.
            delay = Date().timeIntervalSince(began) > 30 ? 1 : min(delay * 2, 10)
            if !isStopped { Thread.sleep(forTimeInterval: delay) }
        }
    }

    private func stream() throws {
        let process = Process(), output = Pipe(), errors = Pipe()
        process.executableURL = try ADB.executable()
        process.arguments = ["track-devices", "-l"]
        process.standardOutput = output
        process.standardError = errors
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        lock.lock()
        guard !stopped else { lock.unlock(); return }
        do { try process.run() } catch { lock.unlock(); throw error }
        self.process = process
        lock.unlock()
        defer {
            lock.lock(); self.process = nil; lock.unlock()
            // An adb server that this client started inherits the pipes, so they never reach end of file. Close our ends.
            try? output.fileHandleForReading.close()
            try? errors.fileHandleForReading.close()
        }

        let reader = output.fileHandleForReading.fileDescriptor
        let errorReader = errors.fileHandleForReading.fileDescriptor
        for fd in [reader, errorReader] { _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK) }
        var pending = Data(), errorText = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while exited.wait(timeout: .now()) == .timedOut {
            var ready = pollfd(fd: reader, events: Int16(POLLIN), revents: 0)
            guard poll(&ready, 1, 1000) > 0 else { continue }
            let count = read(reader, &buffer, buffer.count)
            if count > 0 {
                pending.append(contentsOf: buffer[0..<count])
                parse(&pending)
            }
            readAvailable(errorReader, into: &errorText, buffer: &buffer)
            if count == 0 { exited.wait(); break }    // end of file: the client is exiting
        }
        readAvailable(reader, into: &pending, buffer: &buffer)
        parse(&pending)
        readAvailable(errorReader, into: &errorText, buffer: &buffer)
        if process.terminationStatus != 0, !isStopped {
            let detail = String(decoding: errorText, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw TransportError(message: "adb isn't working, so the app can't see the phone. It keeps trying.",
                                 detail: "adb track-devices exited \(process.terminationStatus): \(detail)")
        }
    }

    /// Each message is four hex digits of length, then that many bytes of `adb devices -l` lines.
    private func parse(_ pending: inout Data) {
        while pending.count >= 4 {
            guard let length = Int(String(decoding: pending.prefix(4), as: UTF8.self), radix: 16) else {
                pending.removeAll()
                return
            }
            guard pending.count >= 4 + length else { return }
            let text = String(decoding: pending.dropFirst(4).prefix(length), as: UTF8.self)
            pending.removeFirst(4 + length)
            report(.success(ADB.parseDevices(text)))
        }
    }

    private func readAvailable(_ fd: Int32, into data: inout Data, buffer: inout [UInt8]) {
        while true {
            let count = read(fd, &buffer, buffer.count)
            if count <= 0 { return }
            data.append(contentsOf: buffer[0..<count])
        }
    }

    private func report(_ result: Result<[AndroidDevice], Error>) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isStopped else { return }
            self.onChange(result)
        }
    }
}
