import AppKit
import Carbon.HIToolbox
import EVESupCore

/// System-wide hotkeys through Carbon's `RegisterEventHotKey`. These work while
/// EVE is in front, need no permission, and the key press is not passed on to
/// the frontmost app.
@MainActor
final class HotkeyCenter {
    static let shared = HotkeyCenter()

    private struct Registration {
        let ref: EventHotKeyRef
        let action: () -> Void
    }

    private var registrations: [UInt32: Registration] = [:]
    private var nextID: UInt32 = 1
    private var handlerInstalled = false
    private let signature: OSType = 0x4556_5350  // "EVSP"

    /// Registers a hotkey. Returns false if macOS or another app already owns it.
    func register(_ hotkey: Hotkey, action: @escaping () -> Void) -> Bool {
        installHandlerIfNeeded()
        var ref: EventHotKeyRef?
        let id = nextID
        nextID += 1
        let status = RegisterEventHotKey(
            hotkey.keyCode,
            hotkey.modifiers,
            EventHotKeyID(signature: signature, id: id),
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else { return false }
        registrations[id] = Registration(ref: ref, action: action)
        return true
    }

    func unregisterAll() {
        for registration in registrations.values {
            UnregisterEventHotKey(registration.ref)
        }
        registrations.removeAll()
    }

    fileprivate func fire(id: UInt32) {
        registrations[id]?.action()
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), hotkeyEventHandler, 1, &eventType, nil, nil)
    }
}

/// Carbon delivers hotkey events on the main thread.
private func hotkeyEventHandler(_: EventHandlerCallRef?, _ event: EventRef?, _: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }
    var hotkeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotkeyID
    )
    guard status == noErr else { return status }
    let id = hotkeyID.id
    MainActor.assumeIsolated { HotkeyCenter.shared.fire(id: id) }
    return noErr
}

/// Converts between AppKit modifier flags and the Carbon flags hotkeys use,
/// and names keys using the current keyboard layout.
enum KeyNames {
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.control) { result |= Hotkey.control }
        if flags.contains(.option) { result |= Hotkey.option }
        if flags.contains(.shift) { result |= Hotkey.shift }
        if flags.contains(.command) { result |= Hotkey.command }
        return result
    }

    static func display(_ hotkey: Hotkey) -> String {
        hotkey.displayString(keyName: layoutName(for:))
    }

    /// The character a key produces on the current layout, e.g. "Q" or "Ö".
    static func layoutName(for keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let layoutData = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data

        return layoutData.withUnsafeBytes { buffer -> String? in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            var deadKeyState: UInt32 = 0
            var characters = [UniChar](repeating: 0, count: 4)
            var length = 0
            let status = UCKeyTranslate(
                layout,
                UInt16(keyCode),
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                characters.count,
                &length,
                &characters
            )
            guard status == noErr, length > 0 else { return nil }
            let text = String(utf16CodeUnits: characters, count: length).uppercased()
            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
        }
    }
}
