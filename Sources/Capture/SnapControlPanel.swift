import AppKit
import SwiftUI

/// Floating parameter panel shown next to the snapped selection.
/// - Snap: PixelSnap-style small/medium/large sensitivity → re-snaps.
/// - Margin: 0–64 pt even padding, 4pt steps, slider + scroll-wheel + manual entry.
/// Drives the overlay through callbacks; it does not observe back.
struct SnapControlPanel: View {
    @State private var threshold: SnapThreshold
    @State private var extendPx: Double

    let onThresholdChange: (SnapThreshold) -> Void
    let onExtendChange: (Double) -> Void
    let onConfirm: () -> Void
    let onCancel: () -> Void

    static let extendRange: ClosedRange<Double> = 0...64
    static let extendStep: Double = 4
    static let minimumContentWidth: CGFloat = 276

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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                rowLabel("Snap")
                Picker("Snap sensitivity", selection: $threshold) {
                    Text("Off").tag(SnapThreshold.off)
                    Text("Small").tag(SnapThreshold.small)
                    Text("Medium").tag(SnapThreshold.medium)
                    Text("Large").tag(SnapThreshold.large)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: .infinity)
            }
            // The native segmented control never shrinks below its intrinsic width,
            // which varies with the control's live glass styling, so this row sets
            // the panel width and the other rows stretch to it.
            .frame(minWidth: Self.minimumContentWidth)
            .help("Snap strength — Large snaps to fainter edges, Small only to crisp ones")

            InspectorSlider("Margin", value: Binding(
                get: { CGFloat(extendPx) }, set: { extendPx = Double($0) }
            ), range: 0...64, format: .points, trackStep: 4)
            .help("Even padding added around the snapped area")
            .background(SnapScrollWheelView { delta in
                let dir = delta > 0 ? Self.extendStep : -Self.extendStep
                extendPx = (extendPx + dir).clampedToExtend
            })

            HStack {
                Text("⏎ Capture · esc Cancel")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", action: onCancel)
                    .controlSize(.small)
                    .keyboardShortcut(.cancelAction)
                Button("Capture", action: onConfirm)
                    .controlSize(.small)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
        )
        .onChange(of: threshold) { _, new in onThresholdChange(new) }
        .onChange(of: extendPx) { _, new in
            // Single place that clamps + forwards, so slider / wheel / text entry
            // never double-fire the callback.
            let clamped = new.clampedToExtend
            if clamped != new {
                extendPx = clamped // re-enters with the clamped value
            } else {
                onExtendChange(clamped)
            }
        }
    }

    @ViewBuilder
    private func rowLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(width: 52, alignment: .leading)
    }
}

private extension Double {
    var clampedToExtend: Double {
        Swift.min(Swift.max(self, SnapControlPanel.extendRange.lowerBound), SnapControlPanel.extendRange.upperBound)
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
