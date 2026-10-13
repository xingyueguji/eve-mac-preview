import AppKit
import Combine
import EVESupCore

/// Ties everything together: config, client tracking, hotkeys, previews.
@MainActor
final class AppState: ObservableObject {
    @Published var config: AppConfig {
        didSet { configDidChange(from: oldValue) }
    }
    /// Clients temporarily skipped by cycling (⇧-click on a preview). Not saved.
    @Published private(set) var excludedPIDs = Set<pid_t>()
    /// Binding ID → problem with that key (taken by another app, duplicate…).
    @Published private(set) var hotkeyIssues: [String: String] = [:]
    @Published private(set) var permissions = PermissionStatus.current()
    @Published var settingsPane: SettingsPane? = .cycling

    let monitor: ClientMonitor
    let configURL: URL
    let isFirstLaunch: Bool
    private(set) var previews: PreviewManager?
    private(set) lazy var syncModel = SyncModel(state: self)

    private var saveWork: DispatchWorkItem?
    private var hotkeySuspensions = 0
    private var permissionTimer: Timer?
    private var monitorForwarding: AnyCancellable?

    init(configURL: URL) {
        let loaded = ConfigStore.load(from: configURL)
        self.configURL = configURL
        self.config = loaded.config
        self.isFirstLaunch = !loaded.existed
        self.monitor = ClientMonitor(extraApps: Set(loaded.config.clientBundleIDs))
        // Views read monitor state through AppState, so pass its changes along.
        monitorForwarding = monitor.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }

    func start() {
        monitor.onClientsChanged = { [weak self] in self?.clientsChanged() }
        monitor.onActiveChanged = { [weak self] in self?.previews?.refreshActiveState() }
        monitor.start()

        let previews = PreviewManager(state: self)
        self.previews = previews
        previews.update()
        registerHotkeys()

        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPermissions() }
        }
        if isFirstLaunch { save() }
        // Learn the names of characters in EVE's settings folder, so they can be
        // added to cycle groups before they've been logged in with EVESup running.
        syncModel.reload()
        Log.info("EVESup started (config \(configURL.path)); screen recording: \(permissions.screenRecording), accessibility: \(permissions.accessibility)")
    }

    // MARK: Switching

    func cycle(groupID: UUID, direction: CycleDirection) {
        guard let group = config.cycleGroups.first(where: { $0.id == groupID }) else { return }
        let candidates = monitor.clients.map {
            CycleClient(pid: $0.pid, characterName: $0.characterName, excluded: excludedPIDs.contains($0.pid))
        }
        let current = monitor.activePID ?? monitor.lastActivePID
        guard let pid = CycleEngine.target(direction: direction, members: group.members, clients: candidates, current: current),
              let client = monitor.client(pid: pid)
        else {
            Log.info("“\(group.name)” \(direction.rawValue): no logged-in client to switch to")
            return
        }
        switchTo(client, reason: "“\(group.name)” \(direction.rawValue)")
    }

    func jump(to name: String) {
        guard let client = monitor.client(named: name) else {
            Log.info("jump to \(name): not logged in")
            return
        }
        switchTo(client, reason: "jump to \(name)")
    }

    func switchTo(_ client: EVEClient, reason: String) {
        monitor.noteRequestedActivation(of: client.pid)
        WindowActivator.activate(client, reason: reason)
    }

    func toggleExcluded(_ pid: pid_t) {
        if excludedPIDs.contains(pid) { excludedPIDs.remove(pid) } else { excludedPIDs.insert(pid) }
        previews?.update()
    }

    // MARK: Hotkeys

    static func bindingID(group: UUID, direction: CycleDirection) -> String {
        "group.\(group.uuidString).\(direction.rawValue)"
    }

    static func bindingID(character: String) -> String {
        "character.\(character.lowercased())"
    }

    /// Pauses global hotkeys while a key recorder is listening.
    func suspendHotkeys() {
        hotkeySuspensions += 1
        HotkeyCenter.shared.unregisterAll()
        MouseButtonCenter.shared.unregisterAll()
    }

    func resumeHotkeys() {
        hotkeySuspensions = max(0, hotkeySuspensions - 1)
        if hotkeySuspensions == 0 { registerHotkeys() }
    }

    func registerHotkeys() {
        let keys = HotkeyCenter.shared
        let mouse = MouseButtonCenter.shared
        keys.unregisterAll()
        mouse.unregisterAll()
        guard hotkeySuspensions == 0 else { return }

        var issues: [String: String] = [:]
        var owners: [Hotkey: String] = [:]

        func bind(_ hotkey: Hotkey?, id: String, owner: String, variants: Bool, action: @escaping () -> Void) {
            guard let hotkey else { return }
            for (index, combo) in (variants ? hotkey.modifierVariants() : [hotkey]).enumerated() {
                if let other = owners[combo] {
                    if index == 0 { issues[id] = "Same key as \(other)" }
                    continue
                }
                if combo.isMouseButton {
                    mouse.register(combo, action: action)
                    owners[combo] = owner
                } else if keys.register(combo, action: action) {
                    owners[combo] = owner
                } else if index == 0 {
                    issues[id] = "macOS or another app already uses this key"
                }
            }
            if hotkey.isMouseButton, issues[id] == nil, !mouse.hidesClicksFromApps {
                issues[id] = "Works, but EVE also gets the click. Allow Accessibility in General to stop that."
            }
        }

        for group in config.cycleGroups where group.isEnabled {
            let groupID = group.id
            bind(group.nextKey, id: Self.bindingID(group: groupID, direction: .forward),
                 owner: "“\(group.name)” next", variants: group.worksWithModifiersHeld) { [weak self] in
                self?.cycle(groupID: groupID, direction: .forward)
            }
            bind(group.previousKey, id: Self.bindingID(group: groupID, direction: .backward),
                 owner: "“\(group.name)” previous", variants: group.worksWithModifiersHeld) { [weak self] in
                self?.cycle(groupID: groupID, direction: .backward)
            }
        }
        for (name, hotkey) in config.characterHotkeys.sorted(by: { $0.key < $1.key }) {
            bind(hotkey, id: Self.bindingID(character: name), owner: "jump to \(name)", variants: false) { [weak self] in
                self?.jump(to: name)
            }
        }
        if issues != hotkeyIssues { hotkeyIssues = issues }
    }

    // MARK: Characters

    /// Every character name we know of: logged in now, seen before, or found in EVE's settings files.
    var allCharacterNames: [String] {
        var seen = Set<String>()
        var names: [String] = []
        let sources = monitor.clients.compactMap(\.characterName) + config.knownCharacters + Array(config.sync.characterNames.values)
        for name in sources where seen.insert(name.lowercased()).inserted {
            names.append(name)
        }
        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func isOnline(_ name: String) -> Bool {
        monitor.client(named: name) != nil
    }

    func groupNames(containing name: String) -> [String] {
        config.cycleGroups
            .filter { group in group.members.contains { $0.caseInsensitiveCompare(name) == .orderedSame } }
            .map(\.name)
    }

    func forgetCharacter(_ name: String) {
        config.knownCharacters.removeAll { $0.caseInsensitiveCompare(name) == .orderedSame }
        config.characterHotkeys[name] = nil
        config.sync.characterNames = config.sync.characterNames.filter { $0.value.caseInsensitiveCompare(name) != .orderedSame }
    }

    // MARK: Previews

    func applyDefaultThumbnailSize() {
        let width = config.previews.defaultWidth, height = config.previews.defaultHeight
        config.thumbnailFrames = config.thumbnailFrames.mapValues {
            StoredRect(x: $0.x, y: $0.y + $0.height - height, width: width, height: height)
        }
        previews?.resizeAll(to: CGSize(width: width, height: height))
    }

    func rearrangePreviews() {
        previews?.rearrangeAll()
    }

    func alignPreviewsToGrid() {
        previews?.alignAllToGrid()
    }

    // MARK: Changes

    private func clientsChanged() {
        let known = Set(config.knownCharacters.map { $0.lowercased() })
        var added: [String] = []
        for name in monitor.clients.compactMap(\.characterName) where !known.contains(name.lowercased()) {
            if !added.contains(name) { added.append(name) }
        }
        if !added.isEmpty {
            config.knownCharacters = (config.knownCharacters + added)
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        }

        let live = Set(monitor.clients.map(\.pid))
        if !excludedPIDs.isSubset(of: live) { excludedPIDs.formIntersection(live) }
        previews?.update()
    }

    private func refreshPermissions() {
        let current = PermissionStatus.current()
        guard current != permissions else { return }
        let accessibilityChanged = current.accessibility != permissions.accessibility
        permissions = current
        // Mouse-button shortcuts can only hide clicks from EVE with Accessibility.
        if accessibilityChanged { registerHotkeys() }
        Log.info("permissions changed; screen recording: \(current.screenRecording), accessibility: \(current.accessibility)")
        monitor.refresh()
        previews?.update()
    }

    private func configDidChange(from old: AppConfig) {
        scheduleSave()
        if old.hotkeySignature != config.hotkeySignature { registerHotkeys() }
        if old.clientBundleIDs != config.clientBundleIDs {
            monitor.extraApps = Set(config.clientBundleIDs)
            monitor.refresh()
        }
        if old.previews != config.previews { previews?.settingsChanged(from: old.previews) }
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.save() }
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func save() {
        saveWork?.cancel()
        saveWork = nil
        do {
            try ConfigStore.save(config, to: configURL)
        } catch {
            Log.error("couldn't save config: \(error.localizedDescription)")
        }
    }
}

/// The parts of the config that decide which hotkeys are registered.
struct HotkeySignature: Equatable {
    struct Group: Equatable {
        let id: UUID
        let name: String
        let isEnabled: Bool
        let nextKey: Hotkey?
        let previousKey: Hotkey?
        let variants: Bool
    }

    let groups: [Group]
    let characters: [String: Hotkey]
}

extension AppConfig {
    var hotkeySignature: HotkeySignature {
        HotkeySignature(
            groups: cycleGroups.map {
                .init(id: $0.id, name: $0.name, isEnabled: $0.isEnabled, nextKey: $0.nextKey,
                      previousKey: $0.previousKey, variants: $0.worksWithModifiersHeld)
            },
            characters: characterHotkeys
        )
    }
}
