import AppKit
import Foundation

/// Off-screen dev automation (kata:android-webcam#2a6e). It exists only when `ANDROID_WEBCAM_DEV_DIR` names a
/// directory. A normal launch has no such variable, so it opens no socket and changes nothing. In dev mode the app
/// keeps its own defaults suite, hides its status item, parks windows below the desktop and answers one JSON
/// request per connection on `<dir>/control.sock`. docs/dev-automation.md lists the operations.
enum DevMode {
    static let environmentKey = "ANDROID_WEBCAM_DEV_DIR"

    static let directory: URL? = {
        guard let path = ProcessInfo.processInfo.environment[environmentKey], path.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }()
    static var isOn: Bool { directory != nil }

    /// The dev instance's own defaults, so it never reads or writes the real app's settings. Cleared on every launch,
    /// then filled from `<dir>/seed.json` when `dev.sh start key=value` wrote one (a lens, a finished Setup). Arrays
    /// and objects are stored as JSON data, the way the app saves its lens lists and image settings.
    static let suiteName = "com.harsha.android-webcam.dev." + (directory?.lastPathComponent ?? "none")
    static let defaults: UserDefaults? = {
        guard isOn, let suite = UserDefaults(suiteName: suiteName) else { return nil }
        suite.removePersistentDomain(forName: suiteName)
        if let directory, let data = try? Data(contentsOf: directory.appendingPathComponent("seed.json")),
           let seed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for (key, value) in seed {
                let structured = value is [Any] || value is [String: Any]
                suite.set(structured ? (try? JSONSerialization.data(withJSONObject: value)) as Any? : value, forKey: key)
            }
        }
        return suite
    }()

    /// Things the app would have done outside its own windows: notifications, opened URLs, pasteboard writes and the like.
    /// Dev mode records them and does none of them.
    private(set) static var effects: [[String: String]] = []

    static func record(_ kind: String, _ text: String) {
        effects.append(["kind": kind, "text": text])
        if effects.count > 200 { effects.removeFirst(effects.count - 200) }
    }

    /// Windows sit one level below the desktop, so the wallpaper covers them and they never take focus.
    static var parkedLevel: NSWindow.Level { NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) - 1) }

    static func park(_ window: NSWindow) {
        window.level = parkedLevel
        window.hidesOnDeactivate = false
        window.orderFrontRegardless()
    }

    static func cleanUp() {
        defaults?.removePersistentDomain(forName: suiteName)
        if let directory { unlink(directory.appendingPathComponent("control.sock").path) }
    }
}

/// What the control server reads from the app.
struct DevHooks {
    let menu: NSMenu
    /// Brings the header, menu and Setup steps up to date, as opening the menu does.
    let refresh: () -> Void
    /// True once the first phone list and the first environment check are in.
    let ready: () -> Bool
    /// Opens setup, settings, image, sync or preview. False for any other name.
    let open: (String) -> Bool
    let close: (String) -> Void
}

final class DevControl {
    private let hooks: DevHooks
    private var server: DevControlServer?

    init(hooks: DevHooks) { self.hooks = hooks }

    func start() {
        guard let directory = DevMode.directory else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("control.sock").path
        let server = DevControlServer(path: path) { [weak self] request in
            self?.handle(request) ?? (["ok": false, "error": "The app is gone."], nil)
        }
        do { try server.start() } catch { fputs("Dev control failed to start. \(error.logText)\n", stderr); return }
        self.server = server
        // The wrapper waits for this line, so it knows the socket answers.
        fputs("Dev control ready at \(path)\n", stderr)
    }

    func stop() { server?.stop() }

    // MARK: Operations

    private typealias Reply = (response: [String: Any], after: (() -> Void)?)

    private func fail(_ message: String) -> Reply { (["ok": false, "error": message], nil) }
    private func succeed(_ fields: [String: Any] = [:]) -> Reply { (fields.merging(["ok": true]) { $1 }, nil) }

    private func handle(_ request: [String: Any]) -> Reply {
        guard let op = request["op"] as? String else { return fail("Send {\"op\": ...}. See docs/dev-automation.md.") }
        switch op {
        case "ping":
            return succeed(["pid": Int(getpid())])
        case "state":
            hooks.refresh()
            return succeed(["header": headerText(), "menu": menuTree(hooks.menu), "windows": windows(),
                            "effects": DevMode.effects.count, "ready": hooks.ready()])
        case "menu":
            hooks.refresh()
            return succeed(["header": headerText(), "menu": menuTree(hooks.menu), "ready": hooks.ready()])
        case "choose":
            guard let title = request["title"] as? String else { return fail("choose needs a title.") }
            return choose(title)
        case "windows":
            return succeed(["windows": windows()])
        case "open":
            guard let name = request["window"] as? String, hooks.open(name) else {
                return fail("open needs window: setup, settings, image, sync or preview.")
            }
            return succeed(["windows": windows()])
        case "close":
            guard let name = request["window"] as? String else { return fail("close needs a window.") }
            hooks.close(name)
            return succeed(["windows": windows()])
        case "tree":
            guard let window = window(request) else { return fail(noWindow(request)) }
            return succeed(["window": describe(window), "elements": DevAccessibility.tree(of: window)])
        case "text":
            guard let window = window(request) else { return fail(noWindow(request)) }
            return succeed(["window": describe(window), "text": DevAccessibility.text(of: window)])
        case "press":
            guard let window = window(request) else { return fail(noWindow(request)) }
            guard let label = request["label"] as? String else { return fail("press needs a label.") }
            switch DevAccessibility.press(label, in: window) {
            case let .pressed(description):
                RunLoop.main.run(until: Date().addingTimeInterval(0.15))    // lets the control and its text settle
                return succeed(["pressed": description, "text": DevAccessibility.text(of: window)])
            case let .failed(message): return fail(message)
            }
        case "shot":
            guard let window = window(request) else { return fail(noWindow(request)) }
            guard let path = request["path"] as? String, path.hasPrefix("/") else { return fail("shot needs an absolute path.") }
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
                return fail("\(path) is a directory. Give shot a file path such as \(path)/settings.png.")
            }
            return DevShot.capture(window, to: path).map { succeed($0) } ?? fail("Couldn't save \(path).")
        case "effects":
            return succeed(["effects": DevMode.effects])
        case "defaults":
            let values = DevMode.defaults?.dictionaryRepresentation().filter { $0.key.first?.isLowercase == true
                && !$0.key.hasPrefix("com.apple") && !$0.key.hasPrefix("NS") } ?? [:]
            return succeed(["suite": DevMode.suiteName, "values": jsonSafe(values)])
        default:
            return fail("Unknown op \(op).")
        }
    }

    /// Chooses a menu item as a click would: it has to exist, show and be enabled. The reply carries the header and the
    /// effects after the action ran. Quit answers first, then quits.
    private func choose(_ title: String) -> Reply {
        hooks.refresh()
        let items = flatten(hooks.menu, path: "")
        let wanted = Self.normalize(title)
        let exact = items.filter { Self.normalize($0.path) == wanted || Self.normalize($0.item.title) == wanted }
        let matches = exact.isEmpty
            ? items.filter { Self.normalize($0.item.title).hasPrefix(wanted) || (wanted == "setup" && $0.item.title == "Finish Setup…") }
            : exact
        let visible = items.filter { !$0.item.isHidden && !$0.item.isSeparatorItem && $0.item.view == nil && !$0.path.contains("/") }
            .map { $0.path + ($0.item.isEnabled ? "" : " (disabled)") }
        guard let match = matches.first, matches.count == 1 else {
            let what = matches.isEmpty ? "No menu item matches" : "More than one menu item matches"
            return fail("\(what) \"\(title)\". Items now: \(visible.joined(separator: " | ")). "
                + "Header: \"\(headerText().joined(separator: " / "))\". Submenu items are chosen as \"Capture Mode/1080p / 60 fps\".")
        }
        let item = match.item
        if item.isHidden { return fail("\"\(match.path)\" is hidden right now.") }
        if !item.isEnabled { return fail("\"\(match.path)\" is disabled right now. The header says: \(headerText().joined(separator: " / "))") }
        guard item.hasSubmenu == false, item.action != nil, let parent = item.menu else { return fail("\"\(match.path)\" is a submenu.") }
        let index = parent.index(of: item)
        let before = DevMode.effects.count
        let perform = { parent.performActionForItem(at: index) }
        if item.title.hasPrefix("Quit") {
            return (["ok": true, "chose": match.path, "quitting": true], { perform() })
        }
        perform()
        hooks.refresh()
        return succeed(["chose": match.path, "header": headerText(), "windows": windows(),
                        "effects": Array(DevMode.effects.dropFirst(before))])
    }

    private static func normalize(_ title: String) -> String {
        title.replacingOccurrences(of: "…", with: "").replacingOccurrences(of: "...", with: "")
            .trimmingCharacters(in: .whitespaces).lowercased()
    }

    private func flatten(_ menu: NSMenu, path: String) -> [(path: String, item: NSMenuItem)] {
        menu.items.flatMap { item -> [(path: String, item: NSMenuItem)] in
            let here = path.isEmpty ? item.title : "\(path)/\(item.title)"
            return [(here, item)] + (item.submenu.map { flatten($0, path: here) } ?? [])
        }
    }

    private func menuTree(_ menu: NSMenu) -> [[String: Any]] {
        menu.items.map { item in
            if item.isSeparatorItem { return ["separator": true] }
            if item.view != nil { return ["header": true] }
            var entry: [String: Any] = ["title": item.title, "enabled": item.isEnabled, "hidden": item.isHidden]
            if item.state != .off { entry["state"] = item.state == .on ? "on" : "mixed" }
            if !item.keyEquivalent.isEmpty { entry["key"] = item.keyEquivalent }
            if let submenu = item.submenu { entry["submenu"] = menuTree(submenu) }
            return entry
        }
    }

    /// The text the menu's header shows, one line per label, as a user reads it.
    private func headerText() -> [String] {
        guard let view = hooks.menu.items.first(where: { $0.view != nil })?.view else { return [] }
        return DevAccessibility.labels(in: view)
    }

    // MARK: Windows

    private func appWindows() -> [NSWindow] {
        NSApp.windows.filter { $0.styleMask.contains(.titled) && $0.identifier != nil }
    }

    private func window(_ request: [String: Any]) -> NSWindow? {
        guard let name = request["window"] as? String else { return nil }
        return appWindows().first { $0.identifier?.rawValue == name }
    }

    private func noWindow(_ request: [String: Any]) -> String {
        let open = appWindows().compactMap { $0.identifier?.rawValue }
        return "No open window \"\(request["window"] as? String ?? "")\". Open: \(open.isEmpty ? "none" : open.joined(separator: ", ")). Use the open op."
    }

    private func windows() -> [[String: Any]] { appWindows().map(describe) }

    private func describe(_ window: NSWindow) -> [String: Any] {
        let frame = window.frame
        return ["id": window.identifier?.rawValue ?? "", "title": window.title, "windowNumber": window.windowNumber,
                "level": window.level.rawValue, "parked": window.level.rawValue < Int(CGWindowLevelForKey(.desktopWindow)),
                "frame": [Int(frame.minX), Int(frame.minY), Int(frame.width), Int(frame.height)], "visible": window.isVisible]
    }

    private func jsonSafe(_ values: [String: Any]) -> [String: Any] {
        values.mapValues { value in
            switch value {
            case is String, is NSNumber, is Bool: value
            case let data as Data: "<\(data.count) bytes> " + (String(data: data, encoding: .utf8) ?? data.base64EncodedString())
            default: "\(value)"
            }
        }
    }
}

// MARK: Socket

/// One request per connection: a line of JSON in, a line of JSON out. Requests run on the main thread.
final class DevControlServer {
    typealias Handler = ([String: Any]) -> (response: [String: Any], after: (() -> Void)?)

    private let path: String
    private let handler: Handler
    private var descriptor: Int32 = -1

    init(path: String, handler: @escaping Handler) {
        self.path = path
        self.handler = handler
    }

    func start() throws {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard path.utf8.count < capacity else { throw WebcamError(message: "The dev directory path is too long for a socket: \(path)") }
        withUnsafeMutablePointer(to: &address.sun_path) {
            $0.withMemoryRebound(to: CChar.self, capacity: capacity) { _ = strlcpy($0, path, capacity) }
        }
        unlink(path)
        descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw WebcamError(message: "socket failed: \(String(cString: strerror(errno)))") }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0 else { throw WebcamError(message: "bind failed: \(String(cString: strerror(errno)))") }
        chmod(path, 0o600)
        guard listen(descriptor, 8) == 0 else { throw WebcamError(message: "listen failed: \(String(cString: strerror(errno)))") }
        let listener = descriptor
        Thread.detachNewThread { [weak self] in
            while true {
                let client = accept(listener, nil, nil)
                if client < 0 { if errno == EINTR { continue } else { return } }
                self?.serve(client)
            }
        }
    }

    func stop() {
        if descriptor >= 0 { close(descriptor); descriptor = -1 }
        unlink(path)
    }

    private func serve(_ client: Int32) {
        defer { close(client) }
        var one: Int32 = 1
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while !data.contains(10), data.count < 1 << 20 {
            let count = read(client, &buffer, buffer.count)
            if count <= 0 { break }
            data.append(contentsOf: buffer[0..<count])
        }
        var result: (response: [String: Any], after: (() -> Void)?)
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            result = DispatchQueue.main.sync { handler(object) }
        } else {
            result = (["ok": false, "error": "Send one line of JSON."], nil)
        }
        var out = (try? JSONSerialization.data(withJSONObject: result.response, options: [.sortedKeys, .withoutEscapingSlashes]))
            ?? Data("{\"ok\":false,\"error\":\"The reply wasn't JSON.\"}".utf8)
        out.append(10)
        out.withUnsafeBytes { raw in
            var sent = 0
            while sent < raw.count {
                let count = write(client, raw.baseAddress! + sent, raw.count - sent)
                if count <= 0 { break }
                sent += count
            }
        }
        // A run loop block, not a main-queue block: Quit while capturing waits in a nested run loop for the stop's
        // main-queue completion, which can't run while a main-queue block is still on the stack.
        if let after = result.after { RunLoop.main.perform(after); CFRunLoopWakeUp(CFRunLoopGetMain()) }
    }
}

// MARK: Screenshots

enum DevShot {
    /// Saves one window as a PNG. Windows below the desktop can't be captured off screen, but the window server still
    /// draws them, so screencapture can read them by number. If it can't, the window renders its own view instead.
    static func capture(_ window: NSWindow, to path: String) -> [String: Any]? {
        var notes: [String] = []
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-o", "-l", "\(window.windowNumber)", path]
        let errors = Pipe()
        process.standardError = errors
        unlink(path)
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                notes.append("screencapture exited \(process.terminationStatus): "
                    + String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
            }
        } catch { notes.append("screencapture didn't run: \(error.localizedDescription)") }
        var backend = "screencapture"
        if let size = pngSize(path), !isBlank(path) {
            return ["path": path, "backend": backend, "width": size.width, "height": size.height, "notes": notes]
        }
        if FileManager.default.fileExists(atPath: path) { notes.append("screencapture saved a blank image") }
        backend = "cacheDisplay"
        guard let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return nil }
        do { try png.write(to: URL(fileURLWithPath: path)) } catch { return nil }
        return ["path": path, "backend": backend, "width": rep.pixelsWide, "height": rep.pixelsHigh, "notes": notes]
    }

    private static func pngSize(_ path: String) -> (width: Int, height: Int)? {
        guard let rep = NSBitmapImageRep(data: (try? Data(contentsOf: URL(fileURLWithPath: path))) ?? Data()) else { return nil }
        return (rep.pixelsWide, rep.pixelsHigh)
    }

    /// True when every sampled pixel is one color, which is what a window nobody drew looks like.
    private static func isBlank(_ path: String) -> Bool {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)), let rep = NSBitmapImageRep(data: data) else { return true }
        var first: [CGFloat]?
        let stepX = max(1, rep.pixelsWide / 24), stepY = max(1, rep.pixelsHigh / 24)
        for y in stride(from: 0, to: rep.pixelsHigh, by: stepY) {
            for x in stride(from: 0, to: rep.pixelsWide, by: stepX) {
                guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let sample = [color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent]
                if let first { if zip(first, sample).contains(where: { abs($0 - $1) > 0.004 }) { return false } } else { first = sample }
            }
        }
        return true
    }
}
