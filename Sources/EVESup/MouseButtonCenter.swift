import AppKit
import ApplicationServices
import EVESupCore

/// Mouse-button shortcuts, such as the side buttons.
///
/// With Accessibility allowed, an event tap catches the click before any app
/// sees it, like keyboard hotkeys. Without it, EVESup still notices the click
/// and switches clients, but the app under the pointer receives the click too.
@MainActor
final class MouseButtonCenter {
    static let shared = MouseButtonCenter()

    private struct Binding {
        let button: Int
        let modifiers: UInt32
        let action: () -> Void
    }

    private var bindings: [Binding] = []
    private var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    private var globalMonitor: Any?
    /// Buttons whose press was swallowed, so the matching release is swallowed too.
    private var heldButtons = Set<Int>()

    /// Whether clicks for these shortcuts are kept away from other apps.
    var hidesClicksFromApps: Bool { tap != nil }

    func register(_ hotkey: Hotkey, action: @escaping () -> Void) {
        guard let button = hotkey.mouseButton else { return }
        bindings.append(Binding(button: button, modifiers: hotkey.modifiers, action: action))
        startIfNeeded()
    }

    func unregisterAll() {
        bindings.removeAll()
        heldButtons.removeAll()
        stop()
    }

    private func startIfNeeded() {
        guard tap == nil, globalMonitor == nil else { return }
        if AXIsProcessTrusted(), let tap = Self.makeTap() {
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            self.tap = tap
            tapSource = source
        } else {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .otherMouseDown) { event in
                let button = event.buttonNumber
                let modifiers = KeyNames.carbonModifiers(from: event.modifierFlags)
                MainActor.assumeIsolated { _ = MouseButtonCenter.shared.press(button: button, modifiers: modifiers) }
            }
        }
    }

    private func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes) }
        tap = nil
        tapSource = nil
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        globalMonitor = nil
    }

    private static func makeTap() -> CFMachPort? {
        let mask = CGEventMask(1 << CGEventType.otherMouseDown.rawValue) | CGEventMask(1 << CGEventType.otherMouseUp.rawValue)
        return CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: mouseTapCallback,
            userInfo: nil
        )
    }

    /// Runs the matching shortcut, if any. Returns true when one matched.
    fileprivate func press(button: Int, modifiers: UInt32) -> Bool {
        guard let binding = bindings.first(where: { $0.button == button && $0.modifiers == modifiers }) else { return false }
        // Run after the event tap returns, so switching can't hold up mouse input.
        DispatchQueue.main.async { binding.action() }
        return true
    }

    /// Returns true when the event should be swallowed.
    fileprivate func handleTap(type: CGEventType, event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        case .otherMouseDown:
            let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
            guard press(button: button, modifiers: Self.carbonModifiers(event.flags)) else { return false }
            heldButtons.insert(button)
            return true
        case .otherMouseUp:
            return heldButtons.remove(Int(event.getIntegerValueField(.mouseEventButtonNumber))) != nil
        default:
            return false
        }
    }

    private static func carbonModifiers(_ flags: CGEventFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.maskControl) { result |= Hotkey.control }
        if flags.contains(.maskAlternate) { result |= Hotkey.option }
        if flags.contains(.maskShift) { result |= Hotkey.shift }
        if flags.contains(.maskCommand) { result |= Hotkey.command }
        return result
    }
}

/// The tap's run-loop source is on the main run loop, so this runs on the main thread.
private func mouseTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    let swallow = MainActor.assumeIsolated { MouseButtonCenter.shared.handleTap(type: type, event: event) }
    return swallow ? nil : Unmanaged.passUnretained(event)
}
