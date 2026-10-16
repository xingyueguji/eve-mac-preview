import Foundation

/// macOS's own keyboard shortcuts (System Settings → Keyboard → Keyboard
/// Shortcuts) that an EVESup key could clash with. For example, F14 and F15
/// change display brightness by default.
public enum SystemShortcuts {
    /// Shortcuts worth warning about: ID in com.apple.symbolichotkeys, name, and the macOS default.
    static let known: [(id: Int, name: String, defaultKey: Hotkey)] = [
        (53, "Decrease display brightness", Hotkey(keyCode: 0x6B)),  // F14
        (54, "Increase display brightness", Hotkey(keyCode: 0x71)),  // F15
        (36, "Show Desktop", Hotkey(keyCode: 0x67)),  // F11
        (64, "Show Spotlight search", Hotkey(keyCode: 0x31, modifiers: Hotkey.command)),
        (32, "Mission Control", Hotkey(keyCode: 0x7E, modifiers: Hotkey.control)),
        (33, "Application windows", Hotkey(keyCode: 0x7D, modifiers: Hotkey.control)),
        (79, "Move left a space", Hotkey(keyCode: 0x7B, modifiers: Hotkey.control)),
        (81, "Move right a space", Hotkey(keyCode: 0x7C, modifiers: Hotkey.control)),
        (28, "Save picture of screen as a file", Hotkey(keyCode: 0x14, modifiers: Hotkey.command | Hotkey.shift)),
        (30, "Save picture of selected area as a file", Hotkey(keyCode: 0x15, modifiers: Hotkey.command | Hotkey.shift)),
        (184, "Screenshot and recording options", Hotkey(keyCode: 0x17, modifiers: Hotkey.command | Hotkey.shift)),
    ]

    /// Maps each enabled shortcut's key to its name, given the `AppleSymbolicHotKeys`
    /// dictionary from com.apple.symbolichotkeys. Entries missing from it are at
    /// their macOS default.
    public static func enabled(in symbolicHotKeys: [String: Any]?) -> [Hotkey: String] {
        var result: [Hotkey: String] = [:]
        for shortcut in known {
            guard let entry = symbolicHotKeys?[String(shortcut.id)] as? [String: Any] else {
                result[shortcut.defaultKey] = shortcut.name
                continue
            }
            guard (entry["enabled"] as? Bool) ?? (entry["enabled"] as? Int).map({ $0 != 0 }) ?? false else { continue }
            let parameters = ((entry["value"] as? [String: Any])?["parameters"] as? [Any])?.compactMap { ($0 as? NSNumber)?.intValue }
            guard let parameters, parameters.count >= 3, parameters[1] >= 0, parameters[1] != 65535 else {
                result[shortcut.defaultKey] = shortcut.name
                continue
            }
            result[Hotkey(keyCode: UInt32(parameters[1]), modifiers: carbonModifiers(fromEventFlags: parameters[2]))] = shortcut.name
        }
        return result
    }

    /// NSEvent modifier flags (as stored in the preferences) to Carbon flags.
    static func carbonModifiers(fromEventFlags flags: Int) -> UInt32 {
        var result: UInt32 = 0
        if flags & 0x20000 != 0 { result |= Hotkey.shift }
        if flags & 0x40000 != 0 { result |= Hotkey.control }
        if flags & 0x80000 != 0 { result |= Hotkey.option }
        if flags & 0x100000 != 0 { result |= Hotkey.command }
        return result
    }
}
