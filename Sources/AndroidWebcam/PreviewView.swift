import AppKit
import AVFoundation
import CoreMedia
import SwiftUI

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
    private let veilWords = NSStackView()
    private let veilTitle = NSTextField(wrappingLabelWithString: "")
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
        // A long phone name wraps to a second line instead of being cut off at both ends.
        veilTitle.maximumNumberOfLines = 2
        veilTitle.lineBreakMode = .byTruncatingTail
        for label in [veilTitle, veilText] { label.alignment = .center }
        veilWords.setViews([veilTitle, veilText], in: .center)
        veilWords.orientation = .vertical
        veilWords.spacing = 3
        veilWords.translatesAutoresizingMaskIntoConstraints = false
        veil.addSubview(veilWords)
        addSubview(veil)
        NSLayoutConstraint.activate([
            veil.leadingAnchor.constraint(equalTo: leadingAnchor),
            veil.trailingAnchor.constraint(equalTo: trailingAnchor),
            veil.topAnchor.constraint(equalTo: topAnchor),
            veil.bottomAnchor.constraint(equalTo: bottomAnchor),
            veilWords.centerXAnchor.constraint(equalTo: veil.centerXAnchor),
            veilWords.centerYAnchor.constraint(equalTo: veil.centerYAnchor),
            veilWords.widthAnchor.constraint(lessThanOrEqualTo: veil.widthAnchor, constant: -32),
        ])
    }

    required init?(coder: NSCoder) { fatalError("Use init(frame:titleSize:textSize:).") }

    override func layout() {
        let wrap = max(0, bounds.width - 32)
        for label in [veilTitle, veilText] where label.preferredMaxLayoutWidth != wrap { label.preferredMaxLayoutWidth = wrap }
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

    /// Fades the veil in or out, or swaps its words: the old ones leave quickly and the new ones come in a beat later.
    func setVeil(_ new: Veil?) {
        guard new != shownVeil else { return }
        let wasShown = shownVeil != nil
        shownVeil = new
        guard let new else { fade(veil, to: 0); return }
        let words = {
            self.veilTitle.stringValue = new.title
            self.veilText.stringValue = new.text ?? ""
            self.veilText.isHidden = new.text == nil
        }
        if wasShown, !veil.isHidden { swapContents(of: veilWords, words) } else { words() }
        fade(veil, to: 1)
    }
}

/// The app's motions: a short ease-out fade between states, a slow pulse for something live or waiting, and the
/// swift-motion package's springs for SwiftUI. All of them turn off under Reduce Motion.
enum Motion {
    /// AppKit fades: a view or a veil showing or hiding.
    static let duration: CFTimeInterval = 0.2
    static var reduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// Something arriving in answer to a click: the panel opening.
    static let entrance = Animation.spring(response: 0.3, dampingFraction: 0.86)
    static let entranceFade: CFTimeInterval = 0.22
    /// The panel leaving when it's closed. Quicker than the entrance settles, since the user asked for it to go.
    static let exitDuration: CFTimeInterval = 0.2
    static let exit = Animation.easeIn(duration: exitDuration)
    /// A value or a selection changing in place, with whatever resizes for it.
    static let stageChange = Animation.spring(response: 0.38, dampingFraction: 0.9)
    /// Words that leave go quickly; their replacement waits a beat, so the two don't overlap into mush.
    static let outgoing = Animation.easeOut(duration: 0.1)
    static let incomingDelay: TimeInterval = 0.08
    static var swap: AnyTransition {
        reduced ? .identity : .asymmetric(insertion: .opacity.animation(stageChange.delay(incomingDelay)),
                                          removal: .opacity.animation(outgoing))
    }

    /// The animation, or none under Reduce Motion.
    static func allowed(_ animation: Animation) -> Animation? { reduced ? nil : animation }

    /// A SwiftUI spring as a Core Animation spring, for AppKit views and layers: stageChange unless told otherwise.
    static func spring(_ keyPath: String, from: Any?, to: Any?, response: Double = 0.38, damping: Double = 0.9,
                       delay: CFTimeInterval = 0) -> CASpringAnimation {
        let animation = CASpringAnimation(keyPath: keyPath)
        animation.mass = 1
        animation.stiffness = pow(2 * .pi / response, 2)
        animation.damping = 4 * .pi * damping / response
        animation.fromValue = from
        animation.toValue = to
        animation.duration = animation.settlingDuration
        if delay > 0 {
            animation.beginTime = CACurrentMediaTime() + delay
            animation.fillMode = .backwards
        }
        return animation
    }

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

/// Changes what a view shows the way `Motion.swap` does in SwiftUI: a picture of the old look leaves in 0.1 s and the
/// new look fades in 0.08 s later, so the two never share the spot. The change itself lands at once, so VoiceOver and
/// the dev tools read the new words straight away.
func swapContents(of view: NSView, _ change: () -> Void) {
    guard !Motion.reduced, view.window != nil, !view.isHiddenOrHasHiddenAncestor, let layer = view.layer,
          let host = view.superview?.layer, !view.bounds.isEmpty,
          let picture = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { change(); return }
    view.cacheDisplay(in: view.bounds, to: picture)
    let ghost = CALayer()
    ghost.contents = picture.cgImage
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    ghost.frame = view.frame
    host.addSublayer(ghost)
    ghost.opacity = 0
    CATransaction.commit()
    let out = CABasicAnimation(keyPath: "opacity")
    out.fromValue = 1
    out.toValue = 0
    out.duration = 0.1
    out.timingFunction = CAMediaTimingFunction(name: .easeOut)
    CATransaction.begin()
    CATransaction.setCompletionBlock { ghost.removeFromSuperlayer() }
    ghost.add(out, forKey: "out")
    CATransaction.commit()
    change()
    layer.add(Motion.spring("opacity", from: 0, to: 1, delay: Motion.incomingDelay), forKey: "swap")
}
