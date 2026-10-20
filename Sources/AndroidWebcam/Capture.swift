import Foundation
import CoreVideo
import Darwin

struct AndroidDevice: Equatable {
    let serial: String
    let status: String
    let model: String
    var authorized: Bool { status == "device" }
}

/// A failure of the link to the phone: adb, the port forward or the video socket.
/// Capture reconnects after these. Every other error ends capture.
struct TransportError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum ScrcpyServer {
    /// The server refuses a client whose version argument differs from its own.
    static let version = "5.0.1"
}

enum ADB {
    private static let lookupLock = NSLock()
    private static var found: URL?

    /// The first executable adb among the usual install locations, cached once found.
    static func executable() throws -> URL {
        lookupLock.lock(); defer { lookupLock.unlock() }
        if let found { return found }
        let environment = ProcessInfo.processInfo.environment
        let candidates = [
            environment["ADB"],
            environment["ANDROID_HOME"].map { "\($0)/platform-tools/adb" },
            environment["ANDROID_SDK_ROOT"].map { "\($0)/platform-tools/adb" },
            "\(NSHomeDirectory())/Library/Android/sdk/platform-tools/adb",
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb"
        ]
        guard let path = candidates.compactMap({ $0 }).first(where: { !$0.isEmpty && FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw WebcamError(message: "Install Android platform tools, for example with brew install android-platform-tools.")
        }
        found = URL(fileURLWithPath: path)
        return found!
    }

    static func command(_ arguments: [String], timeout: TimeInterval = 10) throws -> String {
        try command(arguments, timeout: timeout, onLaunch: { _ in })
    }

    /// Like command(_:timeout:), and hands the running process to onLaunch so the caller can interrupt it.
    fileprivate static func command(_ arguments: [String], timeout: TimeInterval, onLaunch: (Process?) -> Void) throws -> String {
        guard let result = try runTool(executable(), arguments, timeout: timeout, onLaunch: onLaunch) else {
            throw TransportError(message: "ADB didn't answer within \(Int(timeout)) seconds.")
        }
        guard result.status == 0 else {
            throw TransportError(message: "ADB failed. \(result.text.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return result.text
    }

    static func devices() throws -> [AndroidDevice] {
        try devices(onLaunch: { _ in })
    }

    fileprivate static func devices(onLaunch: (Process?) -> Void) throws -> [AndroidDevice] {
        try command(["devices", "-l"], timeout: 10, onLaunch: onLaunch).split(separator: "\n").compactMap { line in
            let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard fields.count >= 2, fields.contains(where: { $0.hasPrefix("usb:") }) else { return nil }
            let model = fields.first(where: { $0.hasPrefix("model:") }).map { String($0.dropFirst(6)).replacingOccurrences(of: "_", with: " ") }
            return AndroidDevice(serial: fields[0], status: fields[1], model: model ?? fields[0])
        }
    }

    static var serverURL: URL? {
        Bundle.main.url(forResource: "scrcpy-server", withExtension: "jar")
    }
}

/// Runs a tool and returns its exit status and combined output, or nil if it outlived the timeout and was ended.
/// onLaunch gets the process once it runs and nil once it has exited.
private func runTool(_ tool: URL, _ arguments: [String], timeout: TimeInterval,
                     onLaunch: (Process?) -> Void) throws -> (status: Int32, text: String)? {
    let process = Process(), output = Pipe(), exited = DispatchSemaphore(value: 0)
    process.executableURL = tool
    process.arguments = arguments
    process.standardOutput = output
    process.standardError = output
    process.terminationHandler = { _ in exited.signal() }
    // `adb devices` can start the adb server, which inherits this pipe and keeps it open.
    // So read what's there while waiting for the process to exit, and never wait for end of file.
    let reader = output.fileHandleForReading.fileDescriptor
    _ = fcntl(reader, F_SETFL, fcntl(reader, F_GETFL) | O_NONBLOCK)
    try process.run()
    onLaunch(process)
    defer { onLaunch(nil) }
    var data = Data()
    let deadline = Date().addingTimeInterval(timeout)
    var finished = true
    while exited.wait(timeout: .now() + 0.05) == .timedOut {
        drain(reader, into: &data)
        if Date() >= deadline {
            end(process, exited: exited)
            finished = false
            break
        }
    }
    drain(reader, into: &data)
    guard finished else { return nil }
    return (process.terminationStatus, String(decoding: data, as: UTF8.self))
}

private func drain(_ fd: Int32, into data: inout Data) {
    var buffer = [UInt8](repeating: 0, count: 16_384)
    while true {
        let count = Darwin.read(fd, &buffer, buffer.count)
        if count <= 0 { return }
        data.append(contentsOf: buffer[0..<count])
    }
}

/// Sends SIGTERM, then SIGKILL if the process is still running a second later, and waits for it to exit.
private func end(_ process: Process, exited: DispatchSemaphore) {
    guard process.isRunning else { return }
    process.terminate()
    if exited.wait(timeout: .now() + 1) == .timedOut {
        kill(process.processIdentifier, SIGKILL)
        exited.wait()
    }
}

/// What a live session left on the Mac and the phone, so the next launch can clean up after a crash.
private struct SessionRecord: Codable {
    let serial: String
    let port: Int
    let scid: String
    let remote: String
    let pid: Int32
    /// The app process that owns the session; a live owner means the session isn't stale.
    let owner: Int32
}

final class CaptureController {
    private static let remotePrefix = "/data/local/tmp/android-webcam-"
    private static let sessionFile = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.harsha.android-webcam")
        .appendingPathComponent("session.json")

    private let worker = DispatchQueue(label: "android-webcam.capture")
    private let lock = NSLock()
    private var stopping = false
    private var socket: Int32 = -1
    private var adbProcess: Process?
    private var decoderError: Error?
    /// Set once a session has sent a frame. Before that, a failure is a setup problem, not a loose cable.
    private var streamed = false
    private var stopCompletions: [() -> Void] = []
    private(set) var running = false
    var onStatus: (String, Bool) -> Void = { _, _ in }
    var onFrame: ((CVPixelBuffer) -> Void)?

    init() {
        worker.async { Self.removeStaleSession() }
    }

    private var shouldStop: Bool {
        lock.lock(); defer { lock.unlock() }
        return stopping
    }

    private func report(_ text: String, active: Bool) {
        DispatchQueue.main.async { [weak self] in self?.onStatus(text, active) }
    }

    func start(device: AndroidDevice, mode: CaptureMode) {
        guard !running else { return }
        lock.lock()
        stopping = false; decoderError = nil; streamed = false
        lock.unlock()
        running = true
        report("Starting \(device.model)...", active: true)
        worker.async { [weak self] in
            guard let self else { return }
            let result = self.run(device: device, mode: mode)
            DispatchQueue.main.async {
                self.running = false
                self.onStatus(result, false)
                let completions = self.stopCompletions
                self.stopCompletions = []
                completions.forEach { $0() }
            }
        }
    }

    /// Stops capture. completion runs on main once the worker has cleaned up, or at once if nothing runs.
    func stop(completion: (() -> Void)? = nil) {
        guard running else { completion?(); return }
        if let completion { stopCompletions.append(completion) }
        cancel()
    }

    private func cancel() {
        lock.lock()
        stopping = true
        if socket >= 0 { Darwin.shutdown(socket, SHUT_RDWR) }
        let process = adbProcess
        lock.unlock()
        if let process { interrupt(process) }
    }

    private func interrupt(_ process: Process) {
        process.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
    }

    /// Records the session's adb process so cancel() can interrupt it.
    private func track(_ process: Process?) {
        lock.lock()
        adbProcess = process
        let stopNow = stopping
        lock.unlock()
        // cancel() may have run between the launch and this call.
        if stopNow, let process { interrupt(process) }
    }

    private func adb(_ arguments: [String], timeout: TimeInterval = 10) throws -> String {
        try ADB.command(arguments, timeout: timeout, onLaunch: track)
    }

    /// Runs phone sessions into one virtual camera until the user stops or a session fails
    /// for a reason reconnecting can't fix. Returns the final status.
    private func run(device: AndroidDevice, mode: CaptureMode) -> String {
        do {
            if shouldStop { return "Webcam stopped" }
            guard device.authorized else { throw WebcamError(message: "Approve USB debugging on your phone.") }
            guard let serverURL = ADB.serverURL else {
                throw WebcamError(message: "The bundled scrcpy-server \(ScrcpyServer.version) is missing.")
            }
            let camera = try VirtualCamera(fps: mode.fps)
            defer { camera.stop() }
            while true {
                do {
                    try session(device: device, mode: mode, serverURL: serverURL, camera: camera)
                    break
                } catch let error as TransportError where !shouldStop && hasStreamed {
                    fputs("Phone session ended. \(error.message)\n", stderr)
                    report("Reconnecting to \(device.model). \(error.message)", active: true)
                    guard waitForDevice(device.serial) else { break }
                }
            }
            return "Webcam stopped"
        } catch {
            lock.lock(); let failure = decoderError; lock.unlock()
            if let failure { return failure.localizedDescription }
            return shouldStop ? "Webcam stopped" : error.localizedDescription
        }
    }

    private var hasStreamed: Bool {
        lock.lock(); defer { lock.unlock() }
        return streamed
    }

    /// Polls adb every second until the phone is back and authorized. Returns false if the user stops first.
    private func waitForDevice(_ serial: String) -> Bool {
        while true {
            for _ in 0..<10 {
                if shouldStop { return false }
                usleep(100_000)
            }
            // The adb server may be busy while the phone reattaches, so a failed poll just waits for the next.
            if let devices = try? ADB.devices(onLaunch: track),
               devices.contains(where: { $0.serial == serial && $0.authorized }) { return true }
        }
    }

    private func session(device: AndroidDevice, mode: CaptureMode, serverURL: URL, camera: VirtualCamera) throws {
        let sdk = Int(try adb(["-s", device.serial, "shell", "getprop", "ro.build.version.sdk"])
            .trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        guard sdk >= 31 else { throw WebcamError(message: "Android camera capture needs Android 12 or later.") }
        let scid = String(format: "%08x", UInt32.random(in: 1...0x7fff_ffff))
        let remote = Self.remotePrefix + "\(scid).jar"
        var port: Int?
        var fd: Int32 = -1
        var server: Process?
        let serverExited = DispatchSemaphore(value: 0)
        var decoder: HEVCDecoder?
        defer {
            decoder?.finish()
            lock.lock(); socket = -1; lock.unlock()
            if fd >= 0 { Darwin.close(fd) }
            if let server { end(server, exited: serverExited) }
            if let port {
                do { _ = try ADB.command(["-s", device.serial, "forward", "--remove", "tcp:\(port)"], timeout: 5) }
                catch { fputs("Forward cleanup failed. \(error.localizedDescription)\n", stderr) }
            }
            do { _ = try ADB.command(["-s", device.serial, "shell", "rm", "-f", remote], timeout: 5) }
            catch { fputs("Phone cleanup failed. \(error.localizedDescription)\n", stderr) }
            try? FileManager.default.removeItem(at: Self.sessionFile)
        }
        _ = try adb(["-s", device.serial, "push", serverURL.path, remote], timeout: 30)
        let forwarding = try adb(["-s", device.serial, "forward", "tcp:0", "localabstract:scrcpy_\(scid)"])
        guard let allocated = Int(forwarding.trimmingCharacters(in: .whitespacesAndNewlines)), (1...65535).contains(allocated) else {
            throw TransportError(message: "ADB did not return a forwarding port.")
        }
        port = allocated
        if shouldStop { return }
        let shell = Process()
        shell.executableURL = try ADB.executable()
        shell.arguments = ["-s", device.serial, "shell", "CLASSPATH=\(remote)", "app_process", "/",
            "com.genymobile.scrcpy.Server", ScrcpyServer.version, "scid=\(scid)", "tunnel_forward=true",
            "video_source=camera", "camera_id=0", "camera_size=\(mode.width)x\(mode.height)",
            "camera_fps=\(mode.fps)", "camera_high_speed=\(mode.fps > 60)",
            "video_codec=h265", "video_bit_rate=\(mode.bitrate)", "audio=false", "control=false",
            "send_device_meta=false", "send_dummy_byte=true", "downsize_on_error=false", "cleanup=true"]
        shell.standardOutput = FileHandle.standardError
        shell.standardError = FileHandle.standardError
        shell.terminationHandler = { _ in serverExited.signal() }
        try shell.run()
        server = shell
        save(SessionRecord(serial: device.serial, port: allocated, scid: scid, remote: remote,
                           pid: shell.processIdentifier, owner: getpid()))
        fd = try connect(port: allocated)
        lock.lock(); socket = fd; lock.unlock()
        if shouldStop { return }
        let codec = try readExactly(4, from: fd)
        guard codec == Data("h265".utf8) else { throw WebcamError(message: "The phone could not start HEVC capture. Try a lower capture mode.") }
        var announced = false
        let videoDecoder = HEVCDecoder(onFrame: { [weak self] pixel in
            guard let self, !self.shouldStop else { return }
            do {
                guard CVPixelBufferGetWidth(pixel) == mode.width, CVPixelBufferGetHeight(pixel) == mode.height else {
                    throw WebcamError(message: "The decoded camera dimensions differ from the selected mode.")
                }
                try camera.send(pixel)
                self.onFrame?(pixel)
                self.lock.lock()
                let firstFrame = !announced
                announced = true
                self.streamed = true
                self.lock.unlock()
                if firstFrame {
                    self.report("\(mode.title) / OBS Virtual Camera", active: true)
                }
            } catch { self.failDecoder(error) }
        }, onError: { [weak self] in self?.failDecoder($0) })
        decoder = videoDecoder
        var streaming = false
        while !shouldStop {
            switch try ScrcpyHeader(readExactly(12, from: fd)) {
            case let .session(width, height):
                guard width == mode.width, height == mode.height else {
                    throw WebcamError(message: "Requested \(mode.width)x\(mode.height), but the phone offered \(width)x\(height).")
                }
            case let .packet(size, pts, _):
                // The camera can take a while to open; once media flows, a 3 second gap means the link is gone.
                if !streaming { streaming = true; setReadTimeout(fd, seconds: 3) }
                try videoDecoder.decode(readExactly(size, from: fd), pts: pts)
            }
        }
        lock.lock(); let failure = decoderError; lock.unlock()
        if let failure { throw failure }
    }

    private func failDecoder(_ error: Error) {
        lock.lock()
        if decoderError == nil { decoderError = error }
        lock.unlock()
        cancel()
    }

    private func save(_ record: SessionRecord) {
        do {
            try FileManager.default.createDirectory(at: Self.sessionFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(record).write(to: Self.sessionFile, options: .atomic)
        } catch { fputs("Could not record the session. \(error.localizedDescription)\n", stderr) }
    }

    /// Cleans up after a session the app didn't get to end, touching only what that session recorded.
    private static func removeStaleSession() {
        guard let data = try? Data(contentsOf: sessionFile) else { return }
        let record = try? JSONDecoder().decode(SessionRecord.self, from: data)
        // Another running copy of the app owns this session; leave it alone.
        if let record, record.owner != getpid(), kill(record.owner, 0) == 0 || errno == EPERM { return }
        defer { try? FileManager.default.removeItem(at: sessionFile) }
        guard let record else {
            fputs("Ignoring an unreadable \(sessionFile.path).\n", stderr)
            return
        }
        do {
            let forward = "\(record.serial) tcp:\(record.port) localabstract:scrcpy_\(record.scid)"
            let forwards = try ADB.command(["forward", "--list"], timeout: 5)
                .split(separator: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if forwards.contains(forward) {
                _ = try ADB.command(["-s", record.serial, "forward", "--remove", "tcp:\(record.port)"], timeout: 5)
            }
        } catch { fputs("Stale forward cleanup failed. \(error.localizedDescription)\n", stderr) }
        do {
            let ps = try runTool(URL(fileURLWithPath: "/bin/ps"), ["-o", "args=", "-p", "\(record.pid)"], timeout: 5, onLaunch: { _ in })
            if let ps, ps.status == 0, ps.text.contains("scid=\(record.scid)") { kill(record.pid, SIGTERM) }
        } catch { fputs("Stale process cleanup failed. \(error.localizedDescription)\n", stderr) }
        guard record.remote.hasPrefix(remotePrefix) else { return }
        do { _ = try ADB.command(["-s", record.serial, "shell", "rm", "-f", record.remote], timeout: 5) }
        catch { fputs("Stale phone cleanup failed. \(error.localizedDescription)\n", stderr) }
    }

    private func setReadTimeout(_ fd: Int32, seconds: Int) {
        var timeout = timeval(tv_sec: seconds, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    }

    private func connect(port: Int) throws -> Int32 {
        // ADB may accept TCP before the phone has opened its abstract socket.
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if shouldStop { throw WebcamError(message: "Capture cancelled.") }
            let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
            guard fd >= 0 else { throw WebcamError(message: "Could not create the ADB video socket.") }
            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = in_port_t(port).bigEndian
            address.sin_addr.s_addr = inet_addr("127.0.0.1")
            var timeout = timeval(tv_sec: 0, tv_usec: 200_000)
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            let status = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            var dummy: UInt8 = 1
            if status == 0, Darwin.recv(fd, &dummy, 1, 0) == 1, dummy == 0 {
                // Until the first media packet the camera may still be opening, so allow 10 seconds.
                setReadTimeout(fd, seconds: 10)
                return fd
            }
            Darwin.close(fd)
            usleep(50_000)
        }
        throw TransportError(message: "The scrcpy camera server did not accept its video connection.")
    }

    private func readExactly(_ count: Int, from fd: Int32) throws -> Data {
        var data = Data(count: count)
        var offset = 0
        try data.withUnsafeMutableBytes { bytes in
            while offset < count {
                let received = Darwin.recv(fd, bytes.baseAddress!.advanced(by: offset), count - offset, 0)
                if received <= 0 {
                    if received < 0, errno == EINTR { continue }
                    throw TransportError(message: "The phone's video stream ended or timed out.")
                }
                offset += received
            }
        }
        return data
    }
}
