import AppKit
import EVESupCore
import Security

/// Checks GitHub for a newer release and installs it in place.
///
/// An update is only installed if it's signed with the same certificate as
/// the running copy. That keeps tampered downloads out, and because macOS
/// ties Screen Recording and Accessibility to that signature, the updated app
/// keeps its permissions. Settings live outside the app, so they're kept too.
@MainActor
final class Updater: ObservableObject {
    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case available(String)
        case downloading
        case installing
        case failed(String)
    }

    enum UpdateError: LocalizedError {
        case server(Int)
        case noArchive
        case unzipFailed
        case wrongApp
        case wrongVersion(String)
        case signatureMismatch
        case notSelfUpdatable

        var errorDescription: String? {
            switch self {
            case .server(let code): "GitHub answered with error \(code)."
            case .noArchive: "This release has no update package. Download it from GitHub instead."
            case .unzipFailed: "The downloaded update couldn't be unpacked."
            case .wrongApp: "The download isn't EVESup."
            case .wrongVersion(let found): "The download is version \(found), not the expected one."
            case .signatureMismatch: "The download isn't signed with EVESup's certificate, so it wasn't installed."
            case .notSelfUpdatable: "This copy of EVESup can't update itself. Download the new version from GitHub."
            }
        }
    }

    nonisolated static let releasesPage = URL(string: "https://github.com/xingyueguji/eve-mac-preview/releases/latest")!
    nonisolated static let defaultFeed = URL(string: "https://api.github.com/repos/xingyueguji/eve-mac-preview/releases/latest")!

    @Published private(set) var status = Status.idle
    private(set) var latest: ReleaseInfo?
    /// Off in test runs, where a modal alert would block everything.
    var presentsAlerts = true

    private unowned let state: AppState
    private let feed: URL
    private var timer: Timer?

    init(state: AppState, feed: URL = Updater.defaultFeed) {
        self.state = state
        self.feed = feed
    }

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// Release builds are signed with the EVESup certificate; ad-hoc builds
    /// (from source) can't prove an update is genuine, so they don't self-update.
    var canUpdateItself: Bool {
        (Self.designatedRequirement().map { !$0.description.contains("cdhash") }) ?? false
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 24 * 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkAutomatically() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            MainActor.assumeIsolated { self?.checkAutomatically() }
        }
    }

    private func checkAutomatically() {
        guard state.config.checksForUpdates else { return }
        check(userInitiated: false)
    }

    /// Looks for a newer release. Checks the user started report errors, and
    /// with `alerts` their result pops up too; automatic checks only update the
    /// menu and the General page, so nothing pops up in the middle of a game.
    func check(userInitiated: Bool, alerts: Bool = true) {
        let alerts = userInitiated && alerts
        switch status {
        case .checking, .downloading, .installing: return
        default: break
        }
        status = .checking
        Task {
            do {
                let release = try await fetchLatest()
                latest = release
                if let available = release.version, let current = AppVersion(currentVersion), available > current {
                    status = .available(available.description)
                    Log.info("update available: \(available) (running \(current))")
                    if alerts { offerInstall(release) }
                } else {
                    status = .upToDate
                    if alerts { showAlert("EVESup is up to date", "You have the latest version, \(currentVersion).") }
                }
            } catch {
                Log.warn("update check failed: \(error.localizedDescription)")
                status = userInitiated ? .failed("Couldn't check for updates: \(error.localizedDescription)") : .idle
                if alerts { showAlert("Couldn't check for updates", error.localizedDescription) }
            }
        }
    }

    func installLatest() {
        guard let release = latest else { return check(userInitiated: true) }
        guard canUpdateItself else {
            NSWorkspace.shared.open(release.pageURL)
            return
        }
        guard let archive = release.updateArchive else {
            status = .failed(UpdateError.noArchive.localizedDescription)
            NSWorkspace.shared.open(release.pageURL)
            return
        }
        status = .downloading
        Task {
            do {
                let app = Bundle.main.bundleURL
                // A scratch folder on the app's volume, so the final swap is a quick rename.
                let work = try FileManager.default.url(
                    for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: app, create: true)
                let zip = work.appendingPathComponent(archive.name)
                if archive.downloadURL.isFileURL {
                    // Local test feeds.
                    try FileManager.default.copyItem(at: archive.downloadURL, to: zip)
                } else {
                    let (download, response) = try await URLSession.shared.download(from: archive.downloadURL)
                    if let http = response as? HTTPURLResponse, http.statusCode != 200 { throw UpdateError.server(http.statusCode) }
                    try FileManager.default.moveItem(at: download, to: zip)
                }

                status = .installing
                try await Self.unzip(zip, into: work)
                let newApp = work.appendingPathComponent("EVESup.app")
                try Self.verify(newApp, expectedVersion: release.version)
                _ = try FileManager.default.replaceItemAt(app, withItemAt: newApp)
                try? FileManager.default.removeItem(at: work)
                Log.info("installed \(release.tagName); relaunching")
                Relauncher.relaunch(app)
            } catch {
                Log.error("update failed: \(error.localizedDescription)")
                status = .failed(error.localizedDescription)
                showAlert("Update not installed", error.localizedDescription)
            }
        }
    }

    // MARK: Steps

    private func fetchLatest() async throws -> ReleaseInfo {
        var request = URLRequest(url: feed)
        request.timeoutInterval = 20
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("EVESup/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 { throw UpdateError.server(http.statusCode) }
        return try JSONDecoder().decode(ReleaseInfo.self, from: data)
    }

    private nonisolated static func unzip(_ zip: URL, into folder: URL) async throws {
        try await Task.detached {
            let ditto = Process()
            ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            ditto.arguments = ["-x", "-k", zip.path, folder.path]
            try ditto.run()
            ditto.waitUntilExit()
            guard ditto.terminationStatus == 0 else { throw UpdateError.unzipFailed }
        }.value
    }

    /// The new app must be EVESup, the advertised version, and signed with this copy's certificate.
    private static func verify(_ app: URL, expectedVersion: AppVersion?) throws {
        guard let bundle = Bundle(url: app), bundle.bundleIdentifier == Bundle.main.bundleIdentifier else {
            throw UpdateError.wrongApp
        }
        let found = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        if let expectedVersion, AppVersion(found) != expectedVersion { throw UpdateError.wrongVersion(found) }

        guard let requirement = designatedRequirement() else { throw UpdateError.notSelfUpdatable }
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else {
            throw UpdateError.signatureMismatch
        }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        guard SecStaticCodeCheckValidity(code, flags, requirement.requirement) == errSecSuccess else {
            throw UpdateError.signatureMismatch
        }
    }

    /// The running app's designated requirement, i.e. "this bundle ID, signed by this certificate".
    private static func designatedRequirement() -> (requirement: SecRequirement, description: String)? {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var requirement: SecRequirement?
        var text: CFString?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess, let requirement,
              SecRequirementCopyString(requirement, [], &text) == errSecSuccess
        else { return nil }
        return (requirement, (text as String?) ?? "")
    }

    private func offerInstall(_ release: ReleaseInfo) {
        guard presentsAlerts else { return }
        let alert = NSAlert()
        alert.messageText = "EVESup \(release.version?.description ?? release.tagName) is available"
        alert.informativeText = canUpdateItself
            ? "You have \(currentVersion). EVESup will download the update, restart, and keep your settings and permissions."
            : "You have \(currentVersion). This copy can't update itself, so the download page will open."
        alert.addButton(withTitle: canUpdateItself ? "Install and Relaunch" : "Open Download Page")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { installLatest() }
    }

    private func showAlert(_ title: String, _ message: String) {
        guard presentsAlerts else { return }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

/// Quits EVESup and starts it again, from the same place and with the same arguments.
enum Relauncher {
    @MainActor
    static func relaunch(_ app: URL = Bundle.main.bundleURL) {
        let pid = ProcessInfo.processInfo.processIdentifier
        let arguments = Array(CommandLine.arguments.dropFirst())
        // Wait for this process to exit first, so the new one can take over the hotkeys.
        var script = "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; /usr/bin/open -n \"$0\""
        if !arguments.isEmpty { script += " --args \"$@\"" }
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/sh")
        shell.arguments = ["-c", script, app.path] + arguments
        try? shell.run()
        NSApp.terminate(nil)
    }
}
