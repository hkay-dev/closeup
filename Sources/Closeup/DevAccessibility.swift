import AppKit
import ApplicationServices

/// A walk of the app's own windows through the accessibility API, aimed at this process. AppKit answers such calls
/// directly on the calling thread, so no Accessibility permission is needed, no events are posted, and it works with
/// the windows parked below the desktop and the app in the background.
enum DevAccessibility {
    enum PressResult {
        case pressed(String)
        case failed(String)
    }

    private static let pressableRoles: Set<String> = [
        "AXButton", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXMenuButton", "AXDisclosureTriangle", "AXMenuItem",
    ]
    private static let maxDepth = 40

    // MARK: Views

    /// The strings an AppKit view tree shows, top to bottom, skipping hidden and transparent views. Used for the menu header.
    static func labels(in view: NSView) -> [String] {
        var lines: [String] = []
        func visit(_ view: NSView) {
            if view.isHidden || view.alphaValue == 0 { return }
            if let field = view as? NSTextField, !field.stringValue.isEmpty { lines.append(field.stringValue) }
            else if let button = view as? NSButton, !button.title.isEmpty { lines.append(button.title) }
            for sub in view.subviews { visit(sub) }
        }
        visit(view)
        return lines
    }

    // MARK: Accessibility tree

    private struct Node {
        var role: String
        var subrole: String?
        var label: String?
        var value: String?
        var help: String?
        var enabled: Bool
        var selected: Bool?
        var children: [Node]
        let element: AXUIElement

        var interesting: Bool { label != nil || value != nil || pressableRoles.contains(role) }
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func string(_ element: AXUIElement, _ name: String) -> String? {
        guard let text = attribute(element, name) as? String, !text.isEmpty else { return nil }
        return text
    }

    /// The accessibility element of one of this app's windows, found by its title.
    private static func element(of window: NSWindow) -> AXUIElement? {
        let app = AXUIElementCreateApplication(getpid())
        let windows = attribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
        return windows.first { string($0, kAXTitleAttribute) == window.title }
    }

    /// SwiftUI builds a window's accessibility tree on the first request and lays it out a moment later, so an empty
    /// answer is asked again after the run loop has had a turn.
    private static func roots(of window: NSWindow) -> [Node] {
        for attempt in 0..<6 {
            if let root = element(of: window) {
                let found = children(of: root, depth: 0)
                if !found.isEmpty { return found }
            }
            if attempt < 5 { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
        }
        return []
    }

    private static func children(of parent: AXUIElement, depth: Int) -> [Node] {
        guard depth < maxDepth else { return [] }
        return (attribute(parent, kAXChildrenAttribute) as? [AXUIElement] ?? []).flatMap { nodes(for: $0, depth: depth) }
    }

    /// One node, or its children when it carries nothing a reader or a click needs.
    private static func nodes(for element: AXUIElement, depth: Int) -> [Node] {
        let role = string(element, kAXRoleAttribute) ?? ""
        let kids = children(of: element, depth: depth + 1)
        let value: String? = {
            switch attribute(element, kAXValueAttribute) {
            case let text as String where !text.isEmpty: return text
            case let number as NSNumber: return number.stringValue
            default: return nil
            }
        }()
        // A native form control carries its label in a separate title element.
        let titleElement = (attribute(element, "AXTitleUIElement")).flatMap { $0 as! AXUIElement? }
        let label = string(element, kAXTitleAttribute) ?? string(element, kAXDescriptionAttribute)
            ?? titleElement.flatMap { string($0, kAXValueAttribute) ?? string($0, kAXTitleAttribute) }
        let node = Node(role: role, subrole: string(element, kAXSubroleAttribute), label: label, value: value,
                        help: string(element, kAXHelpAttribute), enabled: attribute(element, kAXEnabledAttribute) as? Bool ?? true,
                        selected: (attribute(element, kAXSelectedAttribute) as? Bool) == true ? true : nil,
                        children: kids, element: element)
        return node.interesting ? [node] : kids
    }

    private static func flatten(_ nodes: [Node]) -> [Node] { nodes.flatMap { [$0] + flatten($0.children) } }

    private static func shortRole(_ role: String) -> String { role.hasPrefix("AX") ? String(role.dropFirst(2)) : role }

    static func tree(of window: NSWindow) -> [[String: Any]] { roots(of: window).map(json) }

    private static func json(_ node: Node) -> [String: Any] {
        var entry: [String: Any] = ["role": shortRole(node.role)]
        if let subrole = node.subrole { entry["subrole"] = shortRole(subrole) }
        if let label = node.label { entry["label"] = label }
        if let value = node.value, value != node.label { entry["value"] = value }
        if let help = node.help { entry["help"] = help }
        if !node.enabled { entry["enabled"] = false }
        if let selected = node.selected { entry["selected"] = selected }
        if !node.children.isEmpty { entry["children"] = node.children.map(json) }
        return entry
    }

    /// Every string a window shows, one per line in reading order, without the title bar's own buttons and title.
    /// Controls are marked with their role, and a check box or pop-up shows its value after an equals sign (1 is on).
    static func text(of window: NSWindow) -> [String] {
        var lines: [String] = []
        let chrome: Set<String> = ["AXCloseButton", "AXZoomButton", "AXMinimizeButton", "AXFullScreenButton"]
        func visit(_ node: Node) {
            let role = shortRole(node.role)
            var line = ""
            if node.subrole.map(chrome.contains) == true || (role == "StaticText" && node.value == window.title) {
                line = ""
            } else if pressableRoles.contains(node.role) {
                line = "[\(role)\(node.enabled ? "" : " disabled")] \(node.label ?? "")"
                if let value = node.value, value != node.label { line += " = \(value)" }
            } else if let text = node.value ?? node.label {
                line = ["StaticText", "Group", ""].contains(role) ? text : "[\(role)] \(text)"
            }
            if !line.isEmpty, lines.last != line { lines.append(line) }
            node.children.forEach(visit)
        }
        roots(of: window).forEach(visit)
        return lines
    }

    // MARK: Press

    /// Presses the one enabled control whose label is `label`: an exact match first, then a case-blind one, then a part of it.
    static func press(_ label: String, in window: NSWindow) -> PressResult {
        let controls = flatten(roots(of: window)).filter { pressableRoles.contains($0.role) }
        let wanted = label.lowercased()
        var matches = controls.filter { $0.label == label }
        if matches.isEmpty { matches = controls.filter { $0.label?.lowercased() == wanted } }
        if matches.isEmpty { matches = controls.filter { $0.label?.lowercased().contains(wanted) == true } }
        let names = controls.compactMap(\.label).joined(separator: " | ")
        guard !matches.isEmpty else { return .failed("No control labeled \"\(label)\" in \(window.title). Controls: \(names)") }
        let enabled = matches.filter(\.enabled)
        guard !enabled.isEmpty else { return .failed("\"\(label)\" is disabled in \(window.title).") }
        guard enabled.count == 1 else { return .failed("\(enabled.count) controls match \"\(label)\" in \(window.title): \(names)") }
        let control = enabled[0]
        guard AXUIElementPerformAction(control.element, kAXPressAction as CFString) == .success else {
            return .failed("\"\(control.label ?? label)\" didn't accept a press.")
        }
        return .pressed("\(shortRole(control.role)) \(control.label ?? label)")
    }
}
