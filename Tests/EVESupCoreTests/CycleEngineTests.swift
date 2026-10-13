import XCTest
@testable import EVESupCore

final class CycleEngineTests: XCTestCase {
    private let clients = [
        CycleClient(pid: 10, characterName: "Alpha"),
        CycleClient(pid: 11, characterName: "Bravo"),
        CycleClient(pid: 12, characterName: "Charlie"),
        CycleClient(pid: 13, characterName: nil),  // at character select
    ]

    func testForwardFollowsMemberOrderAndWraps() {
        let members = ["Charlie", "Alpha", "Bravo"]
        XCTAssertEqual(CycleEngine.target(direction: .forward, members: members, clients: clients, current: 12), 10)
        XCTAssertEqual(CycleEngine.target(direction: .forward, members: members, clients: clients, current: 10), 11)
        XCTAssertEqual(CycleEngine.target(direction: .forward, members: members, clients: clients, current: 11), 12)
    }

    func testBackwardGoesUpTheListAndWraps() {
        let members = ["Charlie", "Alpha", "Bravo"]
        XCTAssertEqual(CycleEngine.target(direction: .backward, members: members, clients: clients, current: 12), 11)
        XCTAssertEqual(CycleEngine.target(direction: .backward, members: members, clients: clients, current: 11), 10)
    }

    func testOfflineMembersAreSkipped() {
        let members = ["Alpha", "Delta", "Charlie"]
        XCTAssertEqual(CycleEngine.target(direction: .forward, members: members, clients: clients, current: 10), 12)
        XCTAssertEqual(CycleEngine.target(direction: .backward, members: members, clients: clients, current: 10), 12)
    }

    func testStartsAtFirstOrLastWhenCurrentIsOutsideTheGroup() {
        let members = ["Bravo", "Charlie"]
        XCTAssertEqual(CycleEngine.target(direction: .forward, members: members, clients: clients, current: 10), 11)
        XCTAssertEqual(CycleEngine.target(direction: .backward, members: members, clients: clients, current: 10), 12)
        XCTAssertEqual(CycleEngine.target(direction: .forward, members: members, clients: clients, current: nil), 11)
    }

    func testEmptyGroupCyclesAllClientsAlphabeticallyThenCharacterSelect() {
        let order = CycleEngine.sequence(members: [], clients: clients.shuffled()).map(\.pid)
        XCTAssertEqual(order, [10, 11, 12, 13])
        XCTAssertEqual(CycleEngine.target(direction: .forward, members: [], clients: clients, current: 12), 13)
        XCTAssertEqual(CycleEngine.target(direction: .forward, members: [], clients: clients, current: 13), 10)
    }

    func testExcludedClientsAreSkipped() {
        let withExcluded = clients.map { CycleClient(pid: $0.pid, characterName: $0.characterName, excluded: $0.pid == 11) }
        XCTAssertEqual(CycleEngine.target(direction: .forward, members: ["Alpha", "Bravo", "Charlie"], clients: withExcluded, current: 10), 12)
    }

    func testNamesMatchIgnoringCaseAndSpaces() {
        XCTAssertEqual(CycleEngine.target(direction: .forward, members: [" alpha ", "BRAVO"], clients: clients, current: 10), 11)
    }

    func testSingleMemberReturnsThatClient() {
        XCTAssertEqual(CycleEngine.target(direction: .forward, members: ["Alpha"], clients: clients, current: 10), 10)
    }

    func testNobodyOnlineReturnsNil() {
        XCTAssertNil(CycleEngine.target(direction: .forward, members: ["Delta"], clients: clients, current: 10))
        XCTAssertNil(CycleEngine.target(direction: .forward, members: [], clients: [], current: nil))
    }

    func testTitleParsing() {
        XCTAssertEqual(ClientTitle.characterName(from: "EVE - Alpha Bravo"), "Alpha Bravo")
        XCTAssertEqual(ClientTitle.characterName(from: "EVE — Alpha"), "Alpha")
        XCTAssertEqual(ClientTitle.characterName(from: "EVE Online - Alpha"), "Alpha")
        XCTAssertNil(ClientTitle.characterName(from: "EVE"))
        XCTAssertNil(ClientTitle.characterName(from: "EVE - "))
        XCTAssertNil(ClientTitle.characterName(from: "Discord"))
    }
}

final class HotkeyTests: XCTestCase {
    func testDisplayString() {
        let f14 = Hotkey(keyCode: 0x6B, modifiers: Hotkey.control | Hotkey.shift)
        XCTAssertEqual(f14.displayString(), "⌃⇧F14")
        XCTAssertEqual(Hotkey(keyCode: 0x0C, modifiers: Hotkey.option).displayString(), "⌥Q")
    }

    func testTypingKeysNeedARealModifier() {
        XCTAssertFalse(Hotkey(keyCode: 0x6B).blocksTyping)  // F14
        XCTAssertFalse(Hotkey(keyCode: 0x53).blocksTyping)  // keypad 1
        XCTAssertTrue(Hotkey(keyCode: 0x00).blocksTyping)  // A
        XCTAssertTrue(Hotkey(keyCode: 0x00, modifiers: Hotkey.shift).blocksTyping)
        XCTAssertFalse(Hotkey(keyCode: 0x00, modifiers: Hotkey.control).blocksTyping)
    }

    func testMouseButtons() {
        let back = Hotkey(mouseButton: 3)
        XCTAssertEqual(back.displayString(), "Mouse 4")
        XCTAssertEqual(Hotkey(mouseButton: 4, modifiers: Hotkey.control).displayString(), "⌃Mouse 5")
        XCTAssertTrue(back.isMouseButton)
        XCTAssertFalse(back.blocksTyping)
        XCTAssertFalse(back.blocksMiddleClick)
        XCTAssertTrue(Hotkey(mouseButton: 2).blocksMiddleClick)
        XCTAssertFalse(Hotkey(mouseButton: 2, modifiers: Hotkey.option).blocksMiddleClick)
        XCTAssertNotEqual(back, Hotkey(keyCode: 0))  // a mouse button is never the "A" key
        XCTAssertTrue(back.modifierVariants().allSatisfy { $0.mouseButton == 3 })
    }

    func testMouseButtonSurvivesSavingAndOldKeysStillLoad() throws {
        let saved = try JSONEncoder().encode([Hotkey(mouseButton: 3, modifiers: Hotkey.shift), Hotkey(keyCode: 0x6B)])
        XCTAssertEqual(try JSONDecoder().decode([Hotkey].self, from: saved), [Hotkey(mouseButton: 3, modifiers: Hotkey.shift), Hotkey(keyCode: 0x6B)])
        let old = try JSONDecoder().decode(Hotkey.self, from: Data(#"{"keyCode":107,"modifiers":0}"#.utf8))
        XCTAssertEqual(old, Hotkey(keyCode: 107))
        XCTAssertNil(old.mouseButton)
    }

    func testModifierVariantsCoverEveryExtraCombination() {
        let variants = Hotkey(keyCode: 0x6B).modifierVariants()
        XCTAssertEqual(variants.count, 8)
        XCTAssertEqual(Set(variants).count, 8)
        XCTAssertTrue(variants.contains(Hotkey(keyCode: 0x6B)))
        XCTAssertTrue(variants.contains(Hotkey(keyCode: 0x6B, modifiers: Hotkey.control | Hotkey.option | Hotkey.shift)))
        XCTAssertEqual(Hotkey(keyCode: 0x6B, modifiers: Hotkey.control).modifierVariants().count, 4)
    }
}

final class ConfigTests: XCTestCase {
    func testEmptyFileGivesDefaults() throws {
        let config = try JSONDecoder().decode(AppConfig.self, from: Data("{}".utf8))
        var expected = AppConfig()
        expected.cycleGroups[0].id = config.cycleGroups[0].id  // a fresh default group gets a random ID
        XCTAssertEqual(config, expected)
        XCTAssertEqual(config.clientBundleIDs, ["com.ccpgames.eveonline"])
    }

    func testPartialGroupDecodes() throws {
        let json = #"{"cycleGroups":[{"name":"DPS","members":["A","B"],"nextKey":{"keyCode":107,"modifiers":0}}]}"#
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        XCTAssertEqual(config.cycleGroups.first?.name, "DPS")
        XCTAssertEqual(config.cycleGroups.first?.members, ["A", "B"])
        XCTAssertEqual(config.cycleGroups.first?.nextKey, Hotkey(keyCode: 107))
        XCTAssertNil(config.cycleGroups.first?.previousKey)
        XCTAssertEqual(config.cycleGroups.first?.isEnabled, true)
        XCTAssertEqual(config.previews, PreviewSettings())
    }

    func testRoundTrip() throws {
        var config = AppConfig()
        config.cycleGroups[0].members = ["Alpha"]
        config.characterHotkeys["Alpha"] = Hotkey(keyCode: 0x7A, modifiers: Hotkey.option)
        config.thumbnailFrames["Alpha"] = StoredRect(x: 1, y: 2, width: 300, height: 200)
        config.sync.accountNicknames["123"] = "Main"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("config.json")
        try ConfigStore.save(config, to: url)
        let loaded = ConfigStore.load(from: url)
        XCTAssertTrue(loaded.existed)
        XCTAssertEqual(loaded.config, config)
    }
}
