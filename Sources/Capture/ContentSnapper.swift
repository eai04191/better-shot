import CoreGraphics

/// Snaps a rough drag rectangle to the tight bounding box of the *content*
/// inside it — the pixels that differ from the surrounding background — the way
/// PixelSnap fits a selection to a UI element (icon + label, a button, etc).
///
/// Pure function over a luminance buffer (no side effects), so it is
/// unit-testable with synthetic images.
enum ContentSnapper {

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

    /// Maps a PixelSnap-style sensitivity value to a background-difference
    /// threshold. Higher sensitivity → lower threshold (treats fainter pixels as
    /// content, e.g. anti-aliased text edges). 0 = off.
    ///
    /// Calibrated against the PixelSnap presets (14 / 26 / 52); tune on real UIs.
    static func threshold(forSensitivity sensitivity: Int) -> Int {
        guard sensitivity > 0 else { return 0 }
        let value = 48.0 - Double(sensitivity) * 0.8
        return max(4, Int(value.rounded()))
    }

    /// Returns the tight bounding box of content within `dragRectPx`: the pixels
    /// whose luminance differs from the estimated background by more than
    /// `threshold`. A `threshold` of 0 (Off) or "no content found" returns the
    /// drag rect unchanged.
    static func snap(dragRectPx: CGRect, in buffer: LuminanceBuffer, threshold: Int) -> CGRect {
        guard threshold > 0 else { return dragRectPx }

        let imageBounds = CGRect(x: 0, y: 0, width: buffer.width, height: buffer.height)
        let rect = dragRectPx.intersection(imageBounds).integral
        let x0 = Int(rect.minX)
        let y0 = Int(rect.minY)
        let x1 = Int(rect.maxX) - 1
        let y1 = Int(rect.maxY) - 1
        guard x1 > x0, y1 > y0 else { return dragRectPx }

        let background = estimateBackground(x0: x0, y0: y0, x1: x1, y1: y1, buffer: buffer)

        var minX = x1 + 1
        var minY = y1 + 1
        var maxX = x0 - 1
        var maxY = y0 - 1
        for y in y0...y1 {
            for x in x0...x1 {
                if abs(buffer.at(x, y) - background) > threshold {
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                }
            }
        }

        // No content distinguishable from the background — keep the drag rect.
        guard maxX >= minX, maxY >= minY else { return dragRectPx }

        // maxX/maxY are inclusive content pixels; CGRect max edges are exclusive.
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    /// Estimates the background luminance as the median of the drag rect's 1px
    /// border. Robust as long as most of the border is background.
    private static func estimateBackground(
        x0: Int, y0: Int, x1: Int, y1: Int, buffer: LuminanceBuffer
    ) -> Int {
        var samples: [Int] = []
        samples.reserveCapacity(2 * (x1 - x0 + 1) + 2 * (y1 - y0 + 1))
        for x in x0...x1 {
            samples.append(buffer.at(x, y0))
            samples.append(buffer.at(x, y1))
        }
        for y in y0...y1 {
            samples.append(buffer.at(x0, y))
            samples.append(buffer.at(x1, y))
        }
        samples.sort()
        return samples[samples.count / 2]
    }
}
