import Foundation

/// A dotted version number such as "0.2.1" or "v1.0", compared numerically.
public struct AppVersion: Comparable, CustomStringConvertible, Sendable {
    public let components: [Int]

    /// Accepts an optional leading "v" and ignores a pre-release suffix ("1.2.0-beta").
    public init?(_ string: String) {
        var text = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.first == "v" || text.first == "V" { text.removeFirst() }
        let core = text.split(separator: "-", maxSplits: 1).first.map(String.init) ?? ""
        let numbers = core.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !numbers.isEmpty, numbers.allSatisfy({ $0 != nil }) else { return nil }
        components = numbers.compactMap { $0 }
    }

    public var description: String { components.map(String.init).joined(separator: ".") }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        for index in 0..<max(lhs.components.count, rhs.components.count) {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool { !(lhs < rhs) && !(rhs < lhs) }
}

/// The parts of a GitHub release (from the REST API) the updater needs.
public struct ReleaseInfo: Decodable, Sendable {
    public struct Asset: Decodable, Sendable {
        public let name: String
        public let downloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case downloadURL = "browser_download_url"
        }
    }

    public let tagName: String
    public let pageURL: URL
    public let notes: String?
    public let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case pageURL = "html_url"
        case notes = "body"
        case assets
    }

    public var version: AppVersion? { AppVersion(tagName) }

    /// The zipped app the in-app updater installs, e.g. "EVESup-0.2.1.zip".
    public var updateArchive: Asset? {
        assets.first { $0.name.hasPrefix("EVESup-") && $0.name.hasSuffix(".zip") }
    }
}
