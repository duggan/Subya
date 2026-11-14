import CaptionKit
import SwiftUI

/// A track under the video with one block per caption. Drag a block to move it, drag its
/// edges to change when it starts or ends, click it to jump there and edit its text, and
/// click or drag the empty track to scrub. While dragging, the preview follows the edge
/// being moved, so text can be lined up with a frame.
struct CaptionTimeline: View {
    @Bindable var model: AppModel
    @State private var drag: Drag?

    private struct Drag {
        enum Kind { case move, start, end }
        let id: Caption.ID
        let kind: Kind
        let start: Double
        let end: Double
    }

    private let height: CGFloat = 40
    private let handleWidth: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let scale = geo.size.width / max(model.duration, 0.1)  // points per second
            ZStack(alignment: .topLeading) {
                track(scale: scale)
                ForEach(model.captions) { cap in
                    block(cap, scale: scale)
                }
                playhead(scale: scale, height: geo.size.height)
            }
        }
        .frame(height: height)
    }

    // MARK: - Track

    private func track(scale: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(.quaternary.opacity(0.6))
            .overlay(alignment: .topLeading) { ticks(scale: scale) }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                model.player?.pause()
                model.seek(to: min(max(value.location.x / scale, 0), model.duration))
            })
            .help("Click or drag to scrub")
    }

    /// Faint second marks, thinned out so they stay at least 12 points apart.
    private func ticks(scale: CGFloat) -> some View {
        let step = [1.0, 2, 5, 10, 15, 30, 60, 120, 300].first { $0 * scale >= 12 } ?? 600
        let count = Int(model.duration / step)
        return ZStack(alignment: .topLeading) {
            ForEach(0...max(count, 0), id: \.self) { i in
                Rectangle()
                    .fill(.secondary.opacity(0.25))
                    .frame(width: 1, height: 6)
                    .offset(x: CGFloat(Double(i) * step) * scale)
            }
        }
    }

    private func playhead(scale: CGFloat, height: CGFloat) -> some View {
        Rectangle()
            .fill(Color.red)
            .frame(width: 2, height: height)
            .offset(x: min(max(model.currentTime, 0), model.duration) * scale - 1)
            .allowsHitTesting(false)
    }

    // MARK: - Blocks

    private func block(_ cap: Caption, scale: CGFloat) -> some View {
        let showing = model.currentTime >= cap.start && model.currentTime < cap.end
        let width = max((cap.end - cap.start) * scale, 6)
        return RoundedRectangle(cornerRadius: 5)
            .fill(Color.accentColor.opacity(showing || drag?.id == cap.id ? 0.95 : 0.6))
            .overlay {
                RoundedRectangle(cornerRadius: 5).strokeBorder(.white.opacity(showing ? 0.8 : 0.25), lineWidth: 1)
            }
            .overlay(alignment: .leading) {
                Text(cap.text.isEmpty ? "…" : cap.text)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, handleWidth)
                    .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
            .gesture(dragGesture(cap, kind: .move, scale: scale))
            .pointerStyle(drag?.id == cap.id && drag?.kind == .move ? .grabActive : .grabIdle)
            .overlay(alignment: .leading) { handle(cap, kind: .start, scale: scale) }
            .overlay(alignment: .trailing) { handle(cap, kind: .end, scale: scale) }
            .frame(width: width, height: height - 8)
            .offset(x: cap.start * scale, y: 4)
            .help(cap.text.isEmpty ? "Empty line" : cap.text)
    }

    private func handle(_ cap: Caption, kind: Drag.Kind, scale: CGFloat) -> some View {
        Rectangle()
            .fill(.white.opacity(0.001))
            .overlay {
                Capsule().fill(.white.opacity(0.7)).frame(width: 2, height: 12)
            }
            .frame(width: handleWidth)
            .contentShape(Rectangle())
            .gesture(dragGesture(cap, kind: kind, scale: scale))
            .pointerStyle(.columnResize)
    }

    // MARK: - Dragging

    private func dragGesture(_ cap: Caption, kind: Drag.Kind, scale: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if drag == nil {
                    model.player?.pause()
                    drag = Drag(id: cap.id, kind: kind, start: cap.start, end: cap.end)
                }
                guard let drag else { return }
                let delta = value.translation.width / scale
                switch drag.kind {
                case .move: model.moveCaption(drag.id, toStart: drag.start + delta)
                case .start: model.setEdge(.start, of: drag.id, to: drag.start + delta)
                case .end: model.setEdge(.end, of: drag.id, to: drag.end + delta)
                }
            }
            .onEnded { value in
                // A click without movement selects the caption: jump there and edit its text.
                if abs(value.translation.width) < 2, let drag {
                    model.select(drag.id)
                }
                drag = nil
            }
    }
}
