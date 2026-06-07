import AppKit
import SwiftUI

/// Floating parameter panel shown next to the snapped selection.
/// - Threshold: PixelSnap-style small/medium/large segments → re-snaps.
/// - Extend: 0–64 pt slider (also scroll-wheel) → live padding preview.
/// Drives the overlay through callbacks; it does not observe back.
struct SnapControlPanel: View {
    @State private var threshold: SnapThreshold
    @State private var extendPx: Double

    let onThresholdChange: (SnapThreshold) -> Void
    let onExtendChange: (Double) -> Void
    let onConfirm: () -> Void
    let onCancel: () -> Void

    static let extendRange: ClosedRange<Double> = 0...64

    init(
        threshold: SnapThreshold,
        extendPx: Double,
        onThresholdChange: @escaping (SnapThreshold) -> Void,
        onExtendChange: @escaping (Double) -> Void,
        onConfirm: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        _threshold = State(initialValue: threshold)
        _extendPx = State(initialValue: extendPx)
        self.onThresholdChange = onThresholdChange
        self.onExtendChange = onExtendChange
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("", selection: $threshold) {
                Text("Small").tag(SnapThreshold.small)
                Text("Medium").tag(SnapThreshold.medium)
                Text("Large").tag(SnapThreshold.large)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: threshold) { _, new in onThresholdChange(new) }

            HStack(spacing: 8) {
                Image(systemName: "arrow.left.and.right.square")
                    .foregroundStyle(.secondary)
                Slider(value: $extendPx, in: Self.extendRange, step: 1)
                    .onChange(of: extendPx) { _, new in onExtendChange(new) }
                Text("\(Int(extendPx))px")
                    .font(.system(.caption, design: .monospaced))
                    .frame(width: 36, alignment: .trailing)
            }
            .background(SnapScrollWheelView { delta in
                let next = min(max(extendPx + delta, Self.extendRange.lowerBound), Self.extendRange.upperBound)
                if next != extendPx {
                    extendPx = next
                    onExtendChange(next)
                }
            })

            HStack {
                Text("⏎ Capture · esc Cancel")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", action: onCancel)
                    .controlSize(.small)
                Button("Capture", action: onConfirm)
                    .controlSize(.small)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .frame(width: 280)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
        )
    }
}

// MARK: - Scroll-wheel capture (mirrors PinnedScreenshot's pattern)

private struct SnapScrollWheelView: NSViewRepresentable {
    let handler: (CGFloat) -> Void

    func makeNSView(context: Context) -> _SnapScrollWheelNSView {
        let v = _SnapScrollWheelNSView()
        v.handler = handler
        return v
    }

    func updateNSView(_ nsView: _SnapScrollWheelNSView, context: Context) {
        nsView.handler = handler
    }
}

final class _SnapScrollWheelNSView: NSView {
    var handler: ((CGFloat) -> Void)?

    override func scrollWheel(with event: NSEvent) {
        handler?(event.deltaY)
    }
}
