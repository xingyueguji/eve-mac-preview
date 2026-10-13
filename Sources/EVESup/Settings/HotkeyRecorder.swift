import AppKit
import EVESupCore
import SwiftUI

/// Click, then press a key to set a shortcut. Esc cancels, ⌫ clears.
struct HotkeyRecorder: View {
    @EnvironmentObject private var state: AppState
    @Binding var hotkey: Hotkey?
    /// Looks up registration problems in `AppState.hotkeyIssues`.
    var issueID: String?

    @State private var isRecording = false
    @State private var heldModifiers: UInt32 = 0
    @State private var hint: String?
    @State private var monitor: Any?

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            HStack(spacing: 6) {
                Button(action: toggleRecording) {
                    Text(label)
                        .fontWeight(hotkey == nil || isRecording ? .regular : .semibold)
                        .foregroundStyle(hotkey == nil && !isRecording ? .secondary : .primary)
                        .frame(minWidth: 112)
                }
                .buttonStyle(.bordered)
                .tint(isRecording ? .accentColor : nil)
                .help(isRecording ? "Press the key to use. Esc cancels, ⌫ clears." : "Click, then press a key")

                if hotkey != nil, !isRecording {
                    Button {
                        hotkey = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Remove this key")
                }
            }
            if let problem = hint ?? issueID.flatMap({ state.hotkeyIssues[$0] }) {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onDisappear(perform: stopRecording)
    }

    private var label: String {
        if isRecording {
            return heldModifiers == 0 ? "Press a key…" : Hotkey(keyCode: 0, modifiers: heldModifiers).modifierSymbols + "…"
        }
        return hotkey.map(KeyNames.display) ?? "Not set"
    }

    private func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        hint = nil
        heldModifiers = 0
        isRecording = true
        // Our own hotkeys would swallow the key before this view sees it.
        state.suspendHotkeys()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            handle(event)
            return nil
        }
    }

    private func handle(_ event: NSEvent) {
        let modifiers = KeyNames.carbonModifiers(from: event.modifierFlags)
        if event.type == .flagsChanged {
            heldModifiers = modifiers
            return
        }
        let keyCode = UInt32(event.keyCode)
        if modifiers == 0, keyCode == Hotkey.escapeKeyCode {
            stopRecording()
            return
        }
        if modifiers == 0, keyCode == Hotkey.deleteKeyCode || keyCode == Hotkey.forwardDeleteKeyCode {
            hotkey = nil
            stopRecording()
            return
        }
        let candidate = Hotkey(keyCode: keyCode, modifiers: modifiers)
        if candidate.blocksTyping {
            hint = "Add ⌃, ⌥ or ⌘: on its own, \(KeyNames.display(candidate)) would stop working for typing everywhere."
            return
        }
        hint = nil
        hotkey = candidate
        stopRecording()
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        guard isRecording else { return }
        isRecording = false
        heldModifiers = 0
        state.resumeHotkeys()
    }
}
