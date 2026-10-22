import AppKit
import Carbon.HIToolbox

/// The global shortcut that opens and closes Live Controls from any app, a full-screen call too. Carbon's
/// RegisterEventHotKey needs no Accessibility permission, unlike an NSEvent global monitor, and macOS hands the
/// press only to this app. The dev instance never registers it, since it would fire on the real Mac; it records
/// the change instead, and the dev socket's `hotkey` op runs the same action.
final class GlobalHotkey {
    /// Control-Option-Command-L, as the menu and Settings show it.
    static let keys = ["⌃", "⌥", "⌘", "L"]
    static let label = keys.joined()
    static let keyEquivalent = "l"
    static let modifiers: NSEvent.ModifierFlags = [.control, .option, .command]

    private static let signature: OSType = 0x4157_4C43     // "AWLC"
    private let action: () -> Void
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    init(action: @escaping () -> Void) { self.action = action }

    deinit { set(false) }

    /// Registers or drops the shortcut. Returns what went wrong, such as another app holding the same keys.
    @discardableResult
    func set(_ on: Bool) -> String? {
        if DevMode.isOn {
            DevMode.record("hotkey", on ? "register \(Self.label)" : "unregister \(Self.label)")
            return nil
        }
        guard on else {
            if let hotKey { UnregisterEventHotKey(hotKey) }
            if let handler { RemoveEventHandler(handler) }
            hotKey = nil
            handler = nil
            return nil
        }
        guard hotKey == nil else { return nil }
        if handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var id = EventHotKeyID()
                let read = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                             nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
                guard read == noErr, id.signature == GlobalHotkey.signature else { return OSStatus(eventNotHandledErr) }
                Unmanaged<GlobalHotkey>.fromOpaque(userData).takeUnretainedValue().action()
                return noErr
            }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
            guard status == noErr else {
                fputs("Live Controls shortcut: InstallEventHandler failed (\(status)).\n", stderr)
                return "Couldn't set up \(Self.label)."
            }
        }
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_L), UInt32(controlKey | optionKey | cmdKey),
                                         EventHotKeyID(signature: Self.signature, id: 1), GetApplicationEventTarget(), 0, &hotKey)
        guard status == noErr else {
            hotKey = nil
            fputs("Live Controls shortcut: RegisterEventHotKey failed (\(status)).\n", stderr)
            return status == eventHotKeyExistsErr ? "Another app already uses \(Self.label)." : "Couldn't set up \(Self.label)."
        }
        return nil
    }
}
