import SwiftUI
import UndertoneCore

struct Scrubber: View {
    @Environment(PlayerEngine.self) private var engine
    @State private var dragValue: Double?

    var body: some View {
        let duration = engine.duration ?? 0
        let shown = dragValue ?? min(engine.currentTime, max(duration, 0))
        VStack(spacing: 2) {
            Slider(
                value: Binding(get: { shown }, set: { dragValue = $0 }),
                in: 0...max(duration, 1),
                onEditingChanged: { editing in
                    if !editing, let value = dragValue {
                        engine.seek(to: value)
                        dragValue = nil
                    }
                }
            )
            .controlSize(.small)
            .disabled(duration <= 0 || engine.isResolving)
            .overlay(alignment: .bottom) {
                ChapterTicks(starts: engine.track?.chapters.map(\.start) ?? [], duration: duration)
                    .offset(y: 4)
            }
            HStack {
                Text(TimeFormat.clock(shown))
                Spacer()
                if engine.isBuffering && !engine.isResolving {
                    Text("Buffering…")
                }
                Spacer()
                Text(TimeFormat.remaining(shown, of: duration))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }
}

/// A short tick under the scrubber track at each chapter start (the first, at 0:00, is the track's own start).
private struct ChapterTicks: View {
    let starts: [Double]
    let duration: Double
    /// Where a small slider's track begins and ends inside its frame: half the knob's width.
    private let trackInset: CGFloat = 9

    var body: some View {
        if duration > 0, starts.count > 1 {
            GeometryReader { geo in
                let width = geo.size.width - trackInset * 2
                ForEach(Array(starts.enumerated()), id: \.offset) { _, start in
                    if start > 0, start < duration {
                        Capsule()
                            .fill(.tertiary)
                            .frame(width: 1.5, height: 4)
                            .position(x: trackInset + width * start / duration, y: 2)
                    }
                }
            }
            .frame(height: 4)
            .allowsHitTesting(false)
        }
    }
}
