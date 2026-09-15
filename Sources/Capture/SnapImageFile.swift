import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

enum SnapImageFile {
    enum WriteError: LocalizedError {
        case failed
        var errorDescription: String? {
            "The selection couldn’t be written. Check available disk space and try again."
        }
    }

    /// Always write lossless raw pixels; the shared pipeline decides the export format.
    static func writeTemporaryPNG(_ image: CGImage) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bettershot_snap_\(UUID().uuidString).png")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw WriteError.failed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: url)
            throw WriteError.failed
        }
        return url
    }
}
