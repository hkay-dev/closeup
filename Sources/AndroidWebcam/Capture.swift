import Foundation
import CoreVideo
import Darwin

struct AndroidDevice: Equatable {
    let serial: String
    let status: String
    let model: String
    /// On wireless debugging: an mDNS name or ip:port serial instead of a USB one.
    var wireless = false
    /// The phone's own serial where the adb serial carries it (a USB serial, or the middle of an mDNS name).
    var hardwareSerial: String?
    /// product, model and device from adb, for matching an ip:port entry to its USB twin, which has no serial to compare.
    var fingerprint = ""
    var authorized: Bool { status == "device" }
}

/// A failure of the link to the phone: adb, the port forward or the video socket.
/// Capture reconnects after these. Every other error ends capture.
struct TransportError: LocalizedError {
    let message: String
    var detail: String? = nil
    var errorDescription: String? { message }
}

enum ScrcpyServer {
    /// The server refuses a client whose version argument differs from its own.
    static let version = "5.0.1-webcam.1"
}

struct CameraLens: Equatable, Codable {
    let id: String          // camera_id
    let facing: String      // "back" | "front" | "external"
    let label: String       // "Back · Main", "Back · Ultra Wide", "Back · 3x", "Front", "External"
}

struct PhoneStats: Equatable {
    let temperatureC: Double   // battery temperature from `dumpsys battery` (tenths of a degree)
    let batteryPercent: Int
    let charging: Bool
    let thermalStatus: Int?    // `dumpsys thermalservice` "Thermal Status: N" (0 none ... 6 shutdown), nil if unreadable
    var isHot: Bool { temperatureC >= 40 || (thermalStatus ?? 0) >= 2 }
}

enum WhiteBalance: String, CaseIterable, Codable { case auto, daylight, cloudy, incandescent, fluorescent }
enum FocusMode: String, CaseIterable, Codable { case continuous, locked }
enum ProcessingLevel: String, CaseIterable, Codable { case off, fast, highQuality }

struct PhoneImageSettings: Codable, Equatable {
    var exposureEV: Double = 0                 // -2...2 in 1/3 steps
    var whiteBalance: WhiteBalance = .auto
    var focus: FocusMode = .continuous
    var noiseReduction: ProcessingLevel = .highQuality
    var sharpness: ProcessingLevel = .highQuality   // edge mode
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
            throw TransportError(message: "The phone stopped answering. Unplug it, plug it back in and start again.",
                                 detail: "adb \(arguments.joined(separator: " ")) gave no answer in \(Int(timeout)) seconds.")
        }
        guard result.status == 0 else {
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            throw TransportError(message: explain(text), detail: "adb \(arguments.joined(separator: " ")) failed: \(text)")
        }
        return result.text
    }

    /// adb's own words, said for someone who doesn't know adb.
    static func explain(_ text: String) -> String {
        let text = text.lowercased()
        if text.contains("unauthorized") {
            return "The phone hasn't allowed USB debugging for this Mac. Unlock it and tap Allow."
        }
        if ["not found", "no devices", "offline", "no such device", "device still connecting", "closed"].contains(where: text.contains) {
            return "The phone disconnected. Check the cable and start again."
        }
        if text.contains("daemon") || text.contains("cannot connect") {
            return "adb's background service isn't responding. Wait a moment and start again."
        }
        if text.contains("no space left") || text.contains("read-only file system") {
            return "The phone has no room for the webcam's helper. Free some storage on the phone and start again."
        }
        return "The phone didn't answer the way the app expected. Unplug it, plug it back in and start again."
    }

    static func devices() throws -> [AndroidDevice] {
        try devices(onLaunch: { _ in })
    }

    fileprivate static func devices(onLaunch: (Process?) -> Void) throws -> [AndroidDevice] {
        parseDevices(try command(["devices", "-l"], timeout: 10, onLaunch: onLaunch))
    }

    /// Phones from `adb devices -l` or `adb track-devices -l` lines. Emulators are skipped. Wireless entries only
    /// count when the wireless switch is on; then a phone listed over both USB and wireless appears once, as the
    /// wireless entry.
    static func parseDevices(_ text: String, wireless: Bool = Wireless.enabled) -> [AndroidDevice] {
        let devices = text.split(separator: "\n").compactMap { parseLine($0, wireless: wireless) }
        return wireless ? onePerPhone(devices) : devices
    }

    private static let mdnsSuffix = "._adb-tls-connect._tcp"

    private static func parseLine(_ line: Substring, wireless allowWireless: Bool) -> AndroidDevice? {
        let serial: String
        let fields: [String]
        // An mDNS serial has a space in it ("adb-R5CY11B8DHD-KmFSaA (2)._adb-tls-connect._tcp"), so it ends at the
        // service type and the status follows.
        if let service = line.range(of: mdnsSuffix) {
            serial = line[..<service.upperBound].trimmingCharacters(in: .whitespaces)
            fields = line[service.upperBound...].split(whereSeparator: \.isWhitespace).map(String.init)
        } else {
            let all = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard let first = all.first else { return nil }
            serial = first
            fields = Array(all.dropFirst())
        }
        guard let status = fields.first else { return nil }
        let isUSB = fields.contains { $0.hasPrefix("usb:") }
        let isWireless = !isUSB && (serial.hasSuffix(mdnsSuffix) || isHostAndPort(serial))
        guard isUSB || (allowWireless && isWireless) else { return nil }
        func value(_ key: String) -> String? {
            fields.first { $0.hasPrefix(key) }.map { String($0.dropFirst(key.count)) }
        }
        var device = AndroidDevice(serial: serial, status: status,
                                   model: value("model:").map { $0.replacingOccurrences(of: "_", with: " ") } ?? serial)
        device.wireless = isWireless
        device.hardwareSerial = isWireless ? mdnsHardwareSerial(serial) : serial
        let identity = ["product:", "model:", "device:"].map { value($0) ?? "" }
        device.fingerprint = identity.allSatisfy(\.isEmpty) ? "" : identity.joined(separator: "|")
        return device
    }

    /// `192.168.1.20:37215`, what `adb connect` makes the serial.
    private static func isHostAndPort(_ serial: String) -> Bool {
        guard let colon = serial.lastIndex(of: ":"), colon != serial.startIndex else { return false }
        return Int(serial[serial.index(after: colon)...]) != nil
    }

    /// "adb-R5CY11B8DHD-KmFSaA (2)._adb-tls-connect._tcp" is "adb-<serial>-<random>", with " (2)" added when the
    /// name is taken. An ip:port serial has no serial in it.
    private static func mdnsHardwareSerial(_ serial: String) -> String? {
        guard serial.hasPrefix("adb-"), let end = serial.range(of: mdnsSuffix)?.lowerBound else { return nil }
        var name = String(serial[serial.index(serial.startIndex, offsetBy: 4)..<end])
        if let taken = name.range(of: " (", options: .backwards), name.hasSuffix(")") { name = String(name[..<taken.lowerBound]) }
        guard let dash = name.lastIndex(of: "-") else { return nil }
        let hardware = String(name[..<dash])
        return hardware.isEmpty ? nil : hardware
    }

    /// Keeps one entry for each phone, the first wireless one when it has both. Entries match by phone serial;
    /// an ip:port entry has none, so it matches the one phone with the same product, model and device, and stays
    /// separate when that's ambiguous.
    private static func onePerPhone(_ devices: [AndroidDevice]) -> [AndroidDevice] {
        var groups: [[AndroidDevice]] = []
        for device in devices where device.hardwareSerial != nil {
            if let index = groups.firstIndex(where: { $0[0].hardwareSerial == device.hardwareSerial }) { groups[index].append(device) }
            else { groups.append([device]) }
        }
        for device in devices where device.hardwareSerial == nil {
            let matches = groups.indices.filter { !device.fingerprint.isEmpty && groups[$0][0].fingerprint == device.fingerprint }
            if matches.count == 1 { groups[matches[0]].append(device) } else { groups.append([device]) }
        }
        let chosen = Set(groups.map { group in (group.first(where: \.wireless) ?? group[0]).serial })
        return devices.filter { chosen.contains($0.serial) }
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

    private let worker = DispatchQueue(label: "android-webcam.capture", qos: .userInitiated)
    private let statsQueue = DispatchQueue(label: "android-webcam.stats")
    private let lock = NSLock()
    private var stopping = false
    private var socket: Int32 = -1
    private var adbProcess: Process?
    private var decoderError: Error?
    /// The phone server's ERROR lines from the current session, which say why the camera didn't open.
    private var serverErrors = ""
    /// Set once a session has sent a frame. Before that, a failure is a setup problem, not a loose cable.
    private var streamed = false
    /// True while the current session's frames flow.
    private var live = false
    private var lensID: String?
    private var image = PhoneImageSettings()
    /// Bumped by switchLens: the session it ends was asked to end, so that end isn't an error.
    private var lensGeneration = 0
    /// Bumped when capture starts and ends, so only the current capture's stats poll keeps going.
    private var statsGeneration = 0
    /// Guards the control socket, so a message never goes to a closed or reused descriptor.
    private let controlLock = NSLock()
    private var control: Int32 = -1
    private let sharpener = FrameSharpener()
    private var stopCompletions: [() -> Void] = []
    private(set) var running = false
    var onStatus: (String, Bool) -> Void = { _, _ in }
    /// Called on the capture thread with the frame the camera got (after Mac sharpening).
    var onFrame: ((CVPixelBuffer) -> Void)?
    var onPhoneStats: ((PhoneStats) -> Void)?
    var onLive: ((Bool) -> Void)?
    /// 0 = off ... 1 = strong; applied from the next frame.
    var macSharpness: Float {
        get { sharpener.amount }
        set { sharpener.amount = newValue }
    }

    init() {
        worker.async { Self.removeStaleSession() }
    }

    private var shouldStop: Bool {
        lock.lock(); defer { lock.unlock() }
        return stopping
    }

    /// True once the user stopped or switchLens asked the session started at generation to end.
    private func ending(_ generation: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return stopping || lensGeneration != generation
    }

    private func report(_ text: String, active: Bool) {
        DispatchQueue.main.async { [weak self] in self?.onStatus(text, active) }
    }

    private func setLive(_ value: Bool) {
        lock.lock()
        let changed = live != value
        live = value
        lock.unlock()
        if changed { DispatchQueue.main.async { [weak self] in self?.onLive?(value) } }
    }

    func start(device: AndroidDevice, mode: CaptureMode, lensID: String?, image: PhoneImageSettings) {
        guard !running else { return }
        lock.lock()
        stopping = false; decoderError = nil; streamed = false; serverErrors = ""
        self.lensID = lensID
        self.image = image
        statsGeneration += 1
        let statsRun = statsGeneration
        lock.unlock()
        running = true
        report("Starting \(device.model)...", active: true)
        statsQueue.async { [weak self] in self?.pollStats(serial: device.serial, run: statsRun) }
        worker.async { [weak self] in
            guard let self else { return }
            let result = self.run(device: device, mode: mode)
            self.lock.lock(); self.statsGeneration += 1; self.lock.unlock()
            self.setLive(false)
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

    /// Ends the phone session and reconnects with the new camera, keeping the virtual camera open.
    /// While not running it only sets the camera the next session uses.
    func switchLens(_ id: String) {
        lock.lock()
        guard lensID != id else { lock.unlock(); return }
        lensID = id
        guard running, !stopping else { lock.unlock(); return }
        lensGeneration += 1
        // The new lens has to stream before a failure counts as a loose cable.
        streamed = false
        if socket >= 0 { Darwin.shutdown(socket, SHUT_RDWR) }
        let process = adbProcess
        lock.unlock()
        if let process { interrupt(process) }
    }

    func setTorch(_ on: Bool) { sendControl([18, on ? 1 : 0]) }
    func zoomIn() { sendControl([19]) }
    func zoomOut() { sendControl([20]) }

    /// Applies the settings to the live session and keeps them for reconnects and the next start.
    func setImage(_ settings: PhoneImageSettings) {
        lock.lock(); image = settings; lock.unlock()
        let exposure = UInt32(bitPattern: Int32((min(max(settings.exposureEV, -10), 10) * 100).rounded()))
        sendControl([100,
                     UInt8(truncatingIfNeeded: exposure >> 24), UInt8(truncatingIfNeeded: exposure >> 16),
                     UInt8(truncatingIfNeeded: exposure >> 8), UInt8(truncatingIfNeeded: exposure),
                     caseIndex(settings.whiteBalance), caseIndex(settings.focus),
                     caseIndex(settings.noiseReduction), caseIndex(settings.sharpness)])
    }

    private func caseIndex<T: CaseIterable & Equatable>(_ value: T) -> UInt8 {
        UInt8(Array(T.allCases).firstIndex(of: value) ?? 0)
    }

    /// Writes a control message to the live session; does nothing when no session is live.
    private func sendControl(_ message: [UInt8]) {
        lock.lock(); let isLive = live; lock.unlock()
        guard isLive else { return }
        controlLock.lock(); defer { controlLock.unlock() }
        let fd = control
        guard fd >= 0 else { return }
        var offset = 0
        while offset < message.count {
            let sent = message[offset...].withUnsafeBytes { Darwin.send(fd, $0.baseAddress, $0.count, 0) }
            if sent < 0, errno == EINTR { continue }
            guard sent > 0 else {
                fputs("Phone control message failed. \(String(cString: strerror(errno)))\n", stderr)
                return
            }
            offset += sent
        }
    }

    /// Lists the phone's cameras by running the server with list_cameras=true. Blocking; call off main.
    func cameras(serial: String) throws -> [CameraLens] {
        guard let serverURL = ADB.serverURL else {
            throw WebcamError(message: Self.serverMissing)
        }
        let remote = Self.remotePrefix + String(format: "list-%08x.jar", UInt32.random(in: 1...0x7fff_ffff))
        defer {
            do { _ = try ADB.command(["-s", serial, "shell", "rm", "-f", remote], timeout: 5) }
            catch { fputs("Phone cleanup failed. \(error.logText)\n", stderr) }
        }
        _ = try ADB.command(["-s", serial, "push", serverURL.path, remote], timeout: 30)
        let output = try ADB.command(["-s", serial, "shell", "CLASSPATH=\(remote)", "app_process", "/",
            "com.genymobile.scrcpy.Server", ScrcpyServer.version, "list_cameras=true", "cleanup=false"], timeout: 20)
        return Self.lenses(fromCameraList: output)
    }

    /// Parses lines like `--camera-id=0    (back, 4080x3060, fps={15, 30}, zoom-range=[0.6, 10.0], focal=6.30)`.
    private static func lenses(fromCameraList text: String) -> [CameraLens] {
        let found: [(id: String, facing: String, focal: Double?)] = text.split(separator: "\n").compactMap { line in
            guard let marker = line.range(of: "--camera-id=") else { return nil }
            let rest = line[marker.upperBound...]
            let id = String(rest.prefix { !$0.isWhitespace })
            guard !id.isEmpty, let open = rest.firstIndex(of: "(") else { return nil }
            let facing = String(rest[rest.index(after: open)...].prefix { $0 != "," && $0 != ")" })
            let focal = rest.range(of: "focal=").flatMap { Double(rest[$0.upperBound...].prefix { $0.isNumber || $0 == "." }) }
            return (id, facing, focal)
        }
        let main = found.filter { $0.facing == "back" }.min { a, b in
            if let x = Int(a.id), let y = Int(b.id) { return x < y }
            return a.id < b.id
        }
        return found.map { camera in
            let label: String
            switch camera.facing {
            case "front": label = "Front"
            case "external": label = "External"
            case "back":
                let ratio = camera.focal.flatMap { focal in main?.focal.flatMap { $0 > 0 ? focal / $0 : nil } }
                if camera.id == main?.id {
                    label = "Back · Main"
                } else if let ratio, ratio < 0.8 {
                    label = "Back · Ultra Wide"
                } else if let ratio, ratio > 1.4 {
                    label = "Back · \(max(2, Int(ratio.rounded())))x"
                } else {
                    label = "Back · Camera \(camera.id)"
                }
            default: label = "Camera \(camera.id)"
            }
            return CameraLens(id: camera.id, facing: camera.facing, label: label)
        }
    }

    /// Reads battery and heat every 10 seconds until capture `run` ends. A failed read skips that tick.
    private func pollStats(serial: String, run: Int) {
        while statsCurrent(run) {
            if let stats = try? Self.phoneStats(serial: serial) {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.statsCurrent(run) else { return }
                    self.onPhoneStats?(stats)
                }
            }
            for _ in 0..<100 {
                if !statsCurrent(run) { return }
                usleep(100_000)
            }
        }
    }

    private func statsCurrent(_ run: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return !stopping && statsGeneration == run
    }

    private static func phoneStats(serial: String) throws -> PhoneStats {
        var battery: [String: String] = [:]
        for line in try ADB.command(["-s", serial, "shell", "dumpsys", "battery"]).split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            if battery[key] == nil { battery[key] = parts[1].trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        guard let tenths = battery["temperature"].flatMap(Double.init), let level = battery["level"].flatMap(Int.init) else {
            throw TransportError(message: "The phone's battery state was unreadable.")
        }
        let prefix = "Thermal Status:"
        let thermal = (try? ADB.command(["-s", serial, "shell", "dumpsys", "thermalservice"]))?
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix(prefix) }
            .flatMap { Int($0.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)) }
        // BatteryManager.BATTERY_STATUS_CHARGING is 2.
        return PhoneStats(temperatureC: tenths / 10, batteryPercent: level, charging: battery["status"] == "2",
                          thermalStatus: thermal)
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
            guard device.authorized else {
                throw WebcamError(message: "The phone hasn't allowed USB debugging for this Mac. Unlock it and tap Allow.")
            }
            guard let serverURL = ADB.serverURL else { throw WebcamError(message: Self.serverMissing) }
            let camera = try VirtualCamera(fps: mode.fps)
            defer { camera.stop() }
            while true {
                lock.lock(); let generation = lensGeneration; lock.unlock()
                do {
                    try session(device: device, mode: mode, serverURL: serverURL, camera: camera, generation: generation)
                    // A session returns only when asked to end: by the user, or by switchLens.
                    if shouldStop || !ending(generation) { break }
                } catch where !shouldStop && ending(generation) {
                    // switchLens ended this session; whatever it threw on the way out isn't a failure.
                } catch let error as TransportError where !shouldStop && hasStreamed {
                    fputs("Phone session ended. \(error.logText)\n", stderr)
                    report("Reconnecting to \(device.model). \(error.message)", active: true)
                    guard waitForDevice(device.serial) else { break }
                    continue
                }
                report("Switching camera on \(device.model)...", active: true)
            }
            return "Webcam stopped"
        } catch {
            lock.lock(); let failure = decoderError; let server = serverErrors; lock.unlock()
            if failure == nil && shouldStop { return "Webcam stopped" }
            let shown = failure ?? error
            fputs("Webcam stopped. \(shown.logText)\(server.isEmpty ? "" : " Phone said: \(server)")\n", stderr)
            if failure == nil, let reason = Self.explainServer(server) { return reason }
            return shown.localizedDescription
        }
    }

    private static let serverMissing = "This copy of the app is missing its phone helper (scrcpy-server \(ScrcpyServer.version)). Download the app again."

    /// The phone server's error lines, said plainly. Nil when they don't name a cause the user can act on.
    static func explainServer(_ text: String) -> String? {
        if text.contains("CAMERA_IN_USE") || text.contains("in use already") || text.contains("MAX_CAMERAS_IN_USE") {
            return "Another app on the phone is using the camera. Close it and start again."
        }
        if text.contains("CAMERA_DISABLED") {
            return "Camera access is turned off on the phone. Turn it on in the phone's quick settings or privacy settings, then start again."
        }
        if text.contains("Could not select camera size") {
            return "The phone's camera can't capture in this mode. Pick a lower capture mode and start again."
        }
        if text.contains("CameraAccessException") || text.contains("Camera error") || text.contains("Camera configuration error") {
            return "The phone's camera reported an error. Unlock the phone and start again, and restart the phone if it keeps happening."
        }
        return nil
    }

    private func noteServerError(_ line: String) {
        lock.lock()
        serverErrors = String((serverErrors + line + "\n").suffix(4000))
        lock.unlock()
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

    private func session(device: AndroidDevice, mode: CaptureMode, serverURL: URL, camera: VirtualCamera, generation: Int) throws {
        lock.lock(); let lens = lensID ?? "0"; let settings = image; serverErrors = ""; lock.unlock()
        let sdk = Int(try adb(["-s", device.serial, "shell", "getprop", "ro.build.version.sdk"])
            .trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        guard sdk >= 31 else { throw WebcamError(message: "The webcam needs Android 12 or later, and this phone runs an older version.") }
        let scid = String(format: "%08x", UInt32.random(in: 1...0x7fff_ffff))
        let remote = Self.remotePrefix + "\(scid).jar"
        var port: Int?
        var fd: Int32 = -1
        var controlFD: Int32 = -1
        let controlDrained = DispatchSemaphore(value: 0)
        var server: Process?
        let serverExited = DispatchSemaphore(value: 0)
        var decoder: HEVCDecoder?
        defer {
            decoder?.finish()
            setLive(false)
            controlLock.lock(); control = -1; controlLock.unlock()
            if controlFD >= 0 {
                Darwin.shutdown(controlFD, SHUT_RDWR)
                controlDrained.wait()
                Darwin.close(controlFD)
            }
            lock.lock(); socket = -1; lock.unlock()
            if fd >= 0 { Darwin.close(fd) }
            if let server { end(server, exited: serverExited) }
            if let port {
                do { _ = try ADB.command(["-s", device.serial, "forward", "--remove", "tcp:\(port)"], timeout: 5) }
                catch { fputs("Forward cleanup failed. \(error.logText)\n", stderr) }
            }
            do { _ = try ADB.command(["-s", device.serial, "shell", "rm", "-f", remote], timeout: 5) }
            catch { fputs("Phone cleanup failed. \(error.logText)\n", stderr) }
            try? FileManager.default.removeItem(at: Self.sessionFile)
        }
        _ = try adb(["-s", device.serial, "push", serverURL.path, remote], timeout: 30)
        let forwarding = try adb(["-s", device.serial, "forward", "tcp:0", "localabstract:scrcpy_\(scid)"])
        guard let allocated = Int(forwarding.trimmingCharacters(in: .whitespacesAndNewlines)), (1...65535).contains(allocated) else {
            throw TransportError(message: "adb couldn't connect to the phone's camera. Unplug the phone, plug it back in and start again.",
                                 detail: "adb forward returned \(forwarding).")
        }
        port = allocated
        if ending(generation) { return }
        let shell = Process()
        shell.executableURL = try ADB.executable()
        shell.arguments = ["-s", device.serial, "shell", "CLASSPATH=\(remote)", "app_process", "/",
            "com.genymobile.scrcpy.Server", ScrcpyServer.version, "scid=\(scid)", "tunnel_forward=true",
            "video_source=camera", "camera_id=\(lens)", "camera_size=\(mode.width)x\(mode.height)",
            "camera_fps=\(mode.fps)", "camera_high_speed=\(mode.fps > 60)",
            "video_codec=h265", "video_bit_rate=\(mode.bitrate)", "audio=false", "control=true",
            "clipboard_autosync=false", "send_device_meta=false", "send_dummy_byte=true",
            "downsize_on_error=false", "cleanup=true"] + Self.imageArguments(settings)
        // The server's output goes to the log, and its ERROR lines say why a camera didn't open.
        let output = Pipe()
        shell.standardOutput = output
        shell.standardError = output
        let serverLog = output.fileHandleForReading
        Thread { [weak self] in
            var pending = ""
            while case let chunk = serverLog.availableData, !chunk.isEmpty {
                FileHandle.standardError.write(chunk)
                pending += String(decoding: chunk, as: UTF8.self)
                var lines = pending.components(separatedBy: "\n")
                pending = lines.removeLast()
                for line in lines where line.contains("ERROR") { self?.noteServerError(line) }
            }
        }.start()
        shell.terminationHandler = { _ in serverExited.signal() }
        try shell.run()
        server = shell
        save(SessionRecord(serial: device.serial, port: allocated, scid: scid, remote: remote,
                           pid: shell.processIdentifier, owner: getpid()))
        // The server accepts the video socket first (only it gets the dummy byte), then the control socket,
        // and sends the codec once both are connected.
        fd = try connect(port: allocated, generation: generation, server: shell)
        lock.lock(); socket = fd; lock.unlock()
        if ending(generation) { return }
        controlFD = try connectControl(port: allocated)
        let drainFD = controlFD
        // Device messages (clipboard and the like) arrive here; read and drop them so the server never blocks.
        Thread { Self.drainControl(drainFD); controlDrained.signal() }.start()
        controlLock.lock(); control = controlFD; controlLock.unlock()
        let codec = try readExactly(4, from: fd)
        guard codec == Data("h265".utf8) else {
            throw WebcamError(message: "The phone couldn't start its camera in this mode. Pick a lower capture mode and start again.",
                              detail: "The server sent codec \(String(decoding: codec, as: UTF8.self)).")
        }
        var announced = false
        let videoDecoder = HEVCDecoder(onFrame: { [weak self] pixel in
            guard let self, !self.ending(generation) else { return }
            do {
                guard CVPixelBufferGetWidth(pixel) == mode.width, CVPixelBufferGetHeight(pixel) == mode.height else {
                    throw WebcamError(message: "The phone sent a different picture size than \(mode.title). Pick another capture mode and start again.",
                                      detail: "Decoded \(CVPixelBufferGetWidth(pixel))x\(CVPixelBufferGetHeight(pixel)), expected \(mode.width)x\(mode.height).")
                }
                let frame = self.sharpener.process(pixel)
                try camera.send(frame)
                self.onFrame?(frame)
                self.lock.lock()
                let firstFrame = !announced
                announced = true
                self.streamed = true
                self.lock.unlock()
                if firstFrame {
                    self.setLive(true)
                    self.report("\(mode.title) / OBS Virtual Camera", active: true)
                    // Settings changed while the camera opened couldn't be sent yet.
                    self.lock.lock(); let current = self.image; self.lock.unlock()
                    if current != settings { self.setImage(current) }
                }
            } catch { self.failDecoder(error) }
        }, onError: { [weak self] in self?.failDecoder($0) })
        decoder = videoDecoder
        var streaming = false
        let packetLog = Wireless.enabled
            ? PacketLog(label: "\(device.serial) \(device.wireless ? "wireless" : "usb") \(mode.title)") : nil
        defer { packetLog?.stop() }
        while !ending(generation) {
            switch try ScrcpyHeader(readExactly(12, from: fd)) {
            case let .session(width, height):
                guard width == mode.width, height == mode.height else {
                    throw WebcamError(message: "The phone's camera can't capture \(mode.width)x\(mode.height). It offered \(width)x\(height). Pick another capture mode and start again.")
                }
            case let .packet(size, pts, configuration):
                // The camera can take a while to open; once media flows, a 3 second gap means the link is gone.
                if !streaming { streaming = true; setReadTimeout(fd, seconds: 3) }
                let payload = try readExactly(size, from: fd)
                packetLog?.record(size: size, pts: pts, configuration: configuration)
                try videoDecoder.decode(payload, pts: pts)
            }
        }
        lock.lock(); let failure = decoderError; lock.unlock()
        if let failure { throw failure }
    }

    /// The server options for the phone's image controls.
    private static func imageArguments(_ image: PhoneImageSettings) -> [String] {
        func level(_ value: ProcessingLevel) -> String { value == .highQuality ? "high_quality" : value.rawValue }
        return ["webcam_exposure=\(String(format: "%.2f", image.exposureEV))",
                "webcam_awb=\(image.whiteBalance.rawValue)", "webcam_focus=\(image.focus.rawValue)",
                "webcam_nr=\(level(image.noiseReduction))", "webcam_edge=\(level(image.sharpness))"]
    }

    private static func drainControl(_ fd: Int32) {
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = Darwin.recv(fd, &buffer, buffer.count, 0)
            if count < 0, errno == EINTR { continue }
            if count <= 0 { return }
        }
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
        } catch { fputs("Could not record the session. \(error.logText)\n", stderr) }
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
        } catch { fputs("Stale forward cleanup failed. \(error.logText)\n", stderr) }
        do {
            let ps = try runTool(URL(fileURLWithPath: "/bin/ps"), ["-o", "args=", "-p", "\(record.pid)"], timeout: 5, onLaunch: { _ in })
            if let ps, ps.status == 0, ps.text.contains("scid=\(record.scid)") { kill(record.pid, SIGTERM) }
        } catch { fputs("Stale process cleanup failed. \(error.logText)\n", stderr) }
        guard record.remote.hasPrefix(remotePrefix) else { return }
        do { _ = try ADB.command(["-s", record.serial, "shell", "rm", "-f", record.remote], timeout: 5) }
        catch { fputs("Stale phone cleanup failed. \(error.logText)\n", stderr) }
    }

    private func setReadTimeout(_ fd: Int32, seconds: Int) {
        var timeout = timeval(tv_sec: seconds, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    }

    private func connect(port: Int, generation: Int, server: Process) throws -> Int32 {
        // ADB may accept TCP before the phone has opened its abstract socket.
        let deadline = Date().addingTimeInterval(5)
        // A server that already exited won't accept, so its error shows at once instead of after the deadline.
        while Date() < deadline, server.isRunning {
            if ending(generation) { throw WebcamError(message: "Capture cancelled.") }
            let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
            guard fd >= 0 else {
                throw WebcamError(message: Self.socketFailed, detail: "Video socket: \(String(cString: strerror(errno))).")
            }
            var timeout = timeval(tv_sec: 0, tv_usec: 200_000)
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            var dummy: UInt8 = 1
            if Self.connectLocal(fd, port: port), Darwin.recv(fd, &dummy, 1, 0) == 1, dummy == 0 {
                // Until the first media packet the camera may still be opening, so allow 10 seconds.
                setReadTimeout(fd, seconds: 10)
                return fd
            }
            Darwin.close(fd)
            usleep(50_000)
        }
        throw TransportError(message: Self.cameraDidNotStart, detail: "The server didn't accept its video connection.")
    }

    private static let socketFailed = "The Mac couldn't open a local connection to the phone. Quit and reopen the app, then start again."
    private static let cameraDidNotStart = "The phone's camera didn't start. Unlock the phone, close any app that uses the camera and start again."

    /// The server is already waiting for this socket once the video socket got its dummy byte.
    private func connectControl(port: Int) throws -> Int32 {
        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw WebcamError(message: Self.socketFailed, detail: "Control socket: \(String(cString: strerror(errno))).")
        }
        // A write after the phone went away should fail, not kill the app.
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        guard Self.connectLocal(fd, port: port) else {
            Darwin.close(fd)
            throw TransportError(message: Self.cameraDidNotStart, detail: "The server didn't accept its control connection.")
        }
        return fd
    }

    private static func connectLocal(_ fd: Int32, port: Int) -> Bool {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(port).bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let status = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return status == 0
    }

    private func readExactly(_ count: Int, from fd: Int32) throws -> Data {
        var data = Data(count: count)
        var offset = 0
        try data.withUnsafeMutableBytes { bytes in
            while offset < count {
                let received = Darwin.recv(fd, bytes.baseAddress!.advanced(by: offset), count - offset, 0)
                if received <= 0 {
                    if received < 0, errno == EINTR { continue }
                    throw TransportError(message: "The video from the phone stopped arriving. Check the cable and start again.",
                                         detail: received == 0 ? "The video socket closed." : "Video socket: \(String(cString: strerror(errno))).")
                }
                offset += received
            }
        }
        return data
    }
}
