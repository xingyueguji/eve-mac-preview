import XCTest
@testable import EVESupCore

/// Runs against a throwaway folder laid out like ~/Library/Application Support/CCP/EVE.
final class EVESettingsStoreTests: XCTestCase {
    private var root: URL!
    private var backups: URL!
    private var profileURL: URL!

    override func setUpWithError() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("evesup-tests-\(UUID().uuidString)")
        root = base.appendingPathComponent("CCP/EVE")
        backups = base.appendingPathComponent("Backups")
        let server = root.appendingPathComponent("_users_me_library_application_support_eve_online_sharedcache_tq_eve.app_contents_resources_build_tranquility")
        profileURL = server.appendingPathComponent("settings_Default")
        try FileManager.default.createDirectory(at: profileURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: server.appendingPathComponent("settings_Mining"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: server.appendingPathComponent("cache"), withIntermediateDirectories: true)
        let sisi = root.appendingPathComponent("_users_me_library_application_support_eve_online_sharedcache_sisi_eve.app_contents_resources_build_singularity/settings_Default")
        try FileManager.default.createDirectory(at: sisi, withIntermediateDirectories: true)

        for (name, text) in [
            ("core_char_111.dat", "char one"),
            ("core_char_222.dat", "char two"),
            ("core_char_333.dat", "char three"),
            ("core_char__.dat", "char template"),
            ("core_char_('char', None, 'dat').dat", "odd file"),
            ("core_user_9001.dat", "user A"),
            ("core_user_9002.dat", "user B"),
            ("core_user__.dat", "user template"),
            ("prefs.ini", "prefs"),
        ] {
            try Data(text.utf8).write(to: profileURL.appendingPathComponent(name))
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: profileURL.appendingPathComponent("core_char_222.dat").path)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent().deletingLastPathComponent())
    }

    private func read(_ name: String) throws -> String {
        try String(contentsOf: profileURL.appendingPathComponent(name), encoding: .utf8)
    }

    private var profile: EVEProfile {
        EVESettingsStore.discoverProfiles(root: root).first { $0.url.standardizedFileURL == profileURL.standardizedFileURL }!
    }

    func testDiscoversProfilesTranquilityDefaultFirst() {
        let profiles = EVESettingsStore.discoverProfiles(root: root)
        XCTAssertEqual(profiles.map(\.displayName), ["Tranquility · Default", "Tranquility · Mining", "Singularity · Default"])
        XCTAssertTrue(profiles[2].isSingularity)
    }

    func testScanFindsOnlyNumberedFiles() throws {
        let scanned = try EVESettingsStore.scan(profileURL)
        XCTAssertEqual(scanned.characters.map(\.entityID), [111, 222, 333])
        XCTAssertEqual(scanned.accounts.map(\.entityID), [9001, 9002])
    }

    func testCopyOverwritesTargetsKeepsSourceAndPermissions() throws {
        let scanned = try EVESettingsStore.scan(profileURL)
        let source = scanned.characters[0]
        let written = try EVESettingsStore.copy(source, over: scanned.characters)
        XCTAssertEqual(written, 2)
        XCTAssertEqual(try read("core_char_111.dat"), "char one")
        XCTAssertEqual(try read("core_char_222.dat"), "char one")
        XCTAssertEqual(try read("core_char_333.dat"), "char one")
        XCTAssertEqual(try read("core_char__.dat"), "char template")
        XCTAssertEqual(try read("core_user_9001.dat"), "user A")
        let permissions = try FileManager.default.attributesOfItem(atPath: profileURL.appendingPathComponent("core_char_222.dat").path)[.posixPermissions] as? Int
        XCTAssertEqual(permissions, 0o600)
    }

    func testCopyRefusesMixedKinds() throws {
        let scanned = try EVESettingsStore.scan(profileURL)
        XCTAssertThrowsError(try EVESettingsStore.copy(scanned.characters[0], over: scanned.accounts))
        XCTAssertEqual(try read("core_user_9002.dat"), "user B")
    }

    func testBackupAndRestore() throws {
        let backupURL = try EVESettingsStore.backup(profile, into: backups)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.appendingPathComponent("core_char_222.dat").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.appendingPathComponent("manifest.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: backupURL.appendingPathComponent("prefs.ini").path))

        let scanned = try EVESettingsStore.scan(profileURL)
        try EVESettingsStore.copy(scanned.accounts[1], over: scanned.accounts)
        XCTAssertEqual(try read("core_user_9001.dat"), "user B")

        let listed = EVESettingsStore.backups(for: profile, in: backups)
        XCTAssertEqual(listed.count, 1)
        XCTAssertEqual(listed.first?.fileCount, 9 - 1)  // every core_* file, not prefs.ini

        let restored = try EVESettingsStore.restore(listed[0], into: profile, backupsRoot: backups)
        XCTAssertEqual(restored, 8)
        XCTAssertEqual(try read("core_user_9001.dat"), "user A")
        // Restoring made its own backup first.
        XCTAssertEqual(EVESettingsStore.backups(for: profile, in: backups).count, 2)
    }

    func testServerNames() {
        XCTAssertEqual(EVESettingsStore.serverName(forFolder: "c_ccp_eve_online_tq_tranquility"), "Tranquility")
        XCTAssertEqual(EVESettingsStore.serverName(forFolder: "x_sisi_singularity"), "Singularity")
        XCTAssertEqual(EVESettingsStore.serverName(forFolder: "something_custom"), "Custom")
    }
}
