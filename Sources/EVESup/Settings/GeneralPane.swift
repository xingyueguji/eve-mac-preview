import AppKit
import EVESupCore
import SwiftUI

struct GeneralPane: View {
    @EnvironmentObject private var state: AppState
    @State private var bundleIDsText = ""

    var body: some View {
        Form {
            Section {
                PermissionRow(
                    title: "Screen Recording",
                    detail: "Needed to read character names from EVE's window titles and to show live previews.",
                    granted: state.permissions.screenRecording,
                    request: Permissions.requestScreenRecording,
                    openSettings: { Permissions.openSettings(anchor: "Privacy_ScreenCapture") }
                )
                PermissionRow(
                    title: "Accessibility (optional)",
                    detail: "Keeps mouse-button shortcuts from also clicking in EVE, is a backup way to bring a client to the front, and restores minimized clients.",
                    granted: state.permissions.accessibility,
                    request: Permissions.requestAccessibility,
                    openSettings: { Permissions.openSettings(anchor: "Privacy_Accessibility") }
                )
                HStack {
                    Text("Just turned a permission on? macOS applies it after EVESup restarts.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Relaunch EVESup", action: Permissions.relaunch)
                }
            } header: {
                Text("Permissions")
            } footer: {
                Text("If you rebuild EVESup, macOS treats it as a new app: remove the old entry in System Settings and allow it again.")
                    .foregroundStyle(.secondary)
            }

            Section {
                if state.monitor.clients.isEmpty {
                    Text("No EVE clients are running.")
                        .foregroundStyle(.secondary)
                }
                ForEach(state.monitor.clients) { client in
                    LabeledContent {
                        Text(client.pid == state.monitor.activePID ? "In front" : "")
                            .foregroundStyle(.secondary)
                    } label: {
                        Text(client.label)
                        Text("Process \(client.pid) · window \(client.windowID) · title “\(client.title ?? "hidden until Screen Recording is allowed")”")
                    }
                }
                LabeledContent("Also treat as EVE") {
                    TextField("Other apps", text: $bundleIDsText, prompt: Text("Optional, e.g. com.example.app"))
                        .labelsHidden()
                        .frame(maxWidth: 320)
                        .onSubmit(applyBundleIDs)
                }
            } header: {
                Text("EVE clients")
            } footer: {
                Text("EVE clients are always detected; you don't need to enter anything here. This box is only for testing or other games: app IDs or app names, separated by commas, then press Return.")
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Version") {
                    Text(state.updater.currentVersion).monospacedDigit()
                }
                Toggle("Check for updates automatically", isOn: $state.config.checksForUpdates)
                HStack(spacing: 10) {
                    UpdateStatusLabel(status: state.updater.status)
                    Spacer()
                    if case .available = state.updater.status {
                        Button(state.updater.canUpdateItself ? "Install and Relaunch" : "Open Download Page") {
                            state.updater.installLatest()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    Button("Check Now") { state.updater.check(userInitiated: true, alerts: false) }
                        .disabled(state.updater.status == .checking || state.updater.status == .downloading || state.updater.status == .installing)
                }
            } header: {
                Text("Updates")
            } footer: {
                Text("Updates come from the project's GitHub releases. EVESup only installs an update signed with the same certificate as this copy, and your settings and permissions carry over.")
                    .foregroundStyle(.secondary)
            }

            Section("Files") {
                FileRow(title: "Settings file", url: state.configURL)
                FileRow(title: "Log file", url: Log.fileURL)
            }

            Section("About") {
                Text("EVESup only shows previews and brings EVE windows to the front. It never sends keystrokes or mouse clicks to EVE, and it doesn't change the EVE client.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
        .onAppear { bundleIDsText = extraApps.joined(separator: ", ") }
    }

    /// The configured apps, minus EVE itself, which always counts.
    private var extraApps: [String] {
        state.config.clientBundleIDs.filter { $0 != AppConfig.eveBundleID }
    }

    private func applyBundleIDs() {
        let apps = bundleIDsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0 != AppConfig.eveBundleID }
        state.config.clientBundleIDs = [AppConfig.eveBundleID] + apps
        bundleIDsText = apps.joined(separator: ", ")
    }
}


private struct PermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool
    let request: () -> Void
    let openSettings: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(granted ? .green : .orange)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if granted {
                Text("Allowed").foregroundStyle(.secondary)
            } else {
                Button("Allow…", action: request)
                Button("Open Settings", action: openSettings)
            }
        }
    }
}

private struct UpdateStatusLabel: View {
    let status: Updater.Status

    var body: some View {
        switch status {
        case .idle:
            Text("Not checked yet").foregroundStyle(.secondary)
        case .checking:
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Checking…") }
        case .upToDate:
            Label("Up to date", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .available(let version):
            Label("Version \(version) is available", systemImage: "arrow.down.circle.fill").foregroundStyle(.blue)
        case .downloading:
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Downloading…") }
        case .installing:
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Installing…") }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }
}

private struct FileRow: View {
    let title: String
    let url: URL

    var body: some View {
        LabeledContent {
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        } label: {
            Text(title)
            Text(url.path(percentEncoded: false))
                .textSelection(.enabled)
        }
    }
}
