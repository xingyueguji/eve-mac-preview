import AppKit
import EVESupCore
import ScreenCaptureKit

/// Keeps one preview panel (and capture stream) per running EVE client.
@MainActor
final class PreviewManager {
    private unowned let state: AppState
    private var panels: [pid_t: ThumbnailPanel] = [:]
    /// The character name each panel's position is saved under ("" = none yet).
    private var panelNames: [pid_t: String] = [:]
    private var captures: [pid_t: WindowCapture] = [:]
    private var capturedWindowIDs: [pid_t: CGWindowID] = [:]
    /// Size of each client's window when its capture was last configured.
    private var capturedSourceSizes: [pid_t: CGSize] = [:]
    private var pendingCaptures = Set<pid_t>()
    private var hiddenByUser = Set<pid_t>()
    private var retryScheduled = false
    private var cachedLabel: (style: NameLabelStyle, appearance: ThumbnailView.LabelAppearance)?

    init(state: AppState) {
        self.state = state
    }

    private var settings: PreviewSettings { state.config.previews }

    /// Grid cell size while snapping is on.
    private var grid: CGSize? {
        settings.snapsToGrid ? CGSize(width: max(settings.gridWidth, 1), height: max(settings.gridHeight, 1)) : nil
    }

    var hasHiddenPreviews: Bool { !hiddenByUser.isEmpty }

    // MARK: Updates

    func update() {
        let clients = state.monitor.clients
        let live = Set(clients.map(\.pid))
        for pid in Array(panels.keys) where !live.contains(pid) { removePanel(pid) }
        hiddenByUser.formIntersection(live)

        guard settings.isEnabled else {
            for pid in Array(panels.keys) { removePanel(pid) }
            return
        }

        for client in clients {
            let panel = panels[client.pid] ?? makePanel(for: client)
            placeIfNameChanged(panel, for: client)
            panel.thumbnailView.update(
                name: settings.showsName ? client.label : nil,
                excluded: state.excludedPIDs.contains(client.pid)
            )
            if captures[client.pid] != nil, capturedSourceSizes[client.pid] != client.frame.size {
                reconfigureCapture(client.pid)
            }
        }
        applyAppearance()
        updateCaptures(for: clients)
    }

    func refreshActiveState() {
        applyAppearance()
    }

    func settingsChanged(from old: PreviewSettings) {
        let new = settings
        if old.showsOnAllSpaces != new.showsOnAllSpaces {
            for panel in panels.values { panel.applySpacesBehavior(allSpaces: new.showsOnAllSpaces) }
        }
        if old.isBorderless != new.isBorderless {
            for panel in panels.values { panel.applyStyle(borderless: new.isBorderless) }
        }
        if old.framesPerSecond != new.framesPerSecond {
            for pid in captures.keys { reconfigureCapture(pid) }
        }
        update()
    }

    func showHiddenPreviews() {
        hiddenByUser.removeAll()
        update()
    }

    /// Resizes every preview to the default size, keeping each top-left corner in place.
    func resizeAll(to size: CGSize) {
        for (pid, panel) in panels {
            var frame = panel.frame
            frame.origin.y += frame.height - size.height
            frame.size = size
            panel.setFrame(frame, display: true)
            reconfigureCapture(pid)
        }
    }

    /// Moves every preview, and every saved position, onto the nearest grid point.
    func alignAllToGrid() {
        guard let grid else { return }
        func snapped(_ frame: NSRect) -> NSRect {
            GridSnap.position(frame, grid: grid, in: ThumbnailView.snapArea(at: NSPoint(x: frame.midX, y: frame.midY)))
        }
        state.config.thumbnailFrames = state.config.thumbnailFrames.mapValues { stored in
            let frame = snapped(NSRect(x: stored.x, y: stored.y, width: stored.width, height: stored.height))
            return StoredRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height)
        }
        for panel in panels.values {
            let frame = snapped(panel.frame)
            guard frame != panel.frame else { continue }
            panel.setFrame(frame, display: true)
            if let name = state.monitor.client(pid: panel.pid)?.characterName { store(frame, for: name) }
        }
    }

    /// Lines the previews up again along the top of the main screen.
    func rearrangeAll() {
        var placed: [NSRect] = []
        for panel in panels.values.sorted(by: { $0.pid < $1.pid }) {
            let frame = Self.freeFrame(size: CGSize(width: settings.defaultWidth, height: settings.defaultHeight), avoiding: placed, grid: grid)
            placed.append(frame)
            panel.setFrame(frame, display: true)
            reconfigureCapture(panel.pid)
            if let name = state.monitor.client(pid: panel.pid)?.characterName { store(frame, for: name) }
        }
    }

    // MARK: Panels

    private func makePanel(for client: EVEClient) -> ThumbnailPanel {
        let size = CGSize(width: settings.defaultWidth, height: settings.defaultHeight)
        let frame = savedFrame(for: client.characterName)
            ?? Self.freeFrame(size: size, avoiding: panels.values.map(\.frame), grid: grid)
        let panel = ThumbnailPanel(pid: client.pid, frame: frame)
        panel.applySpacesBehavior(allSpaces: settings.showsOnAllSpaces)
        panel.applyStyle(borderless: settings.isBorderless)

        let pid = client.pid
        let view = panel.thumbnailView
        view.onClick = { [weak self] flags in self?.clicked(pid: pid, flags: flags) }
        view.onFrameCommitted = { [weak self] frame, resized in self?.frameCommitted(pid: pid, frame: frame, resized: resized) }
        view.menuProvider = { [weak self] in self?.menu(for: pid) }
        if !state.permissions.screenRecording {
            view.setMessage("Allow Screen Recording in EVESup Settings → General")
        } else {
            view.setMessage("Starting preview…")
        }

        panels[client.pid] = panel
        panelNames[client.pid] = client.characterName ?? ""
        return panel
    }

    /// When a client logs a character in (or switches character), move its
    /// preview to where that character's preview was last time.
    private func placeIfNameChanged(_ panel: ThumbnailPanel, for client: EVEClient) {
        let name = client.characterName ?? ""
        guard panelNames[client.pid] != name else { return }
        panelNames[client.pid] = name
        guard !name.isEmpty else { return }
        if let saved = savedFrame(for: name) {
            panel.setFrame(saved, display: true)
            reconfigureCapture(client.pid)
        } else {
            store(panel.frame, for: name)
        }
    }

    private func removePanel(_ pid: pid_t) {
        stopCapture(pid)
        panels[pid]?.orderOut(nil)
        panels[pid]?.close()
        panels[pid] = nil
        panelNames[pid] = nil
    }

    private func applyAppearance() {
        let settings = self.settings
        let active = state.monitor.activePID
        let showAny = !settings.onlyWhileEVEActive || state.monitor.eveOrSelfIsFrontmost
        let highlight = NSColor(settings.highlightColor)
        let label = labelAppearance()
        let grid = self.grid

        for (pid, panel) in panels {
            let isActive = pid == active
            let visible = showAny && !hiddenByUser.contains(pid) && !(settings.hidesActiveClient && isActive)
            if visible, !panel.isVisible { panel.orderFrontRegardless() }
            if !visible, panel.isVisible { panel.orderOut(nil) }
            panel.alphaValue = isActive ? 1 : settings.inactiveOpacity
            panel.thumbnailView.setHighlight(isActive && settings.highlightsActive ? highlight : nil, width: settings.highlightThickness)
            panel.thumbnailView.isLocked = settings.locksPositions
            panel.thumbnailView.snapGrid = grid
            panel.thumbnailView.setLabelAppearance(label)
        }
    }

    private func labelAppearance() -> ThumbnailView.LabelAppearance {
        let style = settings.label
        if let cachedLabel, cachedLabel.style == style { return cachedLabel.appearance }
        let appearance = ThumbnailView.LabelAppearance(
            font: style.font, color: NSColor(style.color), backgroundOpacity: style.backgroundOpacity)
        cachedLabel = (style, appearance)
        return appearance
    }

    private func savedFrame(for name: String?) -> NSRect? {
        guard let name, let stored = state.config.thumbnailFrames[name] else { return nil }
        let frame = NSRect(x: stored.x, y: stored.y, width: stored.width, height: stored.height)
        // Ignore positions on a display that's no longer connected.
        return NSScreen.screens.contains { $0.frame.intersects(frame) } ? frame : nil
    }

    private func store(_ frame: NSRect, for name: String) {
        state.config.thumbnailFrames[name] = StoredRect(
            x: frame.origin.x, y: frame.origin.y, width: frame.width, height: frame.height)
    }

    /// The first free slot in rows along the top of the main screen, on grid
    /// points when snapping is on.
    private static func freeFrame(size: CGSize, avoiding occupied: [NSRect], grid: CGSize?) -> NSRect {
        let area = NSScreen.screens.first?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let gap: CGFloat = 8
        let cell = grid ?? CGSize(width: 1, height: 1)
        let marginX = (gap / cell.width).rounded(.up) * cell.width
        let marginY = (gap / cell.height).rounded(.up) * cell.height
        let stepX = GridSnap.step(for: size.width, gap: gap, cell: cell.width)
        let stepY = GridSnap.step(for: size.height, gap: gap, cell: cell.height)

        var top = area.maxY - marginY
        while top - size.height >= area.minY {
            var x = area.minX + marginX
            while x + size.width <= area.maxX {
                let candidate = NSRect(x: x, y: top - size.height, width: size.width, height: size.height)
                if !occupied.contains(where: { $0.insetBy(dx: -gap / 2, dy: -gap / 2).intersects(candidate) }) {
                    return candidate
                }
                x += stepX
            }
            top -= stepY
        }
        return NSRect(x: area.minX + marginX, y: area.maxY - marginY - size.height, width: size.width, height: size.height)
    }

    // MARK: Interaction

    private func clicked(pid: pid_t, flags: NSEvent.ModifierFlags) {
        if flags.contains(.shift) {
            state.toggleExcluded(pid)
            return
        }
        guard let client = state.monitor.client(pid: pid) else { return }
        state.switchTo(client, reason: "preview click")
    }

    private func frameCommitted(pid: pid_t, frame: NSRect, resized: Bool) {
        if let name = state.monitor.client(pid: pid)?.characterName { store(frame, for: name) }
        if resized { reconfigureCapture(pid) }
    }

    private func menu(for pid: pid_t) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let client = state.monitor.client(pid: pid)
        let excluded = state.excludedPIDs.contains(pid)

        menu.addItem(ClosureMenuItem("Switch to \(client?.label ?? "Client")") { [weak self] in
            self?.clicked(pid: pid, flags: [])
        })
        menu.addItem(ClosureMenuItem("Skip When Cycling (⇧-click)", checked: excluded) { [weak self] in
            self?.state.toggleExcluded(pid)
        })
        menu.addItem(ClosureMenuItem("Hide This Preview") { [weak self] in
            self?.hiddenByUser.insert(pid)
            self?.update()
        })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Lock Preview Positions", checked: settings.locksPositions) { [weak self] in
            self?.state.config.previews.locksPositions.toggle()
        })
        menu.addItem(ClosureMenuItem("Show Hidden Previews", enabled: !hiddenByUser.isEmpty) { [weak self] in
            self?.showHiddenPreviews()
        })
        menu.addItem(ClosureMenuItem("EVESup Settings…") {
            (NSApp.delegate as? AppDelegate)?.showSettings()
        })
        return menu
    }

    // MARK: Capture

    private func updateCaptures(for clients: [EVEClient]) {
        guard state.permissions.screenRecording else {
            for pid in Array(captures.keys) { stopCapture(pid) }
            for panel in panels.values { panel.thumbnailView.setMessage("Allow Screen Recording in EVESup Settings → General") }
            return
        }

        var needed: [EVEClient] = []
        for client in clients {
            if capturedWindowIDs[client.pid] == client.windowID, captures[client.pid] != nil { continue }
            if captures[client.pid] != nil { stopCapture(client.pid) }  // the client opened a new window
            if !pendingCaptures.contains(client.pid) { needed.append(client) }
        }
        guard !needed.isEmpty else { return }
        for client in needed { pendingCaptures.insert(client.pid) }
        Task { await startCaptures(for: needed) }
    }

    private func startCaptures(for clients: [EVEClient]) async {
        defer { for client in clients { pendingCaptures.remove(client.pid) } }

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        } catch {
            Log.warn("couldn't list windows for previews: \(error.localizedDescription)")
            scheduleRetry()
            return
        }

        for client in clients {
            guard let panel = panels[client.pid] else { continue }
            guard let window = content.windows.first(where: { $0.windowID == client.windowID }) else {
                scheduleRetry()
                continue
            }
            let capture = WindowCapture()
            capture.onFrame = { [weak panel] surface in panel?.thumbnailView.show(surface: surface) }
            capture.onStop = { [weak self] error in self?.captureStopped(pid: client.pid, error: error) }
            do {
                try await capture.start(
                    window: window,
                    pointSize: panel.frame.size,
                    scale: panel.backingScaleFactor,
                    fps: settings.framesPerSecond
                )
            } catch {
                Log.warn("preview capture failed for \(client.label): \(error.localizedDescription)")
                panel.thumbnailView.setMessage("Preview unavailable")
                scheduleRetry()
                continue
            }
            // The client may have quit while the stream was starting.
            guard panels[client.pid] === panel else {
                capture.stop()
                continue
            }
            captures[client.pid] = capture
            capturedWindowIDs[client.pid] = client.windowID
            capturedSourceSizes[client.pid] = window.frame.size
        }
    }

    /// Applies the current preview size, frame rate and source window size to a running capture.
    private func reconfigureCapture(_ pid: pid_t) {
        guard let capture = captures[pid], let panel = panels[pid] else { return }
        let sourceSize = state.monitor.client(pid: pid)?.frame.size ?? capturedSourceSizes[pid] ?? .zero
        capturedSourceSizes[pid] = sourceSize
        capture.update(pointSize: panel.frame.size, sourceSize: sourceSize, scale: panel.backingScaleFactor, fps: settings.framesPerSecond)
    }

    private func captureStopped(pid: pid_t, error: Error) {
        Log.info("preview stream for pid \(pid) stopped: \(error.localizedDescription)")
        captures[pid] = nil
        capturedWindowIDs[pid] = nil
        capturedSourceSizes[pid] = nil
        scheduleRetry()
    }

    private func stopCapture(_ pid: pid_t) {
        captures[pid]?.stop()
        captures[pid] = nil
        capturedWindowIDs[pid] = nil
        capturedSourceSizes[pid] = nil
    }

    private func scheduleRetry() {
        guard !retryScheduled else { return }
        retryScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            MainActor.assumeIsolated {
                self?.retryScheduled = false
                self?.update()
            }
        }
    }
}

extension NameLabelStyle {
    /// Font families the user can pick, without hidden system families.
    static let availableFamilies: [String] = NSFontManager.shared.availableFontFamilies
        .filter { !$0.hasPrefix(".") }
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

    var font: NSFont {
        let size = CGFloat(min(max(fontSize, 6), 72))
        if let family = fontFamily, !family.isEmpty {
            let manager = NSFontManager.shared
            if isBold, let bold = manager.font(withFamily: family, traits: .boldFontMask, weight: 9, size: size) { return bold }
            if let regular = manager.font(withFamily: family, traits: [], weight: 5, size: size) { return regular }
            if let any = NSFont(name: family, size: size) { return any }
        }
        return .systemFont(ofSize: size, weight: isBold ? .semibold : .regular)
    }
}

extension NSColor {
    convenience init(_ color: RGBAColor) {
        self.init(srgbRed: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    }
}

extension RGBAColor {
    init(_ color: NSColor) {
        let srgb = color.usingColorSpace(.sRGB) ?? color
        self.init(red: srgb.redComponent, green: srgb.greenComponent, blue: srgb.blueComponent, alpha: srgb.alphaComponent)
    }
}
