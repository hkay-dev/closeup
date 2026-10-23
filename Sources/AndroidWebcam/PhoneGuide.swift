import AppKit
import SwiftUI

/// The phone half of Setup, from what the Mac can see of the phone.
enum PhoneSetupStage: Equatable {
    case plugIn            // nothing on USB that looks like a phone
    case developerOptions  // a phone is on USB (or the user says it is) but adb can't see it: Developer options, then USB debugging
    case allow             // adb sees the phone and waits for "Allow USB debugging?" on it
    case ready
}

/// Which maker's menus to describe; from the USB vendor ID when the phone is plugged in.
enum PhoneBrand: Equatable { case samsung, google, xiaomi, oneplus, motorola, other }

/// A small animated phone and short steps for whatever the phone needs next. Sits in a Setup step card (about 360 pt wide).
struct PhoneGuideView: View {
    let stage: PhoneSetupStage
    let brand: PhoneBrand
    let phoneName: String?        // e.g. "Galaxy S25 Ultra" from USB, or nil
    let notShowingUp: () -> Void  // the user says the phone is plugged in but nothing happens; shown only in .plugIn

    var body: some View {
        ZStack {
            content
                .id(stage)
                .transition(Motion.swap)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(Motion.allowed(Motion.stageChange), value: stage)
    }

    @ViewBuilder private var content: some View {
        switch stage {
        case .plugIn:
            PhoneGuideLayout(clip: .plug) {
                VStack(alignment: .leading, spacing: 8) {
                    PhoneSteps(items: ["Plug your phone into this Mac with a USB cable."])
                    Text("Use a cable that can move data. One that only charges won't work.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("It's plugged in, but nothing happens") { notShowingUp() }
                        .controlSize(.small)
                }
            }
        case .developerOptions:
            DeveloperOptionsGuide(brand: brand)
        case .allow:
            PhoneGuideLayout(clip: .allow) {
                VStack(alignment: .leading, spacing: 8) {
                    PhoneSteps(items: ["Look at your phone.", "Tick Always allow from this computer.", "Tap Allow."])
                    Text("Don't see the box? Unplug the phone and plug it back in.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        case .ready:
            PhoneGuideLayout(clip: .ready) {
                Text("\(phoneName ?? "Your phone") is ready.")
                    .font(.system(size: 14, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Developer options, in two parts the user steps through

private struct DeveloperOptionsGuide: View {
    let brand: PhoneBrand
    @StateObject private var part = StateBox(0)

    var body: some View {
        PhoneGuideLayout(clip: part.value == 0 ? .build : .debug, brand: brand) {
            VStack(alignment: .leading, spacing: 8) {
                // Both parts sit in the layout, so the card stays the same height whichever one shows.
                ZStack(alignment: .topLeading) {
                    buildText
                        .opacity(part.value == 0 ? 1 : 0)
                        .accessibilityHidden(part.value != 0)
                    debugText
                        .opacity(part.value == 1 ? 1 : 0)
                        .accessibilityHidden(part.value != 1)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .animation(Motion.allowed(Motion.stageChange), value: part.value)
                nav
            }
        }
    }

    private func go(_ index: Int) {
        withAnimation(Motion.allowed(Motion.stageChange)) { part.value = index }
    }

    private var nav: some View {
        HStack(spacing: 8) {
            Button("Back") { go(0) }
                .disabled(part.value == 0)
                .accessibilityLabel("Back to part 1, Developer options")
            Text("\(part.value + 1) of 2")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
            Button("Next") { go(1) }
                .disabled(part.value == 1)
                .accessibilityLabel("Next, part 2, USB debugging")
        }
        .controlSize(.small)
    }

    private var buildText: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Turn on Developer options").font(.system(size: 13, weight: .semibold))
            PhoneSteps(items: [
                "Open Settings.",
                aboutPath,
                brand == .xiaomi ? "Tap that version 7 times." : "Tap Build number 7 times.",
                "Enter your PIN if the phone asks.",
            ])
            Text("Tip: type \"build number\" in the Settings search box to find it on any phone.")
                .font(.system(size: 11))
                .fixedSize(horizontal: false, vertical: true)
            Text("This unlocks hidden settings for people who build apps. The webcam needs one of them, USB debugging, to read the camera directly. It doesn't change anything else on your phone.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var debugText: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Turn on USB debugging").font(.system(size: 13, weight: .semibold))
            PhoneSteps(items: [
                developerPath,
                "Turn on USB debugging.",
                "Tap OK if the phone asks.",
            ])
            Text("Already on? Pull down from the top of the phone, tap the USB notification and choose File transfer.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var aboutPath: String {
        switch brand {
        case .samsung: "Go to About phone, then Software information."
        case .xiaomi: "Go to About phone, then tap MIUI or HyperOS version."
        default: "Go to About phone and scroll to the bottom."
        }
    }

    private var developerPath: String {
        switch brand {
        case .samsung: "Go back to Settings, scroll to the very bottom and tap Developer options."
        case .google, .motorola: "Go to Settings, then System, then Developer options."
        case .xiaomi: "Go to Settings, then Additional settings, then Developer options."
        case .oneplus: "Go to Settings, then System settings, then Developer options."
        case .other: "Open Developer options in Settings. It's often under System."
        }
    }
}

// MARK: - Layout and text

/// The phone on the left, the words on the right.
private struct PhoneGuideLayout<Content: View>: View {
    let clip: Clip
    let brand: PhoneBrand
    let content: Content

    init(clip: Clip, brand: PhoneBrand = .other, @ViewBuilder content: () -> Content) {
        self.clip = clip
        self.brand = brand
        self.content = content()
    }

    var body: some View {
        HStack(alignment: clip == .ready ? .center : .top, spacing: 14) {
            ZStack {
                PhoneMock(clip: clip, brand: brand)
                    .id(clip)
                    .transition(Motion.swap)
            }
            .frame(width: 132, height: clip.height)
            .accessibilityHidden(true)
            content.frame(maxWidth: .infinity, alignment: .leading)
        }
        .animation(Motion.allowed(Motion.stageChange), value: clip)
    }
}

private struct PhoneSteps: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("\(index + 1).").monospacedDigit().foregroundStyle(.secondary)
                    Text(item).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .font(.system(size: 12))
    }
}

// MARK: - Animation clips

/// One looping animation. It runs `length` seconds, holds its last frame for a beat, then starts over.
private enum Clip: Equatable {
    case plug, build, debug, allow, ready

    /// Samsung's Build number is one screen deeper (Software information), so its clip is a bit longer.
    func length(_ brand: PhoneBrand) -> Double {
        switch self {
        case .plug: 4.0
        case .build: 10.8 + Self.hop(brand)
        case .debug: 9.2
        case .allow: 6.0
        case .ready: 1.0
        }
    }

    /// The frame shown under Reduce Motion: the one that says what the step is for.
    func still(_ brand: PhoneBrand) -> Double {
        switch self {
        case .allow: 4.4
        default: length(brand)
        }
    }

    /// How much later Samsung's clip gets to the Build number row.
    static func hop(_ brand: PhoneBrand) -> Double { brand == .samsung ? 0.4 : 0 }

    /// The plug clip is taller than the others by the cable sticking out of the phone.
    var height: CGFloat { self == .plug ? 240 : 208 }

    static let pause = 1.8
}

private func ramp(_ t: Double, _ a: Double, _ b: Double) -> Double { min(1, max(0, (t - a) / (b - a))) }
private func ease(_ x: Double) -> Double { x * x * (3 - 2 * x) }
/// 1 between `a` and `b`, fading in over 0.25 s after `a` and out over 0.25 s after `b`.
private func window(_ t: Double, _ a: Double, _ b: Double) -> Double {
    min(1, max(0, ramp(t, a, a + 0.25) - ramp(t, b, b + 0.25)))
}

private let screenColor = Color(nsColor: .controlBackgroundColor)
private let screenWidth: CGFloat = 122
private let screenHeight: CGFloat = 198
private let statusHeight: CGFloat = 18
private let titleHeight: CGFloat = 22
private let rowHeight: CGFloat = 22
/// Where a list's rows start: under the status bar and the title.
private let listTop = statusHeight + titleHeight

private struct PhoneMock: View {
    let clip: Clip
    let brand: PhoneBrand
    @StateObject private var started = StateBox(Date())

    var body: some View {
        if clip == .ready || Motion.reduced {
            PhoneFrame(clip: clip, brand: brand, t: clip.still(brand))
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                PhoneFrame(clip: clip, brand: brand, t: time(context.date))
            }
        }
    }

    private func time(_ date: Date) -> Double {
        let length = clip.length(brand)
        let elapsed = date.timeIntervalSince(started.value).truncatingRemainder(dividingBy: length + Clip.pause)
        return min(elapsed, length)
    }
}

private struct PhoneFrame: View {
    let clip: Clip
    let brand: PhoneBrand
    let t: Double

    /// How much later than the plain clip the Build number part runs.
    private var d: Double { Clip.hop(brand) }

    var body: some View {
        ZStack(alignment: .top) {
            if clip == .plug { cable }
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(white: 0.1))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
                .frame(width: 132, height: 208)
            screen
                .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                .padding(.top, 5)
            Circle().fill(Color.black).frame(width: 7, height: 7).padding(.top, 11)
        }
        .frame(width: 132, height: clip.height, alignment: .top)
        .clipped()
    }

    private var screen: some View {
        ZStack(alignment: .topLeading) {
            screenColor
            switch clip {
            case .plug: plugScreen
            case .build: buildScreen
            case .debug: debugScreen
            case .allow: allowScreen
            case .ready: readyScreen
            }
            statusBar
        }
        .frame(width: screenWidth, height: screenHeight, alignment: .topLeading)
        .clipped()
    }

    /// The time on the left and a few icons on the right, either side of the punch hole.
    private var statusBar: some View {
        HStack {
            Text("9:41").font(.system(size: 7, weight: .semibold))
            Spacer(minLength: 0)
            HStack(spacing: 2) {
                Image(systemName: "wifi")
                Image(systemName: "battery.100")
            }
            .font(.system(size: 7))
        }
        .padding(.horizontal, 12)
        .frame(width: screenWidth, height: statusHeight)
        .background(screenColor)
        .overlay(Color.black.opacity(dim))
    }

    /// A dialog dims the screen behind it, status bar included.
    private var dim: Double {
        switch clip {
        case .debug: 0.35 * debugDialogOpacity
        case .allow: 0.4 * allowDialogOpacity
        default: 0
        }
    }

    // The cable slides in from below and tucks behind the phone's bottom edge.
    private var cable: some View {
        let progress = ease(ramp(t, 0.6, 2.0))
        let y = 212 + (1 - progress) * 20
        return ZStack(alignment: .top) {
            Capsule().fill(Color(white: 0.5)).frame(width: 4, height: 40).offset(y: CGFloat(y + 8))
            RoundedRectangle(cornerRadius: 2).fill(Color(white: 0.6)).frame(width: 12, height: 16).offset(y: CGFloat(y - 8))
        }
    }

    private var plugScreen: some View {
        ZStack {
            Text("9:41")
                .font(.system(size: 26, weight: .thin))
                .position(x: 61, y: 70)
            HStack(spacing: 3) {
                Image(systemName: "cable.connector")
                Text("USB connected")
            }
            .font(.system(size: 7.5))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.primary.opacity(0.1)))
            .position(x: 61, y: 108)
            .opacity(ramp(t, 2.1, 2.4))
        }
    }

    private var readyScreen: some View {
        ZStack {
            Circle().fill(Color.green).frame(width: 56, height: 56)
            Image(systemName: "checkmark").font(.system(size: 28, weight: .bold)).foregroundStyle(.white)
        }
        .position(x: 61, y: 105)
    }

    // MARK: Part 1: tap Build number

    private var buildTaps: [Double] { (0..<7).map { 3.2 + d + 0.45 * Double($0) } }

    private static let settingsRows = ["Wi-Fi", "Display", "Sound", "Battery", "About phone", "Accessibility"]
    private static let aboutRows = ["Device name", "Model", "Phone number", "Status", "Legal info", "Regulatory info",
                                    "Hardware version", "Build number"]
    private static let samsungAboutRows = ["Device name", "Model number", "Phone number", "Status", "Legal info",
                                           "Software information", "Battery information"]
    private static let softwareRows = ["Android version", "One UI version", "Baseband version", "Build number",
                                       "Kernel version", "Security patch"]

    private var buildScreen: some View {
        let taps = buildTaps.filter { $0 <= t }.count
        let samsung = brand == .samsung
        let toTop = ramp(t, 1.3, 1.6)
        let finger: FingerSpec
        if samsung {
            finger = FingerSpec(
                keys: [(0.2, 90, 185), (0.9, 60, 139), (1.5, 60, 139), (2.0, 60, 161), (2.6, 60, 161),
                       (3.2, 90, 150), (3.5, 70, 117), (6.8, 70, 117)],
                taps: [1.0, 2.3] + buildTaps)
        } else {
            finger = FingerSpec(
                keys: [(0.2, 90, 185), (0.9, 60, 139), (1.5, 60, 139), (2.8, 90, 150), (3.1, 70, 117), (6.4, 70, 117)],
                taps: [1.0] + buildTaps)
        }
        return ZStack(alignment: .topLeading) {
            let push = ease(toTop)
            PhoneList(header: "Settings", rows: Self.settingsRows, offset: 0, x: -screenWidth * CGFloat(push))
            if samsung {
                let deeper = ease(ramp(t, 2.5, 2.8))
                PhoneList(header: "About phone", rows: Self.samsungAboutRows, offset: 0,
                          x: screenWidth * CGFloat(1 - push - deeper))
                PhoneList(header: "Software information", rows: Self.softwareRows, offset: 0,
                          x: screenWidth * CGFloat(1 - deeper))
            } else {
                PhoneList(header: "About phone", rows: Self.aboutRows, offset: -88 * CGFloat(ease(ramp(t, 1.7, 2.8))),
                          x: screenWidth * CGFloat(1 - push))
            }
            pinPad.opacity(window(t, 6.4 + d, 8.7 + d))
            FingerView(spec: finger, t: t)
            if taps > 0 && t < 6.5 + d {
                Text("\(taps)")
                    .font(.system(size: 9, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(Color.accentColor))
                    .position(x: 94, y: 105)
            }
            if let toast = buildToast(taps: taps) { PhoneToast(text: toast.0).opacity(toast.1) }
        }
        .frame(width: screenWidth, height: screenHeight, alignment: .topLeading)
    }

    private func buildToast(taps: Int) -> (String, Double)? {
        if t >= 8.8 + d { return ("Developer mode has been turned on", ramp(t, 8.8 + d, 9.1 + d)) }
        guard t < 6.4 + d, (4...6).contains(taps) else { return nil }
        let texts = ["You are now 3 steps away from being a developer.",
                     "You are now 2 steps away from being a developer.",
                     "You are now 1 step away from being a developer."]
        return (texts[taps - 4], 1)
    }

    private var pinPad: some View {
        let filled = [7.0, 7.35, 7.7, 8.05].filter { $0 + d <= t }.count
        return ZStack(alignment: .top) {
            screenColor
            VStack(spacing: 9) {
                Text("Confirm your PIN").font(.system(size: 8, weight: .semibold))
                HStack(spacing: 6) {
                    ForEach(0..<4, id: \.self) { index in
                        Circle()
                            .fill(index < filled ? Color.primary : Color.primary.opacity(0.15))
                            .frame(width: 7, height: 7)
                    }
                }
                VStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { row in
                        HStack(spacing: 8) {
                            ForEach(0..<3, id: \.self) { column in pinKey(Text("\(row * 3 + column + 1)")) }
                        }
                    }
                    HStack(spacing: 8) {
                        Color.clear.frame(width: 22, height: 22)
                        pinKey(Text("0"))
                        pinKey(Image(systemName: "delete.left").font(.system(size: 8)))
                    }
                }
            }
            .padding(.top, statusHeight + 10)
        }
        .frame(width: screenWidth, height: screenHeight, alignment: .top)
    }

    private func pinKey<Label: View>(_ label: Label) -> some View {
        label
            .font(.system(size: 9))
            .frame(width: 22, height: 22)
            .background(Circle().fill(Color.primary.opacity(0.08)))
    }

    // MARK: Part 2: USB debugging

    private var debugDialogOpacity: Double { window(t, 5.2, 7.1) }

    private var debugScreen: some View {
        let finger = FingerSpec(
            keys: [(1.8, 90, 185), (2.2, 70, 117), (2.7, 70, 117), (3.9, 104, 73), (4.8, 104, 73),
                   (5.9, 80, 160), (6.7, 84, 126), (7.3, 84, 126)],
            taps: [2.3, 4.6, 7.0])
        return ZStack(alignment: .topLeading) {
            PhoneList(header: "Settings",
                      rows: ["Wi-Fi", "Display", "Sound", "Battery", "Storage", "System", "About phone", "Developer options"],
                      offset: -88 * CGFloat(ease(ramp(t, 0.6, 1.7))),
                      x: -screenWidth * CGFloat(ease(ramp(t, 3.3, 3.6))))
            PhoneList(header: "Developer options",
                      rows: ["Stay awake", "USB debugging", "Bluetooth HCI log", "Select mock app"],
                      offset: 0,
                      usbOn: ease(ramp(t, 4.7, 5.0)),
                      x: screenWidth * CGFloat(1 - ease(ramp(t, 3.3, 3.6))))
            Color.black.opacity(0.35 * debugDialogOpacity)
            debugDialog.opacity(debugDialogOpacity)
            FingerView(spec: finger, t: t)
        }
        .frame(width: screenWidth, height: screenHeight, alignment: .topLeading)
    }

    private var debugDialog: some View {
        VStack(spacing: 0) {
            Text("Allow USB debugging?")
                .font(.system(size: 8, weight: .semibold))
                .multilineTextAlignment(.center)
                .frame(height: 26)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                dialogButton("Cancel", main: false)
                dialogButton("OK", main: true)
            }
            .frame(height: 20)
        }
        .padding(8)
        .frame(width: 100, height: 70)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(screenColor))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
        .position(x: 61, y: 110)
    }

    // MARK: Allow on the phone

    private var allowDialogOpacity: Double { window(t, -0.3, 4.8) }

    private var allowScreen: some View {
        let dialog = allowDialogOpacity
        let ticked = ramp(t, 2.3, 2.5)
        let finger = FingerSpec(keys: [(0.8, 90, 185), (1.8, 25, 112), (2.8, 25, 112), (3.8, 83, 143), (4.9, 83, 143)],
                                taps: [2.2, 4.5])
        return ZStack(alignment: .topLeading) {
            VStack(spacing: 10) {
                ForEach(0..<4, id: \.self) { row in
                    HStack(spacing: 10) {
                        ForEach(0..<3, id: \.self) { column in
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.primary.opacity(0.08))
                                .frame(width: 24, height: 24)
                        }
                    }
                }
            }
            .frame(width: screenWidth)
            .padding(.top, 44)
            Color.black.opacity(0.4 * dialog)
            VStack(spacing: 6) {
                Text("Allow USB debugging?")
                    .font(.system(size: 9, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .frame(height: 24)
                VStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 1).fill(Color.primary.opacity(0.15)).frame(height: 5)
                    RoundedRectangle(cornerRadius: 1).fill(Color.primary.opacity(0.15)).frame(width: 60, height: 5)
                }
                .frame(height: 14)
                HStack(spacing: 4) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 2).strokeBorder(Color.primary.opacity(0.5), lineWidth: 1)
                        RoundedRectangle(cornerRadius: 2).fill(Color.accentColor)
                            .opacity(ticked)
                        Image(systemName: "checkmark").font(.system(size: 6, weight: .bold)).foregroundStyle(.white)
                            .opacity(ticked)
                    }
                    .frame(width: 10, height: 10)
                    Text("Always allow from this computer")
                        .font(.system(size: 7))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .frame(height: 26)
                HStack(spacing: 6) {
                    dialogButton("Cancel", main: false)
                    dialogButton("Allow", main: true)
                }
                .frame(height: 24)
            }
            .padding(8)
            .frame(width: 100, height: 122)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(screenColor))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
            .position(x: 61, y: 102)
            .opacity(dialog)
            FingerView(spec: finger, t: t)
        }
        .frame(width: screenWidth, height: screenHeight, alignment: .topLeading)
    }

    private func dialogButton(_ title: String, main: Bool) -> some View {
        Text(title)
            .font(.system(size: 7.5, weight: .semibold))
            .foregroundStyle(main ? Color.white : Color.primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(main ? Color.accentColor : Color.primary.opacity(0.1)))
    }
}

// MARK: - Mock screen pieces

/// A Settings-style list under a title. `offset` scrolls the rows under the title.
private struct PhoneList: View {
    let header: String
    let rows: [String]
    let offset: CGFloat
    var usbOn: Double = 0
    /// Sideways push: 0 is in place, the screen's width is just off to the right.
    var x: CGFloat = 0

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                ForEach(rows, id: \.self) { title in
                    PhoneRow(title: title, switchOn: switchState(title))
                }
            }
            .padding(.top, listTop)
            .offset(y: offset)
            Text(header)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 10)
                .frame(width: screenWidth, height: titleHeight, alignment: .leading)
                .background(screenColor)
                .padding(.top, statusHeight)
        }
        .frame(width: screenWidth, height: screenHeight, alignment: .topLeading)
        .background(screenColor)
        .clipped()
        .offset(x: x)
    }

    private func switchState(_ title: String) -> Double? {
        switch title {
        case "USB debugging": usbOn
        case "Stay awake": 0
        default: nil
        }
    }
}

private struct PhoneRow: View {
    private static let palette: [Color] = [.blue, .green, .orange, .purple, .pink, .teal]
    let title: String
    let switchOn: Double?

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(Self.palette[title.count % Self.palette.count].opacity(0.75)).frame(width: 8, height: 8)
            Text(title).font(.system(size: 9)).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            if let on = switchOn {
                ZStack(alignment: .leading) {
                    Capsule().fill(on > 0.5 ? Color.accentColor : Color.primary.opacity(0.2))
                    Circle().fill(Color.white).frame(width: 8, height: 8).offset(x: 1 + 8 * CGFloat(on))
                }
                .frame(width: 18, height: 10)
            }
        }
        .padding(.horizontal, 8)
        .frame(width: screenWidth, height: rowHeight)
    }
}

/// A toast near the bottom of the screen, clear of the row being tapped.
private struct PhoneToast: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 7.5))
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(width: 108)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.black.opacity(0.8)))
            .position(x: 61, y: 176)
    }
}

/// Where a finger dot goes (time, x, y) and when it taps.
private struct FingerSpec {
    let keys: [(Double, CGFloat, CGFloat)]
    let taps: [Double]
}

private struct FingerView: View {
    let spec: FingerSpec
    let t: Double

    var body: some View {
        let point = position
        let pulse = spec.taps.map { tap -> Double in
            let d = t - tap
            return d >= 0 && d < 0.35 ? 1 - d / 0.35 : 0
        }.max() ?? 0
        let first = spec.keys.first?.0 ?? 0
        let last = spec.keys.last?.0 ?? 0
        return ZStack {
            Circle().fill(Color.accentColor.opacity(0.28)).frame(width: 16 + 10 * CGFloat(pulse), height: 16 + 10 * CGFloat(pulse))
            Circle().strokeBorder(Color.accentColor, lineWidth: 1.5).frame(width: 14, height: 14)
        }
        .position(x: point.x, y: point.y)
        .opacity(ramp(t, first, first + 0.2) * (1 - ramp(t, last, last + 0.2)))
    }

    private var position: CGPoint {
        guard let first = spec.keys.first else { return .zero }
        if t <= first.0 { return CGPoint(x: first.1, y: first.2) }
        for index in 1..<spec.keys.count {
            let a = spec.keys[index - 1]
            let b = spec.keys[index]
            if t <= b.0 {
                let f = CGFloat(ease(ramp(t, a.0, b.0)))
                return CGPoint(x: a.1 + (b.1 - a.1) * f, y: a.2 + (b.2 - a.2) * f)
            }
        }
        let last = spec.keys[spec.keys.count - 1]
        return CGPoint(x: last.1, y: last.2)
    }
}
