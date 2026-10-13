import CoreGraphics
import Foundation

/// Grid snapping for preview windows.
///
/// Rectangles are in AppKit screen coordinates (y grows upward). The grid
/// starts at the top-left corner of `area`, normally the screen's visible
/// frame, so rows line up just below the menu bar.
public enum GridSnap {
    /// Moves `frame` so its top-left corner sits on the nearest grid point. The size is unchanged.
    public static func position(_ frame: CGRect, grid: CGSize, in area: CGRect) -> CGRect {
        guard grid.width >= 1, grid.height >= 1 else { return frame }
        let left = area.minX + ((frame.minX - area.minX) / grid.width).rounded() * grid.width
        let top = area.maxY - ((area.maxY - frame.maxY) / grid.height).rounded() * grid.height
        return CGRect(x: left, y: top - frame.height, width: frame.width, height: frame.height)
    }

    /// Rounds a size to whole grid cells, at least one cell each way.
    public static func size(_ size: CGSize, grid: CGSize) -> CGSize {
        guard grid.width >= 1, grid.height >= 1 else { return size }
        return CGSize(
            width: max(grid.width, (size.width / grid.width).rounded() * grid.width),
            height: max(grid.height, (size.height / grid.height).rounded() * grid.height)
        )
    }

    /// The distance between neighboring previews laid out on the grid: the
    /// preview plus a gap, rounded up to whole grid cells.
    public static func step(for length: CGFloat, gap: CGFloat, cell: CGFloat) -> CGFloat {
        guard cell >= 1 else { return length + gap }
        return ((length + gap) / cell).rounded(.up) * cell
    }
}
