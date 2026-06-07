import AppKit
import CoreGraphics
import ScreenCaptureKit

/// Captures a frozen, in-process snapshot of the display that currently
/// contains the cursor. The snapshot is taken *before* any overlay is shown so
/// the overlay never appears in the frozen image. Used by Snap Capture for both
/// edge detection and the final crop, guaranteeing WYSIWYG and coordinate
/// consistency.
@MainActor
enum DisplayFreezeCapture {

    struct Frozen {
        /// Pixel buffer (top-left origin). Dimensions = display points × scale.
        let image: CGImage
        /// The screen the image belongs to (for coordinate mapping).
        let screen: NSScreen
    }

    /// Freezes the display under the cursor. Returns nil if no display is found
    /// or capture fails through every available method.
    static func captureCursorDisplay() async -> Frozen? {
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
            ?? NSScreen.main,
              let displayID = screen.displayID else {
            return nil
        }

        let scale = screen.backingScaleFactor

        if let image = captureViaCGDisplay(displayID: displayID) {
            return Frozen(image: image, screen: screen)
        }
        if let image = await captureViaScreenCaptureKit(displayID: displayID, scale: scale) {
            return Frozen(image: image, screen: screen)
        }
        if let image = captureViaScreencaptureCLI(displayID: displayID) {
            return Frozen(image: image, screen: screen)
        }
        return nil
    }

    // MARK: - Fastest: CGDisplayCreateImage (synchronous, no SCShareableContent)

    // Deprecated since macOS 14 but still works on 15 and avoids the ~73ms
    // SCShareableContent.current overhead. SCK below is the supported fallback.
    private nonisolated static func captureViaCGDisplay(displayID: CGDirectDisplayID) -> CGImage? {
        CGDisplayCreateImage(displayID)
    }

    // MARK: - Primary: ScreenCaptureKit (non-deprecated, in-process)

    // `nonisolated` so the non-Sendable SCShareableContent never crosses into
    // the main actor. Only Sendable values (displayID, scale, CGImage) flow in/out.
    private nonisolated static func captureViaScreenCaptureKit(displayID: CGDirectDisplayID, scale: CGFloat) async -> CGImage? {
        do {
            let content = try await SCShareableContent.current
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                return nil
            }

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.width = Int(CGFloat(display.width) * scale)
            config.height = Int(CGFloat(display.height) * scale)
            config.showsCursor = false
            config.scalesToFit = false

            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        } catch {
            print("BetterShot: ScreenCaptureKit freeze failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Fallback: screencapture CLI

    private nonisolated static func captureViaScreencaptureCLI(displayID: CGDirectDisplayID) -> CGImage? {
        // `screencapture -D` takes a 1-based index into the active display list.
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        guard count > 0 else { return nil }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &displays, &count)
        let index = (displays.firstIndex(of: displayID) ?? 0) + 1

        let dir = NSTemporaryDirectory()
        let path = "\(dir)bettershot_freeze_\(index).png"
        defer { try? FileManager.default.removeItem(atPath: path) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-D", "\(index)", "-t", "png", path]
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                return nil
            }
            return image
        } catch {
            print("BetterShot: screencapture freeze fallback failed: \(error.localizedDescription)")
            return nil
        }
    }
}

extension NSScreen {
    /// The CoreGraphics display ID backing this screen, if available.
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
