import AppKit
import AVFoundation
import CoreMedia
import UserNotifications
import VideoToolbox

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate, UNUserNotificationCenterDelegate {
    private static let obsBundleID = "com.obsproject.obs-studio"
    private static let coolModeIndex = CaptureMode.all.firstIndex { $0.title == "1080p / 30 fps" } ?? 0

    private let capture = CaptureController()
    /// The dev automation instance has none: a hidden item would still be saved in the app's real defaults.
    private let statusItem: NSStatusItem? = DevMode.isOn ? nil : NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let header = MenuHeaderView()
    private let mainAction = NSMenuItem(title: "Start Webcam", action: #selector(mainActionChosen), keyEquivalent: "s")
    private let coolDown = NSMenuItem(title: "Switch to 1080p · 30 to cool down", action: #selector(switchToCoolMode), keyEquivalent: "")
    private let phoneItem = NSMenuItem(title: "Phone", action: nil, keyEquivalent: "")
    private let modeItem = NSMenuItem(title: "Capture Mode", action: nil, keyEquivalent: "")
    private let orientationItem = NSMenuItem(title: "Orientation", action: nil, keyEquivalent: "")
    private let cameraItem = NSMenuItem(title: "Camera", action: nil, keyEquivalent: "")
    private let controlsItem = NSMenuItem(title: "Live Controls…", action: #selector(showLiveControls), keyEquivalent: "")
    private let syncItem = NSMenuItem(title: "Check Audio Sync…", action: #selector(showSyncCheck), keyEquivalent: "")
    private let preview = NSMenuItem(title: "Show Preview", action: #selector(togglePreview), keyEquivalent: "p")
    private let zoomIn = NSMenuItem(title: "Zoom In", action: #selector(zoomInChosen), keyEquivalent: "+")
    private let zoomOut = NSMenuItem(title: "Zoom Out", action: #selector(zoomOutChosen), keyEquivalent: "-")
    private let flashlight = NSMenuItem(title: "Flashlight", action: #selector(toggleFlashlight), keyEquivalent: "l")
    private let phoneMenu = NSMenu()
    private let modeMenu = NSMenu()
    private let orientationMenu = NSMenu()
    private let cameraMenu = NSMenu()
    // What each submenu was last built from. Rebuilding a submenu while it's open loses the highlight.
    private var phoneMenuKey: String?
    private var cameraMenuKey: String?

    private let wirelessConnector = WirelessConnector()
    /// The Connect over Wi-Fi window's pairing, while it's open.
    private var pairing: WirelessPairing?
    private let setup = SetupModel()
    private let imageStore = ImageSettingsStore()
    private lazy var controls = LiveControlsPanel(store: imageStore)
    /// Ticks the panel's live clock while it's open, as the menu's clock does while the menu is.
    private var controlsClock: Timer?
    private let syncModel = SyncCheckModel()
    private let settingsModel = SettingsModel()
    /// ⌃⌥⌘L opens and closes Live Controls from any app. The dev instance records it instead of registering it.
    private lazy var hotkey = GlobalHotkey { [weak self] in self?.toggleLiveControls() }
    private let shelf = WindowShelf()

    private var devices: [AndroidDevice] = []
    private var selectedSerial: String?
    private var adbPath: String?
    private var discoveryError: String?
    private var extensionActive = false
    private var relaunching = false
    /// The copy before a relaunch for the OBS extension had Setup open, so this one reopens it once (see relaunchForExtension).
    private var reopenSetup = ProcessInfo.processInfo.environment[AppDelegate.showSetupKey] == "1"
    private static let showSetupKey = "ANDROID_WEBCAM_SHOW_SETUP"
    private var modeIndex = AppDelegate.coolModeIndex
    private let watcher = DeviceWatcher()
    private var devicesKnown = false
    private var environmentKnown = false
    private var environmentCheckInProgress = false
    /// Android phones on USB, debugging or not, from the last environment check.
    private var usbPhones: [USBPhone] = []
    /// The user said the phone is plugged in though nothing shows on USB (some hubs and cables hide it).
    private var phoneNotShowingUp = false
    /// Set Up for Me was clicked: Setup downloads, installs and turns on OBS's camera by itself.
    private var setUpForMe = false
    /// macOS has OBS's camera on, though this process may not see it until it reopens (see relaunchForExtension).
    private var cameraApproved = false
    private var environmentTimer: Timer?
    private var captureActivity: NSObjectProtocol?
    /// Stream drops before this time come from the Mac sleeping, not the cable.
    private var sleepQuietUntil = Date.distantPast
    /// When the Mac last went to sleep; a phone gone before then wasn't dropped by the sleep.
    private var sleptAt = Date.distantPast
    /// Every serial adb has listed this run, for taking them out of Copy Diagnostics.
    private var seenSerials: Set<String> = []
    /// Which Copy Diagnostics press the "Copied" reset belongs to.
    private var copyToken = 0
    private var lenses: [String: [CameraLens]] = [:]
    /// Phones whose lenses were listed, or are being listed, since they were plugged in.
    private var lensQueries: Set<String> = []
    /// Phones whose own names were asked for this run; phoneNames keeps the answers.
    private var nameQueries: Set<String> = []
    private var phoneNames: [String: String] = [:]
    /// A phone that start on plug-in leaves alone until it's unplugged.
    private var autoStartBlocked: String?
    /// How long that phone has been gone from adb's list, so a blink around a Mac wake doesn't count as an unplug.
    private var blockedMissingSince: Date?
    /// Start on plug-in fires once per appearance of the saved phone, and once at launch; menus and settings never arm it.
    private var autoStartArmed = true
    /// How long the saved phone has been gone from adb's list. Like blockedMissingSince, a blink isn't a plug-in.
    private var savedMissingSince: Date?
    /// adb's last good list. devices empties when the stream fails; this doesn't.
    private var listedDevices: [AndroidDevice] = []
    /// The note a failed lens switch left, cleared by the next lens pick.
    private var lensNote: String?

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
    private var devControl: DevControl?
    private var window: NSWindow?
    private var clock: Timer?
    private var statusSymbol = ""

    // Written by the capture thread, read on main. At most one frame waits for the preview and one for the header.
    private let frameLock = NSLock()
    private var previewOpen = false
    private var pendingFrame: CVPixelBuffer?
    private var headerOpen = false
    private var headerFrame: CVPixelBuffer?
    private var controlsOpen = false
    private var controlsFrame: CVPixelBuffer?
    private var headerShownAt: UInt64 = 0
    private var previewFailed = false
    private static let previewFailedNote = "The preview couldn't show the picture. Close it and open it again."
    private var syncTest: SyncTest?
    private let headerInterval: UInt64 = {
        var info = mach_timebase_info()
        mach_timebase_info(&info)
        return 100_000_000 * UInt64(info.denom) / UInt64(info.numer)    // 0.1 s in mach ticks
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Prefs.register()
        // Setup opens by itself on a first run and after the relaunch for OBS's camera, once the first checks are in.
        // Ask to come forward now, while the user's open (or the old copy's handoff) is fresh, so it opens in front.
        if !DevMode.isOn, reopenSetup || !Prefs.defaults.bool(forKey: Prefs.setupShown) {
            // A regular app (Dock icon, a place in ⌘-Tab) is let to the front more readily than a menu bar one.
            setupInDock(true)
            activateApp()
        }
        let savedMode = Prefs.defaults.string(forKey: Prefs.mode)
        if let index = CaptureMode.all.firstIndex(where: { $0.title == savedMode }) { modeIndex = index }
        statusItem?.button?.image = NSImage(systemSymbolName: "camera", accessibilityDescription: appName)
        statusItem?.button?.toolTip = appName
        for item in [menu, phoneMenu, modeMenu, orientationMenu, cameraMenu] { item.autoenablesItems = false }
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
        orientationItem.submenu = orientationMenu; menu.addItem(orientationItem)
        cameraItem.submenu = cameraMenu; menu.addItem(cameraItem)
        menu.addItem(controlsItem)
        menu.addItem(syncItem)
        menu.addItem(.separator())
        menu.addItem(preview)
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit \(appName)", action: #selector(quitApp), keyEquivalent: "q")
        menu.addItem(quitItem)
        let symbols: [(NSMenuItem, [String])] = [
            (coolDown, ["thermometer.snowflake", "snowflake"]), (phoneItem, ["smartphone", "iphone"]),
            (modeItem, ["film"]), (orientationItem, ["rectangle.portrait.rotate", "rotate.right"]), (cameraItem, ["camera.aperture", "camera"]),
            (controlsItem, ["slider.horizontal.3"]),
            (syncItem, ["waveform"]), (preview, ["macwindow"]), (settingsItem, ["gearshape"]), (quitItem, ["power"]),
            (zoomIn, ["plus.magnifyingglass"]), (zoomOut, ["minus.magnifyingglass"]), (flashlight, ["flashlight.on.fill"]),
        ]
        for (item, names) in symbols { item.image = Self.symbol(names) }
        for (index, mode) in CaptureMode.all.enumerated() {
            let item = NSMenuItem(title: mode.title, action: #selector(selectMode(_:)), keyEquivalent: "")
            item.tag = index
            modeMenu.addItem(item)
        }
        for (index, orientation) in PictureOrientation.allCases.enumerated() {
            let item = NSMenuItem(title: orientation.title, action: #selector(selectOrientation(_:)), keyEquivalent: "")
            item.tag = index
            orientationMenu.addItem(item)
        }
        for item in menu.items + modeMenu.items + orientationMenu.items + [zoomIn, zoomOut, flashlight] where item.action != nil { item.target = self }
        statusItem?.menu = menu
        NSApp.mainMenu = makeKeyEquivalentMenu()

        capture.onStatus = { [weak self] message, _ in self?.captureStatus(message) }
        capture.onFrame = { [weak self] frame in self?.tap(frame) }
        capture.onLive = { [weak self] isLive in self?.captureLive(isLive) }
        capture.onLensFallback = { [weak self] good, failed in self?.lensFellBack(to: good, from: failed) }
        capture.onPhoneStats = { [weak self] stats in self?.phoneStats(stats) }
        capture.macSharpness = Float(imageStore.macSharpness)
        imageStore.onChange = { [weak self] in
            guard let self else { return }
            self.capture.setImage(self.imageStore.phone)
            self.capture.macSharpness = Float(self.imageStore.macSharpness)
        }
        capture.pictureOrientation = imageStore.orientation
        imageStore.onOrientationChange = { [weak self] in
            guard let self else { return }
            self.capture.pictureOrientation = self.imageStore.orientation
            self.refreshUI()
        }
        syncModel.begin = { [weak self] in self?.beginSyncTest() }
        syncModel.startWebcam = { [weak self] in
            guard let self, !self.capture.running else { return }
            self.mainActionChosen()
        }
        setup.start = { [weak self] in
            guard let self else { return }
            if !self.capture.running { self.mainActionChosen() }
            self.shelf.close("setup")
        }
        // A finished download shows up in Setup at once rather than at the next 3 s check.
        setup.platformTools.onInstalled = { [weak self] in self?.refreshEnvironment() }
        setup.obs.onInstalled = { [weak self] in self?.refreshEnvironment() }
        setup.setUpForMe = { [weak self] in
            guard let self else { return }
            self.setUpForMe = true
            self.setupChanged()
        }
        setup.phoneNotShowingUp = { [weak self] in
            guard let self else { return }
            self.phoneNotShowingUp = true
            self.setupChanged()
        }
        settingsModel.notificationsChanged = { [weak self] on in if on { self?.requestNotificationPermission() } }
        settingsModel.shortcutChanged = { [weak self] on in self?.setShortcut(on) }
        settingsModel.copyDiagnostics = { [weak self] in self?.copyDiagnostics() }
        settingsModel.runSetup = { [weak self] in self?.showSetup() }
        settingsModel.wirelessChanged = { [weak self] _ in self?.wirelessChanged() }
        settingsModel.connectOverWiFi = { [weak self] in self?.showPairing() }
        setShortcut(Prefs.defaults.bool(forKey: Prefs.liveControlsShortcut))
        wirelessConnector.listed = { [weak self] in self?.listedDevices ?? [] }
        if Wireless.enabled { wirelessConnector.start() }

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
            // A run loop block, not a main-queue one: Quit while capturing waits for a main-queue completion.
            source.setEventHandler { RunLoop.main.perform { NSApp.terminate(nil) }; CFRunLoopWakeUp(CFRunLoopGetMain()) }
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
        if DevMode.isOn { startDevControl() }
    }

    /// Opens the dev automation socket. Only a launch with ANDROID_WEBCAM_DEV_DIR gets here.
    private func startDevControl() {
        let control = DevControl(hooks: DevHooks(
            menu: menu,
            // Checks the environment in place, so a reply never shows the state from before the last change.
            refresh: { [weak self] in
                guard let self else { return }
                if !self.capture.running {
                    let adb = try? ADB.executable().path
                    let extensionState = Installer.cameraState()
                    self.environmentKnown = true
                    self.adbPath = adb
                    self.extensionActive = extensionState == .ready
                }
                self.setupChanged()
            },
            ready: { [weak self] in self?.devicesKnown == true && self?.environmentKnown == true },
            open: { [weak self] name in
                guard let self else { return false }
                switch name {
                case "setup": self.showSetup()
                case "settings": self.showSettings()
                case LiveControlsPanel.id: self.showLiveControls()
                case "sync": self.showSyncCheck()
                case "preview": if self.window == nil { self.togglePreview() }
                default: return false
                }
                return true
            },
            close: { [weak self] name in
                switch name {
                case "preview": self?.window?.close()
                case LiveControlsPanel.id: self?.controls.close()
                default: self?.shelf.close(name)
                }
            },
            hotkey: { [weak self] in self?.toggleLiveControls() },
            syncPhase: { [weak self] phase, meter in
                self?.syncModel.meter = meter
                self?.syncModel.phase = phase
            }))
        control.start()
        devControl = control
    }

    func applicationWillTerminate(_ notification: Notification) {
        watcher.stop()
        // An OBS image left mounted for the drag, or mounted by an install that's still running.
        Installer.cleanUp()
        if DevMode.isOn { devControl?.stop(); DevMode.cleanUp() }
    }

    // Opening the running app again (Finder, Spotlight, Raycast) is the way in when the status item
    // is behind the notch or the menu bar is hidden: open the menu if the icon is reachable, else Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // While Setup is open the app has a Dock icon, and its click means "take me to Setup".
        if let window = shelf.window("setup") {
            bringForward(window)
        } else if statusButtonReachable() {
            statusItem?.button?.performClick(nil)
        } else {
            showSettings()
        }
        return false
    }

    private func statusButtonReachable() -> Bool {
        guard let button = statusItem?.button, let window = button.window, window.isVisible,
              window.occlusionState.contains(.visible) else { return false }
        let frame = window.frame
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: frame.midX, y: frame.midY)) }),
              screen.frame.contains(frame) else { return false }
        // A notch leaves two usable strips of menu bar; the icon must sit in one of them.
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            let x = frame.midX
            return x <= screen.frame.minX + left.width || x >= screen.frame.maxX - right.width
        }
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard capture.running else { return .terminateNow }
        stopRequested = true; restarting = false
        refreshUI()
        capture.stop {
            self.withdraw([.run, .cable, .heat]) { DispatchQueue.main.async { NSApp.reply(toApplicationShouldTerminate: true) } }
        }
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
            statusItem?.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        }
        statusItem?.button?.toolTip = "\(appName): \(content.status)"
        statusItem?.button?.setAccessibilityLabel("\(appName), \(live && !stopRequested ? "live" : content.status)")
        // Before setup is done there's no phone to show; the menu and Live Controls offer Finish Setup… right there.
        let veil: PreviewView.Veil? = content.picture == nil
            ? .init(title: setup.steps.isEmpty ? "No picture yet" : "Finish setup to see the picture")
            : content.picture?.veil
        (window?.contentView as? PreviewView)?.setVeil(veil)

        let main: (title: String, symbol: String)
        if running {
            main = ("Stop Webcam", "stop.fill")
            mainAction.isEnabled = !stopRequested
        } else if !setup.complete {
            main = ("Finish Setup…", "checklist")
            mainAction.isEnabled = true
        } else {
            main = ("Start Webcam", "play.fill")
            mainAction.isEnabled = devices.contains { $0.serial == selectedSerial && $0.authorized }
        }
        if mainAction.title != main.title || mainAction.image == nil {
            mainAction.title = main.title
            mainAction.image = Self.symbol([main.symbol])
        }
        coolDown.isHidden = !(running && live && !stopRequested && !restarting && stats?.isHot == true && runModeIndex != Self.coolModeIndex)

        phoneItem.isEnabled = true    // Connect a Phone over Wi-Fi… is always there
        rebuildPhoneMenu()
        for item in modeMenu.items {
            item.state = item.tag == (running ? runModeIndex : modeIndex) ? .on : .off
            item.isEnabled = !running
        }
        for item in orientationMenu.items {
            item.state = PictureOrientation.allCases[item.tag] == imageStore.orientation ? .on : .off
        }
        cameraItem.isEnabled = live && !switchingLens
        rebuildCameraMenu()
        flashlight.state = torchOn ? .on : .off
        // The window can start the webcam itself, so it opens whether or not the webcam is live.
        if syncModel.live != live { syncModel.live = live }
        let busy: String? = !running || live ? nil
            : stopRequested ? "Stopping the webcam"
            : liveSince != nil ? "Reconnecting to the phone" : "Starting the webcam"
        if syncModel.busy != busy { syncModel.busy = busy }
        preview.state = window != nil ? .on : .off
        // Kept current while closed too, so the panel opens on the right state instead of animating into it.
        updateControls(content, veil: veil)
    }

    /// The first of these SF Symbols this macOS has, for a menu item.
    private static func symbol(_ names: [String]) -> NSImage? {
        for name in names {
            if let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) { return image }
        }
        return nil
    }

    /// The Live Controls panel shows what the header does, plus the lens list and the flashlight.
    private func updateControls(_ content: MenuHeaderView.Content, veil: PreviewView.Veil?) {
        let running = capture.running
        let shownLensNote = note != nil && note == lensNote ? note : nil
        let serial = runDevice?.serial ?? selectedSerial
        let lenses = serial.map(lensList) ?? []
        let saved = Prefs.defaults.string(forKey: Prefs.lensID)
        var state = LiveControlsState()
        state.dot = content.dot
        state.status = content.status
        state.model = content.model
        state.stats = content.stats
        state.badge = content.picture?.badge
        state.note = shownLensNote != nil && content.note == shownLensNote ? nil : content.note
        state.lenses = lenses
        // Capture uses camera_id 0 when no lens is given, and the next start uses the saved lens if it's listed.
        state.lensID = running ? runLensID ?? "0" : lenses.contains { $0.id == saved } ? saved : "0"
        state.lensNote = shownLensNote
        state.running = running
        state.stopping = running && stopRequested
        state.phoneSelected = serial != nil
        // The same conditions as the menu's main action, without its Stop.
        state.start = running ? nil
            : !setup.complete ? .finishSetup
            : devices.contains { $0.serial == selectedSerial && $0.authorized } ? .start : nil
        state.canControl = live && !switchingLens && !stopRequested
        state.switching = switchingLens
        state.torchOn = torchOn
        if controls.model.state != state { controls.model.state = state }
        controls.picture.setVeil(veil)
    }

    private func headerContent() -> MenuHeaderView.Content {
        if capture.running, let device = runDevice {
            let mode = Self.shortTitle(CaptureMode.all[runModeIndex])
            var content = MenuHeaderView.Content(dot: .wait, status: "Starting", picture: nil,
                                                 model: Self.headerName(device), stats: stats, note: note)
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
                content.picture = .init(veil: .init(title: "Switching camera on \(device.displayName)", text: "The camera stays open for your call."))
            } else if liveSince != nil {
                content.status = "Reconnecting"
                // The stream can drop with the phone still plugged in, for example when its camera server restarts.
                content.picture = listedDevices.contains(where: { $0.serial == device.serial && $0.authorized })
                    ? .init(veil: .init(title: "Reconnecting to \(device.displayName)", text: "The camera stays open for your call."))
                    : .init(veil: .init(title: "Plug the phone back in",
                                        text: "The camera stays open for your call and picks up again on its own."))
            } else {
                content.picture = .init(veil: .init(title: "Starting \(device.displayName)",
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
        let phone = devices.first { $0.serial == selectedSerial }
        return .init(dot: .ready, status: "Ready",
                     picture: .init(veil: .init(title: phone.map { "\($0.displayName) is ready" } ?? "Ready",
                                                text: "Start the webcam to see the picture.")),
                     model: phone.map(Self.headerName), stats: nil, note: note)
    }

    /// The phone's name under the status, with "Wi-Fi" when it isn't on the cable.
    private static func headerName(_ device: AndroidDevice) -> String {
        device.wireless ? "\(device.displayName) · Wi-Fi" : device.displayName
    }

    private func rebuildPhoneMenu() {
        let key = devices.map { "\($0.serial) \($0.status) \($0.displayName)" }.joined(separator: ",")
            + "|\(selectedSerial ?? "")|\(capture.running)|\(Wireless.enabled)"
        guard key != phoneMenuKey else { return }
        phoneMenuKey = key
        phoneMenu.removeAllItems()
        for (index, device) in devices.enumerated() {
            let title = device.authorized ? device.displayName : "\(device.displayName) (\(Self.statusAdvice(device.status)))"
            let item = NSMenuItem(title: title, action: #selector(selectPhone(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.state = device.serial == selectedSerial ? .on : .off
            item.isEnabled = device.authorized && !capture.running
            // Which way it's connected, once both ways are possible.
            if Wireless.enabled {
                item.image = Self.symbol(device.wireless ? ["wifi"] : ["cable.connector", "cable.connector.horizontal"])
                item.toolTip = device.wireless ? "On Wi-Fi" : "On USB"
            }
            phoneMenu.addItem(item)
        }
        if devices.isEmpty {
            let item = NSMenuItem(title: Wireless.enabled ? "No phone connected" : "No USB phone connected", action: nil, keyEquivalent: "")
            item.isEnabled = false
            phoneMenu.addItem(item)
        }
        phoneMenu.addItem(.separator())
        let connect = NSMenuItem(title: "Connect a Phone over Wi-Fi…", action: #selector(showPairing), keyEquivalent: "")
        connect.target = self
        connect.image = Self.symbol(["wifi"])
        phoneMenu.addItem(connect)
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

    /// What a phone that adb doesn't list as ready needs from the user, for its menu label.
    private static func statusAdvice(_ status: String) -> String {
        switch status {
        case "unauthorized": return "allow USB debugging"
        case "offline", "connecting", "authorizing": return "connecting, unplug and replug if it stays"
        default: return status
        }
    }

    private static func debuggingText(_ phone: AndroidDevice?) -> (help: String, next: String) {
        let status = phone?.status ?? "unauthorized"
        switch status {
        case "unauthorized":
            return ("On the phone, tap Allow when it asks. Turn on Developer options first if you haven't.",
                    "allow USB debugging on the phone.")
        case "offline", "connecting", "authorizing":
            return ("The phone is connecting. Unplug and replug it if it stays that way.",
                    "wait for the phone to connect. Unplug and replug it if it stays that way.")
        default:
            return ("adb lists the phone as \(status).", "check the phone's USB connection. adb lists it as \(status).")
        }
    }

    private static func shortTitle(_ mode: CaptureMode) -> String {
        "\(mode.height >= 2160 ? "4K" : "\(mode.height)p") · \(mode.fps)"
    }

    private static func elapsed(_ since: Date) -> String {
        let s = max(0, Int(Date().timeIntervalSince(since)))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }

    // MARK: Discovery and setup

    /// Checks for platform tools, the OBS extension and phones on USB off main. Skipped while capturing.
    private func refreshEnvironment() {
        guard !capture.running, !environmentCheckInProgress else { return }
        environmentCheckInProgress = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let adb = try? ADB.executable().path
            let extensionState = Installer.cameraState()
            let usb = USBPhones.list()
            DispatchQueue.main.async {
                guard let self else { return }
                self.environmentCheckInProgress = false
                self.environmentKnown = true
                self.adbPath = adb
                self.extensionActive = extensionState == .ready
                // Approved, though this process may not see the camera until it reopens.
                self.cameraApproved = extensionState != .missing
                // A phone seen on USB and then unplugged goes back to "plug it in", even after "nothing happens".
                if usb.isEmpty, !self.usbPhones.isEmpty { self.phoneNotShowingUp = false }
                self.usbPhones = usb
                self.setupChanged()
                if extensionState == .staleInThisProcess { self.relaunchForExtension() }
            }
        }
    }

    /// This process's CoreMediaIO list predates the approved extension and never updates (see VirtualCamera.extensionState),
    /// so Start Webcam would fail too: open a fresh copy and quit. Once per lineage, so a device macOS never shows can't loop.
    private func relaunchForExtension() {
        let key = "ANDROID_WEBCAM_RELAUNCHED"
        // A download or install under way would be cut off by the quit; the 3 s timer comes back here later.
        guard !capture.running, !relaunching, !DevMode.isOn, ProcessInfo.processInfo.environment[key] == nil,
              !setup.platformTools.busy, !setup.obs.busy,
              Bundle.main.bundleURL.pathExtension == "app" else { return }
        // Not while the user is still in System Settings (the approval's password box may be up there): the new copy's
        // Setup would jump over it. The 3 s timer comes back once they leave.
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard front != "com.apple.systempreferences", front != "com.apple.SecurityAgent" else { return }
        // Set once and never reset: the 3 s timer and the menu re-enter refreshEnvironment while the launch is pending,
        // and a launch error must not retry every 3 s.
        relaunching = true
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.environment = ProcessInfo.processInfo.environment.merging(
            [key: "1", Self.showSetupKey: shelf.isOpen("setup") ? "1" : "0"]) { $1 }
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { app, error in
            guard error == nil else { return }
            DispatchQueue.main.async {
                // When this copy is the active app, the new one inherits that, so its Setup opens in front and key.
                if #available(macOS 14, *), let app { NSApp.yieldActivation(to: app) }
                NSApp.terminate(nil)
            }
        }
    }

    private func devicesChanged(_ result: Result<[AndroidDevice], Error>) {
        devicesKnown = true
        switch result {
        case let .success(listed):
            let devices = listed.map { device in
                var named = device
                named.name = phoneNames[device.serial]
                return named
            }
            let savedSerial = Prefs.defaults.string(forKey: Prefs.serial)
            // Compared with adb's last good list, so a failed stream in between doesn't look like a fresh plug-in.
            let savedWasAllowed = listedDevices.contains { $0.serial == savedSerial && $0.authorized }
            let savedWasListed = listedDevices.contains { $0.serial == savedSerial }
            self.devices = devices
            listedDevices = devices
            for device in devices { seenSerials.formUnion([device.serial, device.hardwareSerial].compactMap { $0 }) }
            discoveryError = nil
            // The saved phone wins whenever it is plugged in; otherwise use any authorized one for now.
            if devices.contains(where: { $0.serial == savedSerial }) {
                selectedSerial = savedSerial
            } else if !devices.contains(where: { $0.serial == selectedSerial }) {
                selectedSerial = devices.first(where: \.authorized)?.serial
            }
            if let blocked = autoStartBlocked {
                if devices.contains(where: { $0.serial == blocked }) {
                    // Back after an unplug, not after a blink in adb's list (a Mac wake, a USB mode change).
                    if let since = blockedMissingSince, reallyGone(since) {
                        autoStartBlocked = nil
                    }
                    blockedMissingSince = nil
                } else if blockedMissingSince == nil {
                    blockedMissingSince = Date()
                }
            }
            let savedWasUnauthorized = listedDevices.contains { $0.serial == savedSerial && $0.status == "unauthorized" }
            if devices.contains(where: { $0.serial == savedSerial && $0.authorized }) {
                if !savedWasAllowed {
                    // Just allowed debugging, back after a real unplug, or not seen since launch.
                    if savedWasUnauthorized || savedMissingSince.map(reallyGone) ?? true { autoStartArmed = true }
                }
                savedMissingSince = nil
            } else if !devices.contains(where: { $0.serial == savedSerial }), savedWasListed, savedMissingSince == nil {
                // Offline or connecting in between doesn't reset this, so a blink through those states stays a blink.
                savedMissingSince = Date()
            }
        case let .failure(error):
            // A failed stream isn't an unplug, so it leaves autoStartBlocked alone.
            devices = []
            if discoveryError != error.localizedDescription { fputs("Phone discovery failed. \(error.logText)\n", stderr) }
            discoveryError = error.localizedDescription
        }
        lensQueries.formIntersection(Set(devices.map(\.serial)))
        if Wireless.enabled { wirelessConnector.connectMissing() }
        pairing?.devicesChanged(devices)
        for device in devices where device.authorized { queryLenses(device.serial); queryName(device.serial) }
        setupChanged()
    }

    private func setupChanged() {
        driveSetUpForMe()
        updateSetup()
        autoStartIfNeeded()
        refreshUI()
        showSetupOnFirstRun()
    }

    /// Where the phone is in its half of Setup, from adb's list and what's on USB.
    private func phoneGuide(phone: AndroidDevice?, allowed: AndroidDevice?) -> PhoneGuideState {
        let usb = usbPhones.first { $0.debugging } ?? usbPhones.first
        let stage: PhoneSetupStage
        if allowed != nil {
            stage = .ready
        } else if phone != nil || usb?.debugging == true {
            stage = .allow
        } else if usb != nil || phoneNotShowingUp {
            stage = .developerOptions
        } else {
            stage = .plugIn
        }
        let brand = usb?.brand ?? (phone?.model.hasPrefix("SM") == true ? .samsung : phone?.model.hasPrefix("Pixel") == true ? .google : .other)
        // An unauthorized phone has no model in adb's list, only its serial, so the USB name reads better until it's allowed.
        let name = allowed?.displayName ?? usb?.displayName ?? phone.flatMap { $0.model == $0.serial ? nil : $0.displayName }
        return PhoneGuideState(stage: stage, brand: brand, name: name)
    }

    /// After Set Up for Me: starts each download that hasn't run, then OBS once it's in place so macOS asks about its
    /// camera, and quits OBS again once the camera is on. A failed download waits for Try Again.
    private func driveSetUpForMe() {
        if cameraApproved { OBSSetup.quitRequested() }
        guard setUpForMe else {
            let canSetUp = environmentKnown && (adbPath == nil || !cameraApproved)
            if setup.canSetUpForMe != canSetUp { setup.canSetUpForMe = canSetUp }
            return
        }
        if setup.canSetUpForMe { setup.canSetUpForMe = false }
        let obsURL = Installer.installedOBS()
        if adbPath == nil, setup.platformTools.phase == .idle { setup.platformTools.start() }
        if obsURL == nil, !cameraApproved, setup.obs.phase == .idle { setup.obs.start() }
        if let obsURL, !cameraApproved, !OBSSetup.requested, !setup.obs.busy { OBSSetup.requestCamera(obs: obsURL) }
        if adbPath != nil, cameraApproved { setUpForMe = false }
    }

    private func updateSetup() {
        let obsOpen = !NSRunningApplication.runningApplications(withBundleIdentifier: Self.obsBundleID).isEmpty
        let phone = devices.first { $0.serial == selectedSerial } ?? devices.first
        let allowed = phone.flatMap { $0.authorized ? $0 : nil }
        let debugging = Self.debuggingText(phone)
        // While the user drags OBS in, Finder writes under the final name, so only a copy that passes the signature
        // check counts (checkDraggedCopy makes the installer idle once it does).
        let obsURL = setup.obs.isWaiting ? nil : Installer.installedOBS()
        if setup.obs.isWaiting { setup.obs.checkDraggedCopy() }
        let obsInstalled = obsURL != nil || extensionActive
        // Without adb the phone list fails for that reason alone, which the first step already says.
        let phoneError = adbPath == nil ? nil : discoveryError
        let guide = phoneGuide(phone: phone, allowed: allowed)
        let phoneHelp: String
        let phoneNext: String
        switch guide.stage {
        case .ready:
            phoneHelp = "\(guide.name ?? "Your phone") is connected."
            phoneNext = ""
        case .allow:
            if phone == nil {
                phoneHelp = "USB debugging is on. The phone asks to allow this Mac once platform tools are in."
                phoneNext = "download Android platform tools in Setup."
            } else {
                phoneHelp = phone?.status == "unauthorized" ? "\(guide.name ?? "The phone") is plugged in. Tap Allow on it." : debugging.help
                phoneNext = debugging.next
            }
        case .developerOptions:
            phoneHelp = usbPhones.first.map { "\($0.displayName) is plugged in, but USB debugging is off. These steps turn it on; it takes a minute." }
                ?? "These steps turn on USB debugging. If it's already on, try another cable: some only charge."
            phoneNext = "turn on USB debugging on the phone."
        case .plugIn:
            phoneHelp = phoneError ?? "Plug your phone into this Mac with a USB cable."
            phoneNext = phoneError ?? "plug in your phone with a USB cable."
        }
        let steps = [
            SetupStep(id: "adb", title: "Get Android platform tools", done: adbPath != nil,
                      help: adbPath != nil ? "Platform tools are ready."
                        : setup.platformTools.busy ? "Setup is getting these for you." : "adb, a small tool from Google, talks to your phone.",
                      next: "download Android platform tools in Setup.",
                      actions: [.install("Download Platform Tools", setup.platformTools)],
                      note: "It comes from Google's Android SDK.",
                      link: .open("About platform tools", Installer.platformToolsPage),
                      installer: setup.platformTools, working: setup.platformTools.busy),
            SetupStep(id: "obs-install", title: "Install OBS Studio", done: obsInstalled,
                      help: obsURL != nil ? "OBS Studio is installed."
                        : extensionActive ? "OBS's camera is already on."
                        : setup.obs.busy ? "Setup is installing it for you." : "OBS gives your Mac the camera your call app will see.",
                      next: "install OBS Studio from Setup.",
                      actions: [.install("Download OBS", setup.obs)],
                      note: "Free and open source.",
                      link: .open("Get OBS from obsproject.com", Installer.obsPage),
                      installer: setup.obs, working: setup.obs.busy),
            SetupStep(id: "extension", title: "Turn on OBS's camera", done: extensionActive,
                      help: extensionActive ? "It's on."
                        : OBSSetup.requested ? "macOS is asking you to turn it on."
                        : setUpForMe ? (obsURL != nil ? "Starting OBS in the background…" : "Setup starts OBS for you once it's installed.")
                        : "OBS adds a camera to your Mac. macOS asks you once before it turns on.",
                      next: "turn on OBS's camera in System Settings.",
                      actions: OBSSetup.requested ? [.cameraExtensions] : obsURL.map { [SetupAction.turnOnCamera($0)] } ?? [],
                      howTo: (OBSSetup.requested ? [] : ["Click Turn On OBS's Camera. OBS starts in the background; you "
                                                           + "don't need to do anything in it."])
                        + ["macOS asks about a new camera extension from OBS. Click Open System Settings.",
                           "Click the switch next to OBS, type your Mac's password and click OK.",
                           "That's it: Setup sees the camera and closes OBS for you."],
                      tip: OBSSetup.requested ? "Closed macOS's box by mistake? Open Camera Extensions gets you to the same switch."
                        : nil,
                      working: !OBSSetup.requested && (setUpForMe || obsURL == nil && setup.obs.busy)),
            SetupStep(id: "phone", title: "Connect your phone", done: allowed != nil,
                      help: phoneHelp, next: phoneNext, phone: guide),
            // Done only once OBS is there: "OBS is closed" reads oddly before it's installed. The OBS that Setup started
            // for its camera counts as closed, since Setup quits it.
            SetupStep(id: "obs", title: "Close OBS Studio", done: obsInstalled && (!obsOpen || OBSSetup.requested),
                      help: obsOpen && !OBSSetup.requested ? "Quit OBS Studio while you use the webcam. It can stay installed."
                        : obsInstalled ? "OBS is closed. It can stay installed."
                        : "Once OBS is installed, keep it closed while you use the webcam.",
                      next: "quit OBS Studio.",
                      actions: [.quit("Quit OBS", bundleID: Self.obsBundleID)]),
        ]
        if steps != setup.steps { setup.steps = steps }
    }

    private func showSetupOnFirstRun() {
        guard devicesKnown, environmentKnown else { return }
        if reopenSetup {
            reopenSetup = false
            Prefs.defaults.set(true, forKey: Prefs.setupShown)
            showSetup()
            return
        }
        guard !Prefs.defaults.bool(forKey: Prefs.setupShown) else { return }
        Prefs.defaults.set(true, forKey: Prefs.setupShown)
        if setup.complete { setupInDock(false) } else { showSetup() }
    }

    /// Starts when the saved phone shows up, or at launch. After capture ends, waits for that phone to be unplugged.
    private func autoStartIfNeeded() {
        guard devicesKnown, environmentKnown, autoStartArmed else { return }
        autoStartArmed = false
        guard Prefs.defaults.bool(forKey: Prefs.startOnPlugIn), !capture.running, setup.complete,
              let serial = Prefs.defaults.string(forKey: Prefs.serial), serial != autoStartBlocked,
              let device = devices.first(where: { $0.serial == serial && $0.authorized }) else { return }
        autoStartBlocked = serial
        startCapture(device)
    }

    private func lensList(_ serial: String) -> [CameraLens] {
        if let list = lenses[serial] { return list }
        let data = Prefs.defaults.data(forKey: Prefs.lenses(serial))
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
                    if let data = try? JSONEncoder().encode(list) { Prefs.defaults.set(data, forKey: Prefs.lenses(serial)) }
                case .success: break
                case let .failure(error):
                    self.lensQueries.remove(serial)
                    fputs("Could not list the phone's cameras. \(error.logText)\n", stderr)
                }
                self.refreshUI()
            }
        }
    }

    /// Reads the name the phone's owner gave it (Settings > About phone), once per run, off main. A phone without
    /// one keeps adb's model code.
    private func queryName(_ serial: String) {
        guard !nameQueries.contains(serial) else { return }
        nameQueries.insert(serial)
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let answer = (try? ADB.command(["-s", serial, "shell", "settings", "get", "global", "device_name"], timeout: 5))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            DispatchQueue.main.async {
                guard let self else { return }
                guard !answer.isEmpty, answer != "null", answer.count <= 60 else { return }
                self.phoneNames[serial] = answer
                func named(_ device: AndroidDevice) -> AndroidDevice {
                    var named = device
                    if device.serial == serial { named.name = answer }
                    return named
                }
                self.devices = self.devices.map(named)
                self.listedDevices = self.listedDevices.map(named)
                if self.runDevice?.serial == serial { self.runDevice?.name = answer }
                self.updateSetup()
                self.refreshUI()
            }
        }
    }

    // MARK: Capture

    private func startCapture(_ device: AndroidDevice, quiet: Bool = false) {
        guard !capture.running else { return }
        let saved = Prefs.defaults.string(forKey: Prefs.lensID)
        runLensID = lensList(device.serial).contains { $0.id == saved } ? saved : nil
        runDevice = device
        runModeIndex = modeIndex
        live = false; stats = nil; torchOn = false
        // The cool-down restart is the same call: keep its clock, and the reconnect veil if the phone drops meanwhile.
        if !quiet { liveSince = nil }
        switchingLens = false; stopRequested = false; cableLoose = false; hotNotified = false
        quietStart = quiet
        // Asked here rather than at launch, so the prompt comes when there's something to say.
        if Prefs.defaults.bool(forKey: Prefs.notifications) { requestNotificationPermission() }
        note = nil
        previewFailed = false
        Prefs.defaults.set(device.serial, forKey: Prefs.serial)
        capture.macSharpness = Float(imageStore.macSharpness)
        // Keeps App Nap from throttling the frame path while no window of ours is on screen. Idle sleep stays the
        // receiving app's call: a call or a recording holds its own assertion.
        captureActivity = captureActivity ?? ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
            reason: "Sending the phone's camera to the virtual camera")
        capture.start(device: device, mode: CaptureMode.all[modeIndex], lensID: runLensID, image: imageStore.phone, resume: quiet)
        refreshUI()
    }

    /// onStatus: the header tells the running states itself, so only the final status matters here.
    private func captureStatus(_ message: String) {
        guard !capture.running, let device = runDevice else { refreshUI(); return }
        let userStopped = stopRequested, quiet = restarting
        runDevice = nil
        if let activity = captureActivity { ProcessInfo.processInfo.endActivity(activity); captureActivity = nil }
        live = false; stats = nil; torchOn = false
        // A cool-down restart keeps the call's clock; startCapture(quiet:) picks it up.
        if !quiet { liveSince = nil }
        if note != nil, note == lensNote { note = nil }
        lensNote = nil
        // restarting stays set until the restart's stop completion runs.
        switchingLens = false; stopRequested = false; quietStart = false; cableLoose = false
        autoStartBlocked = device.serial
        // adb's last good list, so a Stop during an adb outage doesn't count as an unplug.
        blockedMissingSince = listedDevices.contains { $0.serial == device.serial } ? nil : Date()
        endSyncTest(reason: "The webcam stopped.")
        header.clearPicture()
        (window?.contentView as? PreviewView)?.clear()
        controls.picture.clear()
        if userStopped || quiet {
            // Whoever stopped it knows; what's left in Notification Center is out of date. A restart keeps the cable
            // notice: the phone may be gone, and the restarted run waits for it.
            withdraw(quiet ? [.run, .heat] : [.run, .cable, .heat])
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
            if stopRequested {
                // Stopped just as the first frame came; no notice that Stop would have to chase.
            } else if cableLoose {
                notify(.cable, "Phone reconnected", "The webcam is live again.")
            } else if liveSince == nil && !quietStart {
                notify(.run, "Webcam is live", "Pick OBS Virtual Camera in your call app.")
            }
            live = true
            liveSince = liveSince ?? Date()
            if switchingLens, let lens = runLensID { Prefs.defaults.set(lens, forKey: Prefs.lensID) }
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
            // Still listed means the cable is fine and the stream is coming back on its own; look again later.
            if let device = self.runDevice, self.listedDevices.contains(where: { $0.serial == device.serial && $0.authorized }) {
                self.checkLooseCable(after: 2); return
            }
            self.cableLoose = true
            self.notify(.cable, "Phone disconnected", "Plug it back in. Your call keeps the camera and picks up again on its own.")
            self.refreshUI()
        }
    }

    @objc private func systemWillSleep() { sleepQuietUntil = .distantFuture; sleptAt = Date() }

    /// Gone long enough to be an unplug: 5 s or more, and either gone before the Mac slept or outside the wake window.
    private func reallyGone(_ since: Date) -> Bool {
        Date().timeIntervalSince(since) >= 5 && (since < sleptAt || Date() >= sleepQuietUntil)
    }

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
        guard capture.running, live, !stopRequested, !restarting, let device = runDevice else { refreshUI(); return }
        modeIndex = Self.coolModeIndex
        Prefs.defaults.set(CaptureMode.all[modeIndex].title, forKey: Prefs.mode)
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
        Prefs.defaults.set(selectedSerial, forKey: Prefs.serial)
        refreshUI()
    }

    @objc private func selectMode(_ sender: NSMenuItem) {
        modeIndex = sender.tag
        Prefs.defaults.set(CaptureMode.all[modeIndex].title, forKey: Prefs.mode)
        refreshUI()
    }

    @objc private func selectOrientation(_ sender: NSMenuItem) {
        imageStore.orientation = PictureOrientation.allCases[sender.tag]
    }

    @objc private func selectLens(_ sender: NSMenuItem) {
        guard let device = runDevice else { return }
        selectLens(id: lensList(device.serial)[sender.tag].id)
    }

    /// The Camera menu and the Live Controls panel's lens chips both switch lenses here.
    private func selectLens(id: String) {
        guard runDevice != nil, live, !switchingLens, !stopRequested else { return }
        // Saved once the new lens is live, so a lens that can't run this mode isn't remembered.
        guard id != (runLensID ?? "0") else { return }
        runLensID = id
        if note != nil, note == lensNote { note = nil }
        switchingLens = true
        capture.switchLens(id)
        refreshUI()
    }

    /// The lens picked mid-call couldn't start in this mode; capture went back to the one that worked.
    private func lensFellBack(to good: String, from failed: String) {
        // A lens picked after the revert wins over this late call.
        guard let device = runDevice, !stopRequested, runLensID == failed else { return }
        let lenses = lensList(device.serial)
        func name(_ id: String) -> String { lenses.first { $0.id == id }?.label ?? "That camera" }
        runLensID = good
        // The way back can fail too (the cable came out mid-switch), so leave it to the cable check, not "Switching".
        switchingLens = false
        if listedDevices.contains(where: { $0.serial == device.serial && $0.authorized }) {
            note = "\(name(failed)) can't run \(Self.shortTitle(CaptureMode.all[runModeIndex])). The webcam went back to \(name(good))."
            lensNote = note
        }
        if liveSince != nil { checkLooseCable(after: 1.5) }
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
        if note == "OBS opened. Don't start its virtual camera while this one runs."
            || (!capture.running && note == "Quit OBS before starting this camera.") { note = nil }
        updateSetup()
        refreshUI()
        // Quitting OBS is step 3's last move; macOS then fronts whatever was behind it, often System Settings.
        if !setup.complete, let window = shelf.window("setup") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                bringForward(window)
                self?.nudgeIfBehind()
            }
        }
    }

    // MARK: Windows

    private func showSetup() {
        updateSetup()
        setup.screen = { [weak self] in self?.shelf.window("setup")?.screen ?? NSScreen.main }
        setup.fit()
        setupInDock(true)
        shelf.show("setup", title: "Set Up \(appName)", onClose: { [weak self] in self?.setupInDock(false) }) {
            SetupView(model: setup)
        }
        setup.fit()
        nudgeIfBehind()
    }

    /// macOS may draw Setup on top yet leave another app active (it does after Open Anyway and after OBS quits), so the
    /// Dock icon bounces once to say where it is.
    private func nudgeIfBehind() {
        guard !DevMode.isOn else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, self.shelf.isOpen("setup"), !NSApp.isActive else { return }
            NSApp.requestUserAttention(.informationalRequest)
        }
    }

    /// While Setup is open the app has a Dock icon, so a stranger can find Setup again behind System Settings or OBS.
    private func setupInDock(_ on: Bool) {
        guard !DevMode.isOn else { return }
        let policy: NSApplication.ActivationPolicy = on ? .regular : .accessory
        if NSApp.activationPolicy() != policy { NSApp.setActivationPolicy(policy) }
    }

    @objc private func showLiveControls() {
        let model = controls.model
        model.selectLens = { [weak self] id in self?.selectLens(id: id) }
        model.zoomIn = { [weak self] in self?.zoomInChosen() }
        model.zoomOut = { [weak self] in self?.zoomOutChosen() }
        model.toggleTorch = { [weak self] in self?.toggleFlashlight() }
        // Start or Finish Setup only: the panel never stops the webcam, even if it started since the press.
        model.mainAction = { [weak self] in
            guard let self, !self.capture.running else { return }
            self.mainActionChosen()
        }
        controls.onOpenChange = { [weak self] open in self?.controlsOpenChanged(open) }
        controls.show(on: statusItem?.button?.window?.screen ?? NSScreen.main)
    }

    /// The panel gets frames and a ticking clock only while it's open.
    private func controlsOpenChanged(_ open: Bool) {
        frameLock.lock()
        controlsOpen = open
        controlsFrame = nil
        frameLock.unlock()
        controlsClock?.invalidate()
        controlsClock = nil
        // A live frame would be stale by the next open, as the header's would.
        if !open, live { controls.picture.clear() }
        guard open else { return }
        refreshUI()
        // Only the live clock moves on its own; everything else refreshes on its event.
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            if let self, self.liveSince != nil { self.refreshUI() }
        }
        RunLoop.main.add(timer, forMode: .common)
        controlsClock = timer
    }

    /// What the global shortcut does: Live Controls opens, or closes when it's open.
    private func toggleLiveControls() {
        if controls.isOpen { controls.close() } else { showLiveControls() }
    }

    private func setShortcut(_ on: Bool) {
        let problem = hotkey.set(on)
        settingsModel.shortcutProblem = problem
        // The menu shows the keys only when they work.
        let shown = on && problem == nil
        controlsItem.keyEquivalent = shown ? GlobalHotkey.keyEquivalent : ""
        controlsItem.keyEquivalentModifierMask = shown ? GlobalHotkey.modifiers : []
    }

    @objc private func showSettings() {
        shelf.show("settings", title: "\(appName) Settings") { SettingsView(model: settingsModel) }
    }

    /// Settings' Phones over Wi-Fi switch: the phone list follows at once, and paired phones connect while it's on.
    private func wirelessChanged() {
        if Wireless.enabled { wirelessConnector.start() } else { wirelessConnector.stop() }
        watcher.refresh()
        phoneMenuKey = nil
        refreshUI()
    }

    /// Connect a Phone over Wi-Fi…: turns the switch on, since a paired phone is no use while the app hides it.
    @objc private func showPairing() {
        if !Wireless.enabled, !Wireless.forcedByEnvironment {
            Prefs.defaults.set(true, forKey: Wireless.defaultsKey)
            wirelessChanged()
        }
        let pairing = self.pairing ?? WirelessPairing()
        if self.pairing == nil {
            self.pairing = pairing
            pairing.close = { [weak self] in self?.shelf.close("pairing") }
            pairing.onPaired = { [weak self] in self?.wirelessConnector.connectMissing() }
            pairing.start(listed: listedDevices)
        }
        shelf.show("pairing", title: "Connect over Wi-Fi", onClose: { [weak self] in
            self?.pairing?.stop()
            self?.pairing = nil
        }) { PairingView(pairing: pairing) }
    }

    /// Puts a plain-text report on the pasteboard for a bug report. adb runs off main; the dev instance records it.
    private func copyDiagnostics() {
        guard settingsModel.copy != .gathering else { return }
        settingsModel.copy = .gathering
        copyToken += 1
        let token = copyToken
        // Includes the saved phone's serial, so one unplugged since doesn't leave its serial in old log lines.
        let serials = seenSerials.union([Prefs.defaults.string(forKey: Prefs.serial)].compactMap { $0 })
        let input = Diagnostics.Input(
            adbPath: adbPath, obsPath: Installer.installedOBS()?.path,
            obsCamera: extensionActive ? "on" : environmentKnown ? "off" : "not checked yet",
            phone: devices.first { $0.serial == selectedSerial } ?? devices.first,
            steps: setup.steps.map { ($0.title, $0.done) },
            mode: CaptureMode.all[capture.running ? runModeIndex : modeIndex].title,
            webcam: live ? "live" : capture.running ? "starting or reconnecting" : "off",
            serials: Array(serials))
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let report = Diagnostics.report(input)
            DispatchQueue.main.async {
                guard let self else { return }
                if DevMode.isOn {
                    DevMode.record("pasteboard", report)
                } else {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(report, forType: .string)
                }
                self.settingsModel.copy = .copied
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                    guard let self, self.copyToken == token, self.settingsModel.copy == .copied else { return }
                    self.settingsModel.copy = .idle
                }
            }
        }
    }

    @objc private func showSyncCheck() {
        syncModel.live = live
        syncModel.microphone = SyncTest.microphoneName
        shelf.show("sync", title: "Check Audio Sync", onClose: { [weak self] in
            self?.endSyncTest(reason: nil)
            self?.syncModel.phase = .idle
        }) { SyncCheckView(model: syncModel) }
    }

    private func beginSyncTest() {
        guard live else { return }
        endSyncTest(reason: nil)
        syncModel.microphone = SyncTest.microphoneName
        let test = SyncTest()
        let id = ObjectIdentifier(test)
        frameLock.lock()
        syncTest = test
        frameLock.unlock()
        syncModel.meter = .init()
        syncModel.phase = .listening
        test.onMeter = { [weak self] in self?.syncModel.meter = $0 }
        test.start { [weak self] result in
            guard let self else { return }
            self.frameLock.lock()
            let current = self.syncTest.map { ObjectIdentifier($0) } == id
            if current { self.syncTest = nil }
            self.frameLock.unlock()
            guard current else { return }
            switch result {
            case let .success(measured): self.syncModel.phase = .result(lagMs: measured.videoLagMs)
            case let .failure(error):
                let microphoneOff = (error as? SyncTestError) == .microphoneDenied
                self.syncModel.phase = .failed(error.localizedDescription, microphoneSettings: microphoneOff)
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
        if let window {
            if window.isMiniaturized { window.deminiaturize(nil); bringForward(window); return }
            if window.isVisible { window.close(); return }
            bringForward(window)
            return
        }
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
        // The dev instance keeps no frame in the app's real defaults.
        if DevMode.isOn { previewWindow.center() } else {
            if !previewWindow.setFrameUsingName("Preview") { previewWindow.center() }
            previewWindow.setFrameAutosaveName("Preview")
        }
        previewWindow.identifier = NSUserInterfaceItemIdentifier("preview")
        window = previewWindow
        setPreviewOpen(true)
        bringForward(previewWindow)
        refreshUI()
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === window else { return }
        setPreviewOpen(false)
        window = nil
        if previewFailed {
            previewFailed = false
            if note == Self.previewFailedNote { note = nil }
        }
        refreshUI()
    }

    private func setPreviewOpen(_ open: Bool) {
        frameLock.lock()
        previewOpen = open
        pendingFrame = nil
        frameLock.unlock()
    }

    // MARK: Frames

    /// Called on the capture thread. Keeps only the newest frame for the preview, the Live Controls panel and, at about
    /// 10 fps while the menu is open, the header; frames that arrive before main runs replace it instead of queueing more work.
    private func tap(_ frame: CVPixelBuffer) {
        let now = mach_absolute_time()
        frameLock.lock()
        let test = syncTest
        var previewHop = false, headerHop = false, controlsHop = false
        if previewOpen {
            previewHop = pendingFrame == nil
            pendingFrame = frame
        }
        if headerOpen, now &- headerShownAt >= headerInterval {
            headerShownAt = now
            headerHop = headerFrame == nil
            headerFrame = frame
        }
        if controlsOpen {
            controlsHop = controlsFrame == nil
            controlsFrame = frame
        }
        frameLock.unlock()
        test?.addFrame(frame, hostTime: now)
        if previewHop { DispatchQueue.main.async { [weak self] in self?.showPendingFrame() } }
        if headerHop { DispatchQueue.main.async { [weak self] in self?.showHeaderFrame() } }
        if controlsHop { DispatchQueue.main.async { [weak self] in self?.showControlsFrame() } }
    }

    private func showPendingFrame() {
        frameLock.lock()
        let frame = pendingFrame
        pendingFrame = nil
        frameLock.unlock()
        guard let frame, let view = window?.contentView as? PreviewView else { return }
        do { try view.show(frame) }
        catch {
            guard !previewFailed else { return }
            previewFailed = true
            fputs("Preview failed. \(error.logText)\n", stderr)
            note = Self.previewFailedNote
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

    private func showControlsFrame() {
        frameLock.lock()
        let frame = controlsFrame
        controlsFrame = nil
        frameLock.unlock()
        guard let frame, live, controls.isOpen else { return }
        controls.show(frame)
    }

    // MARK: Notifications

    /// UNUserNotificationCenter needs a bundled app; a bare `swift run` binary skips notifications.
    private var canNotify: Bool { !DevMode.isOn && Bundle.main.bundleURL.pathExtension == "app" }

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
        // The dev instance records the notification and shows nothing.
        if DevMode.isOn, Prefs.defaults.bool(forKey: Prefs.notifications) { DevMode.record("notification", "\(title): \(body)") }
        guard canNotify else { return }
        // Turned off mid-call: still take back what's out of date, such as "Phone disconnected" once it's back.
        guard Prefs.defaults.bool(forKey: Prefs.notifications) else { withdraw([notice]); return }
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
        guard canNotify else { next(); return }
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
            case UNNotificationDefaultActionIdentifier: self?.statusItem?.button?.performClick(nil)
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
            ADB.prepareEnvironment()
            let arguments = Array(CommandLine.arguments.dropFirst())
            if arguments == ["--diagnose"] { try diagnose(); return }
            if arguments.count == 2, arguments[0] == "--probe-hevc" { try probeHEVC(arguments[1]); return }
            guard arguments.isEmpty else { throw WebcamError(message: "Use --diagnose or --probe-hevc <file> for a headless check.") }
            let app = NSApplication.shared
            // Keeps the last 200 stderr lines for Copy Diagnostics, and still writes them where they went before.
            ErrorLog.start()
            let delegate = AppDelegate()
            app.setActivationPolicy(.accessory)
            app.delegate = delegate
            withExtendedLifetime(delegate) { app.run() }
        } catch { fputs("\(error.logText)\n", stderr); exit(1) }
    }

    static func diagnose() throws {
        let listing = try ADB.command(["devices", "-l"], timeout: 10)
        let devices = ADB.parseDevices(listing)
        // What adb lists on wireless debugging, whether or not the switch lets the app use it.
        let wirelessListed = ADB.parseDevices(listing, wireless: true).filter(\.wireless)
        var driver = false
        var driverError: String?
        do { _ = try VirtualCamera.findDevice(); driver = true }
        catch { driverError = error.logText }
        func entry(_ device: AndroidDevice) -> [String: String] { ["serial": device.serial, "model": device.model, "status": device.status] }
        let report: [String: Any] = [
            "usb_devices": devices.filter { !$0.wireless }.map(entry),
            "wireless_switch": Wireless.enabled, "wireless_devices": wirelessListed.map(entry),
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
