import AppKit
import ServiceManagement
import SwiftUI
import UserNotifications

enum Prefs {
    static let serial = "phoneSerial"
    static let mode = "captureMode"
    static let lensID = "lensID"
    static let imageSettings = "imageSettings"
    static let macSharpness = "macSharpness"
    static let startOnPlugIn = "startOnPlugIn"
    static let notifications = "notifications"
    static let setupShown = "setupShown"
    static func lenses(_ serial: String) -> String { "lenses.\(serial)" }

    /// The app's settings. The dev automation instance keeps its own suite (see DevControl.swift).
    static let defaults: UserDefaults = DevMode.defaults ?? .standard

    static func register() {
        defaults.register(defaults: [startOnPlugIn: false, notifications: true, macSharpness: 0.0])
    }
}

/// The app's display name, so the brand can change in Info.plist alone.
let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? ProcessInfo.processInfo.processName
let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development build"

/// Puts a window in front of the app the user is in. Activation alone doesn't bring an accessory app forward.
/// The dev automation instance parks it below the desktop instead.
func bringForward(_ window: NSWindow) {
    if DevMode.isOn { DevMode.park(window); return }
    if #available(macOS 14, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
    window.makeKeyAndOrderFront(nil)
    window.orderFrontRegardless()
}

/// The app never shows a menu bar, but its main menu still handles key equivalents in its windows.
func makeKeyEquivalentMenu() -> NSMenu {
    let appMenu = NSMenu()
    appMenu.addItem(withTitle: "Quit \(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    let fileMenu = NSMenu(title: "File")
    fileMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
    let editMenu = NSMenu(title: "Edit")
    editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    let main = NSMenu()
    for submenu in [appMenu, fileMenu, editMenu] {
        let item = NSMenuItem()
        item.submenu = submenu
        main.addItem(item)
    }
    return main
}

/// Keeps one window per kind and brings it forward when it's asked for again.
final class WindowShelf: NSObject, NSWindowDelegate {
    private var windows: [String: NSWindow] = [:]
    private var closeHandlers: [String: () -> Void] = [:]

    func show<Content: View>(_ id: String, title: String, onClose: (() -> Void)? = nil, content: () -> Content) {
        let window: NSWindow
        if let existing = windows[id] {
            window = existing
        } else {
            window = NSWindow(contentViewController: NSHostingController(rootView: content()))
            window.title = title
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.identifier = NSUserInterfaceItemIdentifier(id)
            window.delegate = self
            window.center()
            windows[id] = window
            closeHandlers[id] = onClose
        }
        bringForward(window)
    }

    func close(_ id: String) { windows[id]?.close() }

    func isOpen(_ id: String) -> Bool { windows[id] != nil }

    func windowWillClose(_ notification: Notification) {
        guard let id = (notification.object as? NSWindow)?.identifier?.rawValue else { return }
        windows[id] = nil
        closeHandlers.removeValue(forKey: id)?()
    }
}

// MARK: Setup

/// A button on a pending setup step that does the step, or most of it.
enum SetupAction: Hashable {
    case copy(String)                   // a Terminal command
    case open(String, URL)              // a button title and a web page or an app
    case loginItems                     // System Settings > General > Login Items & Extensions
    case quit(String, bundleID: String)

    var title: String {
        switch self {
        case .copy: "Copy Command"
        case let .open(title, _): title
        case .loginItems: "Open Login Items & Extensions"
        case let .quit(title, _): title
        }
    }

    func perform() {
        if DevMode.isOn { DevMode.record("setup-action", title); return }
        switch self {
        case let .copy(command):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(command, forType: .string)
        case let .open(_, url): NSWorkspace.shared.open(url)
        case .loginItems: SMAppService.openSystemSettingsLoginItems()
        case let .quit(_, bundleID):
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) { app.terminate() }
        }
    }
}

struct SetupStep: Identifiable, Equatable {
    let id: String
    let title: String
    let done: Bool
    let help: String
    let next: String    // the header's "Next:" line while this step is pending
    var actions: [SetupAction] = []
}

final class SetupModel: ObservableObject {
    @Published var steps: [SetupStep] = []
    var doneCount: Int { steps.filter(\.done).count }
    var nextStep: SetupStep? { steps.first { !$0.done } }
    var complete: Bool { !steps.isEmpty && nextStep == nil }
    var start: () -> Void = {}
}

/// View-local state held in an object, so these views don't need the `@State` macro (the Command Line Tools toolchain has no SwiftUIMacros plugin).
final class StateBox<Value>: ObservableObject {
    @Published var value: Value
    init(_ value: Value) { self.value = value }
}

struct SetupView: View {
    @ObservedObject var model: SetupModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var copied = StateBox<SetupAction?>(nil)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if model.complete {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(.green)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("All set").font(.title3.weight(.semibold))
                        Text("Start the webcam, then pick OBS Virtual Camera in your call app.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
                .transition(.opacity)
            } else {
                Text("\(appName) needs these before it can send your phone's camera to the Mac.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(model.steps) { step in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    mark(step)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(step.title).fontWeight(step.id == model.nextStep?.id ? .semibold : .regular)
                        Text(step.help).font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                        if !step.done, !step.actions.isEmpty {
                            HStack(spacing: 8) {
                                ForEach(step.actions, id: \.self) { action in
                                    Button(copied.value == action ? "Copied" : action.title) { run(action) }
                                }
                            }
                            .controlSize(.small)
                            .padding(.top, 3)
                        }
                        if step.id == "debugging", !step.done {
                            DisclosureGroup("Show me how") {
                                Text("""
                                    1. On the phone, open Settings > About phone (on Samsung, then Software information) \
                                    and tap Build number seven times. Developer options appear.
                                    2. Open Settings > Developer options and turn on USB debugging.
                                    3. Plug the phone into the Mac. When the phone asks "Allow USB debugging?", \
                                    tick "Always allow from this computer" and tap Allow.
                                    """)
                                    .font(.callout)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.top, 4)
                            }
                            .font(.callout)
                        }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityValue(step.done ? "Done" : "Not done")
            }
            HStack {
                Text("This list checks itself every few seconds.").font(.footnote).foregroundStyle(.secondary)
                Spacer()
                if model.complete {
                    Button("Start Webcam") { model.start() }
                        .keyboardShortcut(.defaultAction)
                        .transition(.opacity)
                }
            }
        }
        .padding(20)
        .frame(width: 440)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: model.steps)
    }

    private func run(_ action: SetupAction) {
        action.perform()
        guard case .copy = action else { return }
        copied.value = action
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { if copied.value == action { copied.value = nil } }
    }

    @ViewBuilder private func mark(_ step: SetupStep) -> some View {
        if step.done {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        } else if step.id == model.nextStep?.id {
            Image(systemName: "smallcircle.filled.circle").foregroundStyle(Color.accentColor)
        } else {
            Image(systemName: "circle").foregroundStyle(.secondary)
        }
    }
}

// MARK: Image settings

/// The saved phone and Mac image settings. onChange runs on main after every change.
final class ImageSettingsStore: ObservableObject {
    @Published var phone: PhoneImageSettings { didSet { save() } }
    @Published var macSharpness: Double { didSet { save() } }
    var onChange: () -> Void = {}

    init() {
        let data = Prefs.defaults.data(forKey: Prefs.imageSettings)
        phone = data.flatMap { try? JSONDecoder().decode(PhoneImageSettings.self, from: $0) } ?? PhoneImageSettings()
        macSharpness = Prefs.defaults.double(forKey: Prefs.macSharpness)
    }

    func reset() {
        phone = PhoneImageSettings()
        macSharpness = 0
    }

    private func save() {
        if let data = try? JSONEncoder().encode(phone) { Prefs.defaults.set(data, forKey: Prefs.imageSettings) }
        Prefs.defaults.set(macSharpness, forKey: Prefs.macSharpness)
        onChange()
    }
}

struct ImageSettingsView: View {
    @ObservedObject var store: ImageSettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Form {
                Section("On the phone") {
                    LabeledContent("Exposure") {
                        HStack {
                            Slider(value: $store.phone.exposureEV, in: -2...2, step: 1.0 / 3.0)
                            Text(store.phone.exposureEV.magnitude < 0.05 ? "0 EV" : String(format: "%+.1f EV", store.phone.exposureEV))
                                .monospacedDigit().frame(width: 56, alignment: .trailing)
                        }
                    }
                    Picker("White balance", selection: $store.phone.whiteBalance) {
                        ForEach(WhiteBalance.allCases, id: \.self) { Text($0.rawValue.capitalized) }
                    }
                    Picker("Focus", selection: $store.phone.focus) {
                        Text("Continuous").tag(FocusMode.continuous)
                        Text("Locked").tag(FocusMode.locked)
                    }
                    Picker("Noise reduction", selection: $store.phone.noiseReduction) { levels }
                    Picker("Sharpness", selection: $store.phone.sharpness) { levels }
                }
                Section("On the Mac") {
                    LabeledContent("Extra sharpening") {
                        HStack {
                            Slider(value: $store.macSharpness, in: 0...1)
                            Text(store.macSharpness == 0 ? "Off" : String(format: "%.0f%%", store.macSharpness * 100))
                                .monospacedDigit().frame(width: 56, alignment: .trailing)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            // A grouped form scrolls and has no height of its own, so the window would hide every control.
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("Changes apply while live. Reset returns everything to the phone's automatic settings.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Reset to Automatic") { store.reset() }
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 460)
    }

    @ViewBuilder private var levels: some View {
        Text("Off").tag(ProcessingLevel.off)
        Text("Fast").tag(ProcessingLevel.fast)
        Text("High quality").tag(ProcessingLevel.highQuality)
    }
}

// MARK: Settings

struct SettingsView: View {
    @AppStorage(Prefs.startOnPlugIn, store: Prefs.defaults) private var startOnPlugIn = false
    @AppStorage(Prefs.notifications, store: Prefs.defaults) private var notifications = true
    @StateObject private var loginStatus = StateBox(SMAppService.mainApp.status)
    @StateObject private var loginError = StateBox<String?>(nil)
    @StateObject private var notificationsBlocked = StateBox(false)
    let onNotificationsChange: (Bool) -> Void

    var body: some View {
        Form {
            Toggle("Launch at login", isOn: Binding(get: { loginStatus.value == .enabled }, set: { setLaunchAtLogin($0) }))
            if loginStatus.value == .requiresApproval {
                HStack {
                    Text("Allow \(appName) in Login Items to finish.").font(.callout).foregroundStyle(.secondary)
                    Button("Open Login Items") {
                        if DevMode.isOn { DevMode.record("open-login-items", "Open Login Items") } else { SMAppService.openSystemSettingsLoginItems() }
                    }
                }
            }
            if let loginError = loginError.value { Text(loginError).font(.callout).foregroundStyle(.secondary) }
            Toggle("Start when the phone is plugged in", isOn: $startOnPlugIn)
            Text("Starts the webcam once when your saved phone connects. After you stop it, it waits until you plug the phone in again.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Toggle("Notifications", isOn: $notifications)
                .onChange(of: notifications) { onNotificationsChange($0); checkNotifications() }
            Text("When the webcam starts, stops on an error, the phone gets hot or the cable comes loose.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if notifications && notificationsBlocked.value {
                Label("macOS has notifications turned off for \(appName). Turn them on in System Settings > Notifications.",
                      systemImage: "bell.slash")
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
            }
            Text("Version \(appVersion) · phone server \(ScrcpyServer.version)")
                .font(.footnote).foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.top, 10)
        }
        .padding(20)
        .frame(width: 420)
        .onAppear(perform: checkNotifications)
    }

    private func checkNotifications() {
        guard !DevMode.isOn, Bundle.main.bundleURL.pathExtension == "app" else { return }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let blocked = settings.authorizationStatus == .denied
            DispatchQueue.main.async { notificationsBlocked.value = blocked }
        }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        if DevMode.isOn {
            DevMode.record("launch-at-login", on ? "on" : "off")
            loginError.value = "The dev instance leaves login items alone."
            return
        }
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError.value = nil
        } catch {
            loginError.value = "Couldn't change it. \(error.localizedDescription)"
        }
        loginStatus.value = SMAppService.mainApp.status
    }
}

// MARK: Audio sync check

final class SyncCheckModel: ObservableObject {
    enum Phase: Equatable {
        case idle, listening, result(lagMs: Double)
        case failed(String, microphoneSettings: Bool = false)
    }
    @Published var phase = Phase.idle
    @Published var live = false
    @Published var starting = false
    @Published var meter = SyncTest.Meter()
    @Published var microphone: String?
    var begin: () -> Void = {}
    var startWebcam: () -> Void = {}
}

struct SyncCheckView: View {
    @ObservedObject var model: SyncCheckModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Clap once, in the middle of the picture, with the webcam live.")
                .fontWeight(.semibold).fixedSize(horizontal: false, vertical: true)
            Text("This measures how far the video lags behind the sound on this Mac. Press Start and clap where the microphone can hear it. It listens for up to 8 seconds and stops once it has the clap. Nothing is saved.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Label(model.microphone ?? "No microphone found", systemImage: model.microphone == nil ? "mic.slash" : "mic")
                .font(.callout).foregroundStyle(.secondary)
                .accessibilityLabel(model.microphone.map { "Microphone: \($0)" } ?? "No microphone found")
            phaseView
                .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: model.phase)
            HStack {
                if model.starting {
                    ProgressView().controlSize(.small)
                    Text("Starting the webcam").font(.callout).foregroundStyle(.secondary)
                } else if !model.live {
                    Text("The webcam isn't live.").font(.callout).foregroundStyle(.secondary)
                    Button("Start Webcam") { model.startWebcam() }
                }
                Spacer()
                Button(startTitle) { model.begin() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.live || model.phase == .listening || model.microphone == nil)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    @ViewBuilder private var phaseView: some View {
        switch model.phase {
        case .idle:
            // Holds the space, so the window keeps its size from one step to the next.
            Color.clear.frame(height: 0)
        case .listening:
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    LevelMeter(level: model.meter.level)
                    Text(model.meter.heard ? "Heard the clap. Matching it to the picture." : "Listening. Clap once.")
                        .font(.callout)
                }
                ProgressView(value: model.meter.heard ? 1 : model.meter.progress)
                    .progressViewStyle(.linear)
                    .animation(reduceMotion ? nil : .linear(duration: 0.05), value: model.meter.progress)
            }
            .accessibilityElement(children: .combine)
        case let .result(lagMs):
            VStack(alignment: .leading, spacing: 4) {
                Text(Self.headline(lagMs))
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(Self.advice(lagMs))
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .accessibilityElement(children: .combine)
        case let .failed(text, microphoneSettings):
            VStack(alignment: .leading, spacing: 8) {
                Label { Text(text).fixedSize(horizontal: false, vertical: true) } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                if microphoneSettings {
                    Button("Open Microphone Settings") {
                        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
                        if DevMode.isOn { DevMode.record("open-url", url.absoluteString) } else { NSWorkspace.shared.open(url) }
                    }
                }
            }
        }
    }

    private var startTitle: String {
        switch model.phase {
        case .idle, .listening: return "Start"
        case .result, .failed: return "Test Again"
        }
    }

    /// The number to act on. Positive lag means the video reaches the Mac after the sound.
    static func headline(_ lagMs: Double) -> String {
        let ms = Int(abs(lagMs).rounded())
        if ms < 20 { return "In sync" }
        return lagMs > 0 ? "Video \(ms) ms behind" : "Sound \(ms) ms behind"
    }

    static func advice(_ lagMs: Double) -> String {
        let ms = Int(abs(lagMs).rounded())
        if ms < 20 { return "Sound and picture are \(ms) ms apart, too little to notice." }
        if lagMs > 0 { return "To line them up, delay the audio by \(ms) ms in your call or recording app." }
        return "To line them up, delay the video by \(ms) ms in your recording app."
    }
}

/// A short bar that follows the microphone level.
private struct LevelMeter: View {
    let level: Float

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(Color.green)
                    .frame(width: max(4, geometry.size.width * CGFloat(level)))
            }
        }
        .frame(width: 72, height: 6)
        .animation(.linear(duration: 0.05), value: level)
        .accessibilityHidden(true)
    }
}
