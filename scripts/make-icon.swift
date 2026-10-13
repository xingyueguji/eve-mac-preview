// Draws the EVESup app icon and writes an .iconset folder.
// Usage: swift scripts/make-icon.swift <output.iconset>
// then:  iconutil -c icns <output.iconset> -o Resources/EVESup.icns
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "EVESup.iconset")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

/// The icon on a 1024-point canvas: a dark space backdrop with four live-preview
/// tiles, one of them outlined in green as the active client.
func drawIcon(in canvas: NSRect) {
    let unit = canvas.width / 1024
    func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
        NSRect(x: canvas.minX + x * unit, y: canvas.minY + y * unit, width: w * unit, height: h * unit)
    }

    // Backdrop, inset like Apple's icon grid.
    let backdrop = NSBezierPath(roundedRect: rect(100, 100, 824, 824), xRadius: 185 * unit, yRadius: 185 * unit)
    NSGradient(colors: [
        NSColor(srgbRed: 0.03, green: 0.05, blue: 0.13, alpha: 1),
        NSColor(srgbRed: 0.07, green: 0.16, blue: 0.32, alpha: 1),
    ])?.draw(in: backdrop, angle: 90)

    // A few stars, placed deterministically.
    NSGraphicsContext.saveGraphicsState()
    backdrop.addClip()
    var seed: UInt64 = 7
    func random() -> CGFloat {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat(seed >> 33) / CGFloat(UInt32.max >> 1)
    }
    for _ in 0..<70 {
        let size = (1.5 + random() * 4) * unit
        NSColor.white.withAlphaComponent(0.15 + random() * 0.5).setFill()
        NSBezierPath(ovalIn: NSRect(x: canvas.minX + (100 + random() * 824) * unit,
                                    y: canvas.minY + (100 + random() * 824) * unit,
                                    width: size, height: size)).fill()
    }
    NSGraphicsContext.restoreGraphicsState()

    // Four preview tiles in a 2 × 2 grid.
    let scenes: [(NSColor, NSColor)] = [
        (NSColor(srgbRed: 0.20, green: 0.45, blue: 0.85, alpha: 1), NSColor(srgbRed: 0.10, green: 0.80, blue: 0.85, alpha: 1)),
        (NSColor(srgbRed: 0.55, green: 0.25, blue: 0.75, alpha: 1), NSColor(srgbRed: 0.95, green: 0.45, blue: 0.55, alpha: 1)),
        (NSColor(srgbRed: 0.85, green: 0.45, blue: 0.15, alpha: 1), NSColor(srgbRed: 0.98, green: 0.80, blue: 0.35, alpha: 1)),
        (NSColor(srgbRed: 0.15, green: 0.55, blue: 0.40, alpha: 1), NSColor(srgbRed: 0.45, green: 0.85, blue: 0.60, alpha: 1)),
    ]
    let tileWidth: CGFloat = 300, tileHeight: CGFloat = 190, gap: CGFloat = 28
    let originX = (1024 - (tileWidth * 2 + gap)) / 2
    let originY = (1024 - (tileHeight * 2 + gap)) / 2
    for (index, colors) in scenes.enumerated() {
        let column = CGFloat(index % 2), row = CGFloat(1 - index / 2)
        let frame = rect(originX + column * (tileWidth + gap), originY + row * (tileHeight + gap), tileWidth, tileHeight)
        let tile = NSBezierPath(roundedRect: frame, xRadius: 26 * unit, yRadius: 26 * unit)
        NSGradient(colors: [colors.0, colors.1])?.draw(in: tile, angle: -35)

        // The name tag in the corner.
        let tag = NSBezierPath(roundedRect: NSRect(x: frame.minX + 18 * unit, y: frame.maxY - 46 * unit, width: 120 * unit, height: 28 * unit),
                               xRadius: 8 * unit, yRadius: 8 * unit)
        NSColor.black.withAlphaComponent(0.45).setFill()
        tag.fill()
        NSColor.white.withAlphaComponent(0.9).setFill()
        NSBezierPath(roundedRect: NSRect(x: frame.minX + 30 * unit, y: frame.maxY - 36 * unit, width: 84 * unit, height: 8 * unit),
                     xRadius: 4 * unit, yRadius: 4 * unit).fill()

        if index == 0 {
            NSColor(srgbRed: 0.24, green: 0.88, blue: 0.45, alpha: 1).setStroke()
            tile.lineWidth = 14 * unit
        } else {
            NSColor.white.withAlphaComponent(0.25).setStroke()
            tile.lineWidth = 4 * unit
        }
        tile.stroke()
    }
}

let sizes: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, pixels) in sizes {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
    else { continue }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    drawIcon(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])?.write(to: output.appendingPathComponent("\(name).png"))
}
print("Wrote \(output.path)")
