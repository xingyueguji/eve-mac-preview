import AppKit
import EVESupCore

/// A running EVE client and its main window.
struct EVEClient: Identifiable, Equatable {
    let pid: pid_t
    var windowID: CGWindowID
    /// nil when macOS won't share window titles (no Screen Recording permission).
    var title: String?
    var characterName: String?
    /// Window frame in Quartz coordinates (origin at the top-left of the main display).
    var frame: CGRect
    var isOnScreen: Bool

    var id: pid_t { pid }

    var label: String {
        if let characterName { return characterName }
        return title == nil ? "EVE client \(pid)" : "Character select"
    }
}

/// Finds EVE clients and tracks which one is in front.
///
/// The EVE launcher starts the game binary directly rather than through
/// LaunchServices, so clients are missing from `NSWorkspace.runningApplications`
/// and activation notifications for them carry no process ID. Clients are
/// therefore found through the window list, and the active one is confirmed
/// by asking each client process whether it's active.
@MainActor
final class ClientMonitor: ObservableObject {
    @Published private(set) var clients: [EVEClient] = []
    /// The EVE client that is the frontmost app right now, if any.
    @Published private(set) var activePID: pid_t?
    /// The EVE client that was in front most recently, even if another app is in front now.
    private(set) var lastActivePID: pid_t?
    /// Whether the frontmost app is an EVE client or EVESup itself.
    @Published private(set) var eveOrSelfIsFrontmost = false

    /// Other app IDs or app names to treat as EVE clients (for testing or other
    /// games). The EVE client itself always counts.
    var extraApps: Set<String> {
        didSet { extraAppKeys = Self.keys(for: extraApps) }
    }
    var onClientsChanged: (() -> Void)?
    var onActiveChanged: (() -> Void)?

    private struct AppIdentity {
        let bundleID: String?
        let name: String?
        let executable: String?
    }

    private var timer: Timer?
    private var extraAppKeys: Set<String>
    /// Identity of each window-owning process, looked up once per process.
    private var identityCache: [pid_t: AppIdentity] = [:]
    /// When EVESup last asked for a switch, so polling doesn't undo it before it lands.
    private var lastRequest = Date.distantPast

    init(extraApps: Set<String>) {
        self.extraApps = extraApps
        extraAppKeys = Self.keys(for: extraApps)
    }

    private static func keys(for apps: Set<String>) -> Set<String> {
        Set(apps.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty })
    }

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.frontmostChanged(to: app) }
        }
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
        frontmostChanged(to: NSWorkspace.shared.frontmostApplication)
    }

    func client(pid: pid_t) -> EVEClient? {
        clients.first { $0.pid == pid }
    }

    func client(named name: String) -> EVEClient? {
        let wanted = name.trimmingCharacters(in: .whitespaces).lowercased()
        return clients.first { $0.characterName?.lowercased() == wanted }
    }

    /// Records a switch we just asked for, so a second key press made before
    /// macOS reports the change steps on from the new client.
    func noteRequestedActivation(of pid: pid_t) {
        lastRequest = Date()
        lastActivePID = pid
        if activePID != pid {
            activePID = pid
            onActiveChanged?()
        }
    }

    /// The client macOS reports as active, asking each client process directly.
    func activeClientPID() -> pid_t? {
        clients.first { NSRunningApplication(processIdentifier: $0.pid)?.isActive == true }?.pid
    }

    /// The frontmost app's process ID, including EVE clients that NSWorkspace reports as -1.
    func frontmostPID() -> pid_t? {
        if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier, pid > 0 { return pid }
        return activeClientPID()
    }

    func refresh() {
        let infos = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        var owners = Set<pid_t>()
        for info in infos {
            if let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value { owners.insert(pid) }
        }
        identityCache = identityCache.filter { owners.contains($0.key) }
        let pids = owners.filter(isClient(pid:))

        let updated = pids.isEmpty ? [] : Self.mainWindows(for: pids, in: infos)
        if updated != clients {
            clients = updated
            if let active = activePID, !pids.contains(active) { activePID = nil }
            if let last = lastActivePID, !pids.contains(last) { lastActivePID = nil }
            onClientsChanged?()
        }
        // Catch anything the activation notifications missed.
        if Date().timeIntervalSince(lastRequest) > 0.5, let actual = activeClientPID(), actual != activePID {
            setActive(actual)
        }
    }

    private func isClient(pid: pid_t) -> Bool {
        let identity = identityCache[pid] ?? {
            let app = NSRunningApplication(processIdentifier: pid)
            let identity = AppIdentity(
                bundleID: app?.bundleIdentifier, name: app?.localizedName, executable: app?.executableURL?.lastPathComponent)
            identityCache[pid] = identity
            return identity
        }()
        return isClient(identity)
    }

    /// EVE itself, or an extra app given by bundle ID, app name or executable name.
    private func isClient(_ identity: AppIdentity) -> Bool {
        if identity.bundleID == AppConfig.eveBundleID { return true }
        return [identity.bundleID, identity.name, identity.executable].contains { value in
            value.map { extraAppKeys.contains($0.lowercased()) } ?? false
        }
    }

    private func setActive(_ pid: pid_t) {
        activePID = pid
        lastActivePID = pid
        eveOrSelfIsFrontmost = true
        onActiveChanged?()
    }

    private func frontmostChanged(to app: NSRunningApplication?) {
        guard let app else { return }
        // EVESup activates itself for a moment while switching clients; ignore that.
        if app.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            eveOrSelfIsFrontmost = true
            onActiveChanged?()
            return
        }
        let isClient = isClient(AppIdentity(
            bundleID: app.bundleIdentifier, name: app.localizedName, executable: app.executableURL?.lastPathComponent))
        guard isClient else {
            activePID = nil
            eveOrSelfIsFrontmost = false
            onActiveChanged?()
            return
        }
        if app.processIdentifier > 0 {
            setActive(app.processIdentifier)
        } else if let pid = activeClientPID() {
            setActive(pid)
        } else {
            // The client may not report itself active yet; look again shortly.
            eveOrSelfIsFrontmost = true
            onActiveChanged?()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                MainActor.assumeIsolated {
                    if let self, let pid = self.activeClientPID() { self.setActive(pid) }
                }
            }
        }
    }

    /// The largest normal window of each process, preferring on-screen windows.
    private static func mainWindows(for pids: Set<pid_t>, in infos: [[String: Any]]) -> [EVEClient] {
        var best: [pid_t: (client: EVEClient, score: Double)] = [:]

        for info in infos {
            guard let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, pids.contains(pid),
                  (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let windowID = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo as CFDictionary),
                  bounds.width >= 120, bounds.height >= 90
            else { continue }

            let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            guard alpha > 0 else { continue }

            let onScreen = (info[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false
            let title = (info[kCGWindowName as String] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let score = (onScreen ? 1e12 : 0) + (title != nil ? 1e11 : 0) + Double(bounds.width * bounds.height)

            if let existing = best[pid], existing.score >= score { continue }
            let client = EVEClient(
                pid: pid,
                windowID: windowID,
                title: title,
                characterName: title.flatMap(ClientTitle.characterName(from:)),
                frame: bounds,
                isOnScreen: onScreen
            )
            best[pid] = (client, score)
        }
        return best.values.map(\.client).sorted { $0.pid < $1.pid }
    }
}
