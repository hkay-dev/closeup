import AppKit
import ServiceManagement
import SwiftUI

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

    static func register() {
        UserDefaults.standard.register(defaults: [startOnPlugIn: false, notifications: true, macSharpness: 0.0])
    }
}

/// The app's display name, so the brand can change in Info.plist alone.
let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? ProcessInfo.processInfo.processName
let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development build"

/// Puts a window in front of the app the user is in. Activation alone doesn't bring an accessory app forward.
func bringForward(_ window: NSWindow) {
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

struct SetupView: View {
    @ObservedObject var model: SetupModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var copied: SetupAction?

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
                                    Button(copied == action ? "Copied" : action.title) { run(action) }
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
        copied = action
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { if copied == action { copied = nil } }
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
        let data = UserDefaults.standard.data(forKey: Prefs.imageSettings)
        phone = data.flatMap { try? JSONDecoder().decode(PhoneImageSettings.self, from: $0) } ?? PhoneImageSettings()
        macSharpness = UserDefaults.standard.double(forKey: Prefs.macSharpness)
    }

    func reset() {
        phone = PhoneImageSettings()
        macSharpness = 0
    }

    private func save() {
        if let data = try? JSONEncoder().encode(phone) { UserDefaults.standard.set(data, forKey: Prefs.imageSettings) }
        UserDefaults.standard.set(macSharpness, forKey: Prefs.macSharpness)
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
    @AppStorage(Prefs.startOnPlugIn) private var startOnPlugIn = false
    @AppStorage(Prefs.notifications) private var notifications = true
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var loginError: String?
    let onNotificationsChange: (Bool) -> Void

    var body: some View {
        Form {
            Toggle("Launch at login", isOn: Binding(get: { loginStatus == .enabled }, set: setLaunchAtLogin))
            if loginStatus == .requiresApproval {
                HStack {
                    Text("Allow \(appName) in Login Items to finish.").font(.callout).foregroundStyle(.secondary)
                    Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                }
            }
            if let loginError { Text(loginError).font(.callout).foregroundStyle(.secondary) }
            Toggle("Start when the phone is plugged in", isOn: $startOnPlugIn)
            Text("Starts the webcam once when your saved phone connects. After you stop it, it waits until you plug the phone in again.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Toggle("Notifications", isOn: $notifications)
                .onChange(of: notifications) { onNotificationsChange($0) }
            Text("When the webcam starts, stops on an error, the phone gets hot or the cable comes loose.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("Version \(appVersion) · phone server \(ScrcpyServer.version)")
                .font(.footnote).foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.top, 10)
        }
        .padding(20)
        .frame(width: 420)
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Couldn't change it. \(error.localizedDescription)"
        }
        loginStatus = SMAppService.mainApp.status
    }
}

// MARK: Audio sync check

final class SyncCheckModel: ObservableObject {
    enum Phase: Equatable { case idle, listening, result(String), failed(String) }
    @Published var phase = Phase.idle
    @Published var live = false
    var begin: () -> Void = {}
}

struct SyncCheckView: View {
    @ObservedObject var model: SyncCheckModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Measures how far the video lags behind the sound on this Mac.")
            Text("Clap once, in the middle of the picture, with the webcam live.")
                .fontWeight(.semibold)
            Text("Press Start, then clap where the Mac's microphone can hear it. The test listens to the default microphone for 6 seconds. Nothing is saved.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            switch model.phase {
            case .idle: EmptyView()
            case .listening:
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Listening. Clap once.") }
            case let .result(text):
                Label { Text(text).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: "checkmark.circle") }
            case let .failed(text):
                Label { Text(text).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: "exclamationmark.triangle") }
            }
            if !model.live {
                Text("Start the webcam first.").font(.callout).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button(startTitle) { model.begin() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.live || model.phase == .listening)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private var startTitle: String {
        switch model.phase {
        case .idle, .listening: return "Start"
        case .result, .failed: return "Test Again"
        }
    }

    /// Plain words for a measured lag. Positive means the video reaches the Mac after the sound.
    static func describe(_ lagMs: Double) -> String {
        let ms = Int(abs(lagMs).rounded())
        if ms < 20 { return "Sound and picture are in sync (\(ms) ms apart)." }
        if lagMs > 0 {
            return "The video reaches the Mac \(ms) ms after the sound. To line them up, delay the audio by \(ms) ms in your recording or call app."
        }
        return "The sound reaches the Mac \(ms) ms after the video. To line them up, delay the video by \(ms) ms in your recording app."
    }
}
