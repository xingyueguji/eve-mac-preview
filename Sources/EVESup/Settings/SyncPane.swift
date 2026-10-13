import AppKit
import EVESupCore
import SwiftUI

/// Copies one character's (and/or one account's) EVE settings file over the
/// others in the same profile folder, with a backup first.
@MainActor
final class SyncModel: ObservableObject {
    struct Status: Equatable {
        let message: String
        let isError: Bool
        var backupURL: URL?
    }

    @Published private(set) var profiles: [EVEProfile] = []
    @Published var selectedProfileID: String? {
        didSet { if oldValue != selectedProfileID { profileChanged() } }
    }
    @Published private(set) var characters: [EVESettingsFile] = []
    @Published private(set) var accounts: [EVESettingsFile] = []
    @Published var characterSource: Int64? {
        didSet { sourceChanged(old: oldValue, new: characterSource, targets: &characterTargets) }
    }
    @Published var accountSource: Int64? {
        didSet { sourceChanged(old: oldValue, new: accountSource, targets: &accountTargets) }
    }
    @Published var characterTargets = Set<Int64>()
    @Published var accountTargets = Set<Int64>()
    @Published private(set) var backups: [EVESettingsBackup] = []
    @Published private(set) var isLookingUpNames = false
    @Published var status: Status?

    private unowned let state: AppState
    let backupsRoot: URL

    init(state: AppState, backupsRoot: URL = EVESettingsStore.defaultBackupsRoot) {
        self.state = state
        self.backupsRoot = backupsRoot
    }

    var profile: EVEProfile? { profiles.first { $0.id == selectedProfileID } }

    // MARK: Loading

    func reload() {
        profiles = EVESettingsStore.discoverProfiles()
        let preferred = state.config.sync.lastProfilePath
        let id = profiles.first { $0.id == preferred }?.id ?? profiles.first?.id
        if selectedProfileID != id {
            selectedProfileID = id
        } else {
            rescan()
        }
    }

    private func profileChanged() {
        if let selectedProfileID, state.config.sync.lastProfilePath != selectedProfileID {
            state.config.sync.lastProfilePath = selectedProfileID
        }
        status = nil
        characterSource = nil
        accountSource = nil
        rescan(resetTargets: true)
    }

    func rescan(resetTargets: Bool = false) {
        guard let profile else {
            characters = []
            accounts = []
            backups = []
            return
        }
        do {
            let scanned = try EVESettingsStore.scan(profile.url)
            characters = scanned.characters
            accounts = scanned.accounts.sorted { $0.modified > $1.modified }
            sortCharacters()
        } catch {
            characters = []
            accounts = []
            status = Status(message: "Couldn't read \(profile.url.path): \(error.localizedDescription)", isError: true)
        }

        let characterIDs = Set(characters.map(\.entityID))
        let accountIDs = Set(accounts.map(\.entityID))
        if let source = characterSource, !characterIDs.contains(source) { characterSource = nil }
        if let source = accountSource, !accountIDs.contains(source) { accountSource = nil }
        if resetTargets || !characterTargets.isSubset(of: characterIDs) {
            characterTargets = characterIDs.subtracting([characterSource].compactMap { $0 })
        }
        if resetTargets || !accountTargets.isSubset(of: accountIDs) {
            accountTargets = accountIDs.subtracting([accountSource].compactMap { $0 })
        }
        backups = EVESettingsStore.backups(for: profile, in: backupsRoot)
        lookUpMissingNames()
    }

    private func sourceChanged(old: Int64?, new: Int64?, targets: inout Set<Int64>) {
        guard old != new else { return }
        if let old { targets.insert(old) }  // the old source goes back to being a target
        if let new { targets.remove(new) }
    }

    private func lookUpMissingNames() {
        guard let profile, !isLookingUpNames else { return }
        let missing = characters.map(\.entityID).filter { state.config.sync.characterNames[String($0)] == nil }
        guard !missing.isEmpty else { return }
        isLookingUpNames = true
        Task {
            let names = await ESINameResolver.characterNames(for: missing, singularity: profile.isSingularity)
            if !names.isEmpty {
                var cache = state.config.sync.characterNames
                for (id, name) in names { cache[String(id)] = name }
                state.config.sync.characterNames = cache
            }
            isLookingUpNames = false
            sortCharacters()
        }
    }

    private func sortCharacters() {
        characters.sort { a, b in
            let nameA = characterName(a.entityID), nameB = characterName(b.entityID)
            switch (nameA, nameB) {
            case let (x?, y?): return x.localizedCaseInsensitiveCompare(y) == .orderedAscending
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): return a.entityID < b.entityID
            }
        }
    }

    // MARK: Names

    func characterName(_ id: Int64) -> String? {
        state.config.sync.characterNames[String(id)]
    }

    func title(for file: EVESettingsFile) -> String {
        switch file.kind {
        case .character:
            return characterName(file.entityID) ?? "Character \(file.entityID)"
        case .account:
            let nickname = state.config.sync.accountNicknames[String(file.entityID)] ?? ""
            return nickname.isEmpty ? "Account \(file.entityID)" : nickname
        }
    }

    func nickname(for id: Int64) -> Binding<String> {
        Binding(
            get: { self.state.config.sync.accountNicknames[String(id)] ?? "" },
            set: { value in
                let trimmed = value.trimmingCharacters(in: .whitespaces)
                self.state.config.sync.accountNicknames[String(id)] = trimmed.isEmpty ? nil : value
            }
        )
    }

    /// Characters whose file was saved within a few seconds of this account
    /// file. EVE writes both when a character logs out, so this usually names
    /// a character on that account. Only shown when it's unambiguous enough.
    func savedTogetherHint(for account: EVESettingsFile) -> String? {
        let matches = characters.filter { abs($0.modified.timeIntervalSince(account.modified)) <= 10 }
        guard (1...2).contains(matches.count) else { return nil }
        return "saved with " + matches.map { title(for: $0) }.joined(separator: ", ")
    }

    // MARK: Sync

    var characterSourceFile: EVESettingsFile? { characters.first { $0.entityID == characterSource } }
    var accountSourceFile: EVESettingsFile? { accounts.first { $0.entityID == accountSource } }

    var characterTargetFiles: [EVESettingsFile] {
        guard characterSource != nil else { return [] }
        return characters.filter { characterTargets.contains($0.entityID) && $0.entityID != characterSource }
    }

    var accountTargetFiles: [EVESettingsFile] {
        guard accountSource != nil else { return [] }
        return accounts.filter { accountTargets.contains($0.entityID) && $0.entityID != accountSource }
    }

    var plannedWrites: Int { characterTargetFiles.count + accountTargetFiles.count }

    var summary: String {
        var parts: [String] = []
        if let source = characterSourceFile, !characterTargetFiles.isEmpty {
            parts.append("\(title(for: source)) → \(characterTargetFiles.count) character\(characterTargetFiles.count == 1 ? "" : "s")")
        }
        if let source = accountSourceFile, !accountTargetFiles.isEmpty {
            parts.append("\(title(for: source)) → \(accountTargetFiles.count) account\(accountTargetFiles.count == 1 ? "" : "s")")
        }
        return parts.isEmpty ? "Choose what to copy from, and tick where it should go." : parts.joined(separator: "   ·   ")
    }

    func sync() {
        guard let profile, plannedWrites > 0 else { return }
        let backupURL: URL
        do {
            backupURL = try EVESettingsStore.backup(profile, into: backupsRoot)
        } catch {
            status = Status(message: "Backup failed, so nothing was changed: \(error.localizedDescription)", isError: true)
            return
        }
        do {
            var written = 0
            if let source = characterSourceFile { written += try EVESettingsStore.copy(source, over: characterTargetFiles) }
            if let source = accountSourceFile { written += try EVESettingsStore.copy(source, over: accountTargetFiles) }
            Log.info("settings sync in \(profile.displayName): wrote \(written) files; backup at \(backupURL.path)")
            status = Status(message: "Done: \(written) file\(written == 1 ? "" : "s") updated. The old files were backed up first.", isError: false, backupURL: backupURL)
        } catch {
            Log.error("settings sync failed: \(error.localizedDescription)")
            status = Status(
                message: "Sync stopped part-way: \(error.localizedDescription). Use Restore Backup to undo.",
                isError: true,
                backupURL: backupURL
            )
        }
        rescan()
    }

    func restore(_ backup: EVESettingsBackup) {
        guard let profile else { return }
        do {
            let restored = try EVESettingsStore.restore(backup, into: profile, backupsRoot: backupsRoot)
            Log.info("restored \(restored) settings files into \(profile.displayName) from \(backup.url.path)")
            status = Status(message: "Restored \(restored) files from the backup of \(backup.created.formatted(date: .abbreviated, time: .standard)).", isError: false)
        } catch {
            status = Status(message: "Restore failed: \(error.localizedDescription)", isError: true)
        }
        rescan()
    }
}

struct SyncPane: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject var model: SyncModel
    @State private var confirmingSync = false
    @State private var restoreCandidate: EVESettingsBackup?

    private var clientsRunning: Bool { !state.monitor.clients.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            header
            if clientsRunning {
                Label("Quit all EVE clients before syncing. EVE saves these files when a character logs out, which would undo the sync.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.1))
            }
            if model.profiles.isEmpty {
                ContentUnavailableView {
                    Label("No EVE Settings Found", systemImage: "folder.badge.questionmark")
                } description: {
                    Text("Log in to EVE once on this Mac, then click Rescan. EVESup looks in \(EVESettingsStore.defaultRoot.path).")
                }
            } else {
                HStack(alignment: .top, spacing: 16) {
                    FileColumn(model: model, kind: .character)
                    FileColumn(model: model, kind: .account)
                }
                .padding(16)
            }
            Divider()
            footer
        }
        .navigationTitle("Settings Sync")
        .onAppear { model.reload() }
        .confirmationDialog("Copy these settings?", isPresented: $confirmingSync) {
            Button("Back Up & Sync") { model.sync() }
        } message: {
            Text("\(model.summary)\n\nThis overwrites \(model.plannedWrites) file\(model.plannedWrites == 1 ? "" : "s"). The current files are backed up first, and Restore Backup puts them back.")
        }
        .confirmationDialog(
            "Restore this backup?",
            isPresented: Binding(get: { restoreCandidate != nil }, set: { if !$0 { restoreCandidate = nil } })
        ) {
            Button("Restore") {
                if let restoreCandidate { model.restore(restoreCandidate) }
            }
        } message: {
            Text("The files in \(model.profile?.displayName ?? "this profile") will be replaced with the backup from \(restoreCandidate?.created.formatted(date: .abbreviated, time: .standard) ?? ""). The current files are backed up first.")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Picker("EVE profile", selection: $model.selectedProfileID) {
                ForEach(model.profiles) { profile in
                    Text(profile.displayName).tag(Optional(profile.id))
                }
            }
            .frame(maxWidth: 380)
            Button {
                if let profile = model.profile { NSWorkspace.shared.activateFileViewerSelecting([profile.url]) }
            } label: {
                Label("Show in Finder", systemImage: "folder")
            }
            .disabled(model.profile == nil)
            Button {
                model.reload()
            } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
            }
            Spacer()
            if model.isLookingUpNames {
                ProgressView().controlSize(.small)
                Text("Looking up names…").foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.summary)
                    .font(.callout)
                    .lineLimit(2)
                if let status = model.status {
                    HStack(spacing: 8) {
                        Label(status.message, systemImage: status.isError ? "xmark.octagon.fill" : "checkmark.circle.fill")
                            .foregroundStyle(status.isError ? .red : .green)
                            .lineLimit(2)
                        if let url = status.backupURL {
                            Button("Show Backup") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                                .buttonStyle(.link)
                        }
                    }
                    .font(.callout)
                }
            }
            Spacer()
            Menu("Restore Backup") {
                ForEach(model.backups.prefix(20)) { backup in
                    Button("\(backup.created.formatted(date: .abbreviated, time: .standard))  (\(backup.fileCount) files)") {
                        restoreCandidate = backup
                    }
                }
                if !model.backups.isEmpty { Divider() }
                Button("Open Backups Folder") {
                    let folder = model.profile.map { EVESettingsStore.backupFolder(for: $0, in: model.backupsRoot) } ?? model.backupsRoot
                    let existing = FileManager.default.fileExists(atPath: folder.path) ? folder : model.backupsRoot
                    NSWorkspace.shared.open(existing)
                }
            }
            .fixedSize()
            .disabled(model.profile == nil || clientsRunning)

            Button("Back Up & Sync…") { confirmingSync = true }
                .buttonStyle(.borderedProminent)
                .disabled(model.plannedWrites == 0 || clientsRunning)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

/// One side of the sync screen: characters (core_char) or accounts (core_user).
private struct FileColumn: View {
    @ObservedObject var model: SyncModel
    let kind: EVESettingsFile.Kind

    private var isCharacters: Bool { kind == .character }
    private var files: [EVESettingsFile] { isCharacters ? model.characters : model.accounts }
    private var source: Binding<Int64?> { isCharacters ? $model.characterSource : $model.accountSource }
    private var targets: Binding<Set<Int64>> { isCharacters ? $model.characterTargets : $model.accountTargets }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text(isCharacters
                     ? "Per-character settings: window layout, overview, chat windows and similar."
                     : "Account-wide settings, such as keyboard shortcuts.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Picker("Copy from", selection: source) {
                    Text("Don't copy \(isCharacters ? "character" : "account") settings").tag(Int64?.none)
                    ForEach(files) { file in
                        Text(model.title(for: file)).tag(Optional(file.entityID))
                    }
                }

                HStack {
                    Text("Copy to")
                        .font(.headline)
                    Spacer()
                    Button("All") { targets.wrappedValue = Set(files.map(\.entityID)).subtracting([source.wrappedValue].compactMap { $0 }) }
                    Button("None") { targets.wrappedValue = [] }
                }
                .buttonStyle(.link)

                List {
                    ForEach(files) { file in
                        row(for: file)
                    }
                }
                .listStyle(.bordered(alternatesRowBackgrounds: true))
                .frame(minHeight: 240)
            }
            .padding(6)
        } label: {
            Label(
                isCharacters ? "Characters (core_char files)" : "Accounts (core_user files)",
                systemImage: isCharacters ? "person.fill" : "person.crop.rectangle.stack.fill"
            )
            .font(.headline)
        }
    }

    @ViewBuilder
    private func row(for file: EVESettingsFile) -> some View {
        let isSource = file.entityID == source.wrappedValue
        HStack(spacing: 8) {
            Toggle(isOn: Binding(
                get: { isSource || targets.wrappedValue.contains(file.entityID) },
                set: { on in
                    if on { targets.wrappedValue.insert(file.entityID) } else { targets.wrappedValue.remove(file.entityID) }
                }
            )) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(model.title(for: file)).fontWeight(isSource ? .semibold : .regular)
                        if isSource {
                            Text("SOURCE")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.accentColor, in: Capsule())
                        }
                    }
                    Text(detail(for: file))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.checkbox)
            // Nicknames stay editable before a source is picked; only the checkboxes wait for it.
            .disabled(isSource || source.wrappedValue == nil)

            if !isCharacters {
                Spacer()
                TextField("Nickname", text: model.nickname(for: file.entityID), prompt: Text("Nickname"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
            }
        }
        .padding(.vertical, 2)
    }

    private func detail(for file: EVESettingsFile) -> String {
        var parts = ["ID \(file.entityID)", "saved \(file.modified.formatted(date: .abbreviated, time: .shortened))"]
        if !isCharacters, let hint = model.savedTogetherHint(for: file) { parts.append(hint) }
        return parts.joined(separator: " · ")
    }
}
