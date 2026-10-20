import AppKit

/// The menu's top item: a 16:9 thumbnail, a status line with a colored dot, the phone's readings and one wrapped note.
final class MenuHeaderView: NSView {
    enum Dot: Equatable { case off, ready, live, wait }
    struct Picture: Equatable {
        var badge: String?
        var veilTitle: String?
        var veilText: String?
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

    private let picture = PreviewView(frame: NSRect(origin: .zero, size: MenuHeaderView.pictureSize))
    private let veil = NSView()
    private let veilTitle = NSTextField(labelWithString: "")
    private let veilText = NSTextField(wrappingLabelWithString: "")
    private let badge = NSTextField(labelWithString: "")
    private let dot = NSView()
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
        picture.layer?.cornerRadius = 8
        picture.layer?.masksToBounds = true
        picture.translatesAutoresizingMaskIntoConstraints = false

        // The veil and badge sit on the video, so they use white text on a dark wash like the system's video overlays.
        veil.wantsLayer = true
        veil.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        veil.translatesAutoresizingMaskIntoConstraints = false
        veilTitle.font = .boldSystemFont(ofSize: 13)
        veilText.font = .systemFont(ofSize: 12)
        for label in [veilTitle, veilText] {
            label.textColor = .white
            label.alignment = .center
            label.preferredMaxLayoutWidth = Self.pictureSize.width - 32
        }
        let veilStack = NSStackView(views: [veilTitle, veilText])
        veilStack.orientation = .vertical
        veilStack.spacing = 3
        veilStack.translatesAutoresizingMaskIntoConstraints = false
        veil.addSubview(veilStack)
        picture.addSubview(veil)

        badge.font = .systemFont(ofSize: 11, weight: .semibold)
        badge.textColor = .white
        badge.drawsBackground = true
        badge.backgroundColor = NSColor.black.withAlphaComponent(0.55)
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 5
        badge.layer?.masksToBounds = true
        badge.translatesAutoresizingMaskIntoConstraints = false
        picture.addSubview(badge)

        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.setAccessibilityElement(false)
        statusLabel.font = .boldSystemFont(ofSize: 13)
        statusLabel.lineBreakMode = .byTruncatingTail
        let statusRow = NSStackView(views: [dot, statusLabel])
        statusRow.spacing = 7

        for label in [modelLabel, tempLabel, batteryLabel] {
            label.font = .systemFont(ofSize: 12)
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
            veil.leadingAnchor.constraint(equalTo: picture.leadingAnchor),
            veil.trailingAnchor.constraint(equalTo: picture.trailingAnchor),
            veil.topAnchor.constraint(equalTo: picture.topAnchor),
            veil.bottomAnchor.constraint(equalTo: picture.bottomAnchor),
            veilStack.centerXAnchor.constraint(equalTo: veil.centerXAnchor),
            veilStack.centerYAnchor.constraint(equalTo: veil.centerYAnchor),
            badge.leadingAnchor.constraint(equalTo: picture.leadingAnchor, constant: 8),
            badge.topAnchor.constraint(equalTo: picture.topAnchor, constant: 8),
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
            statusLabel.widthAnchor.constraint(lessThanOrEqualToConstant: Self.pictureSize.width - 31),
        ])
    }

    required init?(coder: NSCoder) { fatalError("Use init().") }

    func update(_ content: Content) {
        guard content != self.content else { return }
        self.content = content

        switch content.dot {
        case .off: dot.layer?.backgroundColor = NSColor.systemGray.cgColor
        case .ready: dot.layer?.backgroundColor = NSColor.systemGreen.cgColor
        case .live: dot.layer?.backgroundColor = NSColor.systemRed.cgColor
        case .wait: dot.layer?.backgroundColor = NSColor.systemOrange.cgColor
        }
        statusLabel.stringValue = content.status

        picture.isHidden = content.picture == nil
        if let shown = content.picture {
            veilTitle.stringValue = shown.veilTitle ?? ""
            veilText.stringValue = shown.veilText ?? ""
            veilText.isHidden = shown.veilText == nil
            veil.isHidden = shown.veilTitle == nil && shown.veilText == nil
            badge.stringValue = shown.badge.map { " ● \($0) " } ?? ""
            badge.isHidden = shown.badge == nil
        }

        readings.isHidden = content.model == nil && content.stats == nil
        modelLabel.stringValue = content.model ?? ""
        modelLabel.isHidden = content.model == nil
        let stats = content.stats
        for view in [tempIcon, tempLabel, batteryIcon, batteryLabel] as [NSView] { view.isHidden = stats == nil }
        boltIcon.isHidden = stats?.charging != true
        if let stats {
            let hot = stats.isHot
            tempIcon.image = NSImage(systemSymbolName: hot ? "thermometer.high" : "thermometer.medium",
                                     accessibilityDescription: hot ? "Phone is hot" : "Phone temperature")
            tempIcon.contentTintColor = hot ? .systemOrange : .secondaryLabelColor
            tempLabel.stringValue = String(format: "%.0f °C", stats.temperatureC)
            tempLabel.textColor = hot ? .systemOrange : .secondaryLabelColor
            tempLabel.setAccessibilityLabel(String(format: "Phone at %.0f degrees Celsius%@", stats.temperatureC, hot ? ", hot" : ""))
            let level = [100, 75, 50, 25].first { stats.batteryPercent >= $0 - 12 } ?? 0
            batteryIcon.image = NSImage(systemSymbolName: "battery.\(level)", accessibilityDescription: "Battery")
            batteryLabel.stringValue = "\(stats.batteryPercent)%"
            batteryLabel.setAccessibilityLabel("Battery \(stats.batteryPercent) percent\(stats.charging ? ", charging" : "")")
        }

        noteLabel.stringValue = content.note ?? ""
        noteLabel.isHidden = content.note == nil

        stack.layoutSubtreeIfNeeded()
        setFrameSize(NSSize(width: Self.width, height: stack.fittingSize.height))
    }

    /// Shows a frame in the thumbnail. Main thread only.
    func show(_ frame: CVPixelBuffer) {
        guard !picture.isHidden else { return }
        do { try picture.show(frame) }
        catch where !loggedPictureError {
            loggedPictureError = true
            fputs("Menu thumbnail failed. \(error.localizedDescription)\n", stderr)
        } catch {}
    }

    func clearPicture() { picture.display.flushAndRemoveImage() }
}
