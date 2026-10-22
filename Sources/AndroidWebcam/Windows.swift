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

/// Asks macOS to make this app the active one. Since macOS 14 that's a request, which it may turn down while the user
/// is busy in another app.
func activateApp() {
    if #available(macOS 14, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
}

/// Puts a window in front of the app the user is in. Activation alone doesn't bring an accessory app forward.
/// The dev automation instance parks it below the desktop instead.
func bringForward(_ window: NSWindow) {
    if DevMode.isOn { DevMode.park(window); return }
    activateApp()
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

    func window(_ id: String) -> NSWindow? { windows[id] }

    /// A window that grows (Setup opening a step) keeps its top edge, which can run it under the Dock: lift it back up.
    func windowDidResize(_ notification: Notification) {
        guard !DevMode.isOn, let window = notification.object as? NSWindow, let visible = window.screen?.visibleFrame,
              window.frame.minY < visible.minY else { return }
        let lift = min(visible.minY - window.frame.minY, max(0, visible.maxY - window.frame.maxY))
        guard lift > 0 else { return }
        window.setFrameOrigin(NSPoint(x: window.frame.minX, y: window.frame.minY + lift))
    }

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
    var tip: String? = nil              // a line above "Show me how" while pending
    var more: [String] = []             // behind a "Show me how" disclosure: numbered, or bullets after a howTo
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
    /// The tallest the window can be on its screen; the steps scroll past it.
    @Published var maxWindowHeight = CGFloat.infinity
    /// The screen Setup's window is on.
    var screen: () -> NSScreen? = { NSScreen.main }
    private var screenObserver: NSObjectProtocol?

    init() {
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                object: nil, queue: .main) { [weak self] _ in self?.fit() }
    }

    /// A short screen (a 1440×900 Mac with the Dock has about 740 pt) can't fit every step open, so they scroll there.
    func fit() {
        var height = screen().map { $0.visibleFrame.height - 16 } ?? .infinity
        // The dev instance can stand in for a short screen, as Live Controls does: dev.sh start devScreenHeight:=740
        if DevMode.isOn, let fake = Prefs.defaults.object(forKey: "devScreenHeight") as? Double { height = fake }
        if maxWindowHeight != height { maxWindowHeight = height }
    }
}

/// View-local state held in an object, so these views don't need the `@State` macro (the Command Line Tools toolchain has no SwiftUIMacros plugin).
final class StateBox<Value>: ObservableObject {
    @Published var value: Value
    init(_ value: Value) { self.value = value }
}

struct SetupView: View {
    @ObservedObject var model: SetupModel
    /// Natural heights of the header, the steps and the footer.
    @StateObject private var heroHeight = StateBox(CGFloat(0))
    @StateObject private var stepsHeight = StateBox(CGFloat(0))
    @StateObject private var footerHeight = StateBox(CGFloat(0))
    private var change: Animation? { Motion.allowed(Motion.stageChange) }

    /// Title bar, paddings and the spacing between the three parts: what the window adds around them.
    private static let chrome: CGFloat = 28 + 22 * 2 + 18 * 2

    /// The steps' height on screen: all of them, or what fits between the header and the footer on a short screen.
    private var stepsShown: CGFloat? {
        guard stepsHeight.value > 0 else { return nil }
        let room = model.maxWindowHeight - Self.chrome - heroHeight.value - footerHeight.value
        return max(200, min(stepsHeight.value, room))
    }

    private var scrolls: Bool { stepsShown.map { $0 < stepsHeight.value - 0.5 } ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            hero.background(HeightReader(box: heroHeight))
            ScrollViewReader { scroller in
                ScrollView(.vertical, showsIndicators: scrolls) {
                    VStack(spacing: 8) {
                        ForEach(Array(model.steps.enumerated()), id: \.element.id) { index, step in
                            SetupStepCard(number: index + 1, step: step,
                                          mark: step.done ? .done : step.id == model.nextStep?.id ? .next : .later)
                                .id(step.id)
                        }
                    }
                    .background(HeightReader(box: stepsHeight))
                    // Room past the soft edges, outside the reader so it never feeds back into whether it scrolls.
                    .padding(.vertical, scrolls ? 10 : 0)
                }
                .scrollDisabled(!scrolls)
                .frame(height: stepsShown)
                // Soft edges where the steps scroll under the header and the footer.
                .mask {
                    VStack(spacing: 0) {
                        LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: scrolls ? 10 : 0)
                        Color.black
                        LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: scrolls ? 10 : 0)
                    }
                }
                // On a short screen, the step to do next comes into view when the one before it turns done.
                .onChange(of: model.nextStep?.id) { id in
                    guard let id else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        guard scrolls else { return }
                        withAnimation(change) { scroller.scrollTo(id, anchor: .top) }
                    }
                }
            }
            footer.background(HeightReader(box: footerHeight))
        }
        .padding(22)
        .frame(width: 470)
        .animation(change, value: model.steps)
    }

    private var footer: some View {
        HStack(alignment: .center) {
            // The hint and the Start button swap as one when the last step turns done.
            ZStack(alignment: .leading) {
                Text(model.complete ? "You can also start it from the menu bar." : "This list checks itself every few seconds.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .id(model.complete)
                    .transition(Motion.swap)
            }
            Spacer()
            if model.complete {
                Button("Start Webcam") { model.start() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .transition(Motion.swap)
            }
        }
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
                            .transition(Motion.swap)
                    }
                }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                // "Set up" and "All set" share one spot: the old words leave before the new ones come in.
                ZStack(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.complete ? "All set" : "Set up \(appName)")
                            .font(.title2.weight(.semibold))
                        Text(model.complete ? "In your call app, choose OBS Virtual Camera as the camera."
                                            : "Use your Android phone's camera as your Mac's webcam.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .id(model.complete)
                    .transition(Motion.swap)
                }
                if !model.complete, !model.steps.isEmpty {
                    Text("\(model.doneCount) of \(model.steps.count) steps done")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                        .transition(Motion.swap)
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
    @StateObject private var showHow = StateBox(false)

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

    /// The number turning into a check: the old mark leaves before the new one comes in, so they never blend.
    private var badge: some View {
        ZStack {
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
            .id(mark)
            .transition(Motion.swap)
        }
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)
    }

    /// The how-to, buttons, extra help and note of a step that isn't done. A later step keeps only a download that's
    /// under way.
    @ViewBuilder private var pending: some View {
        if mark == .next, !step.howTo.isEmpty { list(step.howTo, numbered: true) }
        if let installer = step.installer {
            InstallerControls(installer: installer, actions: step.actions, showIdle: mark == .next)
                .padding(.top, 4)
        } else if mark == .next, !step.actions.isEmpty {
            SetupButtons(actions: step.actions).padding(.top, 4)
        }
        if mark == .next, let tip = step.tip {
            Text(tip).font(.callout).fixedSize(horizontal: false, vertical: true)
        }
        if mark == .next, !step.more.isEmpty {
            DisclosureGroup(isExpanded: $showHow.value.animation(Motion.allowed(Motion.stageChange))) {
                list(step.more, numbered: step.howTo.isEmpty).padding(.top, 4)
            } label: {
                // A DisclosureGroup toggles only from its chevron; the words should open it too.
                Text("Show me how")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(Motion.allowed(Motion.stageChange)) { showHow.value.toggle() } }
            }
            .font(.callout)
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

    private func list(_ lines: [String], numbered: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(numbered ? "\(index + 1)." : "•").monospacedDigit().foregroundStyle(.secondary)
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

    var body: some View {
        // One spot: buttons, progress or a problem leave before the next look comes in.
        ZStack(alignment: .topLeading) {
            Group {
                switch installer.phase {
                case .idle:
                    if showIdle { SetupButtons(actions: actions) }
                case let .downloading(received, total):
                    progress(total > 0 ? Double(received) / Double(total) : nil,
                             total > 0 ? "Downloading, \(Self.megabytes(received)) of \(Self.megabytes(total)) MB"
                                       : "Downloading, \(Self.megabytes(received)) MB")
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
            .id(look)
            .transition(Motion.swap)
        }
        // Keyed on the look, not the phase: a download's bytes change many times a second and move in place.
        .animation(Motion.allowed(Motion.stageChange), value: look)
    }

    /// Which look the phase shows. Progress within a download or an install keeps the same look.
    private var look: String {
        switch installer.phase {
        case .idle: showIdle ? "idle" : "none"
        case .downloading, .installing: "progress"
        case let .failed(message): "failed " + message
        case let .waiting(text): "waiting " + text
        }
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
    }

    private static func megabytes(_ bytes: Int64) -> Int {
        Int((Double(bytes) / 1_000_000).rounded())
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
    enum Update: Equatable { case idle, checking, done(Updates.Result) }
    @Published var copy = Copy.idle
    @Published var update = Update.idle
    /// Why the Live Controls shortcut isn't working, such as another app holding the same keys.
    @Published var shortcutProblem: String?
    var notificationsChanged: (Bool) -> Void = { _ in }
    var shortcutChanged: (Bool) -> Void = { _ in }
    var copyDiagnostics: () -> Void = {}
    var runSetup: () -> Void = {}

    func checkForUpdates() {
        guard update != .checking else { return }
        update = .checking
        Updates.check(current: appVersion) { [weak self] in self?.update = .done($0) }
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @AppStorage(Prefs.startOnPlugIn, store: Prefs.defaults) private var startOnPlugIn = false
    @AppStorage(Prefs.notifications, store: Prefs.defaults) private var notifications = true
    @AppStorage(Prefs.liveControlsShortcut, store: Prefs.defaults) private var shortcut = true
    @StateObject private var loginStatus = StateBox(SMAppService.mainApp.status)
    @StateObject private var loginError = StateBox<String?>(nil)
    @StateObject private var notificationsBlocked = StateBox(false)
    private var change: Animation? { Motion.allowed(Motion.stageChange) }

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
                        Label {
                            Text("macOS has notifications turned off for \(appName). Turn them on in System Settings > Notifications.")
                        } icon: {
                            Image(systemName: "bell.slash").foregroundStyle(.orange)
                        }
                    }
                }
            }
            SettingsGroup(title: "Live Controls", symbol: "slider.horizontal.3") {
                SettingToggle(title: "Live Controls shortcut \(GlobalHotkey.label)",
                              hint: "Opens and closes Live Controls from any app, even a call in full screen.",
                              isOn: $shortcut, shownTitle: "Keyboard shortcut", keys: GlobalHotkey.keys) {
                    if shortcut, let problem = model.shortcutProblem {
                        Label { Text(problem) } icon: { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                    }
                }
            }
            SettingsGroup(title: "Help", symbol: "questionmark.circle") {
                SettingAction(title: "Report a problem",
                              hint: "Copies the app and macOS versions, the phone model, setup and recent errors for a bug report. No serial numbers.") {
                    Button("Copy Diagnostics") { model.copyDiagnostics() }
                        .disabled(model.copy == .gathering)
                    // Gathering… and Copied share one spot, so Copied doesn't land to the right and then slide back.
                    ZStack(alignment: .leading) { copyStatus }
                }
                GroupDivider()
                SettingAction(title: "Setup", hint: "Go through the setup steps again, to check them or to set up another phone.") {
                    Button("Run Setup Again") { model.runSetup() }
                }
                GroupDivider()
                SettingAction(title: "Updates", hint: "Asks GitHub whether there's a newer version. It only checks when you click.") {
                    Button("Check for Updates") { model.checkForUpdates() }
                        .disabled(model.update == .checking)
                    ZStack(alignment: .leading) { updateStatus }
                }
            }
            Text("Version \(appVersion) · phone server \(ScrcpyServer.version)")
                .font(.footnote).foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity)
        }
        .padding(22)
        .frame(width: 440)
        // Notes under a switch come and go on the same spring as Copied.
        .animation(change, value: model.copy)
        .animation(change, value: model.shortcutProblem)
        .animation(change, value: model.update)
        .animation(change, value: shortcut)
        .animation(change, value: notifications && notificationsBlocked.value)
        .animation(change, value: loginStatus.value)
        .animation(change, value: loginError.value)
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

    /// What the last update check found, in the spot next to its button.
    @ViewBuilder private var updateStatus: some View {
        switch model.update {
        case .idle:
            EmptyView()
        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Checking…").foregroundStyle(.secondary)
            }
            .font(.callout)
            .transition(Motion.swap)
        case .done(.upToDate):
            Label { Text("You're up to date") } icon: { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                .font(.callout.weight(.medium))
                .transition(Motion.swap)
        case let .done(.available(version, page)):
            HStack(spacing: 8) {
                Label { Text("Version \(version) is out") } icon: { Image(systemName: "arrow.down.circle.fill").foregroundStyle(Color.accentColor) }
                    .font(.callout.weight(.medium))
                Button("Get It") {
                    if DevMode.isOn { DevMode.record("open-url", page.absoluteString) } else { NSWorkspace.shared.open(page) }
                }
                .controlSize(.small)
            }
            .transition(Motion.swap)
        case let .done(.failed(message)):
            Text(message).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
                // What the webcam is doing swaps in one spot as it starts, so its words never pile up.
                ZStack(alignment: .leading) {
                    HStack(spacing: 8) {
                        if let busy = model.busy {
                            ProgressView().controlSize(.small)
                            Text(busy).font(.callout).foregroundStyle(.secondary)
                        } else if !model.live {
                            Text("The webcam isn't live.").font(.callout).foregroundStyle(.secondary)
                            Button("Start Webcam") { model.startWebcam() }
                        }
                    }
                    .id(webcamState)
                    .transition(Motion.swap)
                }
                Spacer()
                Button(startTitle) { model.begin() }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
                    .disabled(!model.live || model.phase == .listening || model.microphone == nil)
            }
            .animation(change, value: webcamState)
            .animation(change, value: startTitle)
        }
        .padding(22)
        .frame(width: 440)
    }

    private var change: Animation? { Motion.allowed(Motion.stageChange) }
    private var webcamState: String { model.busy ?? (model.live ? "live" : "off") }

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
        .animation(change, value: model.phase)
        .animation(change, value: meterText)
    }

    /// The line under the meter: what to do before the test, then what it's hearing.
    private var meterText: String {
        switch model.phase {
        case .listening: model.meter.heard ? "Heard the clap. Matching it to the picture." : "Listening. Clap once."
        default: model.live ? "Press Start, then clap where the microphone can hear it."
            : model.busy != nil ? "Press Start once the picture is live, then clap."
            : "Start the webcam below, then press Start and clap."
        }
    }

    @ViewBuilder private var phaseView: some View {
        switch model.phase {
        case .idle, .listening:
            // One meter for both, so pressing Start doesn't swap it for a copy of itself.
            let listening = model.phase == .listening
            VStack(alignment: .leading, spacing: 10) {
                ClapMeter(level: listening ? model.meter.level : 0, heard: listening && model.meter.heard)
                ZStack(alignment: .topLeading) {
                    Text(meterText)
                        .font(listening ? .callout.weight(.medium) : .callout)
                        .foregroundStyle(listening ? HierarchicalShapeStyle.primary : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .id(meterText)
                        .transition(Motion.swap)
                }
                if listening {
                    TimeBar(progress: model.meter.heard ? 1 : model.meter.progress)
                        .transition(Motion.swap)
                }
            }
            .accessibilityElement(children: listening ? .combine : .contain)
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
        LayerBar(fraction: heard ? 1 : CGFloat(min(max(level, 0), 1)), minWidth: 12, visible: heard || level > 0.01,
                 colors: [NSColor.systemGreen.withAlphaComponent(0.75), .systemGreen], move: .spring)
            .frame(height: 12)
            .accessibilityHidden(true)
    }
}

/// How much of the 8 seconds the test has used.
private struct TimeBar: View {
    let progress: Double

    var body: some View {
        LayerBar(fraction: CGFloat(min(max(progress, 0), 1)),
                 colors: [NSColor.controlAccentColor.withAlphaComponent(0.8)], move: .linear)
            .frame(height: 4)
            .accessibilityHidden(true)
    }
}

/// A rounded bar whose fill moves in Core Animation, in the render server: the test sends 20 readings a second for 8
/// seconds, and a SwiftUI spring on each would keep the main thread busy every frame.
private struct LayerBar: NSViewRepresentable {
    /// A level springs to each reading (the entrance spring); a clock moves linearly over the 0.05 s between them.
    enum Move { case spring, linear }

    let fraction: CGFloat
    var minWidth: CGFloat = 0
    var visible = true
    let colors: [NSColor]
    let move: Move

    func makeNSView(context: Context) -> BarView { BarView(colors: colors) }
    func updateNSView(_ view: BarView, context: Context) {
        view.set(fraction: fraction, minWidth: minWidth, visible: visible, move: move)
    }

    final class BarView: NSView {
        private let fill = CAGradientLayer()
        private let colors: [NSColor]
        private var fraction: CGFloat = 0
        private var minWidth: CGFloat = 0
        private var visible = true

        init(colors: [NSColor]) {
            self.colors = colors.count == 1 ? colors + colors : colors
            super.init(frame: .zero)
            wantsLayer = true
            fill.startPoint = CGPoint(x: 0, y: 0.5)
            fill.endPoint = CGPoint(x: 1, y: 0.5)
            fill.anchorPoint = CGPoint(x: 0, y: 0.5)
            layer?.addSublayer(fill)
        }

        required init?(coder: NSCoder) { fatalError("Use init(colors:).") }

        override var wantsUpdateLayer: Bool { true }

        // Runs with the view's light or dark look current, so the colors follow it.
        override func updateLayer() {
            layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            fill.colors = colors.map(\.cgColor)
            CATransaction.commit()
        }

        override func layout() {
            super.layout()
            place(nil)
        }

        func set(fraction: CGFloat, minWidth: CGFloat, visible: Bool, move: Move) {
            guard fraction != self.fraction || minWidth != self.minWidth || visible != self.visible else { return }
            self.fraction = fraction
            self.minWidth = minWidth
            self.visible = visible
            place(move)
        }

        private func place(_ move: Move?) {
            let height = bounds.height
            layer?.cornerRadius = height / 2
            let target = CGRect(x: 0, y: 0, width: max(minWidth, bounds.width * fraction), height: height)
            let opacity: Float = visible ? 1 : 0
            if let move, window != nil, !Motion.reduced {
                let from = NSValue(rect: fill.presentation()?.bounds ?? fill.bounds)
                switch move {
                case .spring:
                    fill.add(Motion.spring("bounds", from: from, to: NSValue(rect: target), response: 0.3, damping: 0.86), forKey: "bounds")
                case .linear:
                    let step = CABasicAnimation(keyPath: "bounds")
                    step.fromValue = from
                    step.toValue = NSValue(rect: target)
                    step.duration = 0.05
                    fill.add(step, forKey: "bounds")
                }
                if fill.opacity != opacity {
                    fill.add(Motion.spring("opacity", from: fill.presentation()?.opacity ?? fill.opacity, to: opacity), forKey: "opacity")
                }
            }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            fill.bounds = target
            fill.position = CGPoint(x: 0, y: height / 2)
            fill.cornerRadius = height / 2
            fill.opacity = opacity
            CATransaction.commit()
        }
    }
}
