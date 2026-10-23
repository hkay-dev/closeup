import SwiftUI
import CoreImage

/// The "Connect a phone over Wi-Fi" window: a QR code for the phone to scan, a typed-code way in, and what's happening now.
struct PairingView: View {
    @ObservedObject var pairing: WirelessPairing
    @StateObject private var showCode = StateBox(false)
    @StateObject private var code = StateBox("")
    private var change: Animation? { Motion.allowed(Motion.stageChange) }

    private var connected: Bool {
        if case .connected = pairing.phase { return true }
        return false
    }

    /// Which phase this is, ignoring what it carries, so the area swaps on a new phase and not on a new sentence.
    private var phaseKey: String {
        switch pairing.phase {
        case .waiting: "waiting"
        case .pairing: "pairing"
        case .connecting: "connecting"
        case .connected: "connected"
        case .failed: "failed"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            HStack(alignment: .top, spacing: 20) {
                QRCodeView(payload: pairing.qrPayload)
                    .opacity(connected ? 0.15 : 1)
                    .animation(change, value: connected)
                steps
            }
            codeSection
            phaseArea
                .frame(maxWidth: .infinity, alignment: .leading)
            footer
        }
        .padding(22)
        .frame(width: 440)
        .animation(change, value: showCode.value)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Connect a phone over Wi-Fi").font(.title2.weight(.semibold))
            Text("Your phone and this Mac need to be on the same Wi-Fi.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 12) {
            step(1, "On the phone, open Settings > Developer options > Wireless debugging and turn it on.")
            step(2, "Tap Pair device with QR code.")
            step(3, "Point the phone at this code.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number)")
                .font(.system(size: 11, weight: .bold).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.accentColor))
                .accessibilityHidden(true)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number), \(text)")
    }

    private var codeSection: some View {
        DisclosureGroup(isExpanded: $showCode.value) {
            VStack(alignment: .leading, spacing: 8) {
                Text("On the phone, tap Pair device with pairing code and type the code it shows.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    TextField("000000", text: $code.value)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 22, weight: .medium, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .frame(width: 140)
                        .onChange(of: code.value) { value in
                            let digits = String(value.filter { $0.isASCII && $0.isNumber }.prefix(6))
                            if digits != value { code.value = digits }
                        }
                        .onSubmit { submit() }
                        .accessibilityLabel("Pairing code from your phone")
                    Button("Pair") { submit() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(code.value.count != 6)
                }
            }
            .padding(.top, 6)
        } label: {
            // A DisclosureGroup toggles only from its chevron; the words should open it too.
            Text("Use a pairing code instead")
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { withAnimation(change) { showCode.value.toggle() } }
        }
        .font(.callout)
        .disabled(connected)
    }

    private func submit() {
        guard code.value.count == 6 else { return }
        pairing.pair(code: code.value)
    }

    private var phaseArea: some View {
        ZStack(alignment: .leading) {
            phaseContent
                .id(phaseKey)
                .transition(Motion.swap)
        }
        .animation(change, value: phaseKey)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var phaseContent: some View {
        switch pairing.phase {
        case .waiting: working("Waiting for your phone…")
        case .pairing: working("Pairing…")
        case .connecting: working("Connecting…")
        case .connected(let name):
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.white, .green)
                    .accessibilityHidden(true)
                Text("\(name) is connected over Wi-Fi.")
                    .font(.body.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Done") { pairing.close() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
        case .failed(let message):
            HStack(spacing: 10) {
                Text(message)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Try Again") { pairing.restart() }
                    .controlSize(.large)
            }
        }
    }

    private func working(_ text: String) -> some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(text).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button(connected ? "Close" : "Cancel") { pairing.close() }
                .keyboardShortcut(.cancelAction)
        }
    }
}

/// The pairing QR code: black on white with a quiet zone, so it scans in dark mode too.
private struct QRCodeView: View {
    let payload: String
    private static let size: CGFloat = 168
    private static let margin: CGFloat = 10

    var body: some View {
        Group {
            if let image = Self.image(for: payload) {
                Image(decorative: image, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: Self.size, height: Self.size)
            } else {
                Color.white.frame(width: Self.size, height: Self.size)
            }
        }
        .padding(Self.margin)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pairing code for your phone")
        .accessibilityAddTraits(.isImage)
    }

    /// The code drawn at a whole number of pixels per module, so nothing blurs when it's scaled up.
    private static func image(for payload: String) -> CGImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(payload.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scale = max(1, (size * 2 / output.extent.width).rounded(.down))
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale), highQualityDownsample: false)
        return CIContext(options: [.useSoftwareRenderer: true]).createCGImage(scaled, from: scaled.extent)
    }
}
