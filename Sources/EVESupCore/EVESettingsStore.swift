import Foundation

/// One `settings_<Profile>` folder inside an EVE server folder.
public struct EVEProfile: Identifiable, Hashable, Sendable {
    public let url: URL
    public let serverName: String
    public let profileName: String

    public var id: String { url.path }
    public var displayName: String { "\(serverName) · \(profileName)" }
    public var isSingularity: Bool { serverName == "Singularity" }
}

/// A `core_char_<characterID>.dat` or `core_user_<userID>.dat` file.
public struct EVESettingsFile: Identifiable, Hashable, Sendable {
    public enum Kind: String, Sendable {
        case character = "char"
        case account = "user"
    }

    public let kind: Kind
    public let entityID: Int64
    public let url: URL
    public let modified: Date
    public let size: Int64

    public var id: Int64 { entityID }
}

public struct EVESettingsBackup: Identifiable, Hashable, Sendable {
    public let url: URL
    public let created: Date
    public let fileCount: Int

    public var id: String { url.path }
}

public enum EVESettingsError: LocalizedError, Equatable {
    case wrongKind(String)
    case differentFolder(String)

    public var errorDescription: String? {
        switch self {
        case .wrongKind(let name): return "\(name) is a different kind of settings file."
        case .differentFolder(let name): return "\(name) is not in the same profile folder as the source."
        }
    }
}

public enum EVESettingsStore {
    /// Where the macOS EVE client keeps its settings.
    public static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CCP/EVE", isDirectory: true)
    }

    public static var defaultBackupsRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/EVESup/Backups", isDirectory: true)
    }

    private static let filePattern = try! NSRegularExpression(pattern: #"^core_(char|user)_(\d+)\.dat$"#)

    // MARK: Discovery

    /// Every `settings_*` folder under each server folder, Tranquility and "Default" first.
    public static func discoverProfiles(root: URL = defaultRoot) -> [EVEProfile] {
        var profiles: [EVEProfile] = []
        for serverFolder in subdirectories(of: root) {
            let server = serverName(forFolder: serverFolder.lastPathComponent)
            for folder in subdirectories(of: serverFolder) where folder.lastPathComponent.hasPrefix("settings_") {
                let profile = String(folder.lastPathComponent.dropFirst("settings_".count))
                profiles.append(EVEProfile(url: folder, serverName: server, profileName: profile))
            }
        }
        return profiles.sorted { a, b in
            let rankA = serverRank(a.serverName), rankB = serverRank(b.serverName)
            if rankA != rankB { return rankA < rankB }
            if (a.profileName == "Default") != (b.profileName == "Default") { return a.profileName == "Default" }
            return a.profileName.localizedStandardCompare(b.profileName) == .orderedAscending
        }
    }

    /// "_users_…_tq_eve.app_contents_resources_build_tranquility" → "Tranquility".
    public static func serverName(forFolder name: String) -> String {
        let lower = name.lowercased()
        for known in ["tranquility", "singularity", "thunderdome", "serenity", "infinity"] where lower.hasSuffix(known) {
            return known.capitalized
        }
        return name.split(separator: "_").last.map { $0.capitalized } ?? name
    }

    private static func serverRank(_ server: String) -> Int {
        switch server {
        case "Tranquility": return 0
        case "Singularity": return 1
        default: return 2
        }
    }

    /// The character and account settings files in a profile folder. The
    /// template files (`core_char__.dat` and friends) are left out.
    public static func scan(_ folder: URL) throws -> (characters: [EVESettingsFile], accounts: [EVESettingsFile]) {
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        let urls = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
        var characters: [EVESettingsFile] = []
        var accounts: [EVESettingsFile] = []

        for url in urls {
            let name = url.lastPathComponent
            let range = NSRange(name.startIndex..., in: name)
            guard let match = filePattern.firstMatch(in: name, range: range),
                  let kindRange = Range(match.range(at: 1), in: name),
                  let idRange = Range(match.range(at: 2), in: name),
                  let id = Int64(name[idRange]),
                  let kind = EVESettingsFile.Kind(rawValue: String(name[kindRange])),
                  let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true
            else { continue }

            let file = EVESettingsFile(
                kind: kind,
                entityID: id,
                url: url,
                modified: values.contentModificationDate ?? .distantPast,
                size: Int64(values.fileSize ?? 0)
            )
            if kind == .character { characters.append(file) } else { accounts.append(file) }
        }
        return (characters.sorted { $0.entityID < $1.entityID }, accounts.sorted { $0.entityID < $1.entityID })
    }

    // MARK: Sync

    /// Overwrites each target with the source file's contents and returns how
    /// many files were written. The source itself is skipped, and each target
    /// keeps its file permissions.
    @discardableResult
    public static func copy(_ source: EVESettingsFile, over targets: [EVESettingsFile]) throws -> Int {
        let folder = source.url.deletingLastPathComponent().standardizedFileURL
        for target in targets {
            guard target.kind == source.kind else { throw EVESettingsError.wrongKind(target.url.lastPathComponent) }
            guard target.url.deletingLastPathComponent().standardizedFileURL == folder else {
                throw EVESettingsError.differentFolder(target.url.lastPathComponent)
            }
        }

        let data = try Data(contentsOf: source.url)
        var written = 0
        for target in targets where target.url.standardizedFileURL != source.url.standardizedFileURL {
            let permissions = try? FileManager.default.attributesOfItem(atPath: target.url.path)[.posixPermissions]
            try data.write(to: target.url, options: .atomic)
            if let permissions {
                try? FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: target.url.path)
            }
            written += 1
        }
        return written
    }

    // MARK: Backups

    /// Copies every `core_*` file in the profile into a new timestamped folder
    /// and returns that folder.
    @discardableResult
    public static func backup(_ profile: EVEProfile, into backupsRoot: URL = defaultBackupsRoot, date: Date = Date()) throws -> URL {
        let fm = FileManager.default
        var destination = backupFolder(for: profile, in: backupsRoot).appendingPathComponent(timestamp(date), isDirectory: true)
        var suffix = 2
        while fm.fileExists(atPath: destination.path) {
            destination = backupFolder(for: profile, in: backupsRoot).appendingPathComponent("\(timestamp(date))-\(suffix)", isDirectory: true)
            suffix += 1
        }
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)

        for file in try settingsFiles(in: profile.url) {
            try fm.copyItem(at: file, to: destination.appendingPathComponent(file.lastPathComponent))
        }
        let manifest = ["source": profile.url.path, "created": ISO8601DateFormatter().string(from: date)]
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: destination.appendingPathComponent("manifest.json"))
        return destination
    }

    /// Backups for a profile, newest first.
    public static func backups(for profile: EVEProfile, in backupsRoot: URL = defaultBackupsRoot) -> [EVESettingsBackup] {
        subdirectories(of: backupFolder(for: profile, in: backupsRoot)).compactMap { folder in
            guard let files = try? settingsFiles(in: folder), !files.isEmpty else { return nil }
            let created = (try? folder.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return EVESettingsBackup(url: folder, created: created, fileCount: files.count)
        }
        .sorted { $0.created > $1.created }
    }

    /// Copies a backup's files back into the profile. The current files are
    /// backed up first, so a restore can itself be undone.
    @discardableResult
    public static func restore(_ backup: EVESettingsBackup, into profile: EVEProfile, backupsRoot: URL = defaultBackupsRoot) throws -> Int {
        try self.backup(profile, into: backupsRoot)
        var restored = 0
        for file in try settingsFiles(in: backup.url) {
            let target = profile.url.appendingPathComponent(file.lastPathComponent)
            try Data(contentsOf: file).write(to: target, options: .atomic)
            restored += 1
        }
        return restored
    }

    public static func backupFolder(for profile: EVEProfile, in backupsRoot: URL) -> URL {
        let raw = "\(profile.serverName)-\(profile.profileName)"
        let safe = String(raw.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "_" })
        return backupsRoot.appendingPathComponent(safe, isDirectory: true)
    }

    // MARK: Helpers

    private static func settingsFiles(in folder: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey])
            .filter { $0.lastPathComponent.hasPrefix("core_") }
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
    }

    private static func subdirectories(of folder: URL) -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        return urls.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter.string(from: date)
    }
}

/// Looks up character names from IDs with CCP's public ESI API.
public enum ESINameResolver {
    private static let userAgent = "EVESup/0.1 (macOS settings tool)"

    public static func characterNames(for ids: [Int64], singularity: Bool = false) async -> [Int64: String] {
        guard !ids.isEmpty else { return [:] }
        let datasource = singularity ? "singularity" : "tranquility"
        var names: [Int64: String] = [:]

        for start in stride(from: 0, to: ids.count, by: 500) {
            let chunk = Array(ids[start..<min(start + 500, ids.count)])
            if let resolved = try? await bulkLookup(chunk, datasource: datasource) {
                names.merge(resolved) { current, _ in current }
                continue
            }
            // One unknown ID makes the bulk call fail, so fall back to one request per character.
            await withTaskGroup(of: (Int64, String?).self) { group in
                for id in chunk {
                    group.addTask { (id, try? await singleLookup(id, datasource: datasource)) }
                }
                for await (id, name) in group {
                    if let name { names[id] = name }
                }
            }
        }
        return names
    }

    private static func bulkLookup(_ ids: [Int64], datasource: String) async throws -> [Int64: String] {
        var request = URLRequest(url: URL(string: "https://esi.evetech.net/latest/universe/names/?datasource=\(datasource)")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONEncoder().encode(ids)

        struct Entry: Decodable { let id: Int64; let name: String; let category: String }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let entries = try JSONDecoder().decode([Entry].self, from: data)
        return Dictionary(entries.filter { $0.category == "character" }.map { ($0.id, $0.name) }) { first, _ in first }
    }

    private static func singleLookup(_ id: Int64, datasource: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://esi.evetech.net/latest/characters/\(id)/?datasource=\(datasource)")!)
        request.timeoutInterval = 15
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        struct Character: Decodable { let name: String }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(Character.self, from: data).name
    }
}
