import EVESupCore
import SwiftUI

/// One key per character that jumps straight to that client.
struct CharactersPane: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Form {
            Section {
                if state.allCharacterNames.isEmpty {
                    Text("No characters yet. Log in with EVE running, or open Settings Sync to load the names of characters that have played on this Mac.")
                        .foregroundStyle(.secondary)
                }
                ForEach(state.allCharacterNames, id: \.self) { name in
                    HStack(spacing: 10) {
                        OnlineDot(online: state.isOnline(name))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(name)
                            let groups = state.groupNames(containing: name)
                            if !groups.isEmpty {
                                Text("In " + groups.joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        HotkeyRecorder(hotkey: binding(for: name), issueID: AppState.bindingID(character: name))
                    }
                    .contextMenu {
                        Button("Forget \(name)") { state.forgetCharacter(name) }
                    }
                }
            } header: {
                Text("Jump straight to a character")
            } footer: {
                Text("Each key brings that character's client to the front from anywhere. To step through several characters with one key, use Cycle Groups. Right-click a name to forget it.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Character Keys")
    }

    private func binding(for name: String) -> Binding<Hotkey?> {
        Binding(
            get: { state.config.characterHotkeys[name] },
            set: { state.config.characterHotkeys[name] = $0 }
        )
    }
}
