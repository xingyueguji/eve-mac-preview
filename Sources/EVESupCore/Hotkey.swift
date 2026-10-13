import Foundation

/// A global keyboard shortcut, stored with the Carbon virtual key code and
/// modifier flags that `RegisterEventHotKey` expects.
public struct Hotkey: Codable, Hashable, Sendable {
    public var keyCode: UInt32
    public var modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32 = 0) {
        self.keyCode = keyCode
        self.modifiers = modifiers & Hotkey.allModifiers
    }

    // Carbon modifier masks (HIToolbox/Events.h), repeated here so this target doesn't need Carbon.
    public static let command: UInt32 = 0x0100
    public static let shift: UInt32 = 0x0200
    public static let option: UInt32 = 0x0800
    public static let control: UInt32 = 0x1000
    public static let allModifiers: UInt32 = command | shift | option | control

    public var modifierSymbols: String {
        var symbols = ""
        if modifiers & Hotkey.control != 0 { symbols += "⌃" }
        if modifiers & Hotkey.option != 0 { symbols += "⌥" }
        if modifiers & Hotkey.shift != 0 { symbols += "⇧" }
        if modifiers & Hotkey.command != 0 { symbols += "⌘" }
        return symbols
    }

    /// A label such as "⌃⇧F14". `keyName` lets the app supply a name that
    /// matches the user's keyboard layout for letter and symbol keys.
    public func displayString(keyName: (UInt32) -> String? = { _ in nil }) -> String {
        let key = Hotkey.fixedKeyNames[keyCode] ?? keyName(keyCode) ?? Hotkey.ansiKeyNames[keyCode] ?? "Key \(keyCode)"
        return modifierSymbols + key
    }

    /// Keys that don't type text (F-keys, keypad, Home/End…), so they're fine without a modifier.
    public var isFunctionStyleKey: Bool { Hotkey.functionStyleKeys.contains(keyCode) }

    /// True when the shortcut would swallow ordinary typing everywhere,
    /// e.g. a bare letter or ⇧+letter.
    public var blocksTyping: Bool {
        !isFunctionStyleKey && modifiers & (Hotkey.control | Hotkey.option | Hotkey.command) == 0
    }

    /// This hotkey plus every combination of ⌃ ⌥ ⇧ it doesn't already use, so it
    /// still fires while those keys are held (for example mid ctrl-click target lock).
    public func modifierVariants() -> [Hotkey] {
        let extras = [Hotkey.control, Hotkey.option, Hotkey.shift].filter { modifiers & $0 == 0 }
        return (0..<(1 << extras.count)).map { mask in
            var mods = modifiers
            for (bit, flag) in extras.enumerated() where mask & (1 << bit) != 0 { mods |= flag }
            return Hotkey(keyCode: keyCode, modifiers: mods)
        }
    }
}

extension Hotkey {
    // Virtual key codes from HIToolbox/Events.h (kVK_*).
    public static let escapeKeyCode: UInt32 = 0x35
    public static let deleteKeyCode: UInt32 = 0x33
    public static let forwardDeleteKeyCode: UInt32 = 0x75

    static let functionKeyCodes: [UInt32] = [
        0x7A, 0x78, 0x63, 0x76, 0x60, 0x61, 0x62, 0x64, 0x65, 0x6D,  // F1–F10
        0x67, 0x6F, 0x69, 0x6B, 0x71, 0x6A, 0x40, 0x4F, 0x50, 0x5A,  // F11–F20
    ]

    static let keypadKeyNames: [UInt32: String] = [
        0x41: "Num .", 0x43: "Num *", 0x45: "Num +", 0x47: "Num Clear", 0x4B: "Num /",
        0x4C: "Num Enter", 0x4E: "Num -", 0x51: "Num =",
        0x52: "Num 0", 0x53: "Num 1", 0x54: "Num 2", 0x55: "Num 3", 0x56: "Num 4",
        0x57: "Num 5", 0x58: "Num 6", 0x59: "Num 7", 0x5B: "Num 8", 0x5C: "Num 9",
    ]

    public static let fixedKeyNames: [UInt32: String] = {
        var names: [UInt32: String] = [
            0x24: "↩", 0x30: "⇥", 0x31: "Space", 0x33: "⌫", 0x35: "⎋", 0x75: "⌦",
            0x72: "Help", 0x73: "Home", 0x77: "End", 0x74: "Page Up", 0x79: "Page Down",
            0x7B: "←", 0x7C: "→", 0x7D: "↓", 0x7E: "↑",
        ]
        for (index, code) in functionKeyCodes.enumerated() { names[code] = "F\(index + 1)" }
        names.merge(keypadKeyNames) { current, _ in current }
        return names
    }()

    static let functionStyleKeys: Set<UInt32> = Set(functionKeyCodes)
        .union(keypadKeyNames.keys)
        .union([0x72, 0x73, 0x77, 0x74, 0x79, 0x75])  // Help, Home, End, Page Up, Page Down, ⌦

    /// US-layout names, used when the current layout can't be queried.
    static let ansiKeyNames: [UInt32: String] = [
        0x00: "A", 0x0B: "B", 0x08: "C", 0x02: "D", 0x0E: "E", 0x03: "F", 0x05: "G", 0x04: "H",
        0x22: "I", 0x26: "J", 0x28: "K", 0x25: "L", 0x2E: "M", 0x2D: "N", 0x1F: "O", 0x23: "P",
        0x0C: "Q", 0x0F: "R", 0x01: "S", 0x11: "T", 0x20: "U", 0x09: "V", 0x0D: "W", 0x07: "X",
        0x10: "Y", 0x06: "Z",
        0x1D: "0", 0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4", 0x17: "5", 0x16: "6", 0x1A: "7",
        0x1C: "8", 0x19: "9",
        0x18: "=", 0x1B: "-", 0x1E: "]", 0x21: "[", 0x27: "'", 0x29: ";", 0x2A: "\\", 0x2B: ",",
        0x2C: "/", 0x2F: ".", 0x32: "`",
    ]
}
