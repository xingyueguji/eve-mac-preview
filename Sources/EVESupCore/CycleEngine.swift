import Foundation

/// One running EVE client as the cycling logic sees it.
public struct CycleClient: Equatable, Sendable {
    public let pid: Int32
    /// nil while the client is at the login / character-select screen, or when
    /// the window title can't be read.
    public let characterName: String?
    /// Temporarily skipped (⇧-click on its preview).
    public let excluded: Bool

    public init(pid: Int32, characterName: String?, excluded: Bool = false) {
        self.pid = pid
        self.characterName = characterName
        self.excluded = excluded
    }
}

public enum CycleDirection: String, Sendable {
    case forward, backward
}

public enum CycleEngine {
    /// The clients a group steps through, in order.
    ///
    /// With members listed, it's those characters in the listed order, skipping
    /// anyone not logged in. With no members, it's every open client: logged-in
    /// characters alphabetically, then character-select clients.
    public static func sequence(members: [String], clients: [CycleClient]) -> [CycleClient] {
        let eligible = clients.filter { !$0.excluded }

        guard !members.isEmpty else {
            let named = eligible
                .filter { $0.characterName != nil }
                .sorted { $0.characterName!.localizedCaseInsensitiveCompare($1.characterName!) == .orderedAscending }
            let unnamed = eligible.filter { $0.characterName == nil }.sorted { $0.pid < $1.pid }
            return named + unnamed
        }

        var result: [CycleClient] = []
        var used = Set<Int32>()
        for member in members {
            let wanted = normalized(member)
            if let client = eligible.first(where: { client in
                !used.contains(client.pid) && client.characterName.map(normalized) == wanted
            }) {
                result.append(client)
                used.insert(client.pid)
            }
        }
        return result
    }

    /// The pid to switch to when a group's next/previous key is pressed.
    ///
    /// `current` is the EVE client the user is on (or was last on). If it's in
    /// the sequence we step from it, wrapping around; otherwise we start at the
    /// first client (forward) or the last one (backward), like EVE-O Preview.
    public static func target(
        direction: CycleDirection,
        members: [String],
        clients: [CycleClient],
        current: Int32?
    ) -> Int32? {
        let order = sequence(members: members, clients: clients)
        guard let first = order.first, let last = order.last else { return nil }

        if let current, let index = order.firstIndex(where: { $0.pid == current }) {
            let count = order.count
            let next = direction == .forward ? (index + 1) % count : (index - 1 + count) % count
            return order[next].pid
        }
        return direction == .forward ? first.pid : last.pid
    }

    static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

public enum ClientTitle {
    private static let pattern = try! NSRegularExpression(
        pattern: #"^EVE(?:\s+Online)?\s*[-–—:]\s*(.+)$"#,
        options: [.caseInsensitive]
    )

    /// "EVE - Name" → "Name". Returns nil for the login / character-select
    /// window, whose title is just "EVE".
    public static func characterName(from title: String) -> String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard let match = pattern.firstMatch(in: trimmed, range: range),
              let nameRange = Range(match.range(at: 1), in: trimmed)
        else { return nil }
        let name = trimmed[nameRange].trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }
}
