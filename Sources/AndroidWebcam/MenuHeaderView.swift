import AppKit

/// The menu's top item: a 16:9 thumbnail, a status pill with a colored dot, the phone's readings and one wrapped note.
final class MenuHeaderView: NSView {
    enum Dot: Equatable {
        case off, ready, live, wait

        var color: NSColor {
            switch self {
            case .off: .systemGray
            case .ready: .systemGreen
            case .live: .systemRed
            case .wait: .systemOrange
            }
        }
    }
    struct Picture: Equatable {
        var badge: String?
        var veil: PreviewView.Veil?
    }
    struct Content: Equatable {
        var dot: Dot
        var status: String
        var picture: Picture?        // nil hides the thumbnail
        var model: String?
        var stats: PhoneStats?
        var note: String?
    }

    static let width: CGFloat = 280
    private static let pictureSize = NSSize(width: 268, height: 151)
    /// The phone's temperature in the Mac's unit, for the header and the heat notification.
    static let temperature: MeasurementFormatter = {
        let formatter = MeasurementFormatter()
        formatter.numberFormatter.maximumFractionDigits = 0
        return formatter
    }()
    static let spokenTemperature: MeasurementFormatter = {
        let formatter = MeasurementFormatter()
        formatter.numberFormatter.maximumFractionDigits = 0
        formatter.unitStyle = .long
        return formatter
    }()

    private let picture = PreviewView(frame: NSRect(origin: .zero, size: MenuHeaderView.pictureSize), titleSize: 13, textSize: 12)
    private let badge = LiveBadge()
    private let dot = NSView()
    private let statusRow = NSStackView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let modelLabel = NSTextField(labelWithString: "")
    private let tempIcon = NSImageView()
    private let tempLabel = NSTextField(labelWithString: "")
    private let batteryIcon = NSImageView()
    private let batteryLabel = NSTextField(labelWithString: "")
    private let boltIcon = NSImageView(image: NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "Charging") ?? NSImage())
    private let readings = NSStackView()
    private let noteLabel = NSTextField(wrappingLabelWithString: "")
    private let stack = NSStackView()
    private var content: Content?
    private var loggedPictureError = false

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: 60))
        picture.wantsLayer = true
        picture.layer?.cornerRadius = 10
        picture.layer?.cornerCurve = .continuous
        picture.layer?.masksToBounds = true
        picture.layer?.borderWidth = 1
        picture.translatesAutoresizingMaskIntoConstraints = false
        badge.alphaValue = 0
        badge.isHidden = true
        badge.translatesAutoresizingMaskIntoConstraints = false
        picture.addSubview(badge)

        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.setAccessibilityElement(false)
        // Fixed-width digits keep the live clock from shifting the line every second.
        statusLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        statusLabel.lineBreakMode = .byTruncatingTail
        // A tinted pill around the dot and the words, so the state reads from the words and not the color alone.
        statusRow.setViews([dot, statusLabel], in: .leading)
        statusRow.spacing = 6
        statusRow.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 10)
        statusRow.wantsLayer = true
        statusRow.layer?.cornerRadius = 11
        statusRow.layer?.cornerCurve = .continuous

        for label in [modelLabel, tempLabel, batteryLabel] {
            label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            label.textColor = .secondaryLabelColor
        }
        for icon in [tempIcon, batteryIcon, boltIcon] {
            icon.contentTintColor = .secondaryLabelColor
            icon.symbolConfiguration = .init(pointSize: 11, weight: .regular)
        }
        readings.setViews([modelLabel, tempIcon, tempLabel, batteryIcon, batteryLabel, boltIcon], in: .leading)
        readings.spacing = 4
        readings.setCustomSpacing(12, after: modelLabel)
        readings.setCustomSpacing(12, after: tempLabel)

        noteLabel.font = .systemFont(ofSize: 12)
        noteLabel.textColor = .secondaryLabelColor
        noteLabel.preferredMaxLayoutWidth = Self.pictureSize.width - 16

        let text = NSStackView(views: [statusRow, readings, noteLabel])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 4
        text.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)

        stack.setViews([picture, text], in: .top)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 6, bottom: 8, right: 6)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.widthAnchor.constraint(equalToConstant: Self.width),
            picture.widthAnchor.constraint(equalToConstant: Self.pictureSize.width),
            picture.heightAnchor.constraint(equalToConstant: Self.pictureSize.height),
            badge.leadingAnchor.constraint(equalTo: picture.leadingAnchor, constant: 8),
            badge.topAnchor.constraint(equalTo: picture.topAnchor, constant: 8),
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
            statusRow.heightAnchor.constraint(equalToConstant: 22),
            statusLabel.widthAnchor.constraint(lessThanOrEqualToConstant: Self.pictureSize.width - 40),
        ])
    }

    required init?(coder: NSCoder) { fatalError("Use init().") }

    // The menu's window comes and goes with each open, so the pulses go back on when it shows again.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { pulse() }
    }

    // Layer colors don't follow the menu's light or dark look by themselves.
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    private func applyColors(blend: Bool = false) {
        let blend = blend && window != nil && !Motion.reduced
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let color = (content?.dot ?? .off).color
            Self.setColor(dot.layer, color.cgColor, blend: blend)
            Self.setColor(statusRow.layer, color.withAlphaComponent(0.16).cgColor, blend: blend)
            picture.layer?.borderColor = NSColor.separatorColor.cgColor
        }
    }

    /// Sets a layer's fill, blending from the old one over the AppKit fade when asked.
    private static func setColor(_ layer: CALayer?, _ color: CGColor, blend: Bool) {
        guard let layer else { return }
        if blend, let from = layer.presentation()?.backgroundColor ?? layer.backgroundColor {
            let animation = CABasicAnimation(keyPath: "backgroundColor")
            animation.fromValue = from
            animation.toValue = color
            animation.duration = Motion.duration
            animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(animation, forKey: "color")
        }
        layer.backgroundColor = color
    }

    /// The status without its numbers: "Live 0:42 · 1080p · 30" and "Live 0:43 · 1080p · 30" are one state, whose
    /// words change in place, while Starting to Live swaps them.
    static func stage(of status: String) -> String { status.filter { !$0.isNumber } }

    func update(_ content: Content) {
        guard content != self.content else { return }
        let old = self.content
        self.content = content

        applyColors(blend: old != nil && old?.dot != content.dot)
        let status = { self.statusLabel.stringValue = content.status }
        if let old, Self.stage(of: old.status) != Self.stage(of: content.status) {
            swapContents(of: statusLabel, status)
        } else {
            status()
        }

        picture.isHidden = content.picture == nil
        picture.setVeil(content.picture?.veil)
        if let text = content.picture?.badge { badge.label.stringValue = text }
        fade(badge, to: content.picture?.badge == nil ? 0 : 1)
        pulse()

        readings.isHidden = content.model == nil && content.stats == nil
        modelLabel.stringValue = content.model ?? ""
        modelLabel.isHidden = content.model == nil
        let stats = content.stats
        for view in [tempIcon, tempLabel, batteryIcon, batteryLabel] as [NSView] { view.isHidden = stats == nil }
        boltIcon.isHidden = stats?.charging != true
        if let stats {
            let hot = stats.isHot
            let celsius = Measurement(value: stats.temperatureC, unit: UnitTemperature.celsius)
            tempIcon.image = NSImage(systemSymbolName: hot ? "thermometer.high" : "thermometer.medium",
                                     accessibilityDescription: hot ? "Phone is hot" : "Phone temperature")
            tempIcon.contentTintColor = hot ? .systemOrange : .secondaryLabelColor
            tempLabel.stringValue = Self.temperature.string(from: celsius)
            tempLabel.textColor = hot ? .systemOrange : .secondaryLabelColor
            tempLabel.setAccessibilityLabel("Phone at \(Self.spokenTemperature.string(from: celsius))\(hot ? ", hot" : "")")
            let level = [100, 75, 50, 25].first { stats.batteryPercent >= $0 - 12 } ?? 0
            batteryIcon.image = NSImage(systemSymbolName: "battery.\(level)", accessibilityDescription: "Battery")
            batteryLabel.stringValue = "\(stats.batteryPercent)%"
            batteryLabel.setAccessibilityLabel("Battery \(stats.batteryPercent) percent\(stats.charging ? ", charging" : "")")
        }

        let note = {
            self.noteLabel.stringValue = content.note ?? ""
            self.noteLabel.isHidden = content.note == nil
        }
        if old?.note != nil, content.note != nil, old?.note != content.note { swapContents(of: noteLabel, note) } else { note() }

        stack.layoutSubtreeIfNeeded()
        setFrameSize(NSSize(width: Self.width, height: stack.fittingSize.height))
    }

    /// The badge's dot pulses while live and the status dot while starting or reconnecting.
    private func pulse() {
        Motion.pulse(badge.dot, content?.picture?.badge != nil)
        Motion.pulse(dot.layer, content?.dot == .wait)
    }

    /// Shows a frame in the thumbnail. Main thread only.
    func show(_ frame: CVPixelBuffer) {
        guard !picture.isHidden else { return }
        do { try picture.show(frame) }
        catch where !loggedPictureError {
            loggedPictureError = true
            fputs("Menu thumbnail failed. \(error.logText)\n", stderr)
        } catch {}
    }

    func clearPicture() { picture.clear() }
}

/// A red dot and the running clock on the live thumbnail, in a pill like the system's recording indicators.
private final class LiveBadge: NSView {
    let label = NSTextField(labelWithString: "")
    let dot = CALayer()

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        layer?.cornerRadius = 9
        dot.backgroundColor = NSColor.systemRed.cgColor
        dot.cornerRadius = 3
        layer?.addSublayer(dot)
        label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 18),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("Use init().") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dot.frame = CGRect(x: 8, y: (bounds.height - 6) / 2, width: 6, height: 6)
        CATransaction.commit()
    }
}
