import AppKit
import ApplicationServices

/// Brings an EVE client to the front.
///
/// Since macOS 14, apps can't take focus whenever they like, so this tries the
/// supported route first (EVESup activates itself, then hands activation to
/// the client). If the client still isn't in front shortly after, it falls
/// back to the Accessibility API, then to the private SkyLight call that
/// window switchers such as AltTab use. The log records which route worked.
@MainActor
enum WindowActivator {
    private static var generation = 0

    static func activate(_ client: EVEClient, reason: String) {
        guard let app = NSRunningApplication(processIdentifier: client.pid) else {
            Log.warn("switch (\(reason)): pid \(client.pid) is gone")
            return
        }
        generation += 1
        let attempt = generation
        let started = Date()

        if app.isHidden { app.unhide() }
        if !client.isOnScreen, AXIsProcessTrusted() { AXWindows.unminimize(pid: client.pid) }

        NSApp.activate(ignoringOtherApps: true)
        NSApp.yieldActivation(to: app)
        if !app.activate(from: NSRunningApplication.current, options: []) {
            app.activate(options: [])
        }

        confirm(client, attempt: attempt, started: started, reason: reason, step: 1)
    }

    private static func confirm(_ client: EVEClient, attempt: Int, started: Date, reason: String, step: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + (step == 1 ? 0.2 : 0.3)) {
            MainActor.assumeIsolated {
                // A newer switch was requested; don't fight it.
                guard attempt == generation else { return }
                let elapsed = Int(Date().timeIntervalSince(started) * 1000)
                // NSWorkspace reports EVE clients with pid -1, so ask the client itself.
                if NSRunningApplication(processIdentifier: client.pid)?.isActive == true {
                    Log.info("switched to \(client.label) (pid \(client.pid)) for \(reason); confirmed on check \(step) at \(elapsed) ms")
                    return
                }
                guard step == 1 else {
                    let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
                    Log.warn("could not confirm switch to \(client.label) (pid \(client.pid)); frontmost app is \(front)")
                    return
                }

                var method = "activate again"
                if AXIsProcessTrusted(), AXWindows.raise(pid: client.pid) {
                    method = "accessibility"
                } else if SkyLight.bringToFront(pid: client.pid, windowID: client.windowID) {
                    method = "skylight"
                } else {
                    NSRunningApplication(processIdentifier: client.pid)?.activate(options: [.activateAllWindows])
                }
                Log.info("switch to \(client.label) not confirmed after \(elapsed) ms; retrying via \(method)")
                confirm(client, attempt: attempt, started: started, reason: reason, step: 2)
            }
        }
    }
}

/// Window control through the Accessibility API (needs the Accessibility permission).
enum AXWindows {
    static func raise(pid: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        let result = AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        if let window = windows(of: app).first {
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        }
        return result == .success
    }

    static func unminimize(pid: pid_t) {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        for window in windows(of: app) {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &value) == .success,
               (value as? Bool) == true {
                AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            }
        }
    }

    private static func windows(of app: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let array = value as? [AnyObject]
        else { return [] }
        return array.compactMap { item in
            CFGetTypeID(item) == AXUIElementGetTypeID() ? unsafeBitCast(item, to: AXUIElement.self) : nil
        }
    }
}

/// Last-resort focus through SkyLight's private `_SLPSSetFrontProcessWithOptions`,
/// looked up at runtime so a future macOS without it simply skips this step.
enum SkyLight {
    private typealias SetFrontProcess = @convention(c) (UnsafeMutableRawPointer, UInt32, UInt32) -> Int32
    private typealias GetProcessForPID = @convention(c) (pid_t, UnsafeMutableRawPointer) -> Int32

    private static let setFrontProcess: SetFrontProcess? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let symbol = dlsym(handle, "_SLPSSetFrontProcessWithOptions")
        else { return nil }
        return unsafeBitCast(symbol, to: SetFrontProcess.self)
    }()

    private static let getProcessForPID: GetProcessForPID? = {
        // RTLD_DEFAULT is ((void *)-2) on Darwin.
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "GetProcessForPID") else { return nil }
        return unsafeBitCast(symbol, to: GetProcessForPID.self)
    }()

    static func bringToFront(pid: pid_t, windowID: CGWindowID) -> Bool {
        guard let setFrontProcess, let getProcessForPID else { return false }
        var psn = ProcessSerialNumber()
        return withUnsafeMutablePointer(to: &psn) { pointer in
            let raw = UnsafeMutableRawPointer(pointer)
            guard getProcessForPID(pid, raw) == 0 else { return false }
            return setFrontProcess(raw, windowID, 0x200) == 0  // kCPSUserGenerated
        }
    }
}
