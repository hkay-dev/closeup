import AppKit
import AVFoundation
import CoreMedia
import VideoToolbox

final class PreviewView: NSView {
    let display = AVSampleBufferDisplayLayer()
    private let sampler = FrameSampler(fps: 30)
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.black.cgColor
        display.videoGravity = .resizeAspect
        layer?.addSublayer(display)
    }
    required init?(coder: NSCoder) { fatalError("Use init(frame:).") }
    override func layout() { super.layout(); display.frame = bounds }

    func show(_ frame: CVPixelBuffer) throws {
        let sample = try sampler.sample(frame)
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true) {
            let dictionary = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dictionary,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        if display.status == .failed { display.flush() }
        display.enqueue(sample)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private static let obsBundleID = "com.obsproject.obs-studio"
    private static let serialKey = "phoneSerial"
    private static let modeKey = "captureMode"

    private let capture = CaptureController()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let status = NSMenuItem(title: "Checking USB phones...", action: nil, keyEquivalent: "")
    private let start = NSMenuItem(title: "Start Android Webcam", action: #selector(toggleCapture), keyEquivalent: "")
    private let preview = NSMenuItem(title: "Show Preview", action: #selector(togglePreview), keyEquivalent: "")
    private let phoneMenu = NSMenu()
    private let modeMenu = NSMenu()
    private var devices: [AndroidDevice] = []
    private var selectedSerial: String?
    private var modeIndex = CaptureMode.all.firstIndex { $0.title == "1080p / 30 fps" } ?? 0
    private var discoveryInProgress = false
    private var discoveryTimer: Timer?
    private var signalSources: [DispatchSourceSignal] = []
    private var window: NSWindow?
    // Written by the capture thread, read on main. At most one frame waits for the preview.
    private let previewLock = NSLock()
    private var previewOpen = false
    private var pendingFrame: CVPixelBuffer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let savedMode = UserDefaults.standard.string(forKey: Self.modeKey)
        if let index = CaptureMode.all.firstIndex(where: { $0.title == savedMode }) { modeIndex = index }
        statusItem.button?.image = NSImage(systemSymbolName: "camera", accessibilityDescription: "Android Webcam")
        statusItem.button?.toolTip = "Android Webcam"
        status.isEnabled = false
        menu.autoenablesItems = false
        phoneMenu.autoenablesItems = false
        modeMenu.autoenablesItems = false
        menu.delegate = self
        menu.addItem(status)
        menu.addItem(.separator())
        start.target = self; menu.addItem(start)
        preview.target = self; menu.addItem(preview)
        let phone = NSMenuItem(title: "Phone", action: nil, keyEquivalent: "")
        phone.submenu = phoneMenu; menu.addItem(phone)
        let mode = NSMenuItem(title: "Capture Mode", action: nil, keyEquivalent: "")
        mode.submenu = modeMenu; menu.addItem(mode)
        for (index, mode) in CaptureMode.all.enumerated() {
            let item = NSMenuItem(title: mode.title, action: #selector(selectMode(_:)), keyEquivalent: "")
            item.target = self; item.tag = index; modeMenu.addItem(item)
        }
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Android Webcam", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self; menu.addItem(quit)
        statusItem.menu = menu
        capture.onStatus = { [weak self] message, active in
            guard let self else { return }
            self.status.title = message
            self.statusItem.button?.image = NSImage(systemSymbolName: active ? "camera.fill" : "camera",
                                                    accessibilityDescription: "Android Webcam")
            self.updateControls()
        }
        capture.onFrame = { [weak self] frame in self?.queuePreview(frame) }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(applicationLaunched(_:)),
                                                          name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        for signalNumber in [SIGTERM, SIGINT] {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }
            source.resume()
            signalSources.append(source)
        }
        refreshDevices()
        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in self?.refreshDevices() }
        RunLoop.main.add(timer, forMode: .common)
        discoveryTimer = timer
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard capture.running else { return .terminateNow }
        status.title = "Stopping webcam..."
        capture.stop { NSApp.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }

    func menuWillOpen(_ menu: NSMenu) { refreshDevices(); updateControls() }

    private func refreshDevices() {
        guard !capture.running, !discoveryInProgress else { return }
        discoveryInProgress = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = Result { try ADB.devices() }
            DispatchQueue.main.async {
                guard let self else { return }
                self.discoveryInProgress = false
                let before = (self.devices, self.selectedSerial)
                switch result {
                case let .success(devices):
                    self.devices = devices
                    // The saved phone wins whenever it is plugged in; otherwise use any authorized one for now.
                    let savedSerial = UserDefaults.standard.string(forKey: Self.serialKey)
                    if devices.contains(where: { $0.serial == savedSerial }) {
                        self.selectedSerial = savedSerial
                    } else if !devices.contains(where: { $0.serial == self.selectedSerial }) {
                        self.selectedSerial = devices.first(where: \.authorized)?.serial
                    }
                    self.status.title = devices.isEmpty ? "No USB Android phone connected" :
                        devices.contains(where: \.authorized) ? "Ready to start" : "Approve USB debugging on your phone"
                case let .failure(error): self.status.title = error.localizedDescription
                }
                // Rebuilding the Phone submenu while it's open loses the highlight, so only rebuild on a change.
                if before != (self.devices, self.selectedSerial) { self.updateControls() }
            }
        }
    }

    private func updateControls() {
        start.title = capture.running ? "Stop Android Webcam" : "Start Android Webcam"
        start.isEnabled = capture.running || devices.contains { $0.serial == selectedSerial && $0.authorized }
        preview.state = window?.isVisible == true ? .on : .off
        phoneMenu.removeAllItems()
        for (index, device) in devices.enumerated() {
            let item = NSMenuItem(title: "\(device.model) / \(device.status)", action: #selector(selectPhone(_:)), keyEquivalent: "")
            item.target = self; item.tag = index
            item.state = device.serial == selectedSerial ? .on : .off
            item.isEnabled = device.authorized && !capture.running
            phoneMenu.addItem(item)
        }
        if devices.isEmpty { phoneMenu.addItem(NSMenuItem(title: "No USB phone connected", action: nil, keyEquivalent: "")) }
        for item in modeMenu.items { item.state = item.tag == modeIndex ? .on : .off; item.isEnabled = !capture.running }
    }

    @objc private func selectPhone(_ sender: NSMenuItem) {
        selectedSerial = devices[sender.tag].serial
        UserDefaults.standard.set(selectedSerial, forKey: Self.serialKey)
        updateControls()
    }

    @objc private func selectMode(_ sender: NSMenuItem) {
        modeIndex = sender.tag
        UserDefaults.standard.set(CaptureMode.all[modeIndex].title, forKey: Self.modeKey)
        updateControls()
    }

    @objc private func toggleCapture() {
        if capture.running { capture.stop(); status.title = "Stopping webcam..."; return }
        guard let device = devices.first(where: { $0.serial == selectedSerial && $0.authorized }) else { return }
        if !NSRunningApplication.runningApplications(withBundleIdentifier: Self.obsBundleID).isEmpty {
            status.title = "Quit OBS before starting this camera sender"
            return
        }
        capture.start(device: device, mode: CaptureMode.all[modeIndex])
        updateControls()
    }

    @objc private func applicationLaunched(_ notification: Notification) {
        let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        guard capture.running, app?.bundleIdentifier == Self.obsBundleID else { return }
        status.title = "OBS opened. Don't start its virtual camera while this one runs."
    }

    @objc private func togglePreview() {
        if let window, window.isVisible { window.close(); return }
        let view = PreviewView(frame: NSRect(x: 0, y: 0, width: 960, height: 540))
        let previewWindow = NSWindow(contentRect: view.frame, styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                     backing: .buffered, defer: false)
        previewWindow.title = "Android Webcam Preview"
        previewWindow.contentView = view
        previewWindow.isReleasedWhenClosed = false
        previewWindow.delegate = self
        previewWindow.center()
        window = previewWindow
        setPreviewOpen(true)
        previewWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        updateControls()
    }

    func windowWillClose(_ notification: Notification) {
        setPreviewOpen(false)
        window = nil
        updateControls()
    }

    private func setPreviewOpen(_ open: Bool) {
        previewLock.lock()
        previewOpen = open
        pendingFrame = nil
        previewLock.unlock()
    }

    /// Called on the capture thread. Keeps only the newest frame and schedules one main-queue hop for it;
    /// frames that arrive before main runs replace it instead of queueing more work.
    private func queuePreview(_ frame: CVPixelBuffer) {
        previewLock.lock()
        guard previewOpen else { previewLock.unlock(); return }
        let hopNeeded = pendingFrame == nil
        pendingFrame = frame
        previewLock.unlock()
        if hopNeeded { DispatchQueue.main.async { [weak self] in self?.showPendingFrame() } }
    }

    private func showPendingFrame() {
        previewLock.lock()
        let frame = pendingFrame
        pendingFrame = nil
        previewLock.unlock()
        guard let frame, let view = window?.contentView as? PreviewView else { return }
        do { try view.show(frame) }
        catch { status.title = "Preview failed. \(error.localizedDescription)" }
    }

    @objc private func quitApp() {
        discoveryTimer?.invalidate()
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
        } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
    }

    static func diagnose() throws {
        let devices = try ADB.devices()
        var driver = false
        var driverError: String?
        do { _ = try VirtualCamera.findDevice(); driver = true }
        catch { driverError = error.localizedDescription }
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
