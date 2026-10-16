import AppKit
import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case cycling, characters, previews, sync, general

    var id: Self { self }

    var title: String {
        switch self {
        case .cycling: "Cycle Groups"
        case .characters: "Character Keys"
        case .previews: "Previews"
        case .sync: "Settings Sync"
        case .general: "General"
        }
    }

    var symbol: String {
        switch self {
        case .cycling: "arrow.triangle.2.circlepath"
        case .characters: "person.2"
        case .previews: "rectangle.on.rectangle"
        case .sync: "doc.on.doc"
        case .general: "gearshape"
        }
    }
}

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    init(state: AppState, remembersFrame: Bool = true) {
        let root = SettingsRootView().environmentObject(state)
        let hosting = NSHostingController(rootView: root)
        // The user decides how big the window is; pages scroll when they don't
        // fit. By default SwiftUI sizes the window to its content, so a long
        // list could stretch it past the bottom of the screen.
        hosting.sizingOptions = []
        let window = NSWindow(contentViewController: hosting)
        window.title = "EVESup"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.setContentSize(NSSize(width: 980, height: 660))
        // Small enough for a 13-inch MacBook set to its largest text size, with the Dock showing.
        window.contentMinSize = NSSize(width: 860, height: 480)
        if remembersFrame { window.setFrameAutosaveName("EVESupSettings") }
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func present() {
        guard let window else { return }
        if !window.isVisible {
            shrinkToFitScreen(window)
            window.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Keeps the size the user chose unless it's bigger than the screen, as
    /// when it was saved on a larger display, or by a version that let long
    /// lists stretch the window.
    private func shrinkToFitScreen(_ window: NSWindow) {
        guard let visible = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
        var frame = window.frame
        frame.size.width = min(frame.width, visible.width)
        frame.size.height = min(frame.height, visible.height)
        if frame.size != window.frame.size { window.setFrame(frame, display: false) }
    }
}

struct SettingsRootView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $state.settingsPane) { pane in
                Label(pane.title, systemImage: pane.symbol)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 196, max: 240)
            .safeAreaInset(edge: .bottom) { statusFooter }
        } detail: {
            switch state.settingsPane ?? .cycling {
            case .cycling: CycleGroupsPane()
            case .characters: CharactersPane()
            case .previews: PreviewsPane()
            case .sync: SyncPane(model: state.syncModel)
            case .general: GeneralPane()
            }
        }
    }

    private var statusFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            let count = state.monitor.clients.count
            Label(count == 1 ? "1 EVE client running" : "\(count) EVE clients running", systemImage: "display")
            if !state.permissions.screenRecording {
                Button {
                    state.settingsPane = .general
                } label: {
                    Label("Screen Recording is off", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }
}

/// A small green/grey dot for logged-in / offline.
struct OnlineDot: View {
    let online: Bool

    var body: some View {
        Circle()
            .fill(online ? Color.green : Color.secondary.opacity(0.35))
            .frame(width: 8, height: 8)
            .help(online ? "Logged in" : "Not logged in")
    }
}
