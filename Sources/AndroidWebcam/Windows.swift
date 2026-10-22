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
    case open(String, URL)              // a button title and a web page or an app
    case loginItems                     // System Settings > General > Login Items & Extensions
    case quit(String, bundleID: String)
    case install(String, Installer)     // downloads and installs, in the dev instance too (into its own directory)

    var title: String {
        switch self {
        case let .open(title, _): title
        case .loginItems: "Open Login Items & Extensions"
        case let .quit(title, _): title
        case let .install(title, _): title
        }
    }

    func perform() {
        if case let .install(_, installer) = self { installer.start(); return }
        if DevMode.isOn { DevMode.record("setup-action", title); return }
        switch self {
        case let .open(_, url): NSWorkspace.shared.open(url)
        case .loginItems: SMAppService.openSystemSettingsLoginItems()
        case let .quit(_, bundleID):
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) { app.terminate() }
        case .install: break
        }
    }
}

struct SetupStep: Identifiable, Equatable {
    let id: String
    let title: String
    let done: Bool
    let help: String
    let next: String    // the header's "Next:" line while this step is pending
    var actions: [SetupAction] = []     // the first is the step's main button
    var howTo: [String] = []            // numbered steps under the help while pending
    var howToFolded = false             // behind a "Show me how" disclosure
    var note: String? = nil             // a small line under the buttons
    var link: SetupAction? = nil        // a small link after the note
    var installer: Installer? = nil     // shows its download in place of the buttons while it runs
}

final class SetupModel: ObservableObject {
    @Published var steps: [SetupStep] = []
    let platformTools = Installer(.platformTools)
    let obs = Installer(.obs)
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

/// The springs Setup moves with, from swift-motion's defaults. Off under Reduce Motion.
private let setupSpring = Animation.spring(response: 0.38, dampingFraction: 0.9)

struct SetupView: View {
    @ObservedObject var model: SetupModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            hero
            VStack(spacing: 8) {
                ForEach(Array(model.steps.enumerated()), id: \.element.id) { index, step in
                    SetupStepCard(number: index + 1, step: step,
                                  mark: step.done ? .done : step.id == model.nextStep?.id ? .next : .later)
                }
            }
            HStack(alignment: .center) {
                Text(model.complete ? "You can also start it from the menu bar." : "This list checks itself every few seconds.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                if model.complete {
                    Button("Start Webcam") { model.start() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
        }
        .padding(22)
        .frame(width: 470)
        .animation(reduceMotion ? nil : setupSpring, value: model.steps)
    }

    private var hero: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 60, height: 60)
                .overlay(alignment: .bottomTrailing) {
                    if model.complete {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.white, .green)
                            .offset(x: 3, y: 3)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(model.complete ? "All set" : "Set up \(appName)")
                    .font(.title2.weight(.semibold))
                Text(model.complete ? "In your call app, choose OBS Virtual Camera as the camera."
                                    : "Use your Android phone's camera as your Mac's webcam.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !model.complete, !model.steps.isEmpty {
                    Text("\(model.doneCount) of \(model.steps.count) steps done")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }
}

/// One numbered step: done (a check, its result), next (open, with its buttons) or later (its title and what it's for).
private struct SetupStepCard: View {
    enum Mark { case done, next, later }

    let number: Int
    let step: SetupStep
    let mark: Mark

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            badge
            VStack(alignment: .leading, spacing: 6) {
                Text(step.title)
                    .font(.body.weight(mark == .later ? .regular : .semibold))
                    .foregroundStyle(mark == .done ? .secondary : .primary)
                Text(step.help)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                if mark != .done { pending }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, mark == .next ? 14 : 10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(fill))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(mark == .next ? Color.accentColor.opacity(0.45) : Color.primary.opacity(0.06), lineWidth: 1))
        .accessibilityElement(children: .contain)
        // A group's value isn't read out, so the state goes in its label.
        .accessibilityLabel("Step \(number), \(step.title), \(mark == .done ? "done" : mark == .next ? "do this next" : "not done yet")")
    }

    private var fill: Color {
        switch mark {
        case .next: Color.accentColor.opacity(0.08)
        case .done: Color.primary.opacity(0.025)
        case .later: Color.primary.opacity(0.04)
        }
    }

    private var badge: some View {
        ZStack {
            switch mark {
            case .done:
                Circle().fill(Color.green)
                Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
            case .next:
                Circle().fill(Color.accentColor)
                Text("\(number)").font(.system(size: 12, weight: .bold).monospacedDigit()).foregroundStyle(.white)
            case .later:
                Circle().strokeBorder(Color.secondary.opacity(0.6), lineWidth: 1.5)
                Text("\(number)").font(.system(size: 12, weight: .semibold).monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)
    }

    /// The how-to, buttons and note of a step that isn't done. A later step keeps only a download that's under way.
    @ViewBuilder private var pending: some View {
        if mark == .next, !step.howTo.isEmpty {
            if step.howToFolded {
                DisclosureGroup("Show me how") { howTo.padding(.top, 4) }
                    .font(.callout)
            } else {
                howTo
            }
        }
        if let installer = step.installer {
            InstallerControls(installer: installer, actions: step.actions, showIdle: mark == .next)
                .padding(.top, 4)
        } else if mark == .next, !step.actions.isEmpty {
            SetupButtons(actions: step.actions).padding(.top, 4)
        }
        if mark == .next, step.note != nil || step.link != nil {
            HStack(spacing: 4) {
                if let note = step.note { Text(note) }
                if let link = step.link {
                    Button(link.title) { link.perform() }.buttonStyle(.link)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var howTo: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(step.howTo.enumerated()), id: \.offset) { index, line in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(index + 1).").monospacedDigit().foregroundStyle(.secondary)
                    Text(line).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .font(.callout)
    }
}

/// A step's buttons: the first is the main one.
private struct SetupButtons: View {
    let actions: [SetupAction]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(actions.enumerated()), id: \.element) { index, action in
                if index == 0 {
                    Button(action.title) { action.perform() }.buttonStyle(.borderedProminent)
                } else {
                    Button(action.title) { action.perform() }
                }
            }
        }
    }
}

/// A download step's buttons, or its progress bar while it runs, or what went wrong and Try Again.
private struct InstallerControls: View {
    @ObservedObject var installer: Installer
    let actions: [SetupAction]
    let showIdle: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch installer.phase {
            case .idle:
                if showIdle { SetupButtons(actions: actions) }
            case let .downloading(received, total):
                progress(total > 0 ? Double(received) / Double(total) : nil,
                         total > 0 ? "Downloading, \(Self.size(received)) of \(Self.size(total))" : "Downloading…")
            case let .installing(text):
                progress(nil, text)
            case let .failed(message):
                VStack(alignment: .leading, spacing: 8) {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    SetupButtons(actions: [.install("Try Again", installer)] + actions.dropFirst())
                }
            case let .waiting(text):
                VStack(alignment: .leading, spacing: 8) {
                    Label(text, systemImage: "hand.point.right.fill")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    SetupButtons(actions: [.install("Try Again", installer)] + actions.dropFirst())
                }
            }
        }
        .animation(reduceMotion ? nil : setupSpring, value: installer.phase)
    }

    private func progress(_ fraction: Double?, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .accessibilityLabel(text)
                if installer.canCancel {
                    Button("Cancel") { installer.cancel() }.controlSize(.small)
                }
            }
            Text(text).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        .transition(.opacity)
    }

    private static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

// MARK: Image settings

/// The saved phone and Mac image settings, which the Live Controls panel changes. onChange runs on main after every change.
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
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginStatus.value = SMAppService.mainApp.status
            checkNotifications()
        }
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
    /// What the webcam is doing while it isn't live and can't be started from here, such as "Reconnecting to the phone".
    @Published var busy: String?
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
                if let busy = model.busy {
                    ProgressView().controlSize(.small)
                    Text(busy).font(.callout).foregroundStyle(.secondary)
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
