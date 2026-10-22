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
    static let liveControlsShortcut = "liveControlsShortcut"
    static func lenses(_ serial: String) -> String { "lenses.\(serial)" }

    /// The app's settings. The dev automation instance keeps its own suite (see DevControl.swift).
    static let defaults: UserDefaults = DevMode.defaults ?? .standard

    static func register() {
        defaults.register(defaults: [startOnPlugIn: false, notifications: true, macSharpness: 0.0, liveControlsShortcut: true])
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

/// What Settings shows that the app owns, and what its buttons do.
final class SettingsModel: ObservableObject {
    enum Copy: Equatable { case idle, gathering, copied }
    @Published var copy = Copy.idle
    /// Why the Live Controls shortcut isn't working, such as another app holding the same keys.
    @Published var shortcutProblem: String?
    var notificationsChanged: (Bool) -> Void = { _ in }
    var shortcutChanged: (Bool) -> Void = { _ in }
    var copyDiagnostics: () -> Void = {}
    var runSetup: () -> Void = {}
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @AppStorage(Prefs.startOnPlugIn, store: Prefs.defaults) private var startOnPlugIn = false
    @AppStorage(Prefs.notifications, store: Prefs.defaults) private var notifications = true
    @AppStorage(Prefs.liveControlsShortcut, store: Prefs.defaults) private var shortcut = true
    @StateObject private var loginStatus = StateBox(SMAppService.mainApp.status)
    @StateObject private var loginError = StateBox<String?>(nil)
    @StateObject private var notificationsBlocked = StateBox(false)

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsGroup(title: "General", symbol: "gearshape") {
                SettingToggle(title: "Launch at login", hint: "Puts \(appName) in the menu bar when you log in.",
                              isOn: Binding(get: { loginStatus.value == .enabled }, set: { setLaunchAtLogin($0) })) {
                    if loginStatus.value == .requiresApproval {
                        HStack(spacing: 8) {
                            Text("Allow \(appName) in Login Items to finish.").foregroundStyle(.secondary)
                            Button("Open Login Items") {
                                if DevMode.isOn { DevMode.record("open-login-items", "Open Login Items") } else { SMAppService.openSystemSettingsLoginItems() }
                            }
                            .controlSize(.small)
                        }
                    }
                    if let loginError = loginError.value { Text(loginError).foregroundStyle(.secondary) }
                }
                GroupDivider()
                SettingToggle(title: "Start when the phone is plugged in",
                              hint: "Starts the webcam once when your saved phone connects. After you stop it, it waits until you plug the phone in again.",
                              isOn: $startOnPlugIn)
                GroupDivider()
                SettingToggle(title: "Notifications", hint: "When the webcam starts, stops on an error, the phone gets hot or the cable comes loose.",
                              isOn: $notifications) {
                    if notifications && notificationsBlocked.value {
                        Label("macOS has notifications turned off for \(appName). Turn them on in System Settings > Notifications.",
                              systemImage: "bell.slash")
                            .foregroundStyle(.orange)
                    }
                }
            }
            SettingsGroup(title: "Live Controls", symbol: "slider.horizontal.3") {
                SettingToggle(title: "Live Controls shortcut \(GlobalHotkey.label)",
                              hint: "Opens and closes Live Controls from any app, even a call in full screen.",
                              isOn: $shortcut, shownTitle: "Keyboard shortcut", keys: GlobalHotkey.keys) {
                    if shortcut, let problem = model.shortcutProblem {
                        Label(problem, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                }
            }
            SettingsGroup(title: "Help", symbol: "questionmark.circle") {
                SettingAction(title: "Report a problem",
                              hint: "Copies the app and macOS versions, the phone model, setup and recent errors for a bug report. No serial numbers.") {
                    Button("Copy Diagnostics") { model.copyDiagnostics() }
                        .disabled(model.copy == .gathering)
                    copyStatus
                }
                GroupDivider()
                SettingAction(title: "Setup", hint: "Go through the setup steps again, to check them or to set up another phone.") {
                    Button("Run Setup Again") { model.runSetup() }
                }
            }
            Text("Version \(appVersion) · phone server \(ScrcpyServer.version)")
                .font(.footnote).foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity)
        }
        .padding(22)
        .frame(width: 440)
        .animation(Motion.allowed(Motion.stageChange), value: model.copy)
        .animation(Motion.allowed(Motion.stageChange), value: model.shortcutProblem)
        .onChange(of: notifications) { model.notificationsChanged($0); checkNotifications() }
        .onChange(of: shortcut) { model.shortcutChanged($0) }
        .onAppear(perform: checkNotifications)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginStatus.value = SMAppService.mainApp.status
            checkNotifications()
        }
    }

    /// "Copied" for a moment after a press, in the spot next to the button.
    @ViewBuilder private var copyStatus: some View {
        switch model.copy {
        case .idle:
            EmptyView()
        case .gathering:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Gathering…").foregroundStyle(.secondary)
            }
            .font(.callout)
            .transition(Motion.swap)
        case .copied:
            Label { Text("Copied") } icon: { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                .font(.callout.weight(.medium))
                .transition(Motion.swap)
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

/// A rounded card with a small header, like Setup's step cards.
private struct SettingsGroup<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            VStack(alignment: .leading, spacing: 0) { content }
                .padding(.horizontal, 14)
                .padding(.vertical, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Card())
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

private struct Card: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.primary.opacity(0.04))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.07), lineWidth: 1))
    }
}

private struct GroupDivider: View {
    var body: some View { Divider().opacity(0.7) }
}

/// A title with its switch at the trailing edge and a hint under it. The switch carries the title, so tools and
/// VoiceOver read "Notifications", and a click on the title flips it too.
private struct SettingToggle<Extra: View>: View {
    let title: String
    let hint: String
    @Binding var isOn: Bool
    /// What the row shows in place of the title, when keycaps say the rest.
    var shownTitle: String? = nil
    var keys: [String] = []
    @ViewBuilder var extra: Extra

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 12) {
                HStack(spacing: 8) {
                    Text(shownTitle ?? title)
                    if !keys.isEmpty { KeyCaps(keys: keys) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { isOn.toggle() }
                .accessibilityHidden(true)
                Toggle(title, isOn: $isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            Text(hint)
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            extra
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 11)
    }
}

extension SettingToggle where Extra == EmptyView {
    init(title: String, hint: String, isOn: Binding<Bool>) {
        self.init(title: title, hint: hint, isOn: isOn) { EmptyView() }
    }
}

/// Keys drawn as small caps, as a shortcut shows on a Mac keyboard.
private struct KeyCaps: View {
    let keys: [String]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(keys, id: \.self) { key in
                Text(key)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .frame(minWidth: 20, minHeight: 20)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.primary.opacity(0.08)))
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.primary.opacity(0.14), lineWidth: 1))
            }
        }
    }
}

/// A title, a hint and a row of buttons.
private struct SettingAction<Buttons: View>: View {
    let title: String
    let hint: String
    @ViewBuilder var buttons: Buttons

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
            Text(hint)
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) { buttons }
                .padding(.top, 5)
        }
        .padding(.vertical, 11)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            hero
            stage
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
                    .controlSize(.large)
                    .disabled(!model.live || model.phase == .listening || model.microphone == nil)
            }
        }
        .padding(22)
        .frame(width: 440)
    }

    private var hero: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.72)], startPoint: .top, endPoint: .bottom))
                Image(systemName: "hands.clap.fill")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.white)
            }
            .frame(width: 52, height: 52)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Clap once, in the middle of the picture")
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text("This measures how far the video lags behind the sound on this Mac. It listens for up to 8 seconds and stops once it hears the clap. Nothing is saved.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The microphone, then the meter, the result or what went wrong. It keeps one height, so the window doesn't jump.
    private var stage: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(model.microphone ?? "No microphone found", systemImage: model.microphone == nil ? "mic.slash" : "mic")
                .font(.callout).foregroundStyle(.secondary)
                .accessibilityLabel(model.microphone.map { "Microphone: \($0)" } ?? "No microphone found")
            ZStack(alignment: .topLeading) { phaseView }
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 176, alignment: .topLeading)
        .background(Card())
        .animation(Motion.allowed(Motion.stageChange), value: model.phase)
    }

    @ViewBuilder private var phaseView: some View {
        switch model.phase {
        case .idle:
            VStack(alignment: .leading, spacing: 10) {
                ClapMeter(level: 0)
                Text(model.live ? "Press Start, then clap where the microphone can hear it." : "Start the webcam first, then press Start and clap.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .transition(Motion.swap)
        case .listening:
            VStack(alignment: .leading, spacing: 10) {
                ClapMeter(level: model.meter.level, heard: model.meter.heard)
                Text(model.meter.heard ? "Heard the clap. Matching it to the picture." : "Listening. Clap once.")
                    .font(.callout.weight(.medium))
                TimeBar(progress: model.meter.heard ? 1 : model.meter.progress)
            }
            .accessibilityElement(children: .combine)
            .transition(Motion.swap)
        case let .result(lagMs):
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("\(Int(abs(lagMs).rounded()))")
                        .font(.system(size: 50, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("ms")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Label { Text(Self.direction(lagMs)) } icon: {
                    Image(systemName: Self.inSync(lagMs) ? "checkmark.circle.fill" : "speaker.wave.2.fill")
                        .foregroundStyle(Self.inSync(lagMs) ? Color.green : Color.orange)
                }
                .font(.headline)
                Text(Self.advice(lagMs))
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .padding(.top, 4)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(Self.headline(lagMs)). \(Self.advice(lagMs))")
            .transition(Motion.swap)
        case let .failed(text, microphoneSettings):
            VStack(alignment: .leading, spacing: 10) {
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
            .transition(Motion.swap)
        }
    }

    private var startTitle: String {
        switch model.phase {
        case .idle, .listening: return "Start"
        case .result, .failed: return "Test Again"
        }
    }

    private static func inSync(_ lagMs: Double) -> Bool { abs(lagMs).rounded() < 20 }

    /// The line under the big number. Positive lag means the video reaches the Mac after the sound.
    static func direction(_ lagMs: Double) -> String {
        if inSync(lagMs) { return "In sync" }
        return lagMs > 0 ? "Video is behind the sound" : "Sound is behind the video"
    }

    /// The result as one line, for VoiceOver and the dev tools.
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

/// A wide rounded bar that follows the microphone level on a spring, and fills once the clap is heard.
private struct ClapMeter: View {
    let level: Float
    var heard = false

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(LinearGradient(colors: [Color.green.opacity(0.75), Color.green], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(12, geometry.size.width * fraction))
                    .opacity(heard || level > 0.01 ? 1 : 0)
            }
        }
        .frame(height: 12)
        .animation(Motion.allowed(Motion.entrance), value: level)
        .animation(Motion.allowed(Motion.stageChange), value: heard)
        .accessibilityHidden(true)
    }

    private var fraction: CGFloat { heard ? 1 : CGFloat(min(max(level, 0), 1)) }
}

/// How much of the 8 seconds the test has used.
private struct TimeBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule().fill(Color.accentColor.opacity(0.8))
                    .frame(width: geometry.size.width * CGFloat(min(max(progress, 0), 1)))
            }
        }
        .frame(height: 4)
        .animation(Motion.allowed(.linear(duration: 0.05)), value: progress)
        .accessibilityHidden(true)
    }
}
