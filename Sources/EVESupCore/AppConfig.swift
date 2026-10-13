import Foundation

/// Everything EVESup remembers, saved as human-readable JSON.
///
/// Every field decodes with a default, so hand edits and files from older
/// versions keep working.
public struct AppConfig: Codable, Equatable {
    public static let eveBundleID = "com.ccpgames.eveonline"

    /// Apps whose windows count as EVE clients.
    public var clientBundleIDs: [String] = [AppConfig.eveBundleID]
    public var cycleGroups: [CycleGroup] = [CycleGroup(name: "Group 1")]
    /// Character name → key that jumps straight to that character.
    public var characterHotkeys: [String: Hotkey] = [:]
    public var previews = PreviewSettings()
    /// Character name → saved preview position and size.
    public var thumbnailFrames: [String: StoredRect] = [:]
    /// Characters seen in running clients, offered when building groups.
    public var knownCharacters: [String] = []
    public var sync = SyncSettings()

    public init() {}

    enum CodingKeys: String, CodingKey {
        case clientBundleIDs, cycleGroups, characterHotkeys, previews, thumbnailFrames, knownCharacters, sync
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppConfig()
        clientBundleIDs = c.value(.clientBundleIDs, default: d.clientBundleIDs)
        cycleGroups = c.value(.cycleGroups, default: d.cycleGroups)
        characterHotkeys = c.value(.characterHotkeys, default: d.characterHotkeys)
        previews = c.value(.previews, default: d.previews)
        thumbnailFrames = c.value(.thumbnailFrames, default: d.thumbnailFrames)
        knownCharacters = c.value(.knownCharacters, default: d.knownCharacters)
        sync = c.value(.sync, default: d.sync)
    }
}

public struct CycleGroup: Codable, Equatable, Identifiable {
    public var id = UUID()
    public var name: String
    public var isEnabled = true
    public var nextKey: Hotkey?
    public var previousKey: Hotkey?
    /// Also register the keys with every ⌃ ⌥ ⇧ combination.
    public var worksWithModifiersHeld = false
    /// Character names in cycle order. Empty means "every open client".
    public var members: [String] = []

    public init(
        id: UUID = UUID(),
        name: String,
        isEnabled: Bool = true,
        nextKey: Hotkey? = nil,
        previousKey: Hotkey? = nil,
        worksWithModifiersHeld: Bool = false,
        members: [String] = []
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.nextKey = nextKey
        self.previousKey = previousKey
        self.worksWithModifiersHeld = worksWithModifiersHeld
        self.members = members
    }

    enum CodingKeys: String, CodingKey {
        case id, name, isEnabled, nextKey, previousKey, worksWithModifiersHeld, members
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, default: UUID())
        name = c.value(.name, default: "Group")
        isEnabled = c.value(.isEnabled, default: true)
        nextKey = c.value(.nextKey, default: nil)
        previousKey = c.value(.previousKey, default: nil)
        worksWithModifiersHeld = c.value(.worksWithModifiersHeld, default: false)
        members = c.value(.members, default: [])
    }
}

public struct PreviewSettings: Codable, Equatable {
    public var isEnabled = true
    public var framesPerSecond: Double = 15
    public var defaultWidth: Double = 288
    public var defaultHeight: Double = 180
    /// Opacity of previews for clients that aren't in front (0.2–1).
    public var inactiveOpacity: Double = 0.9
    public var showsName = true
    public var highlightsActive = true
    public var highlightColor = RGBAColor(red: 0.24, green: 0.78, blue: 0.42)
    public var highlightThickness: Double = 3
    public var hidesActiveClient = false
    /// Hide all previews unless an EVE client (or EVESup) is the frontmost app.
    public var onlyWhileEVEActive = false
    public var locksPositions = false
    public var showsOnAllSpaces = true
    /// Only the picture: no background, shadow or rounded corners.
    public var isBorderless = false
    /// Snap previews to a grid while dragging or resizing them.
    public var snapsToGrid = false
    public var gridWidth: Double = 20
    public var gridHeight: Double = 20
    /// How the character name on every preview looks.
    public var label = NameLabelStyle()

    public init() {}

    enum CodingKeys: String, CodingKey {
        case isEnabled, framesPerSecond, defaultWidth, defaultHeight, inactiveOpacity, showsName
        case highlightsActive, highlightColor, highlightThickness, hidesActiveClient, onlyWhileEVEActive
        case locksPositions, showsOnAllSpaces, isBorderless, snapsToGrid, gridWidth, gridHeight, label
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PreviewSettings()
        isEnabled = c.value(.isEnabled, default: d.isEnabled)
        framesPerSecond = c.value(.framesPerSecond, default: d.framesPerSecond)
        defaultWidth = c.value(.defaultWidth, default: d.defaultWidth)
        defaultHeight = c.value(.defaultHeight, default: d.defaultHeight)
        inactiveOpacity = c.value(.inactiveOpacity, default: d.inactiveOpacity)
        showsName = c.value(.showsName, default: d.showsName)
        highlightsActive = c.value(.highlightsActive, default: d.highlightsActive)
        highlightColor = c.value(.highlightColor, default: d.highlightColor)
        highlightThickness = c.value(.highlightThickness, default: d.highlightThickness)
        hidesActiveClient = c.value(.hidesActiveClient, default: d.hidesActiveClient)
        onlyWhileEVEActive = c.value(.onlyWhileEVEActive, default: d.onlyWhileEVEActive)
        locksPositions = c.value(.locksPositions, default: d.locksPositions)
        showsOnAllSpaces = c.value(.showsOnAllSpaces, default: d.showsOnAllSpaces)
        isBorderless = c.value(.isBorderless, default: d.isBorderless)
        snapsToGrid = c.value(.snapsToGrid, default: d.snapsToGrid)
        gridWidth = c.value(.gridWidth, default: d.gridWidth)
        gridHeight = c.value(.gridHeight, default: d.gridHeight)
        label = c.value(.label, default: d.label)
    }
}

public struct NameLabelStyle: Codable, Equatable {
    /// Font family, such as "Menlo". nil means the system font.
    public var fontFamily: String?
    public var fontSize: Double = 12
    public var isBold = true
    public var color = RGBAColor(red: 1, green: 1, blue: 1)
    /// Opacity of the dark box behind the name; 0 means no box.
    public var backgroundOpacity: Double = 0.55

    public init() {}

    enum CodingKeys: String, CodingKey {
        case fontFamily, fontSize, isBold, color, backgroundOpacity
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = NameLabelStyle()
        fontFamily = c.value(.fontFamily, default: d.fontFamily)
        fontSize = c.value(.fontSize, default: d.fontSize)
        isBold = c.value(.isBold, default: d.isBold)
        color = c.value(.color, default: d.color)
        backgroundOpacity = c.value(.backgroundOpacity, default: d.backgroundOpacity)
    }
}

public struct SyncSettings: Codable, Equatable {
    /// Folder of the EVE settings profile picked last time.
    public var lastProfilePath: String?
    /// Account (user) ID → nickname typed by the user.
    public var accountNicknames: [String: String] = [:]
    /// Character ID → name, cached from CCP's ESI API.
    public var characterNames: [String: String] = [:]

    public init() {}

    enum CodingKeys: String, CodingKey {
        case lastProfilePath, accountNicknames, characterNames
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lastProfilePath = c.value(.lastProfilePath, default: nil)
        accountNicknames = c.value(.accountNicknames, default: [:])
        characterNames = c.value(.characterNames, default: [:])
    }
}

public struct RGBAColor: Codable, Equatable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}

/// A rectangle in AppKit screen coordinates (origin at the bottom-left of the main display).
public struct StoredRect: Codable, Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public enum ConfigStore {
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/EVESup/config.json")
    }

    /// Loads the config, falling back to defaults when the file is missing or unreadable.
    public static func load(from url: URL) -> (config: AppConfig, existed: Bool) {
        guard let data = try? Data(contentsOf: url) else { return (AppConfig(), false) }
        return ((try? JSONDecoder().decode(AppConfig.self, from: data)) ?? AppConfig(), true)
    }

    public static func save(_ config: AppConfig, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(config).write(to: url, options: .atomic)
    }
}

extension KeyedDecodingContainer {
    /// Decodes a value if it's present and valid, otherwise returns the default.
    func value<T: Decodable>(_ key: Key, default defaultValue: @autoclosure () -> T) -> T {
        if let decoded = try? decodeIfPresent(T.self, forKey: key) { return decoded }
        return defaultValue()
    }
}
