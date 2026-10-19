import Foundation
import CoreVideo
import Darwin

struct AndroidDevice: Equatable {
    let serial: String
    let status: String
    let model: String
    var authorized: Bool { status == "device" }
}

enum ADB {
    static let executable = URL(fileURLWithPath: "/opt/homebrew/bin/adb")

    static func command(_ arguments: [String]) throws -> String {
        let process = Process(), output = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw WebcamError(message: "ADB failed. \(text.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return text
    }

    static func devices() throws -> [AndroidDevice] {
        try command(["devices", "-l"]).split(separator: "\n").compactMap { line in
            let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard fields.count >= 2, fields.contains(where: { $0.hasPrefix("usb:") }) else { return nil }
            let model = fields.first(where: { $0.hasPrefix("model:") }).map { String($0.dropFirst(6)).replacingOccurrences(of: "_", with: " ") }
            return AndroidDevice(serial: fields[0], status: fields[1], model: model ?? fields[0])
        }
    }

    static var serverURL: URL? {
        Bundle.main.url(forResource: "scrcpy-server-5.0", withExtension: "jar")
    }
}

final class CaptureController {
    private let worker = DispatchQueue(label: "android-webcam.capture")
    private let lock = NSLock()
    private var stopping = false
    private var socket: Int32 = -1
    private var frame: CVPixelBuffer?
    private var decoderError: Error?
    private(set) var running = false
    var onStatus: (String, Bool) -> Void = { _, _ in }

    var latestFrame: CVPixelBuffer? {
        lock.lock(); defer { lock.unlock() }
        return frame
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
        stopping = false; frame = nil; decoderError = nil
        lock.unlock()
        running = true
        report("Starting \(device.model)...", active: true)
        worker.async { [weak self] in
            guard let self else { return }
            var result = "Webcam stopped"
            do { try self.capture(device: device, mode: mode) }
            catch {
                self.lock.lock()
                let failure = self.decoderError
                self.lock.unlock()
                if let failure { result = failure.localizedDescription }
                else if !self.shouldStop { result = error.localizedDescription }
            }
            DispatchQueue.main.async {
                self.running = false
                self.onStatus(result, false)
            }
        }
    }

    func stop() {
        lock.lock()
        stopping = true
        if socket >= 0 { Darwin.shutdown(socket, SHUT_RDWR) }
        lock.unlock()
    }

    private func capture(device: AndroidDevice, mode: CaptureMode) throws {
        guard device.authorized else { throw WebcamError(message: "Approve USB debugging on your phone.") }
        guard let serverURL = ADB.serverURL else { throw WebcamError(message: "The bundled scrcpy-server 5.0 is missing.") }
        let sdk = Int(try ADB.command(["-s", device.serial, "shell", "getprop", "ro.build.version.sdk"])
            .trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        guard sdk >= 31 else { throw WebcamError(message: "Android camera capture needs Android 12 or later.") }
        let id = String(format: "%08x", UInt32.random(in: 1...0x7fff_ffff))
        let remote = "/data/local/tmp/android-webcam-\(id).jar"
        var port: Int?
        var fd: Int32 = -1
        var server: Process?
        var output: VirtualCamera?
        var decoder: HEVCDecoder?
        defer {
            decoder?.finish()
            output?.stop()
            lock.lock(); socket = -1; frame = nil; lock.unlock()
            if fd >= 0 { Darwin.close(fd) }
            if let server, server.isRunning { server.terminate(); server.waitUntilExit() }
            if let port {
                do { _ = try ADB.command(["-s", device.serial, "forward", "--remove", "tcp:\(port)"]) }
                catch { fputs("Forward cleanup failed. \(error.localizedDescription)\n", stderr) }
            }
            do { _ = try ADB.command(["-s", device.serial, "shell", "rm", "-f", remote]) }
            catch { fputs("Phone cleanup failed. \(error.localizedDescription)\n", stderr) }
        }
        _ = try ADB.command(["-s", device.serial, "push", serverURL.path, remote])
        let forwarding = try ADB.command(["-s", device.serial, "forward", "tcp:0", "localabstract:scrcpy_\(id)"])
        guard let allocated = Int(forwarding.trimmingCharacters(in: .whitespacesAndNewlines)), (1...65535).contains(allocated) else {
            throw WebcamError(message: "ADB did not return a forwarding port.")
        }
        port = allocated
        if shouldStop { return }
        let shell = Process()
        shell.executableURL = ADB.executable
        shell.arguments = ["-s", device.serial, "shell", "CLASSPATH=\(remote)", "app_process", "/",
            "com.genymobile.scrcpy.Server", "5.0", "scid=\(id)", "tunnel_forward=true",
            "video_source=camera", "camera_id=0", "camera_size=\(mode.width)x\(mode.height)",
            "camera_fps=\(mode.fps)", "camera_high_speed=\(mode.fps > 60)",
            "video_codec=h265", "video_bit_rate=\(mode.bitrate)", "audio=false", "control=false",
            "send_device_meta=false", "send_dummy_byte=true", "downsize_on_error=false", "cleanup=true"]
        shell.standardOutput = FileHandle.standardError
        shell.standardError = FileHandle.standardError
        try shell.run()
        server = shell
        fd = try connect(port: allocated)
        lock.lock(); socket = fd; lock.unlock()
        if shouldStop { return }
        let codec = try readExactly(4, from: fd)
        guard codec == Data("h265".utf8) else { throw WebcamError(message: "The phone could not start HEVC capture. Try a lower capture mode.") }
        let publisher = try VirtualCamera(fps: mode.fps)
        output = publisher
        var announced = false
        let videoDecoder = HEVCDecoder(onFrame: { [weak self] pixel in
            guard let self, !self.shouldStop else { return }
            do {
                guard CVPixelBufferGetWidth(pixel) == mode.width, CVPixelBufferGetHeight(pixel) == mode.height else {
                    throw WebcamError(message: "The decoded camera dimensions differ from the selected mode.")
                }
                try publisher.send(pixel)
                self.lock.lock()
                self.frame = pixel
                let firstFrame = !announced
                announced = true
                self.lock.unlock()
                if firstFrame {
                    self.report("\(mode.title) / OBS Virtual Camera", active: true)
                }
            } catch { self.failDecoder(error) }
        }, onError: { [weak self] in self?.failDecoder($0) })
        decoder = videoDecoder
        while !shouldStop {
            switch try ScrcpyHeader(readExactly(12, from: fd)) {
            case let .session(width, height):
                guard width == mode.width, height == mode.height else {
                    throw WebcamError(message: "Requested \(mode.width)x\(mode.height), but the phone offered \(width)x\(height).")
                }
            case let .packet(size, pts, _):
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
        stop()
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
                timeout.tv_sec = 3
                timeout.tv_usec = 0
                setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
                return fd
            }
            Darwin.close(fd)
            usleep(50_000)
        }
        throw WebcamError(message: "The scrcpy camera server did not accept its video connection.")
    }

    private func readExactly(_ count: Int, from fd: Int32) throws -> Data {
        var data = Data(count: count)
        var offset = 0
        try data.withUnsafeMutableBytes { bytes in
            while offset < count {
                let received = Darwin.recv(fd, bytes.baseAddress!.advanced(by: offset), count - offset, 0)
                if received <= 0 {
                    if received < 0, errno == EINTR { continue }
                    throw WebcamError(message: "The phone's video stream ended or timed out.")
                }
                offset += received
            }
        }
        return data
    }
}
