import XCTest
@testable import EVESupCore

final class SystemShortcutsTests: XCTestCase {
    private let f14 = Hotkey(keyCode: 0x6B)
    private let f15 = Hotkey(keyCode: 0x71)

    func testMissingPreferencesMeanMacOSDefaults() {
        let shortcuts = SystemShortcuts.enabled(in: nil)
        XCTAssertEqual(shortcuts[f14], "Decrease display brightness")
        XCTAssertEqual(shortcuts[f15], "Increase display brightness")
        XCTAssertEqual(shortcuts[Hotkey(keyCode: 0x31, modifiers: Hotkey.command)], "Show Spotlight search")
        XCTAssertNil(shortcuts[Hotkey(keyCode: 0x69)])  // F13 is free
    }

    func testDisabledShortcutIsNotAClash() {
        let prefs: [String: Any] = ["53": ["enabled": false, "value": ["parameters": [65535, 107, 8388608], "type": "standard"]]]
        let shortcuts = SystemShortcuts.enabled(in: prefs)
        XCTAssertNil(shortcuts[f14])
        XCTAssertEqual(shortcuts[f15], "Increase display brightness")
    }

    func testCustomizedShortcutUsesItsNewKey() {
        // Brightness down moved to ⌃⌥F13; F-keys carry the fn flag (0x800000), which is ignored.
        let prefs: [String: Any] = ["53": ["enabled": 1, "value": ["parameters": [65535, 105, 0x800000 | 0x40000 | 0x80000], "type": "standard"]]]
        let shortcuts = SystemShortcuts.enabled(in: prefs)
        XCTAssertNil(shortcuts[f14])
        XCTAssertEqual(shortcuts[Hotkey(keyCode: 0x69, modifiers: Hotkey.control | Hotkey.option)], "Decrease display brightness")
    }
}
