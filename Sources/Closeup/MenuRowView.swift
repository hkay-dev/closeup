import AppKit

/// A menu row that the app draws itself, so a click runs its item's action and the menu stays open to show what
/// happened. It shows the item's title, subtitle, image, check mark and enabled state, so the rest of the app keeps
/// setting those on the NSMenuItem as usual and calls `MenuRowView.refreshAll()` after. Changes fade in place.
final class MenuRowView: NSView {
    private static let rows = NSHashTable<MenuRowView>.weakObjects()

    /// Picks up every row's item changes, animating the ones that are on screen.
    static func refreshAll() {
        for row in rows.allObjects { row.refresh() }
    }

    private struct Look: Equatable {
        var title = ""
        var subtitle: String?
        var image: NSImage?
        var on = false
        var enabled = true
        var highlighted = false
    }

    private weak var item: NSMenuItem?
    private let checkColumn: Bool
    private let highlight = NSVisualEffectView()
    private let check = NSImageView()
    private let icon = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private var shown: Look?

    // Lined up with the system's own rows on macOS 26.
    private static let inset: CGFloat = 5
    private static let checkX: CGFloat = 11
    private static let leading: CGFloat = 14
    private static let iconWidth: CGFloat = 18
    private static let iconGap: CGFloat = 4
    private static let trailing: CGFloat = 14

    /// Makes a row for `item`, to set as its view. `checkColumn` leaves room on the left for a check mark, as in a list of
    /// choices.
    init(_ item: NSMenuItem, checkColumn: Bool) {
        self.item = item
        self.checkColumn = checkColumn
        super.init(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        autoresizingMask = [.width]

        highlight.material = .selection
        highlight.state = .active
        highlight.isEmphasized = true
        highlight.blendingMode = .behindWindow
        highlight.wantsLayer = true
        highlight.layer?.cornerRadius = 5
        highlight.layer?.cornerCurve = .continuous
        highlight.isHidden = true
        addSubview(highlight)

        check.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)
        check.symbolConfiguration = .init(pointSize: 12, weight: .semibold)
        for view in [check, icon] {
            view.imageScaling = .scaleProportionallyDown
            view.wantsLayer = true
            addSubview(view)
        }
        icon.symbolConfiguration = .init(pointSize: 13, weight: .regular)
        titleLabel.font = .menuFont(ofSize: 0)
        subtitleLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        for label in [titleLabel, subtitleLabel] {
            label.lineBreakMode = .byTruncatingTail
            label.wantsLayer = true
            addSubview(label)
        }

        setAccessibilityElement(true)
        setAccessibilityRole(.menuItem)
        Self.rows.add(self)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("Use init(_:checkColumn:).") }

    private var look: Look {
        guard let item else { return Look() }
        var look = Look(title: item.title, image: item.image, on: item.state == .on, enabled: item.isEnabled,
                        highlighted: item.isHighlighted && item.isEnabled)
        if #available(macOS 14.4, *) { look.subtitle = item.subtitle }
        return look
    }

    /// Shows the item as it is now. A change on screen fades; the highlight follows the pointer at once, as the
    /// system's rows do.
    func refresh() {
        let new = look
        guard new != shown else { return }
        let old = shown
        shown = new
        let animate = old != nil && window != nil

        if animate, old?.title != new.title || old?.subtitle != new.subtitle || old?.enabled != new.enabled {
            crossfade(titleLabel)
            crossfade(subtitleLabel)
        }
        titleLabel.stringValue = new.title
        subtitleLabel.stringValue = new.subtitle ?? ""
        subtitleLabel.isHidden = new.subtitle == nil

        if new.image !== old?.image {
            if let image = new.image, animate, old?.image != nil, #available(macOS 14, *) {
                icon.setSymbolImage(image, contentTransition: .replace)
            } else {
                if animate { crossfade(icon) }
                icon.image = new.image
            }
        }
        icon.isHidden = new.image == nil
        if animate { fade(check, to: new.on ? 1 : 0) } else { check.alphaValue = new.on ? 1 : 0; check.isHidden = !new.on }

        highlight.isHidden = !new.highlighted
        let text: NSColor = !new.enabled ? .disabledControlTextColor : new.highlighted ? .selectedMenuItemTextColor : .labelColor
        titleLabel.textColor = text
        subtitleLabel.textColor = new.highlighted ? NSColor.selectedMenuItemTextColor.withAlphaComponent(0.8)
            : !new.enabled ? .disabledControlTextColor : .secondaryLabelColor
        for view in [check, icon] { view.contentTintColor = new.highlighted ? .selectedMenuItemTextColor : !new.enabled ? .disabledControlTextColor : .labelColor }
        setAccessibilityLabel(new.subtitle.map { "\(new.title), \($0)" } ?? new.title)
        setAccessibilityEnabled(new.enabled)
        setAccessibilitySelected(new.on)

        let height: CGFloat = new.subtitle == nil ? 24 : 38
        let width = ceil(textX + max(titleLabel.intrinsicContentSize.width, subtitleLabel.isHidden ? 0 : subtitleLabel.intrinsicContentSize.width) + Self.trailing + 12)
        if frame.height != height || (window == nil && frame.width < width) {
            setFrameSize(NSSize(width: window == nil ? max(frame.width, width) : frame.width, height: height))
        }
        needsLayout = true
    }

    private var textX: CGFloat {
        let iconX = checkColumn ? Self.checkX + 16 : Self.leading
        return shown?.image == nil ? iconX : iconX + Self.iconWidth + Self.iconGap
    }

    override func layout() {
        super.layout()
        highlight.frame = bounds.insetBy(dx: Self.inset, dy: 0)
        check.frame = NSRect(x: Self.checkX, y: (bounds.height - 14) / 2, width: 14, height: 14)
        let iconX = checkColumn ? Self.checkX + 16 : Self.leading
        icon.frame = NSRect(x: iconX, y: (bounds.height - 18) / 2, width: Self.iconWidth, height: 18)
        let x = textX
        let width = max(0, bounds.width - x - Self.trailing)
        let titleHeight = titleLabel.intrinsicContentSize.height
        if subtitleLabel.isHidden {
            titleLabel.frame = NSRect(x: x, y: (bounds.height - titleHeight) / 2, width: width, height: titleHeight)
        } else {
            let subHeight = subtitleLabel.intrinsicContentSize.height
            let top = (bounds.height - titleHeight - subHeight) / 2
            titleLabel.frame = NSRect(x: x, y: bounds.height - top - titleHeight, width: width, height: titleHeight)
            subtitleLabel.frame = NSRect(x: x, y: top, width: width, height: subHeight)
        }
    }

    /// The menu marks the row for redrawing when it gains or loses the highlight.
    override func viewWillDraw() {
        refresh()
        super.viewWillDraw()
    }

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        press()
    }

    override func accessibilityPerformPress() -> Bool {
        press()
        return true
    }

    private func press() {
        guard let item, item.isEnabled, let action = item.action else { return }
        NSApp.sendAction(action, to: item.target, from: item)
        Self.refreshAll()
    }
}
