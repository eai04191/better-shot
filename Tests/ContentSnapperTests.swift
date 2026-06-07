import XCTest
// ContentSnapper.swift is compiled directly into this logic-test bundle (no host
// app), so its internal symbols are visible without @testable import.

// PixelSnap-style sensitivity presets (mirror of SnapThreshold's raw values).
private let kSensitivitySmall = 14
private let kSensitivityMedium = 26
private let kSensitivityLarge = 52

final class ContentSnapperTests: XCTestCase {

    /// Builds a `width × height` buffer filled with `background`, then paints the
    /// rectangle `[cx0, cx1) × [cy0, cy1)` with `content`.
    private func bufferWithBlock(
        width: Int, height: Int, background: UInt8, content: UInt8,
        cx0: Int, cy0: Int, cx1: Int, cy1: Int
    ) -> ContentSnapper.LuminanceBuffer {
        var pixels = [UInt8](repeating: background, count: width * height)
        for y in cy0..<cy1 {
            for x in cx0..<cx1 {
                pixels[y * width + x] = content
            }
        }
        return ContentSnapper.LuminanceBuffer(pixels: pixels, width: width, height: height)
    }

    private let strongThreshold = ContentSnapper.threshold(forSensitivity: kSensitivityMedium)

    // MARK: - Bounding box fit

    func testFitsTightlyToContentBlock() {
        // Content block occupies x∈[50,100), y∈[10,30) on a white background.
        let buffer = bufferWithBlock(width: 200, height: 40, background: 255, content: 0,
                                     cx0: 50, cy0: 10, cx1: 100, cy1: 30)
        let drag = CGRect(x: 20, y: 5, width: 160, height: 30) // generously around it
        let snapped = ContentSnapper.snap(dragRectPx: drag, in: buffer, threshold: strongThreshold)
        XCTAssertEqual(snapped.minX, 50)
        XCTAssertEqual(snapped.minY, 10)
        XCTAssertEqual(snapped.maxX, 100) // inclusive pixels 50..99 → exclusive edge 100
        XCTAssertEqual(snapped.maxY, 30)
    }

    func testShrinksWhenDragIsLargerThanContent() {
        let buffer = bufferWithBlock(width: 200, height: 40, background: 255, content: 0,
                                     cx0: 80, cy0: 15, cx1: 120, cy1: 25)
        let drag = CGRect(x: 10, y: 2, width: 180, height: 36)
        let snapped = ContentSnapper.snap(dragRectPx: drag, in: buffer, threshold: strongThreshold)
        XCTAssertLessThan(snapped.width, drag.width, "should shrink to the content")
        XCTAssertEqual(snapped.minX, 80)
        XCTAssertEqual(snapped.maxX, 120)
    }

    func testOnlyConsidersContentInsideDragRect() {
        // Two blocks; the drag rect only covers the right one.
        var pixels = [UInt8](repeating: 255, count: 200 * 40)
        func paint(_ x0: Int, _ x1: Int) { for y in 10..<30 { for x in x0..<x1 { pixels[y*200+x] = 0 } } }
        paint(10, 40)    // outside the drag
        paint(120, 160)  // inside the drag
        let buffer = ContentSnapper.LuminanceBuffer(pixels: pixels, width: 200, height: 40)
        let drag = CGRect(x: 90, y: 5, width: 90, height: 30) // x∈[90,180)
        let snapped = ContentSnapper.snap(dragRectPx: drag, in: buffer, threshold: strongThreshold)
        XCTAssertEqual(snapped.minX, 120)
        XCTAssertEqual(snapped.maxX, 160)
    }

    // MARK: - No-op cases

    func testNoContentReturnsDragRect() {
        let buffer = ContentSnapper.LuminanceBuffer(
            pixels: [UInt8](repeating: 255, count: 200 * 40), width: 200, height: 40)
        let drag = CGRect(x: 20, y: 5, width: 160, height: 30)
        let snapped = ContentSnapper.snap(dragRectPx: drag, in: buffer, threshold: strongThreshold)
        XCTAssertEqual(snapped, drag, "flat background → drag rect unchanged")
    }

    func testThresholdZeroIsNoOp() {
        let buffer = bufferWithBlock(width: 200, height: 40, background: 255, content: 0,
                                     cx0: 50, cy0: 10, cx1: 100, cy1: 30)
        let drag = CGRect(x: 20, y: 5, width: 160, height: 30)
        let snapped = ContentSnapper.snap(dragRectPx: drag, in: buffer, threshold: 0)
        XCTAssertEqual(snapped, drag, "threshold 0 (Off) returns the drag rect unchanged")
    }

    func testFaintContentBelowThresholdIsIgnored() {
        // Content only 4 levels off the background — below the medium threshold.
        let buffer = bufferWithBlock(width: 200, height: 40, background: 200, content: 204,
                                     cx0: 50, cy0: 10, cx1: 100, cy1: 30)
        let drag = CGRect(x: 20, y: 5, width: 160, height: 30)
        let snapped = ContentSnapper.snap(dragRectPx: drag, in: buffer, threshold: strongThreshold)
        XCTAssertEqual(snapped, drag, "content fainter than the threshold is treated as background")
    }

    // MARK: - Sensitivity → threshold mapping

    func testSensitivityMapsInverselyToThreshold() {
        XCTAssertEqual(ContentSnapper.threshold(forSensitivity: 0), 0, "0 is Off")
        let small = ContentSnapper.threshold(forSensitivity: kSensitivitySmall)
        let medium = ContentSnapper.threshold(forSensitivity: kSensitivityMedium)
        let large = ContentSnapper.threshold(forSensitivity: kSensitivityLarge)
        XCTAssertGreaterThan(small, medium)
        XCTAssertGreaterThan(medium, large)
        XCTAssertGreaterThanOrEqual(large, 4, "threshold has a floor")
    }
}
