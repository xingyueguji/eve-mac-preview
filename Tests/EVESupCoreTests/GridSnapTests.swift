import CoreGraphics
import XCTest
@testable import EVESupCore

final class GridSnapTests: XCTestCase {
    /// A screen area whose top edge is at y = 800 (AppKit coordinates grow upward).
    private let area = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let grid = CGSize(width: 20, height: 20)

    func testTopLeftCornerSnapsToNearestGridPoint() {
        // Top-left corner 33 pt from the left and 47 pt below the top.
        let frame = CGRect(x: 33, y: 800 - 47 - 100, width: 150, height: 100)
        let snapped = GridSnap.position(frame, grid: grid, in: area)
        XCTAssertEqual(snapped.minX, 40)
        XCTAssertEqual(snapped.maxY, 800 - 40)
        XCTAssertEqual(snapped.size, frame.size)
    }

    func testGridStartsAtTheAreaCorner() {
        // A screen area below a 25 pt menu bar and right of a 7 pt Dock.
        let offsetArea = CGRect(x: 7, y: 0, width: 1000, height: 775)
        let frame = CGRect(x: 7 + 18, y: 775 - 3 - 100, width: 150, height: 100)
        let snapped = GridSnap.position(frame, grid: grid, in: offsetArea)
        XCTAssertEqual(snapped.minX, 7 + 20)
        XCTAssertEqual(snapped.maxY, 775)
    }

    func testDifferentCellWidthAndHeight() {
        let frame = CGRect(x: 26, y: 800 - 26 - 50, width: 80, height: 50)
        let snapped = GridSnap.position(frame, grid: CGSize(width: 50, height: 10), in: area)
        XCTAssertEqual(snapped.minX, 50)
        XCTAssertEqual(snapped.maxY, 800 - 30)
    }

    func testSizeRoundsToWholeCellsButNeverBelowOne() {
        XCTAssertEqual(GridSnap.size(CGSize(width: 288, height: 181), grid: grid), CGSize(width: 280, height: 180))
        XCTAssertEqual(GridSnap.size(CGSize(width: 291, height: 171), grid: grid), CGSize(width: 300, height: 180))
        XCTAssertEqual(GridSnap.size(CGSize(width: 3, height: 4), grid: grid), CGSize(width: 20, height: 20))
    }

    func testStepRoundsPreviewPlusGapUpToWholeCells() {
        XCTAssertEqual(GridSnap.step(for: 288, gap: 8, cell: 20), 300)
        XCTAssertEqual(GridSnap.step(for: 280, gap: 8, cell: 20), 300)
        XCTAssertEqual(GridSnap.step(for: 288, gap: 8, cell: 1), 296)
    }

    func testTinyGridIsIgnored() {
        let frame = CGRect(x: 33.5, y: 10, width: 150, height: 100)
        XCTAssertEqual(GridSnap.position(frame, grid: CGSize(width: 0, height: 0), in: area), frame)
    }

    func testLabelAndGridSettingsDecodeWithDefaults() throws {
        let json = #"{"snapsToGrid": true, "label": {"fontSize": 16}}"#
        let settings = try JSONDecoder().decode(PreviewSettings.self, from: Data(json.utf8))
        XCTAssertTrue(settings.snapsToGrid)
        XCTAssertEqual(settings.gridWidth, 20)
        XCTAssertEqual(settings.label.fontSize, 16)
        XCTAssertEqual(settings.label.isBold, true)
        XCTAssertNil(settings.label.fontFamily)
        XCTAssertEqual(settings.label.color, RGBAColor(red: 1, green: 1, blue: 1))
    }
}
