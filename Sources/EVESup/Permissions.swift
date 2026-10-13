import AppKit
import ApplicationServices

struct PermissionStatus: Equatable {
    /// Needed for character names (window titles) and live previews.
    var screenRecording: Bool
    /// Optional: more reliable switching and restoring minimized clients.
    var accessibility: Bool

    static func current() -> PermissionStatus {
        PermissionStatus(screenRecording: CGPreflightScreenCaptureAccess(), accessibility: AXIsProcessTrusted())
    }
}

enum Permissions {
    static func requestScreenRecording() {
        if !CGRequestScreenCaptureAccess() { openSettings(anchor: "Privacy_ScreenCapture") }
    }

    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) { openSettings(anchor: "Privacy_Accessibility") }
    }

    static func openSettings(anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }

    /// macOS often only applies a newly granted permission after the app restarts.
    static func relaunch() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.5; /usr/bin/open \"$0\"", path]
        try? task.run()
        NSApp.terminate(nil)
    }
}
