import AppKit
import AVFoundation
import CoreMedia

/// Video in a sample buffer layer, with a veil of white text on a dark wash for the moments without a live picture.
/// The menu header and the preview window both use it.
final class PreviewView: NSView {
    struct Veil: Equatable {
        var title: String
        var text: String?
    }

    let display = AVSampleBufferDisplayLayer()
    private let sampler = FrameSampler(fps: 30)
    private let veil = NSView()
    private let veilTitle = NSTextField(labelWithString: "")
    private let veilText = NSTextField(wrappingLabelWithString: "")
    private var shownVeil: Veil?

    init(frame: NSRect, titleSize: CGFloat, textSize: CGFloat) {
        super.init(frame: frame)
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.black.cgColor
        display.videoGravity = .resizeAspect
        layer?.addSublayer(display)

        // White on a dark wash, like the system's own video overlays.
        veil.wantsLayer = true
        veil.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        veil.alphaValue = 0
        veil.isHidden = true
        veil.translatesAutoresizingMaskIntoConstraints = false
        veilTitle.font = .systemFont(ofSize: titleSize, weight: .semibold)
        veilText.font = .systemFont(ofSize: textSize)
        veilTitle.textColor = .white
        veilText.textColor = NSColor.white.withAlphaComponent(0.85)
        for label in [veilTitle, veilText] { label.alignment = .center }
        let stack = NSStackView(views: [veilTitle, veilText])
        stack.orientation = .vertical
        stack.spacing = 3
        stack.translatesAutoresizingMaskIntoConstraints = false
        veil.addSubview(stack)
        addSubview(veil)
        NSLayoutConstraint.activate([
            veil.leadingAnchor.constraint(equalTo: leadingAnchor),
            veil.trailingAnchor.constraint(equalTo: trailingAnchor),
            veil.topAnchor.constraint(equalTo: topAnchor),
            veil.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.centerXAnchor.constraint(equalTo: veil.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: veil.centerYAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualTo: veil.widthAnchor, constant: -32),
        ])
    }

    required init?(coder: NSCoder) { fatalError("Use init(frame:titleSize:textSize:).") }

    override func layout() {
        let wrap = max(0, bounds.width - 32)
        if veilText.preferredMaxLayoutWidth != wrap { veilText.preferredMaxLayoutWidth = wrap }
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        display.frame = bounds
        CATransaction.commit()
    }

    /// Shows a frame. Main thread only.
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

    func clear() { display.flushAndRemoveImage() }

    /// Fades the veil in, out, or across to new words.
    func setVeil(_ new: Veil?) {
        guard new != shownVeil else { return }
        let wasShown = shownVeil != nil
        shownVeil = new
        guard let new else { fade(veil, to: 0); return }
        if wasShown, !Motion.reduced, veil.window != nil {
            let crossfade = CATransition()
            crossfade.type = .fade
            crossfade.duration = Motion.duration
            veil.layer?.add(crossfade, forKey: "words")
        }
        veilTitle.stringValue = new.title
        veilText.stringValue = new.text ?? ""
        veilText.isHidden = new.text == nil
        fade(veil, to: 1)
    }
}

/// The app's two motions: a short ease-out fade between states, and a slow pulse for something live or waiting.
/// Both turn off under Reduce Motion.
enum Motion {
    static let duration: CFTimeInterval = 0.2
    static var reduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    static func pulse(_ layer: CALayer?, _ on: Bool) {
        guard let layer else { return }
        guard on, !reduced else { layer.removeAnimation(forKey: "pulse"); return }
        guard layer.animation(forKey: "pulse") == nil else { return }
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1
        pulse.toValue = 0.4
        pulse.duration = 0.9
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(pulse, forKey: "pulse")
    }
}

/// Fades a view in or out. A view that's faded out is hidden too, so VoiceOver skips it.
func fade(_ view: NSView, to alpha: CGFloat) {
    if alpha > 0 { view.isHidden = false }
    guard view.alphaValue != alpha else { return }
    guard !Motion.reduced, view.window != nil else {
        view.alphaValue = alpha
        view.isHidden = alpha == 0
        return
    }
    NSAnimationContext.runAnimationGroup { context in
        context.duration = Motion.duration
        context.timingFunction = CAMediaTimingFunction(name: .easeOut)
        view.animator().alphaValue = alpha
    } completionHandler: {
        if view.alphaValue == 0 { view.isHidden = true }
    }
}
