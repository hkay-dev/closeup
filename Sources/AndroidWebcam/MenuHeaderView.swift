import AppKit

/// The menu's top item: a 16:9 thumbnail, the phone's name beside a status pill, the phone's readings and one wrapped note.
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
        /// The last picture, already blurred, under the veil once the webcam has stopped.
        var still: CGImage?
    }
    struct Phone: Equatable {
        enum Link: Equatable { case usb, wifi }
        var name: String
        var link: Link?              // nil while it isn't connected either way
    }
    struct Content: Equatable {
        var dot: Dot
        var status: String
        var picture: Picture?        // nil hides the thumbnail
        var phone: Phone?
        var stats: PhoneStats?
        var note: String?
    }

    static let width: CGFloat = 300
    private static let pictureSize = NSSize(width: 288, height: 162)
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
    private let nameLabel = NSTextField(labelWithString: "")
    private let nameRow = NSStackView()
    private let linkIcon = NSImageView()
    private let linkLabel = NSTextField(labelWithString: "")
    private let tempIcon = NSImageView()
    private let tempLabel = NSTextField(labelWithString: "")
    private let batteryIcon = NSImageView()
    private let batteryLabel = NSTextField(labelWithString: "")
    private let boltIcon = NSImageView(image: NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "Charging") ?? NSImage())
    private lazy var linkGroup = Self.group([linkIcon, linkLabel])
    private lazy var tempGroup = Self.group([tempIcon, tempLabel])
    private lazy var batteryGroup = Self.group([batteryIcon, batteryLabel, boltIcon])
    private let tempDivider = MenuHeaderView.divider()
    private let batteryDivider = MenuHeaderView.divider()
    private let readings = NSStackView()
    private let noteLabel = NSTextField(wrappingLabelWithString: "")
    private let stack = NSStackView()
    private var content: Content?
    private var loggedPictureError = false

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: 60))
        // The menu sizes this view to its own width, which other rows can make wider than Self.width.
        autoresizingMask = [.width]
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

        nameLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        nameLabel.lineBreakMode = .byTruncatingTail
        // The name takes the room that's left, so the pill sits at the right edge and a long name is cut, not the status.
        nameLabel.setContentHuggingPriority(.defaultLow - 1, for: .horizontal)
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        statusRow.setContentHuggingPriority(.required, for: .horizontal)
        statusRow.setContentCompressionResistancePriority(.required, for: .horizontal)
        nameRow.setViews([nameLabel, statusRow], in: .leading)
        nameRow.spacing = 8

        // Plain values, no pills: only the status gets a badge.
        for label in [linkLabel, tempLabel, batteryLabel] {
            label.font = .monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
        }
        for icon in [linkIcon, tempIcon, batteryIcon, boltIcon] {
            icon.contentTintColor = .secondaryLabelColor
            icon.symbolConfiguration = .init(pointSize: 14, weight: .regular)
        }
        boltIcon.symbolConfiguration = .init(pointSize: 11, weight: .regular)
        readings.setViews([linkGroup, tempDivider, tempGroup, batteryDivider, batteryGroup], in: .leading)
        // Spread across the row: connection at the left edge, battery at the right, temperature halfway.
        readings.distribution = .equalSpacing
        readings.spacing = 10

        noteLabel.font = .systemFont(ofSize: 12)
        noteLabel.textColor = .secondaryLabelColor
        noteLabel.preferredMaxLayoutWidth = Self.width - 28

        let text = NSStackView(views: [nameRow, readings, noteLabel])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 8
        text.setCustomSpacing(4, after: readings)
        text.edgeInsets = NSEdgeInsets(top: 2, left: 4, bottom: 0, right: 4)

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
            stackWidth,
            picture.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -12),
            picture.heightAnchor.constraint(equalTo: picture.widthAnchor, multiplier: 9.0 / 16),
            badge.leadingAnchor.constraint(equalTo: picture.leadingAnchor, constant: 8),
            badge.topAnchor.constraint(equalTo: picture.topAnchor, constant: 8),
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
            statusRow.heightAnchor.constraint(equalToConstant: 22),
            nameRow.widthAnchor.constraint(equalTo: picture.widthAnchor, constant: -8),
            readings.widthAnchor.constraint(equalTo: picture.widthAnchor, constant: -8),
            statusLabel.widthAnchor.constraint(lessThanOrEqualTo: picture.widthAnchor, constant: -40),
        ])
    }

    private lazy var stackWidth = stack.widthAnchor.constraint(equalToConstant: Self.width)

    /// A new width from the menu lays the header out again at that width, with the height that it then needs.
    override func setFrameSize(_ newSize: NSSize) {
        guard newSize.width != stackWidth.constant else { return super.setFrameSize(newSize) }
        stackWidth.constant = newSize.width
        noteLabel.preferredMaxLayoutWidth = newSize.width - 28
        stack.layoutSubtreeIfNeeded()
        super.setFrameSize(NSSize(width: newSize.width, height: stack.fittingSize.height))
    }

    required init?(coder: NSCoder) { fatalError("Use init().") }

    private static func group(_ views: [NSView]) -> NSStackView {
        let group = NSStackView(views: views)
        group.spacing = 5
        // Its own width only; the row spreads the groups out instead of stretching one.
        group.setHuggingPriority(.required, for: .horizontal)
        return group
    }

    private static func divider() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        box.widthAnchor.constraint(equalToConstant: 1).isActive = true
        box.heightAnchor.constraint(equalToConstant: 16).isActive = true
        return box
    }

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
        picture.setStill(content.picture?.still)
        picture.setVeil(content.picture?.veil)
        if let text = content.picture?.badge { badge.label.stringValue = text }
        fade(badge, to: content.picture?.badge == nil ? 0 : 1)
        pulse()

        nameLabel.stringValue = content.phone?.name ?? ""
        nameLabel.isHidden = content.phone == nil
        showReadings(content.phone, content.stats)

        let note = {
            self.noteLabel.stringValue = content.note ?? ""
            self.noteLabel.isHidden = content.note == nil
        }
        if old?.note != nil, content.note != nil, old?.note != content.note { swapContents(of: noteLabel, note) } else { note() }

        stack.layoutSubtreeIfNeeded()
        setFrameSize(NSSize(width: stackWidth.constant, height: stack.fittingSize.height))
    }

    /// At or under this, and not charging, the battery reads red.
    static let lowBattery = 20

    /// Connection, temperature and battery as plain values. A warm phone or a low battery changes color, and its
    /// tooltip says why; the words carry it for VoiceOver.
    private func showReadings(_ phone: Phone?, _ stats: PhoneStats?) {
        readings.isHidden = phone == nil
        guard let phone else { return }
        let link: (symbols: [String], text: String, tip: String) = switch phone.link {
        case .usb: (["cable.connector", "cable.connector.horizontal"], "USB", "Connected over USB")
        case .wifi: (["wifi"], "Wi-Fi", "Connected over Wi-Fi")
        case nil: (["iphone.slash", "wifi.slash"], "Not connected", "The phone isn't on USB or Wi-Fi")
        }
        linkIcon.image = link.symbols.lazy.compactMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }.first
        linkLabel.stringValue = link.text
        linkLabel.textColor = phone.link == nil ? .secondaryLabelColor : .labelColor
        linkGroup.toolTip = link.tip
        linkGroup.setAccessibilityElement(true)
        linkGroup.setAccessibilityLabel(phone.link == nil ? "Phone not connected" : link.tip)

        let shown = phone.link != nil ? stats : nil
        for view in [tempDivider, tempGroup, batteryDivider, batteryGroup] as [NSView] { view.isHidden = shown == nil }
        guard let stats = shown else { return }
        let hot = stats.isHot
        let celsius = Measurement(value: stats.temperatureC, unit: UnitTemperature.celsius)
        let spoken = Self.spokenTemperature.string(from: celsius)
        tempIcon.image = NSImage(systemSymbolName: hot ? "thermometer.high" : "thermometer.medium", accessibilityDescription: nil)
        tempIcon.contentTintColor = hot ? .systemOrange : .secondaryLabelColor
        tempLabel.stringValue = Self.temperature.string(from: celsius)
        tempLabel.textColor = hot ? .systemOrange : .labelColor
        let tempTip = hot ? "The phone is getting hot. A hot phone can drop frames or stop the camera." : "Phone temperature"
        tempGroup.toolTip = tempTip
        tempGroup.setAccessibilityElement(true)
        tempGroup.setAccessibilityLabel(hot ? "Phone at \(spoken). \(tempTip)" : "Phone at \(spoken)")

        let low = stats.batteryPercent <= Self.lowBattery && !stats.charging
        let level = [100, 75, 50, 25].first { stats.batteryPercent >= $0 - 12 } ?? 0
        batteryIcon.image = NSImage(systemSymbolName: "battery.\(level)", accessibilityDescription: nil)
        batteryIcon.contentTintColor = low ? .systemRed : .secondaryLabelColor
        batteryLabel.stringValue = "\(stats.batteryPercent)%"
        batteryLabel.textColor = low ? .systemRed : .labelColor
        boltIcon.isHidden = !stats.charging
        let batteryTip = low ? "The battery is low and the phone isn't charging." : stats.charging ? "Battery, charging" : "Battery"
        batteryGroup.toolTip = batteryTip
        batteryGroup.setAccessibilityElement(true)
        batteryGroup.setAccessibilityLabel("Battery \(stats.batteryPercent) percent\(stats.charging ? ", charging" : low ? ". \(batteryTip)" : "")")
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
