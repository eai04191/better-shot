import XCTest
// EdgeSnapper.swift is compiled directly into this logic-test bundle (no host app),
// so its internal symbols are visible without @testable import.

// PixelSnap-style sensitivity presets (mirror of SnapThreshold's raw values).
private let kSensitivitySmall = 14
private let kSensitivityMedium = 26
private let kSensitivityLarge = 52

final class EdgeSnapperTests: XCTestCase {

    // MARK: - Helpers

    /// Builds a luminance buffer with a single vertical edge at column `edgeX`
    /// (pixels left of it are `left`, the rest are `right`).
    private func verticalEdgeBuffer(
        width: Int, height: Int, edgeX: Int, left: UInt8, right: UInt8
    ) -> EdgeSnapper.LuminanceBuffer {
        var pixels = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                pixels[y * width + x] = x < edgeX ? left : right
            }
        }
        return EdgeSnapper.LuminanceBuffer(pixels: pixels, width: width, height: height)
    }

    /// Builds a luminance buffer with a single horizontal edge at row `edgeY`.
    private func horizontalEdgeBuffer(
        width: Int, height: Int, edgeY: Int, top: UInt8, bottom: UInt8
    ) -> EdgeSnapper.LuminanceBuffer {
        var pixels = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            let v = y < edgeY ? top : bottom
            for x in 0..<width {
                pixels[y * width + x] = v
            }
        }
        return EdgeSnapper.LuminanceBuffer(pixels: pixels, width: width, height: height)
    }

    private let strongCutoff = EdgeSnapper.cutoff(forSensitivity: kSensitivityMedium)

    // MARK: - Inward-only snapping (regression for the "grows past the drag" bug)

    func testLeftEdgeDoesNotSnapToOutsideEdge() {
        // Strong edge OUTSIDE the drag (to the left of the left edge); interior is flat.
        let buffer = verticalEdgeBuffer(width: 200, height: 40, edgeX: 30, left: 0, right: 255)
        let drag = CGRect(x: 60, y: 5, width: 100, height: 30) // left=60, right=160
        let snapped = EdgeSnapper.snap(dragRectPx: drag, in: buffer, cutoff: strongCutoff)
        // Left edge must NOT move out to x=30 — it stays put (no interior edge found).
        XCTAssertEqual(snapped.minX, 60, "left edge must not grow outward to the external edge")
    }

    func testLeftEdgeSnapsToInteriorEdge() {
        // Strong edge INSIDE the drag, just right of the left edge.
        let buffer = verticalEdgeBuffer(width: 200, height: 40, edgeX: 90, left: 0, right: 255)
        let drag = CGRect(x: 60, y: 5, width: 100, height: 30) // left=60
        let snapped = EdgeSnapper.snap(dragRectPx: drag, in: buffer, cutoff: strongCutoff)
        // Snaps inward to the edge column (89 or 90 depending on tie-break).
        XCTAssertTrue((89...90).contains(Int(snapped.minX)), "got \(snapped.minX)")
        XCTAssertGreaterThan(snapped.minX, drag.minX, "left edge should shrink inward")
    }

    func testRightEdgeSnapsInwardOnly() {
        // Interior edge near the right side, plus an external edge further right.
        var pixels = [UInt8](repeating: 128, count: 200 * 40)
        func setColumnEdge(at edgeX: Int) {
            for y in 0..<40 {
                for x in edgeX..<200 { pixels[y * 200 + x] = 255 }
            }
        }
        // External edge at x=180 (outside right=150), interior edge at x=130.
        setColumnEdge(at: 180)
        setColumnEdge(at: 130)
        let buffer = EdgeSnapper.LuminanceBuffer(pixels: pixels, width: 200, height: 40)
        let drag = CGRect(x: 40, y: 5, width: 110, height: 30) // right=150
        let snapped = EdgeSnapper.snap(dragRectPx: drag, in: buffer, cutoff: strongCutoff)
        XCTAssertLessThanOrEqual(snapped.maxX, drag.maxX, "right edge must not grow outward")
        XCTAssertTrue((129...131).contains(Int(snapped.maxX)), "got \(snapped.maxX)")
    }

    func testTopAndBottomSnapInward() {
        let buffer = horizontalEdgeBuffer(width: 40, height: 200, edgeY: 90, top: 0, bottom: 255)
        let drag = CGRect(x: 5, y: 60, width: 30, height: 100) // top=60, bottom=160
        let snapped = EdgeSnapper.snap(dragRectPx: drag, in: buffer, cutoff: strongCutoff)
        // Top edge snaps down to the interior edge; bottom has no interior edge → stays.
        XCTAssertTrue((89...90).contains(Int(snapped.minY)), "top got \(snapped.minY)")
        XCTAssertEqual(snapped.maxY, 160, "bottom edge must not grow outward")
    }

    // MARK: - Cutoff behaviour

    func testCutoffZeroIsNoOp() {
        let buffer = verticalEdgeBuffer(width: 200, height: 40, edgeX: 90, left: 0, right: 255)
        let drag = CGRect(x: 60, y: 5, width: 100, height: 30)
        let snapped = EdgeSnapper.snap(dragRectPx: drag, in: buffer, cutoff: 0)
        XCTAssertEqual(snapped, drag, "cutoff 0 (Off) must return the drag rect unchanged")
    }

    func testWeakGradientBelowCutoffDoesNotMove() {
        // A faint interior edge whose gradient is below the cutoff.
        let buffer = verticalEdgeBuffer(width: 200, height: 40, edgeX: 90, left: 120, right: 124)
        let drag = CGRect(x: 60, y: 5, width: 100, height: 30)
        let snapped = EdgeSnapper.snap(dragRectPx: drag, in: buffer, cutoff: strongCutoff)
        XCTAssertEqual(snapped.minX, 60, "faint edge below cutoff must not attract the edge")
    }

    // MARK: - Sensitivity → cutoff mapping

    func testSensitivityMapsInverselyToCutoff() {
        XCTAssertEqual(EdgeSnapper.cutoff(forSensitivity: 0), 0, "0 is Off")
        let small = EdgeSnapper.cutoff(forSensitivity: kSensitivitySmall)
        let medium = EdgeSnapper.cutoff(forSensitivity: kSensitivityMedium)
        let large = EdgeSnapper.cutoff(forSensitivity: kSensitivityLarge)
        // Higher sensitivity → lower cutoff (more eager to snap).
        XCTAssertGreaterThan(small, medium)
        XCTAssertGreaterThan(medium, large)
        XCTAssertGreaterThanOrEqual(large, 4, "cutoff has a floor")
    }
}
