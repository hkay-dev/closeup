import Foundation

/// The app's recent stderr, for Copy Diagnostics. Errors go to stderr with `fputs` all over the app; rather than
/// route each through a helper, stderr becomes a pipe whose reader thread writes every byte on to the original
/// stderr (Console, a terminal, `dev.sh`'s log) and keeps the last 200 lines in memory. Nothing goes to disk.
enum ErrorLog {
    private static let keep = 200
    private static let lock = NSLock()
    private static var lines: [String] = []

    /// Call once, before anything else writes to stderr.
    static func start() {
        var ends: [Int32] = [0, 0]
        guard pipe(&ends) == 0 else { return }
        let original = dup(STDERR_FILENO)
        guard original >= 0, dup2(ends[1], STDERR_FILENO) >= 0 else {
            close(ends[0]); close(ends[1])
            if original >= 0 { close(original) }
            return
        }
        close(ends[1])
        let reader = ends[0]
        let thread = Thread { tee(from: reader, to: original) }
        thread.name = "stderr tee"
        thread.qualityOfService = .utility
        thread.start()
    }

    /// The last `count` lines, oldest first.
    static func recent(_ count: Int) -> [String] {
        lock.lock(); defer { lock.unlock() }
        return Array(lines.suffix(count))
    }

    private static func tee(from reader: Int32, to original: Int32) {
        let clock = DateFormatter()
        clock.dateFormat = "HH:mm:ss"
        var buffer = [UInt8](repeating: 0, count: 4096)
        var partial: [UInt8] = []
        while true {
            let count = read(reader, &buffer, buffer.count)
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { return }
            var written = 0
            while written < count {
                let result = buffer.withUnsafeBytes { write(original, $0.baseAddress! + written, count - written) }
                if result < 0, errno == EINTR { continue }
                guard result > 0 else { break }
                written += result
            }
            partial.append(contentsOf: buffer[0..<count])
            var finished: [String] = []
            while let newline = partial.firstIndex(of: 10) {
                finished.append(String(decoding: partial[..<newline], as: UTF8.self))
                partial.removeSubrange(...newline)
            }
            // A runaway line without a newline still gets kept, in pieces.
            if partial.count > 4096 {
                finished.append(String(decoding: partial, as: UTF8.self))
                partial.removeAll(keepingCapacity: true)
            }
            guard !finished.isEmpty else { continue }
            let stamp = clock.string(from: Date())
            lock.lock()
            lines.append(contentsOf: finished.filter { !$0.isEmpty }.map { "\(stamp) \($0)" })
            if lines.count > keep { lines.removeFirst(lines.count - keep) }
            lock.unlock()
        }
    }
}

/// The plain-text report Copy Diagnostics puts on the pasteboard for a bug report. It names the phone's model and
/// Android version but never a serial number, and shows paths under the home folder as `~`.
enum Diagnostics {
    /// What the app knows, read on main.
    struct Input {
        var adbPath: String?
        var obsPath: String?
        var obsCamera: String
        var phone: AndroidDevice?
        var steps: [(title: String, done: Bool)]
        var mode: String
        var webcam: String
        /// Every serial the app has seen this run, to take out of the log lines.
        var serials: [String]
    }

    /// Runs adb, so call it off main.
    static func report(_ input: Input) -> String {
        var lines = ["\(appName) diagnostics", ""]
        lines.append("App: \(appVersion), phone server \(ScrcpyServer.version)")
        lines.append("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        let chip = sysctl("machdep.cpu.brand_string") ?? "unknown chip"
        lines.append("Mac: \(sysctl("hw.model") ?? "unknown model"), \(chip), app built for \(architecture)")
        lines.append("adb: \(input.adbPath.map(tilde) ?? "not found")")
        if input.adbPath != nil {
            let version = (try? ADB.command(["version"], timeout: 5))?.split(separator: "\n").first.map(String.init)
            lines.append("adb version: \(version ?? "didn't answer")")
        }
        lines.append("OBS: \(input.obsPath.map(tilde) ?? "not installed")")
        lines.append("OBS camera: \(input.obsCamera)")
        lines.append("Phone: \(phoneLine(input.phone))")
        let done = input.steps.filter(\.done).count
        lines.append("Setup: \(done) of \(input.steps.count) steps done")
        for step in input.steps { lines.append("  [\(step.done ? "x" : " ")] \(step.title)") }
        lines.append("Capture mode: \(input.mode)")
        lines.append("Webcam: \(input.webcam)")
        let log = ErrorLog.recent(50)
        lines.append("")
        lines.append(log.isEmpty ? "Recent log: empty" : "Recent log (last \(log.count) lines):")
        lines.append(contentsOf: log)
        return redact(lines.joined(separator: "\n") + "\n", serials: input.serials)
    }

    private static func phoneLine(_ phone: AndroidDevice?) -> String {
        guard let phone else { return "none connected" }
        var parts = [phone.model.replacingOccurrences(of: "_", with: " ")]
        if phone.authorized {
            let release = (try? ADB.command(["-s", phone.serial, "shell", "getprop", "ro.build.version.release"], timeout: 5))?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            parts.append(release.map { $0.isEmpty ? "Android version unknown" : "Android \($0)" } ?? "Android version unknown")
        } else {
            parts.append("adb says \(phone.status)")
        }
        parts.append(phone.wireless ? "wireless" : "USB")
        return parts.joined(separator: ", ")
    }

    /// Takes out serials (known ones, anything after `adb -s`, wireless mDNS names) and the home folder's path.
    static func redact(_ text: String, serials: [String]) -> String {
        var out = text
        for serial in Set(serials) where serial.count >= 4 {
            out = out.replacingOccurrences(of: serial, with: "<serial>")
        }
        out = out.replacingOccurrences(of: #"(-s\s+)(?!<serial>)\S+"#, with: "$1<serial>", options: .regularExpression)
        out = out.replacingOccurrences(of: #"adb-[^\s.]+\._adb-tls-connect\._tcp\.?"#, with: "<serial>", options: .regularExpression)
        // adb's own wording for a serial it can't find, and forward --list lines.
        out = out.replacingOccurrences(of: #"device '(?!<serial>)[^']+'"#, with: "device '<serial>'", options: .regularExpression)
        out = out.replacingOccurrences(of: #"(?<=^|\s)(?!<serial>)[^\s<]+(?= tcp:\d+ localabstract:)"#, with: "<serial>", options: [.regularExpression])
        return out.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    private static func tilde(_ path: String) -> String { (path as NSString).abbreviatingWithTildeInPath }

    private static var architecture: String {
        #if arch(arm64)
        "arm64"
        #else
        "x86_64"
        #endif
    }

    private static func sysctl(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
    }
}
