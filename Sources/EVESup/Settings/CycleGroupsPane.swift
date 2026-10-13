import EVESupCore
import SwiftUI

/// Cycle groups: each has a name, a next key, a previous key and an ordered
/// list of characters.
struct CycleGroupsPane: View {
    @EnvironmentObject private var state: AppState
    @State private var selection: UUID?
    @State private var confirmingDelete = false

    var body: some View {
        HStack(spacing: 0) {
            groupList
                .frame(width: 250)
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Cycle Groups")
        .onAppear {
            if selection == nil { selection = state.config.cycleGroups.first?.id }
        }
        .confirmationDialog("Delete “\(selectedGroup?.name ?? "")”?", isPresented: $confirmingDelete) {
            Button("Delete Group", role: .destructive, action: removeSelected)
        } message: {
            Text("Its keys and character order will be removed.")
        }
    }

    private var selectedGroup: CycleGroup? {
        state.config.cycleGroups.first { $0.id == selection }
    }

    private var groupList: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(state.config.cycleGroups) { group in
                    GroupRow(group: group).tag(group.id)
                }
                .onMove { state.config.cycleGroups.move(fromOffsets: $0, toOffset: $1) }
            }
            Divider()
            HStack(spacing: 0) {
                Button(action: addGroup) {
                    Image(systemName: "plus").frame(width: 26, height: 22)
                }
                .help("New group")
                Button {
                    if let group = selectedGroup, group.members.isEmpty, group.nextKey == nil, group.previousKey == nil {
                        removeSelected()
                    } else {
                        confirmingDelete = true
                    }
                } label: {
                    Image(systemName: "minus").frame(width: 26, height: 22)
                }
                .help("Delete group")
                .disabled(selection == nil)
                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(6)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let id = selection, state.config.cycleGroups.contains(where: { $0.id == id }) {
            CycleGroupEditor(groupID: id).id(id)
        } else {
            ContentUnavailableView {
                Label("No Group Selected", systemImage: "arrow.triangle.2.circlepath")
            } description: {
                Text("Click + to make a group, give it a key, then add characters in the order you want to cycle.")
            }
        }
    }

    private func addGroup() {
        let group = CycleGroup(name: "Group \(state.config.cycleGroups.count + 1)")
        state.config.cycleGroups.append(group)
        selection = group.id
    }

    private func removeSelected() {
        guard let id = selection, let index = state.config.cycleGroups.firstIndex(where: { $0.id == id }) else { return }
        state.config.cycleGroups.remove(at: index)
        let groups = state.config.cycleGroups
        selection = groups.indices.contains(index) ? groups[index].id : groups.last?.id
    }
}

private struct GroupRow: View {
    @EnvironmentObject private var state: AppState
    let group: CycleGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(group.name.isEmpty ? "Untitled group" : group.name)
                    .fontWeight(.semibold)
                if hasIssue {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .imageScale(.small)
                }
                if !group.isEnabled {
                    Text("Off")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                }
            }
            HStack(spacing: 10) {
                KeyCap(title: "Next", hotkey: group.nextKey)
                KeyCap(title: "Prev", hotkey: group.previousKey)
            }
            Text(membersSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
        .opacity(group.isEnabled ? 1 : 0.6)
    }

    private var hasIssue: Bool {
        [CycleDirection.forward, .backward].contains { state.hotkeyIssues[AppState.bindingID(group: group.id, direction: $0)] != nil }
    }

    private var membersSummary: String {
        guard !group.members.isEmpty else { return "All open clients" }
        let online = group.members.filter(state.isOnline).count
        let characters = group.members.count == 1 ? "1 character" : "\(group.members.count) characters"
        return "\(characters) · \(online) online"
    }
}

/// "Next F14" with the key drawn like a keycap.
private struct KeyCap: View {
    let title: String
    let hotkey: Hotkey?

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(hotkey.map(KeyNames.display) ?? "—")
                .font(.caption.monospaced().weight(.semibold))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 4).strokeBorder(.tertiary))
        }
    }
}

struct CycleGroupEditor: View {
    @EnvironmentObject private var state: AppState
    let groupID: UUID
    @State private var typedName = ""

    /// Reads and writes the group by ID, so deleting it can't leave a stale index behind.
    private var group: Binding<CycleGroup> {
        Binding(
            get: { state.config.cycleGroups.first { $0.id == groupID } ?? CycleGroup(id: groupID, name: "") },
            set: { updated in
                if let index = state.config.cycleGroups.firstIndex(where: { $0.id == groupID }) {
                    state.config.cycleGroups[index] = updated
                }
            }
        )
    }

    private var members: [String] { group.wrappedValue.members }

    var body: some View {
        Form {
            Section {
                TextField("Group name", text: group.name)
                Toggle("Enabled", isOn: group.isEnabled)
            }

            Section {
                LabeledContent("Next client") {
                    HotkeyRecorder(hotkey: group.nextKey, issueID: AppState.bindingID(group: groupID, direction: .forward))
                }
                LabeledContent("Previous client") {
                    HotkeyRecorder(hotkey: group.previousKey, issueID: AppState.bindingID(group: groupID, direction: .backward))
                }
                Toggle(isOn: group.worksWithModifiersHeld) {
                    Text("Also work while ⌃ ⌥ ⇧ are held")
                    Text("The key still switches if you're holding Ctrl to lock a target.")
                }
            } header: {
                Text("Keys")
            } footer: {
                Text("EVE never receives these key presses; EVESup uses them to switch clients. F13–F20 work well if you bind them to mouse or keypad buttons.")
                    .foregroundStyle(.secondary)
            }

            Section {
                if members.isEmpty {
                    Label("No characters yet, so this group cycles through every open EVE client in alphabetical order.", systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(members.enumerated()), id: \.element) { index, name in
                    MemberRow(
                        index: index,
                        name: name,
                        isLast: index == members.count - 1,
                        online: state.isOnline(name),
                        move: { offset in move(name, by: offset) },
                        remove: { group.wrappedValue.members.removeAll { $0 == name } }
                    )
                }
                .onMove { group.wrappedValue.members.move(fromOffsets: $0, toOffset: $1) }
                addControls
            } header: {
                Text("Cycle order")
            } footer: {
                Text("Next goes down this list and wraps around; previous goes up. Characters who aren't logged in are skipped. ⇧-click a preview to skip a client for now.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var candidates: [String] {
        state.allCharacterNames.filter { name in
            !members.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
        }
    }

    private var addControls: some View {
        HStack(spacing: 10) {
            Menu {
                if candidates.isEmpty {
                    Text("No other characters known yet")
                }
                ForEach(candidates, id: \.self) { name in
                    Button(state.isOnline(name) ? "\(name)  (logged in)" : name) { add(name) }
                }
            } label: {
                Label("Add Character", systemImage: "plus")
            }
            .fixedSize()

            Button("Add All Logged-In") {
                for name in state.monitor.clients.compactMap(\.characterName) { add(name) }
            }
            .disabled(!state.monitor.clients.contains { client in client.characterName.map { candidates.contains($0) } ?? false })

            TextField("Add by name", text: $typedName, prompt: Text("or type a name ↩"))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 180)
                .onSubmit {
                    add(typedName)
                    typedName = ""
                }
            Spacer(minLength: 0)
        }
    }

    private func add(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !members.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        group.wrappedValue.members.append(trimmed)
    }

    private func move(_ name: String, by offset: Int) {
        var list = members
        guard let index = list.firstIndex(of: name) else { return }
        let target = index + offset
        guard list.indices.contains(target) else { return }
        list.swapAt(index, target)
        group.wrappedValue.members = list
    }
}

private struct MemberRow: View {
    let index: Int
    let name: String
    let isLast: Bool
    let online: Bool
    let move: (Int) -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text("\(index + 1)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .trailing)
            OnlineDot(online: online)
            Text(name)
            Spacer()
            Button { move(-1) } label: { Image(systemName: "chevron.up") }
                .disabled(index == 0)
                .help("Move up")
            Button { move(1) } label: { Image(systemName: "chevron.down") }
                .disabled(isLast)
                .help("Move down")
            Button(action: remove) { Image(systemName: "minus.circle") }
                .help("Remove from this group")
        }
        .buttonStyle(.borderless)
    }
}
