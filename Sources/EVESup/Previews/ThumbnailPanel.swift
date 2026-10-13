import AppKit
import EVESupCore

/// A floating, borderless preview window that never takes keyboard focus.
final class ThumbnailPanel: NSPanel {
    let pid: pid_t
    let thumbnailView: ThumbnailView

    init(pid: pid_t, frame: NSRect) {
        self.pid = pid
        thumbnailView = ThumbnailView(frame: NSRect(origin: .zero, size: frame.size))
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        animationBehavior = .none
        becomesKeyOnlyIfNeeded = true
        contentView = thumbnailView
    }

    func applySpacesBehavior(allSpaces: Bool) {
        collectionBehavior = allSpaces
            ? [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            : [.fullScreenAuxiliary, .ignoresCycle]
    }

    /// Borderless: only the picture, with no background, shadow or rounded corners.
    func applyStyle(borderless: Bool) {
        thumbnailView.setBorderless(borderless)
        if hasShadow == borderless {
            hasShadow = !borderless
            invalidateShadow()
        }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Draws the live frame plus the name label, active highlight and status
/// badges, and turns mouse input into click, drag-to-move and corner-resize.
final class ThumbnailView: NSView {
    var onClick: ((NSEvent.ModifierFlags) -> Void)?
    /// The panel's new frame after a drag; the flag is true for a resize.
    var onFrameCommitted: ((NSRect, Bool) -> Void)?
    var menuProvider: (() -> NSMenu?)?
    var isLocked = false {
        didSet { updateGrip() }
    }
    /// Grid cell size while snapping is on; nil means free movement.
    var snapGrid: CGSize?

    /// How the character name is drawn.
    struct LabelAppearance: Equatable {
        var font: NSFont
        var color: NSColor
        var backgroundOpacity: CGFloat

        static let standard = LabelAppearance(font: .systemFont(ofSize: 12, weight: .semibold), color: .white, backgroundOpacity: 0.55)
    }

    static let minimumSize = NSSize(width: 96, height: 60)
    static let maximumSize = NSSize(width: 1280, height: 800)
    private static let gripSize: CGFloat = 18
    private static let cornerRadius: CGFloat = 6
    private static let messageFont = NSFont.systemFont(ofSize: 11, weight: .medium)

    private let imageLayer = CALayer()
    private let borderLayer = CALayer()
    private let nameBackground = CALayer()
    private let nameLayer = CATextLayer()
    private let badgeBackground = CALayer()
    private let badgeLayer = CATextLayer()
    private let messageLayer = CATextLayer()
    private let gripLayer = CAShapeLayer()

    private var name: String?
    private var labelAppearance = LabelAppearance.standard
    private var message: String?
    private var hasFrame = false
    private var isHovered = false
    private var isBorderless = false
    /// Width / height of the captured picture, once known.
    private var contentAspect: CGFloat?

    private enum Drag {
        case none
        case move(mouseStart: NSPoint, originStart: NSPoint)
        case resize(mouseStart: NSPoint, frameStart: NSRect)
    }
    private var drag = Drag.none
    private var didDrag = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        guard let root = layer else { return }
        root.masksToBounds = true

        imageLayer.contentsGravity = .resizeAspect

        nameBackground.cornerRadius = 4
        nameLayer.truncationMode = .end
        nameLayer.shadowColor = NSColor.black.cgColor
        nameLayer.shadowOffset = CGSize(width: 0, height: 1)
        nameLayer.shadowRadius = 1.5
        nameBackground.addSublayer(nameLayer)
        renderName()

        badgeBackground.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.9).cgColor
        badgeBackground.cornerRadius = 4
        badgeBackground.isHidden = true
        badgeLayer.string = NSAttributedString(string: "skipped", attributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .bold),
            .foregroundColor: NSColor.black,
        ])
        badgeLayer.alignmentMode = .center
        badgeBackground.addSublayer(badgeLayer)

        messageLayer.isWrapped = true
        messageLayer.alignmentMode = .center
        messageLayer.isHidden = true

        borderLayer.borderWidth = 0

        gripLayer.strokeColor = NSColor.white.withAlphaComponent(0.8).cgColor
        gripLayer.lineWidth = 1.5
        gripLayer.isHidden = true

        for sublayer in [imageLayer, messageLayer, nameBackground, badgeBackground, borderLayer, gripLayer] {
            root.addSublayer(sublayer)
        }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        applyChrome()
        layoutLayers()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }

    // MARK: Content

    func show(surface: IOSurfaceRef) {
        let width = IOSurfaceGetWidth(surface), height = IOSurfaceGetHeight(surface)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.contents = surface
        CATransaction.commit()
        contentArrived(aspect: height > 0 ? CGFloat(width) / CGFloat(height) : nil)
    }

    /// Shows a still image (used for the snapshot sample).
    func show(image: CGImage) {
        imageLayer.contents = image
        contentArrived(aspect: image.height > 0 ? CGFloat(image.width) / CGFloat(image.height) : nil)
    }

    private func contentArrived(aspect: CGFloat?) {
        var needsLayout = false
        if let aspect, contentAspect.map({ abs($0 - aspect) > 0.001 }) ?? true {
            contentAspect = aspect
            needsLayout = true
        }
        if !hasFrame {
            hasFrame = true
            applyChrome()
            setMessage(nil)
        }
        if needsLayout { layoutLayers() }
    }

    func update(name: String?, excluded: Bool) {
        if name != self.name {
            self.name = name
            renderName()
        }
        badgeBackground.isHidden = !excluded
        layoutLayers()
    }

    func setLabelAppearance(_ appearance: LabelAppearance) {
        guard appearance != labelAppearance else { return }
        labelAppearance = appearance
        renderName()
        layoutLayers()
    }

    private func renderName() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        nameLayer.string = name.map {
            NSAttributedString(string: $0, attributes: [.font: labelAppearance.font, .foregroundColor: labelAppearance.color])
        }
        nameBackground.backgroundColor = NSColor.black.withAlphaComponent(labelAppearance.backgroundOpacity).cgColor
        // Without a dark box behind it, a soft shadow keeps the name readable on bright scenes.
        nameLayer.shadowOpacity = labelAppearance.backgroundOpacity < 0.3 ? 0.9 : 0
        CATransaction.commit()
    }

    func setHighlight(_ color: NSColor?, width: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        borderLayer.borderWidth = color == nil ? 0 : width
        borderLayer.borderColor = color?.cgColor
        CATransaction.commit()
    }

    /// Text shown in the middle of the preview, e.g. while waiting for permission.
    func setMessage(_ text: String?) {
        guard text != message else { return }
        message = text
        messageLayer.string = text.map {
            NSAttributedString(string: $0, attributes: [.font: Self.messageFont, .foregroundColor: NSColor.white.withAlphaComponent(0.85)])
        }
        messageLayer.isHidden = text == nil
        layoutLayers()
    }

    func setBorderless(_ borderless: Bool) {
        guard borderless != isBorderless else { return }
        isBorderless = borderless
        applyChrome()
    }

    /// Framed: a dark rounded card, so any space around the picture shows as black bars.
    /// Borderless: nothing but the picture. Until the first frame arrives it
    /// keeps a dark background, so the preview can still be seen and moved.
    private func applyChrome() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let radius = isBorderless ? 0 : Self.cornerRadius
        layer?.cornerRadius = radius
        borderLayer.cornerRadius = radius
        layer?.backgroundColor = isBorderless && hasFrame
            ? NSColor.clear.cgColor
            : NSColor.black.withAlphaComponent(isBorderless ? 0.6 : 1).cgColor
        CATransaction.commit()
    }

    // MARK: Layout

    /// Where the picture is drawn: the largest rectangle with the picture's
    /// shape that fits, centered. The whole view until the shape is known.
    private var contentFrame: CGRect {
        guard let aspect = contentAspect, aspect > 0, bounds.width > 0, bounds.height > 0 else { return bounds }
        var size = CGSize(width: bounds.width, height: bounds.width / aspect)
        if size.height > bounds.height { size = CGSize(width: bounds.height * aspect, height: bounds.height) }
        return CGRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutLayers()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2
        for textLayer in [nameLayer, badgeLayer, messageLayer] { textLayer.contentsScale = scale }
    }

    private func layoutLayers() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let content = contentFrame
        imageLayer.frame = content
        borderLayer.frame = content

        if let name, !name.isEmpty {
            let textSize = NSAttributedString(string: name, attributes: [.font: labelAppearance.font]).size()
            let width = min(ceil(textSize.width) + 12, content.width - 8)
            nameBackground.isHidden = false
            nameBackground.frame = CGRect(x: content.minX + 4, y: content.minY + 4, width: max(width, 0), height: ceil(textSize.height) + 4)
            nameLayer.frame = nameBackground.bounds.insetBy(dx: 6, dy: 2)
        } else {
            nameBackground.isHidden = true
        }

        badgeBackground.frame = CGRect(x: content.maxX - 58, y: content.minY + 4, width: 54, height: 16)
        badgeLayer.frame = badgeBackground.bounds.insetBy(dx: 2, dy: 1.5)

        let messageHeight: CGFloat = 34
        messageLayer.frame = CGRect(x: 8, y: (bounds.height - messageHeight) / 2, width: bounds.width - 16, height: messageHeight)

        let size = Self.gripSize
        gripLayer.frame = CGRect(x: content.maxX - size, y: content.maxY - size, width: size, height: size)
        let path = CGMutablePath()
        for inset in [5.0, 9.0, 13.0] {
            path.move(to: CGPoint(x: size - 3, y: inset))
            path.addLine(to: CGPoint(x: inset, y: size - 3))
        }
        gripLayer.path = path
    }

    private func updateGrip() {
        gripLayer.isHidden = !(isHovered && !isLocked)
    }

    // MARK: Mouse

    /// The visible part of the screen under `point` (below the menu bar, beside the Dock).
    /// The snapping grid starts at its top-left corner.
    static func snapArea(at point: NSPoint, window: NSWindow? = nil) -> NSRect {
        let screen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? window?.screen ?? NSScreen.main
        return screen?.visibleFrame ?? .zero
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateGrip()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateGrip()
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            showMenu(for: event)
            return
        }
        guard let window else { return }
        didDrag = false
        let point = convert(event.locationInWindow, from: nil)
        let content = contentFrame
        let inGrip = point.x >= content.maxX - Self.gripSize && point.y >= content.maxY - Self.gripSize
        drag = inGrip
            ? .resize(mouseStart: NSEvent.mouseLocation, frameStart: window.frame)
            : .move(mouseStart: NSEvent.mouseLocation, originStart: window.frame.origin)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let mouse = NSEvent.mouseLocation
        switch drag {
        case .none:
            return
        case let .move(start, origin):
            let dx = mouse.x - start.x, dy = mouse.y - start.y
            if !didDrag, hypot(dx, dy) < 4 { return }
            didDrag = true
            guard !isLocked else { return }
            var moved = NSRect(origin: NSPoint(x: origin.x + dx, y: origin.y + dy), size: window.frame.size)
            if let grid = snapGrid {
                moved = GridSnap.position(moved, grid: grid, in: Self.snapArea(at: mouse, window: window))
            }
            if moved.origin != window.frame.origin { window.setFrameOrigin(moved.origin) }
        case let .resize(start, frame):
            let dx = mouse.x - start.x, dy = mouse.y - start.y
            if !didDrag, hypot(dx, dy) < 2 { return }
            didDrag = true
            guard !isLocked else { return }
            var size = CGSize(width: frame.width + dx, height: frame.height - dy)
            if let grid = snapGrid { size = GridSnap.size(size, grid: grid) }
            size.width = min(max(size.width, Self.minimumSize.width), Self.maximumSize.width)
            size.height = min(max(size.height, Self.minimumSize.height), Self.maximumSize.height)
            let resized = NSRect(x: frame.minX, y: frame.maxY - size.height, width: size.width, height: size.height)
            if resized != window.frame { window.setFrame(resized, display: true) }
        }
    }

    override func mouseUp(with event: NSEvent) {
        let finished = drag
        drag = .none
        guard let window else { return }
        switch finished {
        case .none:
            return
        case .move:
            if !didDrag { onClick?(event.modifierFlags) } else if !isLocked { onFrameCommitted?(window.frame, false) }
        case .resize:
            if !didDrag { onClick?(event.modifierFlags) } else if !isLocked { onFrameCommitted?(window.frame, true) }
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        showMenu(for: event)
    }

    private func showMenu(for event: NSEvent) {
        guard let menu = menuProvider?() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}

/// A menu item that runs a closure.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, checked: Bool = false, enabled: Bool = true, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
        state = checked ? .on : .off
        isEnabled = enabled
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func run() { handler() }
}
