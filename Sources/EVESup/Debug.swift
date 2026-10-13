import AppKit
import EVESupCore

/// Test hooks. Only active when EVESup is launched with `--debug-ipc`.
///
/// Post a distributed notification named `com.evesup.debug.command` whose
/// object is one of: `cycle <groupIndex> next|prev`, `jump <name>`,
/// `dump <path>` (writes clients and state as JSON).
enum DebugIPC {
    static let notificationName = Notification.Name("com.evesup.debug.command")

    @MainActor
    static func install(state: AppState) {
        DistributedNotificationCenter.default().addObserver(forName: notificationName, object: nil, queue: .main) { note in
            guard let command = note.object as? String else { return }
            MainActor.assumeIsolated { state.handleDebugCommand(command) }
        }
        Log.info("debug commands enabled")
    }
}

extension AppState {
    func handleDebugCommand(_ command: String) {
        Log.info("debug command: \(command)")
        let parts = command.split(separator: " ").map(String.init)
        switch parts.first {
        case "cycle":
            guard parts.count >= 3, let index = Int(parts[1]), config.cycleGroups.indices.contains(index) else { return }
            cycle(groupID: config.cycleGroups[index].id, direction: parts[2] == "prev" ? .backward : .forward)
        case "jump":
            jump(to: parts.dropFirst().joined(separator: " "))
        case "dump":
            guard parts.count >= 2 else { return }
            writeDebugDump(to: URL(fileURLWithPath: parts.dropFirst().joined(separator: " ")))
        default:
            Log.warn("unknown debug command: \(command)")
        }
    }

    private func writeDebugDump(to url: URL) {
        let clients: [[String: Any]] = monitor.clients.map {
            [
                "pid": Int($0.pid),
                "windowID": Int($0.windowID),
                "title": $0.title ?? NSNull(),
                "character": $0.characterName ?? NSNull(),
                "onScreen": $0.isOnScreen,
            ]
        }
        let dump: [String: Any] = [
            "clients": clients,
            "activePID": monitor.activePID.map { Int($0) } ?? NSNull(),
            "frontmostPID": monitor.frontmostPID().map { Int($0) } ?? NSNull(),
            "hotkeyIssues": hotkeyIssues,
            "screenRecording": permissions.screenRecording,
            "accessibility": permissions.accessibility,
            "excludedPIDs": excludedPIDs.map { Int($0) }.sorted(),
        ]
        if let data = try? JSONSerialization.data(withJSONObject: dump, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url)
        }
    }
}

/// `--snapshot <folder>`: renders every settings page (and a sample preview)
/// to PNG files without showing anything on screen, then quits.
@MainActor
enum Snapshots {
    static func run(into directory: URL, delegate: AppDelegate) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let window = delegate.makeSettingsWindowIfNeeded() else {
            NSApp.terminate(nil)
            return
        }
        // Invisible and click-through, and EVESup never activates, so whatever
        // the user is doing keeps focus.
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        // Tall enough that long pages render without scrolling.
        window.setContentSize(NSSize(width: 980, height: 1900))
        window.orderFrontRegardless()

        var remaining = SettingsPane.allCases
        func next() {
            guard !remaining.isEmpty else {
                renderSamplePreview(borderless: false, to: directory.appendingPathComponent("preview-framed.png"))
                renderSamplePreview(borderless: true, to: directory.appendingPathComponent("preview-borderless.png"))
                NSApp.terminate(nil)
                return
            }
            let pane = remaining.removeFirst()
            delegate.state.settingsPane = pane
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                MainActor.assumeIsolated {
                    guard let view = window.contentView else { return next() }
                    save(view, to: directory.appendingPathComponent("\(pane.rawValue).png"))
                    // Long pages: also capture the bottom.
                    guard scrollToBottom(in: view) else { return next() }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        MainActor.assumeIsolated {
                            save(view, to: directory.appendingPathComponent("\(pane.rawValue)-bottom.png"))
                            next()
                        }
                    }
                }
            }
        }
        next()
    }

    /// Scrolls the first scroll view with hidden content to its end. Returns false if there was none.
    private static func scrollToBottom(in view: NSView) -> Bool {
        if let scrollView = view as? NSScrollView, let document = scrollView.documentView {
            let visible = scrollView.contentView.bounds.height
            if document.frame.height > visible + 1 {
                let y = document.isFlipped ? document.frame.height - visible : 0
                scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
                scrollView.reflectScrolledClipView(scrollView.contentView)
                return true
            }
        }
        return view.subviews.contains { scrollToBottom(in: $0) }
    }

    private static func save(_ view: NSView, to url: URL) {
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
    }

    /// A 16:9 picture in a 16:10 preview, so the space around it is visible.
    private static func renderSamplePreview(borderless: Bool, to url: URL) {
        let size = NSSize(width: 288, height: 180)
        let view = ThumbnailView(frame: NSRect(origin: .zero, size: size))
        view.setBorderless(borderless)
        view.update(name: "Example Pilot", excluded: true)
        view.setHighlight(.systemGreen, width: 3)
        view.show(image: sampleImage(size: NSSize(width: 320, height: 180)))

        let scale: CGFloat = 2
        guard let layer = view.layer,
              let context = CGContext(
                data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
                bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return }
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        layer.render(in: context)
        guard let image = context.makeImage() else { return }
        try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url)
    }

    private static func sampleImage(size: NSSize) -> CGImage {
        let image = NSImage(size: size, flipped: false) { rect in
            NSGradient(colors: [.systemIndigo, .systemTeal])?.draw(in: rect, angle: -30)
            let text = NSAttributedString(string: "EVE client", attributes: [
                .font: NSFont.boldSystemFont(ofSize: 28), .foregroundColor: NSColor.white.withAlphaComponent(0.8),
            ])
            text.draw(at: NSPoint(x: rect.midX - text.size().width / 2, y: rect.midY - 14))
            return true
        }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    }
}

