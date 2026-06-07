import CoreGraphics

/// Pure edge-detection snapping. Given a rough drag rectangle (in pixels) and a
/// frozen image's luminance buffer, snaps each of the 4 edges to the nearest
/// strong luminance gradient within a fixed search radius.
///
/// No side effects — inputs are a luminance buffer and a CGRect, output is a
/// CGRect — so it is unit-testable with synthetic images.
enum EdgeSnapper {

    /// 8-bit grayscale buffer, top-left origin, row-major.
    struct LuminanceBuffer {
        let pixels: [UInt8]
        let width: Int
        let height: Int

        @inline(__always)
        func at(_ x: Int, _ y: Int) -> Int {
            Int(pixels[y * width + x])
        }
    }

    /// How far (in pixels) each edge searches perpendicular to itself.
    static let defaultSearchRadius = 40

    /// Renders the image to a single-channel grayscale bitmap and returns its
    /// luminance buffer. Returns nil on degenerate sizes or context failure.
    static func makeLuminanceBuffer(from image: CGImage) -> LuminanceBuffer? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }

        var pixels = [UInt8](repeating: 0, count: width * height)
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let ok: Bool = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard ok else { return nil }
        return LuminanceBuffer(pixels: pixels, width: width, height: height)
    }

    /// Maps a PixelSnap-style sensitivity value to a gradient cutoff.
    /// Higher sensitivity → lower cutoff (snaps to fainter edges). 0 = off.
    ///
    /// The linear mapping below is a starting point calibrated against the
    /// PixelSnap presets (14 / 26 / 52); tune against real displays.
    static func cutoff(forSensitivity sensitivity: Int) -> Int {
        guard sensitivity > 0 else { return 0 }
        let value = 48.0 - Double(sensitivity) * 0.8
        return max(4, Int(value.rounded()))
    }

    /// Snaps the 4 edges of `dragRectPx`. A `cutoff` of 0 (Off) returns the
    /// rect unchanged. Each edge moves independently; if no candidate within the
    /// search window exceeds the cutoff, that edge stays put.
    static func snap(
        dragRectPx: CGRect,
        in buffer: LuminanceBuffer,
        cutoff: Int,
        searchRadius: Int = defaultSearchRadius
    ) -> CGRect {
        guard cutoff > 0 else { return dragRectPx }

        let left = Int(dragRectPx.minX.rounded())
        let right = Int(dragRectPx.maxX.rounded())
        let top = Int(dragRectPx.minY.rounded())
        let bottom = Int(dragRectPx.maxY.rounded())
        guard right > left, bottom > top else { return dragRectPx }

        let snappedLeft = snapVerticalEdge(at: left, yLo: top, yHi: bottom, buffer: buffer, cutoff: cutoff, searchRadius: searchRadius)
        let snappedRight = snapVerticalEdge(at: right, yLo: top, yHi: bottom, buffer: buffer, cutoff: cutoff, searchRadius: searchRadius)
        let snappedTop = snapHorizontalEdge(at: top, xLo: left, xHi: right, buffer: buffer, cutoff: cutoff, searchRadius: searchRadius)
        let snappedBottom = snapHorizontalEdge(at: bottom, xLo: left, xHi: right, buffer: buffer, cutoff: cutoff, searchRadius: searchRadius)

        // Guard against snapping that inverts or collapses the rect.
        guard snappedRight > snappedLeft, snappedBottom > snappedTop else {
            return dragRectPx
        }

        return CGRect(
            x: snappedLeft,
            y: snappedTop,
            width: snappedRight - snappedLeft,
            height: snappedBottom - snappedTop
        )
    }

    // MARK: - Per-edge search

    /// Finds the x with the strongest mean horizontal gradient along the edge's
    /// y-span. Ties prefer the position closest to the original edge.
    private static func snapVerticalEdge(
        at edgeX: Int,
        yLo: Int,
        yHi: Int,
        buffer: LuminanceBuffer,
        cutoff: Int,
        searchRadius: Int
    ) -> Int {
        let y0 = max(0, yLo)
        let y1 = min(buffer.height - 1, yHi)
        guard y1 >= y0 else { return edgeX }
        let yCount = y1 - y0 + 1

        let x0 = max(1, edgeX - searchRadius)
        let x1 = min(buffer.width - 2, edgeX + searchRadius)
        guard x1 >= x0 else { return edgeX }

        var bestX = edgeX
        var bestScore = 0.0
        for px in x0...x1 {
            var sum = 0
            for y in y0...y1 {
                sum += abs(buffer.at(px + 1, y) - buffer.at(px - 1, y))
            }
            let mean = Double(sum) / Double(yCount)
            if mean > bestScore || (mean == bestScore && abs(px - edgeX) < abs(bestX - edgeX)) {
                bestScore = mean
                bestX = px
            }
        }
        return bestScore >= Double(cutoff) ? bestX : edgeX
    }

    /// Finds the y with the strongest mean vertical gradient along the edge's
    /// x-span. Ties prefer the position closest to the original edge.
    private static func snapHorizontalEdge(
        at edgeY: Int,
        xLo: Int,
        xHi: Int,
        buffer: LuminanceBuffer,
        cutoff: Int,
        searchRadius: Int
    ) -> Int {
        let x0 = max(0, xLo)
        let x1 = min(buffer.width - 1, xHi)
        guard x1 >= x0 else { return edgeY }
        let xCount = x1 - x0 + 1

        let y0 = max(1, edgeY - searchRadius)
        let y1 = min(buffer.height - 2, edgeY + searchRadius)
        guard y1 >= y0 else { return edgeY }

        var bestY = edgeY
        var bestScore = 0.0
        for py in y0...y1 {
            var sum = 0
            for x in x0...x1 {
                sum += abs(buffer.at(x, py + 1) - buffer.at(x, py - 1))
            }
            let mean = Double(sum) / Double(xCount)
            if mean > bestScore || (mean == bestScore && abs(py - edgeY) < abs(bestY - edgeY)) {
                bestScore = mean
                bestY = py
            }
        }
        return bestScore >= Double(cutoff) ? bestY : edgeY
    }
}
