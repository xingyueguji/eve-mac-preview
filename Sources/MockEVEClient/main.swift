import AppKit

// A stand-in for an EVE client when testing EVESup: one window titled
// "EVE - <name>" (or just "EVE" with --login), with a ticking clock so live
// previews visibly update. Launch several with:
//   open -n build/MockEVEClient.app --args Alpha

let arguments = CommandLine.arguments.dropFirst()
let isLogin = arguments.contains("--login")
let name = arguments.first { !$0.hasPrefix("-") } ?? "Pilot"
let windowTitle = isLogin ? "EVE" : "EVE - \(name)"

final class MockView: NSView {
    let label: String
    let hue: CGFloat
    var ticks = 0

    init(label: String) {
        self.label = label
        hue = CGFloat(abs(label.hashValue % 360)) / 360
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedHue: hue, saturation: 0.55, brightness: 0.42, alpha: 1).setFill()
        bounds.fill()
        let title = NSAttributedString(string: label, attributes: [
            .font: NSFont.systemFont(ofSize: 54, weight: .heavy), .foregroundColor: NSColor.white,
        ])
        title.draw(at: NSPoint(x: 32, y: bounds.midY))
        let clock = NSAttributedString(string: "tick \(ticks)  ·  \(Date().formatted(date: .omitted, time: .standard))", attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 22, weight: .medium), .foregroundColor: NSColor.white.withAlphaComponent(0.8),
        ])
        clock.draw(at: NSPoint(x: 34, y: bounds.midY - 44))
    }
}

final class MockDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = MockDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)

    let offset = CGFloat(Int(getpid()) % 8) * 36
    let window = NSWindow(
        contentRect: NSRect(x: 160 + offset, y: 120 + offset, width: 640, height: 400),
        styleMask: [.titled, .closable, .miniaturizable, .resizable],
        backing: .buffered,
        defer: false
    )
    window.title = windowTitle
    let view = MockView(label: isLogin ? "Character select" : name)
    window.contentView = view
    window.makeKeyAndOrderFront(nil)

    Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
        MainActor.assumeIsolated {
            view.ticks += 1
            view.needsDisplay = true
        }
    }
    app.activate(ignoringOtherApps: true)
    app.run()
}
