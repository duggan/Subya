import CaptionKit
import SwiftUI

/// A track under the video with one block per caption. Drag a block to move it, drag its
/// edges to change when it starts or ends, click it to jump there and edit its text, and
/// click or drag the empty track to scrub. While dragging, the preview follows the edge
/// being moved, so text can be lined up with a frame.
///
/// In one-word display, each block is split into its words: drag the divider between two
/// words to change when the second appears, and click a word to jump to it.
///
/// The timeline zooms (`AppModel.timelineZoom`, pinch, or View › Zoom In/Out) and then
/// scrolls sideways, following the playhead. A ruler above the blocks shows the time.
struct CaptionTimeline: View {
    @Bindable var model: AppModel
    @State private var drag: Drag?

    private struct Drag {
        enum Kind: Equatable { case move, start, end, word(Int) }
        let id: Caption.ID
        let kind: Kind
        let start: Double
        let end: Double
        /// For `.word`, the dragged word's start when the drag began.
        var wordStart: Double = 0
    }

    private var wordMode: Bool { model.style.display == .word }

    /// Height of the caption blocks' lane; the ruler sits above it.
    private let height: CGFloat = 40
    private let rulerHeight: CGFloat = 14
    private let handleWidth: CGFloat = 8

    @State private var scrollPosition = ScrollPosition()
    @State private var offsetX: CGFloat = 0
    @State private var visibleWidth: CGFloat = 0
    @State private var pinchStart: Double?

    var body: some View {
        GeometryReader { geo in
            let contentWidth = geo.size.width * model.timelineZoom
            let scale = contentWidth / max(model.duration, 0.1)  // points per second
            ScrollView(.horizontal) {
                ZStack(alignment: .topLeading) {
                    ruler(scale: scale, width: contentWidth)
                    track(scale: scale)
                        .frame(width: contentWidth, height: height)
                        .offset(y: rulerHeight)
                    ForEach(model.captions) { cap in
                        block(cap, scale: scale)
                    }
                    playhead(scale: scale, height: rulerHeight + height)
                }
                .frame(width: contentWidth, height: rulerHeight + height, alignment: .topLeading)
            }
            .scrollIndicators(model.timelineZoom > 1.01 ? .visible : .hidden)
            .scrollPosition($scrollPosition)
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.x } action: { _, x in offsetX = x }
            .onAppear { visibleWidth = geo.size.width }
            .onChange(of: geo.size.width) { _, width in visibleWidth = width }
            .onChange(of: model.currentTime) { _, time in follow(time, scale: scale, contentWidth: contentWidth) }
            .onChange(of: model.timelineZoom) { old, new in
                keepAnchored(oldZoom: old, newZoom: new, width: geo.size.width)
            }
            .simultaneousGesture(MagnifyGesture()
                .onChanged { value in
                    if pinchStart == nil { pinchStart = model.timelineZoom }
                    model.setTimelineZoom((pinchStart ?? 1) * value.magnification)
                }
                .onEnded { _ in pinchStart = nil })
        }
        .frame(height: rulerHeight + height + (model.timelineZoom > 1.01 ? 10 : 0))
    }

    // MARK: - Zoom and scrolling

    /// Keeps the playhead in view while it moves (playing or seeking), unless a block is
    /// being dragged. When it leaves the view, scroll so it sits a quarter of the way in.
    private func follow(_ time: Double, scale: CGFloat, contentWidth: CGFloat) {
        guard drag == nil, model.timelineZoom > 1.01, visibleWidth > 0 else { return }
        let x = time * scale
        guard x < offsetX + 8 || x > offsetX + visibleWidth - 8 else { return }
        scrollPosition.scrollTo(x: clampedOffset(x - visibleWidth * 0.25, contentWidth: contentWidth))
    }

    /// Zooming keeps the playhead at the same place on screen (or, if it's out of view,
    /// the middle of the view).
    private func keepAnchored(oldZoom: Double, newZoom: Double, width: CGFloat) {
        let oldScale = width * oldZoom / max(model.duration, 0.1)
        let newScale = width * newZoom / max(model.duration, 0.1)
        let playX = model.currentTime * oldScale
        let onScreen = playX >= offsetX && playX <= offsetX + width
        let anchorTime = onScreen ? model.currentTime : (offsetX + width / 2) / oldScale
        let screenX = anchorTime * oldScale - offsetX
        let target = clampedOffset(anchorTime * newScale - screenX, contentWidth: width * newZoom)
        scrollPosition.scrollTo(x: target)
    }

    private func clampedOffset(_ x: CGFloat, contentWidth: CGFloat) -> CGFloat {
        min(max(x, 0), max(contentWidth - visibleWidth, 0))
    }

    // MARK: - Ruler and track

    /// Time labels, spaced at least 60 points apart, with minor ticks between. Click or
    /// drag it to scrub, like the empty track.
    private func ruler(scale: CGFloat, width: CGFloat) -> some View {
        let steps: [Double] = [0.1, 0.2, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600]
        let major = steps.first { $0 * scale >= 60 } ?? 1200
        let minor = steps.last { $0 < major && $0 * scale >= 10 } ?? major
        let minorCount = Int(model.duration / minor)
        return ZStack(alignment: .topLeading) {
            Rectangle().fill(.clear)
            ForEach(0...max(minorCount, 0), id: \.self) { i in
                let t = Double(i) * minor
                let isMajor = abs((t / major).rounded() - t / major) < 0.001
                Rectangle()
                    .fill(.secondary.opacity(isMajor ? 0.6 : 0.3))
                    .frame(width: 1, height: isMajor ? 6 : 3)
                    .offset(x: t * scale, y: rulerHeight - (isMajor ? 6 : 3))
                if isMajor {
                    Text(Self.label(t, step: major))
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .offset(x: t * scale + 3, y: -1)
                }
            }
        }
        .frame(width: width, height: rulerHeight, alignment: .topLeading)
        .contentShape(Rectangle())
        .gesture(scrubGesture(scale: scale))
    }

    private static func label(_ t: Double, step: Double) -> String {
        let minutes = Int(t) / 60
        let seconds = t - Double(minutes * 60)
        return step < 1 ? String(format: "%d:%04.1f", minutes, seconds) : String(format: "%d:%02d", minutes, Int(seconds))
    }

    private func track(scale: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(.quaternary.opacity(0.6))
            .contentShape(Rectangle())
            .gesture(scrubGesture(scale: scale))
            .help("Click or drag to scrub")
    }

    private func scrubGesture(scale: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0).onChanged { value in
            model.player?.pause()
            model.seek(to: min(max(value.location.x / scale, 0), model.duration))
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
                    .opacity(wordMode && !cap.timedWords.isEmpty ? 0 : 1)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, handleWidth)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .topLeading) {
                if wordMode { words(cap, scale: scale) }
            }
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
            .gesture(dragGesture(cap, kind: .move, scale: scale))
            .pointerStyle(drag?.id == cap.id && drag?.kind == .move ? .grabActive : .grabIdle)
            .overlay(alignment: .leading) { handle(cap, kind: .start, scale: scale) }
            .overlay(alignment: .trailing) { handle(cap, kind: .end, scale: scale) }
            .frame(width: width, height: height - 8)
            .offset(x: cap.start * scale, y: rulerHeight + 4)
            .help(cap.text.isEmpty ? "Empty line" : cap.text)
    }

    /// The caption's words as segments, with a draggable divider before each word but the
    /// first. The word on screen is highlighted.
    private func words(_ cap: Caption, scale: CGFloat) -> some View {
        let words = cap.timedWords
        return ZStack(alignment: .topLeading) {
            ForEach(Array(words.enumerated()), id: \.offset) { i, word in
                let x = (word.start - cap.start) * scale
                let width = max((word.end - word.start) * scale, 1)
                let current = model.currentTime >= word.start && model.currentTime < word.end
                ZStack {
                    Rectangle().fill(.white.opacity(current ? 0.3 : 0))
                    if width > 9 {
                        Text(word.text)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .padding(.horizontal, 1)
                    }
                }
                .frame(width: width, height: height - 8)
                .offset(x: x)
                .allowsHitTesting(false)
                if i > 0 {
                    wordDivider(cap, index: i, scale: scale)
                        .offset(x: x - handleWidth / 2)
                }
            }
        }
    }

    private func wordDivider(_ cap: Caption, index: Int, scale: CGFloat) -> some View {
        Rectangle()
            .fill(.white.opacity(0.001))
            .overlay { Rectangle().fill(.white.opacity(0.55)).frame(width: 1) }
            .frame(width: handleWidth, height: height - 8)
            .contentShape(Rectangle())
            .gesture(dragGesture(cap, kind: .word(index), scale: scale))
            .pointerStyle(.columnResize)
            .help("Drag to change when this word appears")
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
                    var newDrag = Drag(id: cap.id, kind: kind, start: cap.start, end: cap.end)
                    if case .word(let i) = kind, cap.timedWords.indices.contains(i) {
                        newDrag.wordStart = cap.timedWords[i].start
                    }
                    drag = newDrag
                }
                guard let drag else { return }
                let delta = value.translation.width / scale
                switch drag.kind {
                case .move: model.moveCaption(drag.id, toStart: drag.start + delta)
                case .start: model.setEdge(.start, of: drag.id, to: drag.start + delta)
                case .end: model.setEdge(.end, of: drag.id, to: drag.end + delta)
                case .word(let i): model.setWordStart(i, of: drag.id, to: drag.wordStart + delta)
                }
            }
            .onEnded { value in
                // A click without movement selects the caption: jump there and edit its text.
                // In one-word display, clicking a word jumps to that word.
                if abs(value.translation.width) < 2, let drag {
                    let clicked = drag.start + value.startLocation.x / scale
                    let word = wordMode && drag.kind == .move
                        ? cap.timedWords.last { clicked >= $0.start }?.start : nil
                    model.select(drag.id, at: word)
                }
                drag = nil
            }
    }
}
