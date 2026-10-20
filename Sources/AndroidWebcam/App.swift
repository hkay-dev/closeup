import AppKit
import AVFoundation
import CoreMedia
import UserNotifications
import VideoToolbox

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate, UNUserNotificationCenterDelegate {
    private static let obsBundleID = "com.obsproject.obs-studio"
    private static let coolModeIndex = CaptureMode.all.firstIndex { $0.title == "1080p / 30 fps" } ?? 0

    private let capture = CaptureController()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let header = MenuHeaderView()
    private let mainAction = NSMenuItem(title: "Start Webcam", action: #selector(mainActionChosen), keyEquivalent: "s")
    private let coolDown = NSMenuItem(title: "Switch to 1080p · 30 to cool down", action: #selector(switchToCoolMode), keyEquivalent: "")
    private let phoneItem = NSMenuItem(title: "Phone", action: nil, keyEquivalent: "")
    private let modeItem = NSMenuItem(title: "Capture Mode", action: nil, keyEquivalent: "")
    private let cameraItem = NSMenuItem(title: "Camera", action: nil, keyEquivalent: "")
    private let imageItem = NSMenuItem(title: "Image Settings…", action: #selector(showImageSettings), keyEquivalent: "")
    private let syncItem = NSMenuItem(title: "Check Audio Sync…", action: #selector(showSyncCheck), keyEquivalent: "")
    private let preview = NSMenuItem(title: "Show Preview", action: #selector(togglePreview), keyEquivalent: "p")
    private let zoomIn = NSMenuItem(title: "Zoom In", action: #selector(zoomInChosen), keyEquivalent: "+")
    private let zoomOut = NSMenuItem(title: "Zoom Out", action: #selector(zoomOutChosen), keyEquivalent: "-")
    private let flashlight = NSMenuItem(title: "Flashlight", action: #selector(toggleFlashlight), keyEquivalent: "l")
    private let phoneMenu = NSMenu()
    private let modeMenu = NSMenu()
    private let cameraMenu = NSMenu()
    // What each submenu was last built from. Rebuilding a submenu while it's open loses the highlight.
    private var phoneMenuKey: String?
    private var cameraMenuKey: String?

    private let setup = SetupModel()
    private let imageStore = ImageSettingsStore()
    private let syncModel = SyncCheckModel()
    private let shelf = WindowShelf()

    private var devices: [AndroidDevice] = []
    private var selectedSerial: String?
    private var adbPath: String?
    private var discoveryError: String?
    private var extensionActive = false
    private var modeIndex = AppDelegate.coolModeIndex
    private let watcher = DeviceWatcher()
    private var devicesKnown = false
    private var environmentKnown = false
    private var environmentCheckInProgress = false
    private var environmentTimer: Timer?
    private var captureActivity: NSObjectProtocol?
    /// Stream drops before this time come from the Mac sleeping, not the cable.
    private var sleepQuietUntil = Date.distantPast
    private var lenses: [String: [CameraLens]] = [:]
    /// Phones whose lenses were listed, or are being listed, since they were plugged in.
    private var lensQueries: Set<String> = []
    /// A phone that start on plug-in leaves alone until it's unplugged.
    private var autoStartBlocked: String?

    // The current capture run. liveSince stays set across reconnects, for the clock and the lost state.
    private var runDevice: AndroidDevice?
    private var runModeIndex = 0
    private var runLensID: String?
    private var live = false
    private var liveSince: Date?
    private var stats: PhoneStats?
    private var torchOn = false
    private var switchingLens = false
    private var stopRequested = false
    /// A mode switch ends the old run without telling the user it stopped,
    private var restarting = false
    /// and starts the new one without a "live" notice.
    private var quietStart = false
    private var hotNotified = false
    private var cableLoose = false
    /// One plain line for the header: the last error or a warning.
    private var note: String?

    private var signalSources: [DispatchSourceSignal] = []
    private var window: NSWindow?
    private var clock: Timer?
    private var statusSymbol = ""

    // Written by the capture thread, read on main. At most one frame waits for the preview and one for the header.
    private let frameLock = NSLock()
    private var previewOpen = false
    private var pendingFrame: CVPixelBuffer?
    private var headerOpen = false
    private var headerFrame: CVPixelBuffer?
    private var headerShownAt: UInt64 = 0
    private var syncTest: SyncTest?
    private let headerInterval: UInt64 = {
        var info = mach_timebase_info()
        mach_timebase_info(&info)
        return 100_000_000 * UInt64(info.denom) / UInt64(info.numer)    // 0.1 s in mach ticks
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Prefs.register()
        let savedMode = UserDefaults.standard.string(forKey: Prefs.mode)
        if let index = CaptureMode.all.firstIndex(where: { $0.title == savedMode }) { modeIndex = index }
        statusItem.button?.image = NSImage(systemSymbolName: "camera", accessibilityDescription: appName)
        statusItem.button?.toolTip = appName
        for item in [menu, phoneMenu, modeMenu, cameraMenu] { item.autoenablesItems = false }
        menu.delegate = self

        let headerItem = NSMenuItem()
        headerItem.view = header
        menu.addItem(headerItem)
        menu.addItem(.separator())
        menu.addItem(mainAction)
        menu.addItem(coolDown)
        menu.addItem(.separator())
        phoneItem.submenu = phoneMenu; menu.addItem(phoneItem)
        modeItem.submenu = modeMenu; menu.addItem(modeItem)
        cameraItem.submenu = cameraMenu; menu.addItem(cameraItem)
        menu.addItem(imageItem)
        menu.addItem(syncItem)
        menu.addItem(.separator())
        menu.addItem(preview)
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit \(appName)", action: #selector(quitApp), keyEquivalent: "q"))
        for (index, mode) in CaptureMode.all.enumerated() {
            let item = NSMenuItem(title: mode.title, action: #selector(selectMode(_:)), keyEquivalent: "")
            item.tag = index
            modeMenu.addItem(item)
        }
        for item in menu.items + modeMenu.items + [zoomIn, zoomOut, flashlight] where item.action != nil { item.target = self }
        statusItem.menu = menu
        NSApp.mainMenu = makeKeyEquivalentMenu()

        capture.onStatus = { [weak self] message, _ in self?.captureStatus(message) }
        capture.onFrame = { [weak self] frame in self?.tap(frame) }
        capture.onLive = { [weak self] isLive in self?.captureLive(isLive) }
        capture.onPhoneStats = { [weak self] stats in self?.phoneStats(stats) }
        capture.macSharpness = Float(imageStore.macSharpness)
        imageStore.onChange = { [weak self] in
            guard let self else { return }
            self.capture.setImage(self.imageStore.phone)
            self.capture.macSharpness = Float(self.imageStore.macSharpness)
        }
        syncModel.begin = { [weak self] in self?.beginSyncTest() }
        setup.start = { [weak self] in
            guard let self else { return }
            if !self.capture.running { self.mainActionChosen() }
            self.shelf.close("setup")
        }

        if canNotify {
            let center = UNUserNotificationCenter.current()
            center.delegate = self
            let cool = UNNotificationAction(identifier: Self.coolAction, title: "Switch to 1080p · 30", options: [])
            center.setNotificationCategories([UNNotificationCategory(identifier: Self.heatCategory, actions: [cool],
                                                                     intentIdentifiers: [])])
        }
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(applicationLaunched(_:)),
                              name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        workspace.addObserver(self, selector: #selector(applicationQuit(_:)),
                              name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        workspace.addObserver(self, selector: #selector(systemWillSleep), name: NSWorkspace.willSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(systemDidWake), name: NSWorkspace.didWakeNotification, object: nil)
        for signalNumber in [SIGTERM, SIGINT] {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }
            source.resume()
            signalSources.append(source)
        }
        refreshUI()
        watcher.onChange = { [weak self] in self?.devicesChanged($0) }
        watcher.start()
        refreshEnvironment()
        // Platform tools and the OBS extension only need watching until they're there, or while Setup is open.
        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            guard let self, self.adbPath == nil || !self.extensionActive || self.shelf.isOpen("setup") else { return }
            self.refreshEnvironment()
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        environmentTimer = timer
    }

    func applicationWillTerminate(_ notification: Notification) {
        watcher.stop()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard capture.running else { return .terminateNow }
        stopRequested = true; restarting = false
        refreshUI()
        capture.stop { NSApp.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }

    // MARK: Menu

    func menuWillOpen(_ menu: NSMenu) {
        frameLock.lock()
        headerOpen = true
        headerShownAt = 0
        frameLock.unlock()
        refreshEnvironment()
        updateSetup()
        refreshUI()
        // The menu runs the loop in event tracking mode, so the clock goes in the common modes.
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.refreshUI() }
        RunLoop.main.add(timer, forMode: .common)
        clock = timer
    }

    func menuDidClose(_ menu: NSMenu) {
        frameLock.lock()
        headerOpen = false
        headerFrame = nil
        frameLock.unlock()
        // A live frame would be stale by the next open; a reconnecting one stays frozen under its veil.
        if live { header.clearPicture() }
        clock?.invalidate()
        clock = nil
    }

    private func refreshUI() {
        let running = capture.running
        let content = headerContent()
        header.update(content)
        let symbol = !running ? "camera" : live && !stopRequested ? "camera.fill" : "camera.badge.ellipsis"
        if symbol != statusSymbol {
            statusSymbol = symbol
            statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        }
        statusItem.button?.toolTip = "\(appName): \(content.status)"
        statusItem.button?.setAccessibilityLabel("\(appName), \(live && !stopRequested ? "live" : content.status)")
        if let view = window?.contentView as? PreviewView {
            view.setVeil(content.picture == nil
                ? .init(title: "No picture yet", text: "Finish setup from the menu bar, then start the webcam.")
                : content.picture?.veil)
        }

        if running {
            mainAction.title = "Stop Webcam"
            mainAction.isEnabled = !stopRequested
        } else if !setup.complete {
            mainAction.title = "Finish Setup…"
            mainAction.isEnabled = true
        } else {
            mainAction.title = "Start Webcam"
            mainAction.isEnabled = devices.contains { $0.serial == selectedSerial && $0.authorized }
        }
        coolDown.isHidden = !(running && !stopRequested && !restarting && stats?.isHot == true && runModeIndex != Self.coolModeIndex)

        phoneItem.isEnabled = !devices.isEmpty
        rebuildPhoneMenu()
        for item in modeMenu.items {
            item.state = item.tag == (running ? runModeIndex : modeIndex) ? .on : .off
            item.isEnabled = !running
        }
        cameraItem.isEnabled = live && !switchingLens
        rebuildCameraMenu()
        flashlight.state = torchOn ? .on : .off
        syncItem.isEnabled = live
        if syncModel.live != live { syncModel.live = live }
        preview.state = window?.isVisible == true ? .on : .off
    }

    private func headerContent() -> MenuHeaderView.Content {
        if capture.running, let device = runDevice {
            let mode = Self.shortTitle(CaptureMode.all[runModeIndex])
            var content = MenuHeaderView.Content(dot: .wait, status: "Starting", picture: nil,
                                                 model: device.model, stats: stats, note: note)
            if stopRequested {
                content.status = "Stopping"
                content.picture = .init(veil: .init(title: "Stopping the webcam"))
            } else if live, let since = liveSince {
                let time = Self.elapsed(since)
                content.dot = .live
                content.status = "Live \(time) · \(mode)"
                content.picture = .init(badge: "LIVE \(time)")
            } else if switchingLens {
                content.status = "Switching camera"
                content.picture = .init(veil: .init(title: "Switching camera on \(device.model)", text: "The camera stays open for your call."))
            } else if liveSince != nil {
                content.status = "Reconnecting"
                content.picture = .init(veil: .init(title: "Plug the phone back in",
                                                    text: "The camera stays open for your call and picks up again on its own."))
            } else {
                content.picture = .init(veil: .init(title: "Starting \(device.model)",
                                                    text: "The phone's camera can take a few seconds to open."))
            }
            return content
        }
        if setup.steps.isEmpty {
            return .init(dot: .off, status: "Checking setup", picture: nil, model: nil, stats: nil, note: note)
        }
        if let next = setup.nextStep {
            let lines = ["Next: \(next.next)", note].compactMap { $0 }
            return .init(dot: .off, status: "\(setup.doneCount) of \(setup.steps.count) setup steps done", picture: nil,
                         model: nil, stats: nil, note: lines.joined(separator: "\n"))
        }
        let model = devices.first { $0.serial == selectedSerial }?.model
        return .init(dot: .ready, status: "Ready",
                     picture: .init(veil: .init(title: model.map { "\($0) is ready" } ?? "Ready",
                                                text: "Start the webcam to see the picture.")),
                     model: model, stats: nil, note: note)
    }

    private func rebuildPhoneMenu() {
        let key = devices.map { "\($0.serial) \($0.status) \($0.model)" }.joined(separator: ",")
            + "|\(selectedSerial ?? "")|\(capture.running)"
        guard key != phoneMenuKey else { return }
        phoneMenuKey = key
        phoneMenu.removeAllItems()
        for (index, device) in devices.enumerated() {
            let title = device.authorized ? device.model : "\(device.model) (allow USB debugging)"
            let item = NSMenuItem(title: title, action: #selector(selectPhone(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.state = device.serial == selectedSerial ? .on : .off
            item.isEnabled = device.authorized && !capture.running
            phoneMenu.addItem(item)
        }
        if devices.isEmpty {
            let item = NSMenuItem(title: "No USB phone connected", action: nil, keyEquivalent: "")
            item.isEnabled = false
            phoneMenu.addItem(item)
        }
    }

    private func rebuildCameraMenu() {
        let list = runDevice.map { lensList($0.serial) } ?? []
        let checked = runLensID ?? "0"    // capture uses camera_id 0 when no lens is given
        let key = list.map(\.id).joined(separator: ",") + "|\(checked)"
        guard key != cameraMenuKey else { return }
        cameraMenuKey = key
        cameraMenu.removeAllItems()
        for (index, lens) in list.enumerated() {
            let item = NSMenuItem(title: lens.label, action: #selector(selectLens(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.state = lens.id == checked ? .on : .off
            cameraMenu.addItem(item)
        }
        if list.isEmpty {
            let item = NSMenuItem(title: "No lens list for this phone", action: nil, keyEquivalent: "")
            item.isEnabled = false
            cameraMenu.addItem(item)
        }
        cameraMenu.addItem(.separator())
        for item in [zoomIn, zoomOut, flashlight] { cameraMenu.addItem(item) }
    }

    private static func shortTitle(_ mode: CaptureMode) -> String {
        "\(mode.height >= 2160 ? "4K" : "\(mode.height)p") · \(mode.fps)"
    }

    private static func elapsed(_ since: Date) -> String {
        let s = max(0, Int(Date().timeIntervalSince(since)))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }

    // MARK: Discovery and setup

    /// Checks for platform tools and the OBS extension off main. Skipped while capturing.
    private func refreshEnvironment() {
        guard !capture.running, !environmentCheckInProgress else { return }
        environmentCheckInProgress = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let adb = try? ADB.executable().path
            let extensionActive = (try? VirtualCamera.findDevice()) != nil
            DispatchQueue.main.async {
                guard let self else { return }
                self.environmentCheckInProgress = false
                self.environmentKnown = true
                self.adbPath = adb
                self.extensionActive = extensionActive
                self.setupChanged()
            }
        }
    }

    private func devicesChanged(_ result: Result<[AndroidDevice], Error>) {
        devicesKnown = true
        switch result {
        case let .success(devices):
            self.devices = devices
            discoveryError = nil
            // The saved phone wins whenever it is plugged in; otherwise use any authorized one for now.
            let savedSerial = UserDefaults.standard.string(forKey: Prefs.serial)
            if devices.contains(where: { $0.serial == savedSerial }) {
                selectedSerial = savedSerial
            } else if !devices.contains(where: { $0.serial == selectedSerial }) {
                selectedSerial = devices.first(where: \.authorized)?.serial
            }
            if let blocked = autoStartBlocked, !devices.contains(where: { $0.serial == blocked }) {
                autoStartBlocked = nil
            }
        case let .failure(error):
            // A failed stream isn't an unplug, so it leaves autoStartBlocked alone.
            devices = []
            if discoveryError != error.localizedDescription { fputs("Phone discovery failed. \(error.logText)\n", stderr) }
            discoveryError = error.localizedDescription
        }
        lensQueries.formIntersection(Set(devices.map(\.serial)))
        for device in devices where device.authorized { queryLenses(device.serial) }
        setupChanged()
    }

    private func setupChanged() {
        updateSetup()
        autoStartIfNeeded()
        refreshUI()
        showSetupOnFirstRun()
    }

    private func updateSetup() {
        let obsOpen = !NSRunningApplication.runningApplications(withBundleIdentifier: Self.obsBundleID).isEmpty
        let phone = devices.first { $0.serial == selectedSerial } ?? devices.first
        let allowed = devices.first(where: \.authorized)
        let obsURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.obsBundleID)
        let steps = [
            SetupStep(id: "adb", title: "Android platform tools", done: adbPath != nil,
                      help: adbPath.map { "adb found in \(URL(fileURLWithPath: $0).deletingLastPathComponent().path)." }
                        ?? "Install them, for example with: brew install android-platform-tools",
                      next: "install Android platform tools.",
                      actions: [.copy("brew install android-platform-tools"),
                                .open("Get Platform Tools", URL(string: "https://developer.android.com/tools/releases/platform-tools")!)]),
            SetupStep(id: "extension", title: "OBS camera extension", done: extensionActive,
                      help: extensionActive ? "Installed and approved." : obsURL != nil
                        ? "Open OBS once, click Start Virtual Camera, then allow the extension in System Settings > General > Login Items & Extensions."
                        : "Install OBS Studio 30 or later from obsproject.com, open it once and click Start Virtual Camera.",
                      next: "turn on the OBS camera extension.",
                      actions: obsURL.map { [.open("Open OBS", $0), .loginItems] }
                        ?? [.open("Get OBS Studio", URL(string: "https://obsproject.com/download")!)]),
            SetupStep(id: "phone", title: "Phone connected over USB", done: phone != nil,
                      help: phone.map { "\($0.model) is plugged in." } ?? discoveryError ?? "Plug it in with a USB-C data cable.",
                      next: "plug in your phone with a USB cable."),
            SetupStep(id: "debugging", title: "Allow USB debugging", done: allowed != nil,
                      help: allowed.map { "Allowed on \($0.model)." }
                        ?? "On the phone, tap Allow when it asks. Turn on Developer options first if you haven't.",
                      next: "allow USB debugging on the phone."),
            SetupStep(id: "obs", title: "OBS Studio closed", done: !obsOpen,
                      help: obsOpen ? "Quit OBS Studio. It can stay installed." : "OBS can stay installed.",
                      next: "quit OBS Studio.",
                      actions: [.quit("Quit OBS", bundleID: Self.obsBundleID)]),
        ]
        if steps != setup.steps { setup.steps = steps }
    }

    private func showSetupOnFirstRun() {
        guard devicesKnown, environmentKnown, !UserDefaults.standard.bool(forKey: Prefs.setupShown) else { return }
        UserDefaults.standard.set(true, forKey: Prefs.setupShown)
        if !setup.complete { showSetup() }
    }

    /// Starts once when the saved phone shows up. After capture ends, waits for that phone to be unplugged.
    private func autoStartIfNeeded() {
        guard UserDefaults.standard.bool(forKey: Prefs.startOnPlugIn), !capture.running, setup.complete,
              let serial = UserDefaults.standard.string(forKey: Prefs.serial), serial != autoStartBlocked,
              let device = devices.first(where: { $0.serial == serial && $0.authorized }) else { return }
        autoStartBlocked = serial
        startCapture(device)
    }

    private func lensList(_ serial: String) -> [CameraLens] {
        if let list = lenses[serial] { return list }
        let data = UserDefaults.standard.data(forKey: Prefs.lenses(serial))
        let list = data.flatMap { try? JSONDecoder().decode([CameraLens].self, from: $0) } ?? []
        lenses[serial] = list
        return list
    }

    /// Lists the phone's lenses once per plug-in, off main, and keeps the last good list.
    private func queryLenses(_ serial: String) {
        guard !lensQueries.contains(serial) else { return }
        lensQueries.insert(serial)
        let capture = capture
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = Result { try capture.cameras(serial: serial) }
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case let .success(list) where !list.isEmpty:
                    self.lenses[serial] = list
                    if let data = try? JSONEncoder().encode(list) { UserDefaults.standard.set(data, forKey: Prefs.lenses(serial)) }
                case .success: break
                case let .failure(error):
                    self.lensQueries.remove(serial)
                    fputs("Could not list the phone's cameras. \(error.logText)\n", stderr)
                }
                self.refreshUI()
            }
        }
    }

    // MARK: Capture

    private func startCapture(_ device: AndroidDevice, quiet: Bool = false) {
        guard !capture.running else { return }
        let saved = UserDefaults.standard.string(forKey: Prefs.lensID)
        runLensID = lensList(device.serial).contains { $0.id == saved } ? saved : nil
        runDevice = device
        runModeIndex = modeIndex
        live = false; liveSince = nil; stats = nil; torchOn = false
        switchingLens = false; stopRequested = false; cableLoose = false; hotNotified = false
        quietStart = quiet
        // Asked here rather than at launch, so the prompt comes when there's something to say.
        if UserDefaults.standard.bool(forKey: Prefs.notifications) { requestNotificationPermission() }
        note = nil
        UserDefaults.standard.set(device.serial, forKey: Prefs.serial)
        capture.macSharpness = Float(imageStore.macSharpness)
        // Keeps App Nap from throttling the frame path while no window of ours is on screen. Idle sleep stays the
        // receiving app's call: a call or a recording holds its own assertion.
        captureActivity = captureActivity ?? ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
            reason: "Sending the phone's camera to the virtual camera")
        capture.start(device: device, mode: CaptureMode.all[modeIndex], lensID: runLensID, image: imageStore.phone)
        refreshUI()
    }

    /// onStatus: the header tells the running states itself, so only the final status matters here.
    private func captureStatus(_ message: String) {
        guard !capture.running, let device = runDevice else { refreshUI(); return }
        let userStopped = stopRequested, quiet = restarting
        runDevice = nil
        if let activity = captureActivity { ProcessInfo.processInfo.endActivity(activity); captureActivity = nil }
        live = false; liveSince = nil; stats = nil; torchOn = false
        // restarting stays set until the restart's stop completion runs.
        switchingLens = false; stopRequested = false; quietStart = false; cableLoose = false
        autoStartBlocked = device.serial
        endSyncTest(reason: "The webcam stopped.")
        header.clearPicture()
        (window?.contentView as? PreviewView)?.clear()
        if userStopped || quiet {
            // Whoever stopped it knows; what's left in Notification Center is out of date.
            withdraw([.run, .cable, .heat])
        } else {
            note = message
            withdraw([.cable, .heat])
            notify(.run, "Webcam stopped", message)
        }
        refreshUI()
    }

    private func captureLive(_ isLive: Bool) {
        guard capture.running, runDevice != nil else { return }
        if isLive {
            if cableLoose {
                notify(.cable, "Phone reconnected", "The webcam is live again.")
            } else if liveSince == nil && !quietStart {
                notify(.run, "Webcam is live", "Pick OBS Virtual Camera in your call app.")
            }
            live = true
            liveSince = liveSince ?? Date()
            if switchingLens, let lens = runLensID { UserDefaults.standard.set(lens, forKey: Prefs.lensID) }
            cableLoose = false; switchingLens = false; quietStart = false
        } else {
            live = false
            torchOn = false
            endSyncTest(reason: "The picture stopped.")
            // capture also reports false when it ends, just before its final status, so wait a moment before calling it a loose cable.
            if !switchingLens, !stopRequested, !restarting, liveSince != nil { checkLooseCable(after: 1.5) }
        }
        refreshUI()
    }

    /// Calls it a loose cable if the picture is still gone after the delay. Drops around Mac sleep wait out the quiet time.
    private func checkLooseCable(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.capture.running, self.liveSince != nil, !self.live, !self.cableLoose,
                  !self.switchingLens, !self.stopRequested, !self.restarting else { return }
            let quiet = self.sleepQuietUntil.timeIntervalSinceNow
            if quiet > 0 { self.checkLooseCable(after: min(quiet, 20)); return }
            self.cableLoose = true
            self.notify(.cable, "Phone disconnected", "Plug it back in. Your call keeps the camera and picks up again on its own.")
            self.refreshUI()
        }
    }

    @objc private func systemWillSleep() { sleepQuietUntil = .distantFuture }

    /// The stream reconnects after a wake, so give it time before telling anyone the phone is gone.
    @objc private func systemDidWake() { sleepQuietUntil = Date().addingTimeInterval(20) }

    private func phoneStats(_ newStats: PhoneStats) {
        guard capture.running else { return }
        stats = newStats
        if newStats.isHot && !hotNotified {
            hotNotified = true
            let cool = runModeIndex == Self.coolModeIndex
            notify(.heat, "Phone at \(MenuHeaderView.temperature.string(from: Measurement(value: newStats.temperatureC, unit: UnitTemperature.celsius)))",
                   cool ? "Take it out of its case or stop the webcam for a while." : "Switching to 1080p · 30 keeps it cooler.",
                   category: cool ? nil : Self.heatCategory)
        }
        refreshUI()
    }

    @objc private func mainActionChosen() {
        if capture.running {
            stopRequested = true; restarting = false
            capture.stop()
            refreshUI()
            return
        }
        guard setup.complete else { showSetup(); return }
        guard let device = devices.first(where: { $0.serial == selectedSerial && $0.authorized }) else { return }
        if !NSRunningApplication.runningApplications(withBundleIdentifier: Self.obsBundleID).isEmpty {
            note = "Quit OBS before starting this camera."
            updateSetup()
            refreshUI()
            return
        }
        startCapture(device)
    }

    @objc private func switchToCoolMode() {
        modeIndex = Self.coolModeIndex
        UserDefaults.standard.set(CaptureMode.all[modeIndex].title, forKey: Prefs.mode)
        guard capture.running, !stopRequested, !restarting, let device = runDevice else { refreshUI(); return }
        restarting = true
        capture.stop { [weak self] in
            // Stop or Quit during the switch clears restarting and cancels the restart.
            guard let self, self.restarting else { return }
            self.restarting = false
            self.startCapture(device, quiet: true)
        }
        refreshUI()
    }

    @objc private func selectPhone(_ sender: NSMenuItem) {
        selectedSerial = devices[sender.tag].serial
        UserDefaults.standard.set(selectedSerial, forKey: Prefs.serial)
        refreshUI()
    }

    @objc private func selectMode(_ sender: NSMenuItem) {
        modeIndex = sender.tag
        UserDefaults.standard.set(CaptureMode.all[modeIndex].title, forKey: Prefs.mode)
        refreshUI()
    }

    @objc private func selectLens(_ sender: NSMenuItem) {
        guard let device = runDevice else { return }
        let list = lensList(device.serial)
        let lens = list[sender.tag]
        // Saved once the new lens is live, so a lens that can't run this mode isn't remembered.
        guard lens.id != (runLensID ?? "0") else { return }
        runLensID = lens.id
        switchingLens = true
        capture.switchLens(lens.id)
        refreshUI()
    }

    @objc private func zoomInChosen() { capture.zoomIn() }
    @objc private func zoomOutChosen() { capture.zoomOut() }

    @objc private func toggleFlashlight() {
        torchOn.toggle()
        capture.setTorch(torchOn)
        refreshUI()
    }

    @objc private func applicationLaunched(_ notification: Notification) {
        let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        guard app?.bundleIdentifier == Self.obsBundleID else { return }
        if capture.running { note = "OBS opened. Don't start its virtual camera while this one runs." }
        updateSetup()
        refreshUI()
    }

    @objc private func applicationQuit(_ notification: Notification) {
        let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        guard app?.bundleIdentifier == Self.obsBundleID else { return }
        if !capture.running, note == "Quit OBS before starting this camera." { note = nil }
        updateSetup()
        refreshUI()
    }

    // MARK: Windows

    private func showSetup() {
        updateSetup()
        shelf.show("setup", title: "Set Up \(appName)") { SetupView(model: setup) }
    }

    @objc private func showImageSettings() {
        shelf.show("image", title: "Image Settings") { ImageSettingsView(store: imageStore) }
    }

    @objc private func showSettings() {
        shelf.show("settings", title: "\(appName) Settings") {
            SettingsView(onNotificationsChange: { [weak self] on in if on { self?.requestNotificationPermission() } })
        }
    }

    @objc private func showSyncCheck() {
        syncModel.live = live
        shelf.show("sync", title: "Check Audio Sync", onClose: { [weak self] in
            self?.endSyncTest(reason: nil)
            self?.syncModel.phase = .idle
        }) { SyncCheckView(model: syncModel) }
    }

    private func beginSyncTest() {
        guard live else { return }
        endSyncTest(reason: nil)
        let test = SyncTest()
        let id = ObjectIdentifier(test)
        frameLock.lock()
        syncTest = test
        frameLock.unlock()
        syncModel.phase = .listening
        test.start { [weak self] result in
            guard let self else { return }
            self.frameLock.lock()
            let current = self.syncTest.map { ObjectIdentifier($0) } == id
            if current { self.syncTest = nil }
            self.frameLock.unlock()
            guard current else { return }
            switch result {
            case let .success(measured): self.syncModel.phase = .result(SyncCheckView.describe(measured.videoLagMs))
            case let .failure(error): self.syncModel.phase = .failed(error.localizedDescription)
            }
        }
    }

    /// Cancels a running sync test. reason, when given, is shown in its window.
    private func endSyncTest(reason: String?) {
        frameLock.lock()
        let test = syncTest
        syncTest = nil
        frameLock.unlock()
        guard let test else { return }
        test.cancel()
        syncModel.phase = reason.map { .failed($0) } ?? .idle
    }

    @objc private func togglePreview() {
        if let window, window.isVisible { window.close(); return }
        let view = PreviewView(frame: NSRect(x: 0, y: 0, width: 960, height: 540), titleSize: 17, textSize: 14)
        let previewWindow = NSWindow(contentRect: view.frame, styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                     backing: .buffered, defer: false)
        previewWindow.title = "\(appName) Preview"
        previewWindow.contentView = view
        // Every capture mode is 16:9, so the window keeps that shape instead of growing black bars.
        previewWindow.contentAspectRatio = NSSize(width: 16, height: 9)
        previewWindow.contentMinSize = NSSize(width: 320, height: 180)
        previewWindow.isReleasedWhenClosed = false
        previewWindow.delegate = self
        if !previewWindow.setFrameUsingName("Preview") { previewWindow.center() }
        previewWindow.setFrameAutosaveName("Preview")
        window = previewWindow
        setPreviewOpen(true)
        bringForward(previewWindow)
        refreshUI()
    }

    func windowWillClose(_ notification: Notification) {
        setPreviewOpen(false)
        window = nil
        refreshUI()
    }

    private func setPreviewOpen(_ open: Bool) {
        frameLock.lock()
        previewOpen = open
        pendingFrame = nil
        frameLock.unlock()
    }

    // MARK: Frames

    /// Called on the capture thread. Keeps only the newest frame for the preview and, at about 10 fps while
    /// the menu is open, for the header; frames that arrive before main runs replace it instead of queueing more work.
    private func tap(_ frame: CVPixelBuffer) {
        let now = mach_absolute_time()
        frameLock.lock()
        let test = syncTest
        var previewHop = false, headerHop = false
        if previewOpen {
            previewHop = pendingFrame == nil
            pendingFrame = frame
        }
        if headerOpen, now &- headerShownAt >= headerInterval {
            headerShownAt = now
            headerHop = headerFrame == nil
            headerFrame = frame
        }
        frameLock.unlock()
        test?.addFrame(frame, hostTime: now)
        if previewHop { DispatchQueue.main.async { [weak self] in self?.showPendingFrame() } }
        if headerHop { DispatchQueue.main.async { [weak self] in self?.showHeaderFrame() } }
    }

    private func showPendingFrame() {
        frameLock.lock()
        let frame = pendingFrame
        pendingFrame = nil
        frameLock.unlock()
        guard let frame, let view = window?.contentView as? PreviewView else { return }
        do { try view.show(frame) }
        catch {
            fputs("Preview failed. \(error.logText)\n", stderr)
            note = "The preview couldn't show the picture. Close it and open it again."
            refreshUI()
        }
    }

    private func showHeaderFrame() {
        frameLock.lock()
        let frame = headerFrame
        headerFrame = nil
        frameLock.unlock()
        guard let frame, live else { return }
        header.show(frame)
    }

    // MARK: Notifications

    /// UNUserNotificationCenter needs a bundled app; a bare `swift run` binary skips notifications.
    private var canNotify: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    private func requestNotificationPermission() {
        guard canNotify else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, error in
            if let error { fputs("Notification permission failed. \(error.localizedDescription)\n", stderr) }
        }
    }

    /// What a notification is about. Each topic keeps one notification, so a newer one takes the last one's place.
    /// Ids are "<topic>.<uuid>": macOS shows a request that reuses a delivered id as a silent update, with no banner.
    private enum Notice: String {
        case run        // live, stopped
        case cable      // disconnected, reconnected
        case heat
    }
    private static let heatCategory = "heat"
    private static let coolAction = "switch-to-cool"

    private func notify(_ notice: Notice, _ title: String, _ body: String, category: String? = nil) {
        guard canNotify, UserDefaults.standard.bool(forKey: Prefs.notifications) else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.threadIdentifier = "webcam"
        if let category { content.categoryIdentifier = category }
        let request = UNNotificationRequest(identifier: "\(notice.rawValue).\(UUID().uuidString)", content: content, trigger: nil)
        withdraw([notice]) {
            UNUserNotificationCenter.current().add(request) { error in
                if let error { fputs("Notification failed. \(error.localizedDescription)\n", stderr) }
            }
        }
    }

    private func withdraw(_ notices: [Notice], then next: @escaping () -> Void = {}) {
        guard canNotify else { return }
        let center = UNUserNotificationCenter.current()
        center.getDeliveredNotifications { delivered in
            let ids = delivered.map(\.request.identifier).filter { id in notices.contains { id.hasPrefix("\($0.rawValue).") } }
            center.removeDeliveredNotifications(withIdentifiers: ids)
            next()
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }

    /// A click opens the menu, where the status and every control are; the heat warning's button switches modes.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let action = response.actionIdentifier
        DispatchQueue.main.async { [weak self] in
            switch action {
            case Self.coolAction: self?.switchToCoolMode()
            case UNNotificationDefaultActionIdentifier: self?.statusItem.button?.performClick(nil)
            default: break
            }
            completionHandler()
        }
    }

    @objc private func quitApp() {
        environmentTimer?.invalidate()
        NSApp.terminate(nil)
    }
}

@main
enum AndroidWebcamApp {
    static func main() {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            if arguments == ["--diagnose"] { try diagnose(); return }
            if arguments.count == 2, arguments[0] == "--probe-hevc" { try probeHEVC(arguments[1]); return }
            guard arguments.isEmpty else { throw WebcamError(message: "Use --diagnose or --probe-hevc <file> for a headless check.") }
            let app = NSApplication.shared
            let delegate = AppDelegate()
            app.setActivationPolicy(.accessory)
            app.delegate = delegate
            withExtendedLifetime(delegate) { app.run() }
        } catch { fputs("\(error.logText)\n", stderr); exit(1) }
    }

    static func diagnose() throws {
        let devices = try ADB.devices()
        var driver = false
        var driverError: String?
        do { _ = try VirtualCamera.findDevice(); driver = true }
        catch { driverError = error.logText }
        let report: [String: Any] = [
            "usb_devices": devices.map { ["serial": $0.serial, "model": $0.model, "status": $0.status] },
            "scrcpy_server_version": ScrcpyServer.version, "bundled_server": ADB.serverURL != nil,
            "adb": (try? ADB.executable().path) ?? "",
            "obs_camera_installed": driver, "obs_camera_error": driverError ?? "",
            "hevc_hardware_supported": VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC),
            "camera_started": false, "preview_started": false
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    static func probeHEVC(_ path: String) throws {
        let units = AnnexB.units(try Data(contentsOf: URL(fileURLWithPath: path)))
        guard units.contains(where: { AnnexB.nalType($0) == 35 }) else {
            throw WebcamError(message: "The probe sample needs HEVC access-unit delimiters.")
        }
        let lock = NSLock()
        var count = 0, width = 0, height = 0
        var failure: Error?
        let decoder = HEVCDecoder(onFrame: { frame in
            lock.lock(); defer { lock.unlock() }
            count += 1; width = CVPixelBufferGetWidth(frame); height = CVPixelBufferGetHeight(frame)
        }, onError: { error in lock.lock(); failure = error; lock.unlock() })
        defer { decoder.finish() }
        var packet = Data(), hasPicture = false
        var timestamp: Int64 = 0
        func flush() throws {
            if hasPicture { try decoder.decode(packet, pts: timestamp); timestamp += 16_667 }
            packet = Data(); hasPicture = false
        }
        for unit in units {
            if AnnexB.nalType(unit) == 35 { try flush() }
            packet.append(contentsOf: [0, 0, 0, 1]); packet.append(unit)
            if AnnexB.nalType(unit) < 32 { hasPicture = true }
        }
        try flush()
        decoder.finish()
        if let failure { throw failure }
        guard count > 0 else { throw WebcamError(message: "The hardware decoder produced no frames.") }
        print("Decoded \(count) frames at \(width)x\(height); hardware=\(decoder.hardwareAccelerated). No camera output or preview was started.")
    }
}
