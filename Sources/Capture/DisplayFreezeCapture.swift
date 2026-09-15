import AppKit
import ScreenCaptureKit

/// Freeze before presenting the overlay; detection and export use these same pixels.
@MainActor
enum DisplayFreezeCapture {
    struct Frozen {
        let image: CGImage
        let screen: NSScreen
    }

    enum CaptureError: LocalizedError {
        case displayUnavailable
        var errorDescription: String? {
            "The selected display is no longer available. Move the pointer to a connected display and try again."
        }
    }

    static func capture(on requestedScreen: NSScreen? = nil) async throws -> Frozen {
        guard let screen = requestedScreen ?? ActiveDisplayResolver.activeScreen(preferPointer: true),
              let displayID = ActiveDisplayResolver.displayID(for: screen) else {
            throw CaptureError.displayUnavailable
        }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.displayUnavailable
        }
        let ownWindows = PreviewWindowCaptureExclusion.includesAppWindowsInCaptures ? [] : content.windows.filter {
            $0.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier
        }
        let filter = SCContentFilter(display: display, excludingWindows: ownWindows)
        let config = SCStreamConfiguration()
        config.width = Int(screen.frame.width * screen.backingScaleFactor)
        config.height = Int(screen.frame.height * screen.backingScaleFactor)
        config.showsCursor = false
        config.scalesToFit = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return Frozen(image: image, screen: screen)
    }
}
