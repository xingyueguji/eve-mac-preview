import Foundation
import os

/// Writes to the unified log and to ~/Library/Logs/EVESup/EVESup.log, so
/// switching problems can be diagnosed after the fact.
enum Log {
    private static let logger = Logger(subsystem: "com.evesup.EVESup", category: "app")
    private static let queue = DispatchQueue(label: "EVESup.log")

    static let fileURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/EVESup/EVESup.log")

    private static let handle: FileHandle? = {
        let fm = FileManager.default
        try? fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Start over once the file passes 2 MB.
        if let size = (try? fm.attributesOfItem(atPath: fileURL.path))?[.size] as? Int, size > 2_000_000 {
            try? fm.removeItem(at: fileURL)
        }
        if !fm.fileExists(atPath: fileURL.path) { fm.createFile(atPath: fileURL.path, contents: nil) }
        let handle = try? FileHandle(forWritingTo: fileURL)
        _ = try? handle?.seekToEnd()
        return handle
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    static func info(_ message: String) { write("INFO", message) }
    static func warn(_ message: String) { write("WARN", message) }
    static func error(_ message: String) { write("ERROR", message) }

    private static func write(_ level: String, _ message: String) {
        logger.log("\(level, privacy: .public) \(message, privacy: .public)")
        let date = Date()
        queue.async {
            let line = "\(timeFormatter.string(from: date)) \(level) \(message)\n"
            if let data = line.data(using: .utf8) { try? handle?.write(contentsOf: data) }
        }
    }
}
