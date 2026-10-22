import AppKit
import SwiftUI

/// What the Live Controls panel shows besides the picture settings: the header's status and the camera's state.
struct LiveControlsState: Equatable {
    var dot: MenuHeaderView.Dot = .off
    var status = ""
    var model: String?
    var stats: PhoneStats?
    var badge: String?          // "LIVE 0:42" while the picture is live
    var note: String?           // the header's note, unless it's the lens note below
    var lenses: [CameraLens] = []
    var lensID: String?
    var lensNote: String?       // why the last lens pick went back
    var running = false
    var stopping = false
    var phoneSelected = false
    var canControl = false      // live and not switching lenses
    var switching = false
    var torchOn = false
    /// The panel's own way to start: Start Webcam when the menu's would be enabled, Finish Setup while setup isn't
    /// done, none while running. It never offers Stop, which is too easy to hit mid-call.
    var start: StartAction?

    enum StartAction: Equatable { case start, finishSetup }
}

final class LiveControlsModel: ObservableObject {
    @Published var state = LiveControlsState()
    /// Drives the panel's entrance.
    @Published var appeared = false
    var selectLens: (String) -> Void = { _ in }
    var zoomIn: () -> Void = {}
    var zoomOut: () -> Void = {}
    var toggleTorch: () -> Void = {}
    /// The menu's main action: starts the webcam, or opens Setup while setup isn't done.
    var mainAction: () -> Void = {}
}

/// A floating HUD panel for changing the picture during a call. It floats over full-screen call apps and every Space,
/// and doesn't take the call app's place as the active app.
final class LiveControlsPanel: NSObject, NSWindowDelegate {
    static let id = "controls"
    static let pictureSize = NSSize(width: 288, height: 162)

    let model = LiveControlsModel()
    let picture = PreviewView(frame: NSRect(origin: .zero, size: LiveControlsPanel.pictureSize), titleSize: 13, textSize: 11)
    /// Runs with true when the panel opens and false when it closes.
    var onOpenChange: (Bool) -> Void = { _ in }
    var isOpen: Bool { panel != nil }

    private let store: ImageSettingsStore
    private var panel: NSPanel?
    private var loggedPictureError = false

    init(store: ImageSettingsStore) {
        self.store = store
        super.init()
        picture.layer?.cornerRadius = 12
        picture.layer?.masksToBounds = true
        picture.setAccessibilityElement(false)
    }

    /// Opens the panel, the first time near the top right of `screen` (the status item's), without taking the
    /// call app's place as the active app: a nonactivating panel still gets keys for its sliders and Esc.
    func show(on screen: NSScreen?) {
        if let panel { present(panel); return }
        let host = NSHostingController(rootView: LiveControlsView(model: model, store: store, picture: picture))
        host.sizingOptions = [.preferredContentSize]
        let panel = HUDPanel(contentRect: NSRect(x: 0, y: 0, width: LiveControlsView.width, height: 600),
                             styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        panel.contentViewController = host
        panel.title = "Live Controls"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.isReleasedWhenClosed = false
        panel.identifier = NSUserInterfaceItemIdentifier(Self.id)
        panel.delegate = self
        for kind in [NSWindow.ButtonType.miniaturizeButton, .zoomButton] { panel.standardWindowButton(kind)?.isHidden = true }
        // Sized before it's placed, so the saved or top-right spot fits the panel.
        panel.setContentSize(host.view.fittingSize)
        // The dev instance keeps no frame in the app's real defaults.
        if DevMode.isOn {
            panel.center()
        } else {
            // A saved spot on a display that's gone now would leave the panel where nobody can see it.
            if !panel.setFrameUsingName("LiveControls")
                || !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(panel.frame) }) {
                placeTopRight(panel, on: screen)
            }
            panel.setFrameAutosaveName("LiveControls")
        }
        self.panel = panel
        onOpenChange(true)
        model.appeared = Motion.reduced
        present(panel)
        guard !Motion.reduced else { return }
        // The first frame goes out with the content clear, then it fades and grows in.
        DispatchQueue.main.async { [weak self] in
            withAnimation(Motion.entrance) { self?.model.appeared = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { self?.panel?.invalidateShadow() }
        }
    }

    func close() { panel?.close() }

    private func present(_ panel: NSPanel) {
        if DevMode.isOn { DevMode.park(panel); return }
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    /// Near the menu bar's right end, where the status item is, out of the way of a call's faces.
    private func placeTopRight(_ panel: NSPanel, on screen: NSScreen?) {
        guard let screen = screen ?? NSScreen.main else { panel.center(); return }
        let visible = screen.visibleFrame
        panel.setFrameTopLeftPoint(NSPoint(x: visible.maxX - panel.frame.width - 16, y: visible.maxY - 12))
    }

    /// Shows a frame in the panel's picture. Main thread only.
    func show(_ frame: CVPixelBuffer) {
        do { try picture.show(frame) }
        catch where !loggedPictureError {
            loggedPictureError = true
            fputs("Live Controls picture failed. \(error.logText)\n", stderr)
        } catch {}
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === panel else { return }
        panel = nil
        model.appeared = false
        onOpenChange(false)
    }
}

/// Esc closes it, as it does a popover.
private final class HUDPanel: NSPanel {
    override func cancelOperation(_ sender: Any?) { performClose(sender) }
}

// MARK: View

struct LiveControlsView: View {
    static let width: CGFloat = 320
    private static let inner = width - 32

    @ObservedObject var model: LiveControlsModel
    @ObservedObject var store: ImageSettingsStore
    let picture: PreviewView
    @StateObject private var more = StateBox(false)
    @Namespace private var lensSpace
    @Namespace private var balanceSpace
    @Namespace private var focusSpace

    private var state: LiveControlsState { model.state }
    private var change: Animation? { Motion.allowed(Motion.stageChange) }

    var body: some View {
        VStack(spacing: 12) {
            livePicture
            statusLines
            if let start = state.start {
                startButton(start).transition(Motion.swap)
            }
            cameraModule
            pictureModule
            Text("Call apps list this camera as OBS Virtual Camera.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .animation(change, value: state.start)
        .padding(.horizontal, 16)
        .padding(.top, 2)
        .padding(.bottom, 14)
        .frame(width: Self.width)
        // The title sits in the clear title bar, beside the close button; the content starts below it.
        .overlay(alignment: .top) {
            Text("Live Controls")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(height: 28)
                .offset(y: -28)
                .accessibilityHidden(true)
        }
        .background(HUDBackground(radius: 18).ignoresSafeArea())
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1).ignoresSafeArea())
        .opacity(model.appeared ? 1 : 0)
        .scaleEffect(model.appeared ? 1 : 0.97)
        .environment(\.colorScheme, .dark)
    }

    // MARK: Picture and status

    private var livePicture: some View {
        PictureHost(view: picture, size: CGSize(width: Self.inner, height: Self.inner * 9 / 16))
            .frame(width: Self.inner, height: Self.inner * 9 / 16)
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
            .overlay(alignment: .topLeading) {
                if let badge = state.badge {
                    LivePill(text: badge).padding(8).transition(Motion.swap)
                }
            }
            .animation(change, value: state.badge != nil)
            .accessibilityElement()
            .accessibilityAddTraits(.isImage)
            .accessibilityLabel(state.badge != nil ? "Live picture" : "No live picture")
    }

    private var statusLines: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 7) {
                Circle().fill(Color(nsColor: state.dot.color)).frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(state.status)
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .lineLimit(1)
            }
            HStack(spacing: 10) {
                if let model = state.model { Text(model).lineLimit(1) }
                if let stats = state.stats { StatsView(stats: stats) }
                if state.model == nil && state.stats == nil { Text("No phone running").lineLimit(1) }
            }
            .font(.system(size: 11).monospacedDigit())
            .foregroundStyle(.secondary)
            if let note = state.note {
                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(Motion.swap)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 2)
        .accessibilityElement(children: .combine)
    }

    // MARK: Camera: lens, zoom, flashlight

    private var cameraModule: some View {
        Module {
            if state.lenses.isEmpty {
                Text(state.phoneSelected ? "This phone hasn't listed its lenses yet." : "No phone is selected.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ChipFlow(spacing: 6) {
                    ForEach(state.lenses, id: \.id) { lens in
                        Chip(selected: lens.id == state.lensID, space: lensSpace, id: "lens") {
                            model.selectLens(lens.id)
                        } label: {
                            Text(lens.label).font(.system(size: 12, weight: .medium)).padding(.horizontal, 11)
                        }
                        .frame(height: 28)
                        .accessibilityLabel(lens.label)
                        .help("Switch to the \(lens.label) camera")
                    }
                }
                .disabled(!state.canControl)
            }
            HStack(spacing: 8) {
                HStack(spacing: 0) {
                    RepeatButton(label: "Zoom out", symbol: "minus", active: model.appeared, action: model.zoomOut)
                    Text("Zoom")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.white.opacity(state.canControl ? 0.85 : 0.4))
                        .frame(width: 48)
                        .accessibilityHidden(true)
                    RepeatButton(label: "Zoom in", symbol: "plus", active: model.appeared, action: model.zoomIn)
                }
                .padding(2)
                .background(Capsule().fill(Color.white.opacity(0.08)))
                Spacer(minLength: 0)
                Toggle(isOn: Binding(get: { state.torchOn }, set: { _ in model.toggleTorch() })) {
                    Text("Flashlight")
                }
                .toggleStyle(TileToggleStyle(symbolOn: "flashlight.on.fill", symbolOff: "flashlight.off.fill"))
                .help("Turn the phone's flashlight \(state.torchOn ? "off" : "on")")
            }
            .disabled(!state.canControl)
            // Old and new words share one spot while they swap, so the module doesn't grow for a moment.
            ZStack(alignment: .topLeading) {
                Text(cameraHint)
                    .font(.system(size: 11))
                    .foregroundStyle(state.lensNote != nil ? Color.orange : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id(cameraHint)
                    .transition(Motion.swap)
            }
        }
        .animation(change, value: state.lensID)
        .animation(change, value: cameraHint)
        .animation(change, value: state.canControl)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Camera")
    }

    private var cameraHint: String {
        if let note = state.lensNote { return note }
        if state.stopping { return "Stopping the webcam." }
        if state.switching { return "Switching camera. Your call keeps the camera." }
        if state.canControl { return "Hold a zoom button to keep zooming." }
        if state.running { return "Lens, zoom and flashlight work once the picture is live." }
        if !state.phoneSelected { return "Plug in your phone, then start the webcam." }
        return "Start the webcam to switch lenses."
    }

    /// Start Webcam, or Finish Setup while setup isn't done: the menu's main action, without its Stop.
    private func startButton(_ action: LiveControlsState.StartAction) -> some View {
        let title = action == .start ? "Start Webcam" : "Finish Setup…"
        return Button(action: model.mainAction) {
            Label(title, systemImage: action == .start ? "play.fill" : "checklist")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(action == .start ? Color.white : Color.black)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(Capsule().fill(action == .start ? Color.accentColor : Color.white))
                .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(title)
        .help(action == .start ? "Start sending the phone's camera to call apps" : "Open Setup to finish the steps left")
    }

    // MARK: Picture settings

    private var pictureModule: some View {
        Module(spacing: 14) {
            VStack(spacing: 4) {
                Row(title: "Exposure") {
                    Text(Self.exposureText(store.phone.exposureEV))
                        .contentTransition(.numericText())
                        .animation(change, value: store.phone.exposureEV)
                }
                ZStack {
                    // The centre detent's mark. The slider has no tick marks of its own, so this one stands out.
                    Capsule().fill(Color.white.opacity(0.4)).frame(width: 2, height: 4)
                        .offset(y: 11)
                        .accessibilityHidden(true)
                    Slider(value: exposure, in: -2...2) { Text("Exposure") }
                        .labelsHidden()
                        .controlSize(.small)
                        .accessibilityLabel("Exposure")
                        .accessibilityValue(Self.spokenExposure(store.phone.exposureEV))
                }
            }

            VStack(spacing: 6) {
                Row(title: "White balance") {
                    ZStack(alignment: .trailing) {
                        Text(Self.balanceName(store.phone.whiteBalance))
                            .id(store.phone.whiteBalance)
                            .transition(Motion.swap)
                    }
                }
                HStack(spacing: 4) {
                    ForEach(WhiteBalance.allCases, id: \.self) { balance in
                        Chip(selected: store.phone.whiteBalance == balance, space: balanceSpace, id: "balance") {
                            store.phone.whiteBalance = balance
                        } label: {
                            Self.balanceIcon(balance).frame(maxWidth: .infinity)
                        }
                        .frame(height: 30)
                        .accessibilityLabel(balance == .auto ? "Auto white balance" : Self.balanceName(balance))
                        .help(balance == .auto ? "Auto white balance" : "\(Self.balanceName(balance)) white balance")
                    }
                }
                .padding(2)
                .background(Capsule().fill(Color.white.opacity(0.06)))
            }
            .animation(change, value: store.phone.whiteBalance)

            HStack {
                Text("Focus").font(.system(size: 12, weight: .medium))
                Spacer()
                HStack(spacing: 2) {
                    focusChip(.continuous, title: "Continuous", symbol: "viewfinder")
                    focusChip(.locked, title: "Locked", symbol: "lock.fill")
                }
                .padding(2)
                .background(Capsule().fill(Color.white.opacity(0.06)))
            }
            .animation(change, value: store.phone.focus)

            VStack(spacing: 4) {
                Row(title: "Extra sharpening", detail: "Mac") {
                    Text(store.macSharpness == 0 ? "Off" : String(format: "%.0f%%", store.macSharpness * 100))
                        .contentTransition(.numericText())
                        .animation(change, value: store.macSharpness)
                }
                Slider(value: $store.macSharpness, in: 0...1) { Text("Extra sharpening on the Mac") }
                    .labelsHidden()
                    .controlSize(.small)
                    .accessibilityLabel("Extra sharpening on the Mac")
                    .accessibilityValue(store.macSharpness == 0 ? "Off" : String(format: "%.0f percent", store.macSharpness * 100))
            }

            DisclosureGroup(isExpanded: $more.value) {
                VStack(alignment: .leading, spacing: 10) {
                    levelPicker("Noise reduction", selection: $store.phone.noiseReduction)
                    levelPicker("Phone sharpness", selection: $store.phone.sharpness)
                }
                .padding(.top, 8)
            } label: {
                Text("More").font(.system(size: 12, weight: .medium))
            }

            let automatic = store.phone == PhoneImageSettings() && store.macSharpness == 0
            Button { store.reset() } label: {
                Label("Reset to Automatic", systemImage: "arrow.counterclockwise")
                    .font(.system(size: 12, weight: .medium))
                    .opacity(automatic ? 0.4 : 1)
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .background(Capsule().fill(Color.white.opacity(automatic ? 0.05 : 0.1)))
                    .contentShape(Capsule())
            }
            .buttonStyle(PressStyle())
            .disabled(automatic)
            .accessibilityLabel("Reset to Automatic")
            .help("Back to the phone's automatic picture, and no extra sharpening")
            .animation(change, value: automatic)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Picture")
    }

    /// Steps of a third of a stop, with a tick of the trackpad at 0, so the neutral setting is easy to find by feel.
    private var exposure: Binding<Double> {
        Binding(get: { store.phone.exposureEV }, set: { value in
            let snapped = (value * 3).rounded() / 3
            guard snapped != store.phone.exposureEV else { return }
            if snapped == 0 { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
            store.phone.exposureEV = snapped
        })
    }

    private func focusChip(_ mode: FocusMode, title: String, symbol: String) -> some View {
        Chip(selected: store.phone.focus == mode, space: focusSpace, id: "focus") {
            store.phone.focus = mode
        } label: {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 10)
        }
        .frame(height: 24)
        .accessibilityLabel("\(title) focus")
    }

    private func levelPicker(_ title: String, selection: Binding<ProcessingLevel>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            Picker(title, selection: selection) {
                Text("Off").tag(ProcessingLevel.off)
                Text("Fast").tag(ProcessingLevel.fast)
                Text("High quality").tag(ProcessingLevel.highQuality)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
        }
    }

    // MARK: Words and icons

    static func exposureText(_ ev: Double) -> String {
        if ev.magnitude < 0.05 { return "0 EV" }
        return (ev > 0 ? "+" : "\u{2212}") + String(format: "%.1f EV", ev.magnitude)
    }

    private static func spokenExposure(_ ev: Double) -> String {
        ev.magnitude < 0.05 ? "0 EV" : String(format: "%@%.1f EV", ev > 0 ? "plus " : "minus ", ev.magnitude)
    }

    static func balanceName(_ balance: WhiteBalance) -> String {
        switch balance {
        case .auto: "Auto"
        case .daylight: "Daylight"
        case .cloudy: "Cloudy"
        case .incandescent: "Incandescent"
        case .fluorescent: "Fluorescent"
        }
    }

    @ViewBuilder private static func balanceIcon(_ balance: WhiteBalance) -> some View {
        switch balance {
        case .auto: Text("AUTO").font(.system(size: 10, weight: .bold, design: .rounded))
        case .daylight: Image(systemName: "sun.max.fill")
        case .cloudy: Image(systemName: "cloud.fill")
        case .incandescent: Image(systemName: "lightbulb.fill")
        case .fluorescent: symbol("light.panel.fill", fallback: "light.max")
        }
    }

    /// A symbol that's newer than macOS 13, with an older one in its place there.
    private static func symbol(_ name: String, fallback: String) -> Image {
        Image(systemName: NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil ? name : fallback)
    }
}

// MARK: Pieces

/// A rounded group of controls, like a Control Center module.
private struct Module<Content: View>: View {
    var spacing: CGFloat = 10
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) { content }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
    }
}

/// A control's name on the left and its value on the right.
private struct Row<Value: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder var value: Value

    var body: some View {
        HStack(spacing: 6) {
            Text(title).font(.system(size: 12, weight: .medium))
            if let detail {
                Text(detail)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
            }
            Spacer()
            value.font(.system(size: 12, weight: .medium).monospacedDigit()).foregroundStyle(.secondary)
        }
        .accessibilityHidden(true)
    }
}

/// A capsule that's filled when selected. The fill slides between chips that share a namespace.
private struct Chip<Label: View>: View {
    let selected: Bool
    let space: Namespace.ID
    let id: String
    let action: () -> Void
    @ViewBuilder var label: Label
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            label
                .frame(maxHeight: .infinity)
                .foregroundStyle(selected ? Color.black : Color.white.opacity(enabled ? 0.9 : 0.4))
                .background {
                    if selected {
                        Capsule().fill(Color.white.opacity(enabled ? 0.92 : 0.35)).matchedGeometryEffect(id: id, in: space)
                    } else {
                        Capsule().fill(Color.white.opacity(0.0001))
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A slight shrink while pressed, on the panel's spring.
private struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .brightness(configuration.isPressed ? -0.08 : 0)
            .animation(Motion.allowed(Motion.stageChange), value: configuration.isPressed)
    }
}

/// Zoom steps once per click and keeps stepping while held.
private struct RepeatButton: View {
    let label: String
    let symbol: String
    /// False once the panel closes, which ends a hold in progress.
    let active: Bool
    let action: () -> Void
    @StateObject private var repeater = Repeater()
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button {
            if !repeater.consumeRepeated() { action() }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 34, height: 28)
                .foregroundStyle(Color.white.opacity(enabled ? 0.9 : 0.4))
                .contentShape(Capsule())
        }
        .buttonStyle(RepeatStyle(repeater: repeater, action: action))
        .accessibilityLabel(label)
        .help(label)
        // A hold ends when the button turns off (the picture stopped being live) or the panel goes away.
        .onChange(of: enabled && active) { on in if !on { repeater.stop() } }
        .onDisappear { repeater.stop() }
    }
}

private struct RepeatStyle: ButtonStyle {
    let repeater: Repeater
    let action: () -> Void

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.18 : 0)))
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(Motion.allowed(Motion.stageChange), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { pressed in repeater.pressed(pressed, action: action) }
    }
}

/// Repeats an action while a button is held: after a short wait, then several times a second.
private final class Repeater: ObservableObject {
    private var timer: Timer?
    private var repeated = false

    deinit { timer?.invalidate() }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func pressed(_ down: Bool, action: @escaping () -> Void) {
        stop()
        guard down else { return }
        repeated = false
        let start = Timer(timeInterval: 0.4, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.repeated = true
            action()
            let step = Timer(timeInterval: 0.12, repeats: true) { _ in action() }
            RunLoop.main.add(step, forMode: .common)
            self.timer = step
        }
        RunLoop.main.add(start, forMode: .common)
        timer = start
    }

    /// True once after a hold, so the release doesn't add one more step.
    func consumeRepeated() -> Bool {
        defer { repeated = false }
        return repeated
    }
}

/// The flashlight: a capsule tile that lights up when on.
private struct TileToggleStyle: ToggleStyle {
    let symbolOn: String
    let symbolOff: String

    func makeBody(configuration: Configuration) -> some View {
        Tile(isOn: configuration.$isOn, symbol: configuration.isOn ? symbolOn : symbolOff) { configuration.label }
    }

    private struct Tile<Title: View>: View {
        @Binding var isOn: Bool
        let symbol: String
        @ViewBuilder var title: Title
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            Button { isOn.toggle() } label: {
                HStack(spacing: 6) {
                    Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                    title.font(.system(size: 12, weight: .medium))
                }
                .padding(.horizontal, 12)
                .frame(height: 32)
                .foregroundStyle(isOn ? Color.black : Color.white.opacity(enabled ? 0.9 : 0.4))
                .background(Capsule().fill(isOn ? Color.white.opacity(0.92) : Color.white.opacity(0.08)))
                .contentShape(Capsule())
                .animation(Motion.allowed(Motion.stageChange), value: isOn)
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Flashlight")
            .accessibilityValue(isOn ? "On" : "Off")
        }
    }
}

/// The phone's temperature and battery, the same readings as the menu header.
private struct StatsView: View {
    let stats: PhoneStats

    var body: some View {
        let celsius = Measurement(value: stats.temperatureC, unit: UnitTemperature.celsius)
        HStack(spacing: 10) {
            HStack(spacing: 3) {
                Image(systemName: stats.isHot ? "thermometer.high" : "thermometer.medium")
                Text(MenuHeaderView.temperature.string(from: celsius))
            }
            .foregroundStyle(stats.isHot ? Color.orange : Color.secondary)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Phone at \(MenuHeaderView.spokenTemperature.string(from: celsius))\(stats.isHot ? ", hot" : "")")
            HStack(spacing: 3) {
                Image(systemName: "battery.\([100, 75, 50, 25].first { stats.batteryPercent >= $0 - 12 } ?? 0)")
                Text("\(stats.batteryPercent)%")
                if stats.charging { Image(systemName: "bolt.fill") }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Battery \(stats.batteryPercent) percent\(stats.charging ? ", charging" : "")")
        }
    }
}

/// The red dot and the clock on a live picture, like the menu header's.
private struct LivePill: View {
    let text: String
    @StateObject private var dim = StateBox(false)

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(Color(nsColor: .systemRed)).frame(width: 6, height: 6).opacity(dim.value ? 0.4 : 1)
            Text(text).font(.system(size: 11, weight: .semibold).monospacedDigit()).foregroundStyle(.white)
        }
        .padding(.horizontal, 8)
        .frame(height: 20)
        .background(Capsule().fill(Color.black.opacity(0.55)))
        .onAppear(perform: pulse)
        // Reduce Motion can change while the pill shows.
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)) { _ in
            pulse()
        }
    }

    private func pulse() {
        guard !Motion.reduced else {
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) { dim.value = false }
            return
        }
        guard !dim.value else { return }
        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { dim.value = true }
    }
}

/// Lays chips out in rows, wrapping when the next one doesn't fit.
private struct ChipFlow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        return CGSize(width: rows.map(\.width).max() ?? 0, height: rows.last.map { $0.y + $0.height } ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Line { var indices: [Int] = []; var y: CGFloat = 0; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Line] {
        var lines = [Line()]
        for (index, view) in subviews.enumerated() {
            let size = view.sizeThatFits(.unspecified)
            if !lines[lines.count - 1].indices.isEmpty, lines[lines.count - 1].width + spacing + size.width > width {
                let last = lines[lines.count - 1]
                lines.append(Line(y: last.y + last.height + spacing))
            }
            var line = lines[lines.count - 1]
            line.width += (line.indices.isEmpty ? 0 : spacing) + size.width
            line.height = max(line.height, size.height)
            line.indices.append(index)
            lines[lines.count - 1] = line
        }
        return lines
    }
}

/// The app's video view, which the frame tap feeds directly. It sits at a fixed size in a clipping container: SwiftUI
/// lays the container out at the panel's full width for a moment whenever the panel resizes, and a video view that
/// followed it kept its video layer that wide, off center, once it shrank back.
private struct PictureHost: NSViewRepresentable {
    let view: PreviewView
    let size: CGSize

    func makeNSView(context: Context) -> NSView {
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.wantsLayer = true
        container.layer?.masksToBounds = true
        view.removeFromSuperview()
        view.autoresizingMask = []
        view.frame = container.bounds
        container.addSubview(view)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSView, context: Context) -> CGSize? { size }
}

/// Dark HUD vibrancy, with rounded corners of its own since the panel's window is clear.
private struct HUDBackground: NSViewRepresentable {
    let radius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        let side = radius * 2 + 1
        let mask = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: self.radius, yRadius: self.radius).fill()
            return true
        }
        mask.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        mask.resizingMode = .stretch
        view.maskImage = mask
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
