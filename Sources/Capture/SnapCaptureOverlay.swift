import AppKit
import CoreGraphics
import SwiftUI

/// Full-screen overlay for Snap Capture. Draws a frozen display image, lets the
/// user drag a rough rectangle, snaps its edges to UI boundaries, then adds even
/// padding and crops the *real* frozen pixels. Returns the cropped CGImage, or
/// nil on cancel.
@MainActor
final class SnapCaptureOverlay {

    private let frozenImage: CGImage
    private let screen: NSScreen
    private var window: NSWindow?
    private var continuation: CheckedContinuation<CGImage?, Never>?
    private var didFinish = false

    init(frozenImage: CGImage, screen: NSScreen) {
        self.frozenImage = frozenImage
        self.screen = screen
    }

    func run() async -> CGImage? {
        await withCheckedContinuation { cont in
            self.continuation = cont
            show()
        }
    }

    private func show() {
        let window = OverlaySnapWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = true
        window.backgroundColor = .black
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenPrimary]

        let view = SnapSelectionView(
            frozenImage: frozenImage,
            scale: screen.backingScaleFactor
        ) { [weak self] crop in
            self?.finish(with: crop)
        } onCancel: { [weak self] in
            self?.finish(with: nil)
        }

        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(view)
        self.window = window
    }

    private func finish(with crop: CGImage?) {
        guard !didFinish else { return }
        didFinish = true
        window?.orderOut(nil)
        window = nil
        continuation?.resume(returning: crop)
        continuation = nil
    }
}

// MARK: - Window

private final class OverlaySnapWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Selection View

private final class SnapSelectionView: NSView {

    private let frozenImage: CGImage
    private let displayImage: NSImage
    private let scale: CGFloat
    // Built lazily on first snap (mouseUp), not during init, so the overlay
    // appears immediately instead of waiting for the grayscale pass on a 6K image.
    private lazy var luminance: ContentSnapper.LuminanceBuffer? =
        ContentSnapper.makeLuminanceBuffer(from: frozenImage)
    private let onConfirm: (CGImage) -> Void
    private let onCancel: () -> Void

    // Interaction state
    private var dragStart: NSPoint?
    private var dragCurrent: NSPoint?
    private var isDragging = false
    private var mouseLocation: NSPoint?

    // Result state
    private var roughRectPx: CGRect?     // last rough drag rect, for re-snapping
    private var snappedRectPx: CGRect?   // current snapped rect
    private var threshold: SnapThreshold = AppPreferences.snapThreshold
    private var extendPx: Double = AppPreferences.snapExtendPx

    private var panelHost: NSHostingView<SnapControlPanel>?
    private let crosshair = CrosshairCursor.shared.makeCursor()

    init(
        frozenImage: CGImage,
        scale: CGFloat,
        onConfirm: @escaping (CGImage) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.frozenImage = frozenImage
        self.scale = scale
        self.displayImage = NSImage(
            cgImage: frozenImage,
            size: NSSize(width: CGFloat(frozenImage.width) / scale, height: CGFloat(frozenImage.height) / scale)
        )
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func resetCursorRects() {
        if snappedRectPx == nil {
            addCursorRect(bounds, cursor: crosshair)
        }
    }

    // MARK: - Coordinate mapping (view points ↔ image pixels, Y-flipped)

    private func viewToPixel(_ rect: CGRect) -> CGRect {
        let h = bounds.height
        return CGRect(
            x: rect.minX * scale,
            y: (h - rect.maxY) * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
    }

    private func pixelToView(_ rect: CGRect) -> CGRect {
        let h = bounds.height
        return CGRect(
            x: rect.minX / scale,
            y: h - (rect.maxY / scale),
            width: rect.width / scale,
            height: rect.height / scale
        )
    }

    private var imageBoundsPx: CGRect {
        CGRect(x: 0, y: 0, width: frozenImage.width, height: frozenImage.height)
    }

    /// Snapped rect plus uniform padding, clamped to the image, in pixels.
    private func finalCropRectPx() -> CGRect? {
        guard let snapped = snappedRectPx else { return nil }
        let padPx = CGFloat(extendPx) * scale
        let padded = snapped.insetBy(dx: -padPx, dy: -padPx)
        let clamped = padded.intersection(imageBoundsPx).integral
        guard clamped.width >= 1, clamped.height >= 1 else { return nil }
        return clamped
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        displayImage.draw(in: bounds)

        let selectionViewRect: CGRect? = {
            if isDragging, let s = dragStart, let c = dragCurrent {
                return rectFromPoints(s, c)
            }
            if let snapped = snappedRectPx {
                return pixelToView(snapped)
            }
            return nil
        }()

        // Dim everything, then punch the bright selection back in.
        NSColor.black.withAlphaComponent(0.45).setFill()
        bounds.fill()

        guard let sel = selectionViewRect, sel.width > 1, sel.height > 1 else {
            if let mouse = mouseLocation, snappedRectPx == nil {
                drawGuideLines(at: mouse)
            }
            return
        }

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: sel).addClip()
        displayImage.draw(in: bounds)
        NSGraphicsContext.restoreGraphicsState()

        // Padded crop preview (dashed, outside) — only once snapped.
        if snappedRectPx != nil, let crop = finalCropRectPx() {
            let paddedView = pixelToView(crop)
            NSColor.white.withAlphaComponent(0.7).setStroke()
            let dashed = NSBezierPath(rect: paddedView)
            dashed.lineWidth = 1
            dashed.setLineDash([5, 4], count: 2, phase: 0)
            dashed.stroke()
        }

        // Snapped/selection rect (solid).
        NSColor.white.setStroke()
        let border = NSBezierPath(rect: sel)
        border.lineWidth = 1.5
        border.stroke()

        drawDimensionLabel(for: sel)
    }

    private func drawGuideLines(at point: NSPoint) {
        NSColor.white.withAlphaComponent(0.4).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 0.5
        path.move(to: NSPoint(x: point.x, y: bounds.minY))
        path.line(to: NSPoint(x: point.x, y: bounds.maxY))
        path.move(to: NSPoint(x: bounds.minX, y: point.y))
        path.line(to: NSPoint(x: bounds.maxX, y: point.y))
        path.stroke()
    }

    private func drawDimensionLabel(for sel: CGRect) {
        let wPx: Int
        let hPx: Int
        if let snapped = snappedRectPx {
            wPx = Int(snapped.width.rounded())
            hPx = Int(snapped.height.rounded())
        } else {
            wPx = Int(sel.width * scale)
            hPx = Int(sel.height * scale)
        }
        let label = "\(wPx) × \(hPx)" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let labelSize = label.size(withAttributes: attrs)
        let boxW = labelSize.width + 12
        let boxH = labelSize.height + 4
        // Prefer just above the selection (the parameter panel sits below it, so
        // this avoids overlap); fall back below if it would clip off the top.
        let aboveY = sel.maxY + 8
        let belowY = sel.minY - boxH - 8
        let y = (aboveY + boxH <= bounds.maxY - 4) ? aboveY : belowY
        let x = min(max(sel.midX - boxW / 2, 4), bounds.maxX - boxW - 4)
        let labelRect = CGRect(x: x, y: y, width: boxW, height: boxH)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: labelRect, xRadius: 4, yRadius: 4).fill()
        label.draw(at: NSPoint(x: labelRect.minX + 6, y: labelRect.minY + 2), withAttributes: attrs)
    }

    // MARK: - Mouse

    override func mouseMoved(with event: NSEvent) {
        guard snappedRectPx == nil else { return }
        crosshair.set()
        mouseLocation = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        // Double-click inside a snapped selection confirms.
        if event.clickCount >= 2, let snapped = snappedRectPx {
            let loc = convert(event.locationInWindow, from: nil)
            if pixelToView(snapped).contains(loc) {
                confirm()
                return
            }
        }

        // Start a fresh rough drag, discarding any previous selection.
        removePanel()
        snappedRectPx = nil
        roughRectPx = nil
        let loc = convert(event.locationInWindow, from: nil)
        dragStart = loc
        dragCurrent = loc
        isDragging = true
        mouseLocation = nil
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        dragCurrent = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging, let start = dragStart else { return }
        isDragging = false
        let end = convert(event.locationInWindow, from: nil)
        let viewRect = rectFromPoints(start, end)
        dragStart = nil
        dragCurrent = nil

        guard viewRect.width > 3, viewRect.height > 3 else {
            needsDisplay = true
            return
        }

        roughRectPx = viewToPixel(viewRect)
        performSnap()
        window?.invalidateCursorRects(for: self)
        showPanel()
        needsDisplay = true
    }

    // MARK: - Snapping & parameters

    private func performSnap() {
        guard let rough = roughRectPx else { return }
        guard let buffer = luminance else {
            snappedRectPx = rough.intersection(imageBoundsPx).integral
            return
        }
        let bgThreshold = ContentSnapper.threshold(forSensitivity: threshold.rawValue)
        let snapped = ContentSnapper.snap(dragRectPx: rough, in: buffer, threshold: bgThreshold)
        snappedRectPx = snapped.intersection(imageBoundsPx).integral
    }

    private func updateThreshold(_ new: SnapThreshold) {
        threshold = new
        performSnap()
        needsDisplay = true
    }

    private func updateExtend(_ new: Double) {
        extendPx = new
        needsDisplay = true
    }

    // MARK: - Panel

    private func showPanel() {
        removePanel()
        let panel = SnapControlPanel(
            threshold: threshold,
            extendPx: extendPx,
            onThresholdChange: { [weak self] in self?.updateThreshold($0) },
            onExtendChange: { [weak self] in self?.updateExtend($0) },
            onConfirm: { [weak self] in self?.confirm() },
            onCancel: { [weak self] in self?.onCancel() }
        )
        let host = NSHostingView(rootView: panel)
        host.frame.size = host.fittingSize
        addSubview(host)
        panelHost = host
        positionPanel()
    }

    private func positionPanel() {
        guard let host = panelHost, let snapped = snappedRectPx else { return }
        let sel = pixelToView(snapped)
        let size = host.frame.size
        let margin: CGFloat = 12

        var x = sel.midX - size.width / 2
        x = min(max(x, 8), bounds.maxX - size.width - 8)

        // Prefer below the selection; flip above if it would clip off-screen.
        var y = sel.minY - size.height - margin
        if y < 8 {
            y = sel.maxY + margin
        }
        y = min(max(y, 8), bounds.maxY - size.height - 8)

        host.frame.origin = CGPoint(x: x, y: y)
    }

    private func removePanel() {
        panelHost?.removeFromSuperview()
        panelHost = nil
    }

    // MARK: - Confirm / cancel

    private func confirm() {
        guard let crop = finalCropRectPx(),
              let image = frozenImage.cropping(to: crop) else {
            onCancel()
            return
        }
        onConfirm(image)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // esc
            onCancel()
        case 36, 76: // return / keypad enter
            if snappedRectPx != nil {
                confirm()
            }
        default:
            super.keyDown(with: event)
        }
    }

    // MARK: - Helpers

    private func rectFromPoints(_ a: NSPoint, _ b: NSPoint) -> CGRect {
        CGRect(
            x: min(a.x, b.x),
            y: min(a.y, b.y),
            width: abs(b.x - a.x),
            height: abs(b.y - a.y)
        )
    }
}
