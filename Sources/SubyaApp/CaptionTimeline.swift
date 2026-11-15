import AVFoundation
import CaptionKit
import SwiftUI

/// The caption timeline under the video, in the spirit of Photos' trim bar: a filmstrip of
/// the video, one see-through block per caption, and a white playhead. Click a caption to
/// select it (yellow frame with chevron grips) and jump there; drag it to move it, drag its
/// edges to retime it; click or drag the filmstrip to scrub. While dragging, the preview
/// follows the edge being moved, so text can be lined up with a frame.
///
/// In one-word display, each block is split into its words: drag the divider between two
/// words to change when the second appears, and click a word to jump to it.
///
/// The timeline zooms (`AppModel.timelineZoom`, pinch, or View › Zoom In/Out) and then
/// scrolls sideways, following the playhead. A ruler above the blocks shows the time.
///
/// For responsiveness, only `TimelinePlayhead` reads the playhead time (which changes 30
/// times a second); blocks read `currentCaptionID`/`currentWordIndex`, and the filmstrip
/// is its own view with its own model, so thumbnails arriving don't re-render the blocks.
struct CaptionTimeline: View {
    @Bindable var model: AppModel
    @State private var drag: Drag?
    @State private var filmstrip = Filmstrip()

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

    /// Drags are measured in the timeline's own coordinates. Measuring them in the dragged
    /// view's coordinates made grips and blocks lag behind the pointer: the view moves as
    /// the caption changes, so each step partly undid the last.
    private static let space = "timeline"

    /// Height of the filmstrip lane the blocks sit on; the ruler sits above it.
    private let lane: CGFloat = 48
    private let rulerHeight: CGFloat = 14
    private let gripWidth: CGFloat = 12

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
                    FilmstripView(filmstrip: filmstrip, frameSize: model.frameSize, duration: model.duration,
                                  scale: scale, contentWidth: contentWidth, height: lane,
                                  visibleRange: offsetX...(offsetX + max(visibleWidth, geo.size.width)))
                        .frame(width: contentWidth, height: lane)
                        .contentShape(Rectangle())
                        .gesture(scrubGesture(scale: scale))
                        .help("Click or drag to scrub")
                        .offset(y: rulerHeight)
                    ForEach(model.captions) { cap in
                        block(cap, scale: scale)
                    }
                    TimelinePlayhead(model: model, scale: scale, height: rulerHeight + lane,
                                     contentWidth: contentWidth, offsetX: offsetX,
                                     visibleWidth: visibleWidth, isDragging: drag != nil,
                                     scrollPosition: $scrollPosition)
                }
                .frame(width: contentWidth, height: rulerHeight + lane, alignment: .topLeading)
                .coordinateSpace(name: Self.space)
            }
            .scrollIndicators(model.timelineZoom > 1.01 ? .visible : .hidden)
            .scrollPosition($scrollPosition)
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.x } action: { _, x in offsetX = x }
            .onAppear {
                visibleWidth = geo.size.width
                filmstrip.load(model.asset, height: lane)
            }
            .onChange(of: model.videoURL) { filmstrip.load(model.asset, height: lane) }
            .onChange(of: geo.size.width) { _, width in visibleWidth = width }
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
        .frame(height: rulerHeight + lane + (model.timelineZoom > 1.01 ? 10 : 0))
    }

    // MARK: - Zoom

    /// Zooming keeps the playhead at the same place on screen (or, if it's out of view,
    /// the middle of the view).
    private func keepAnchored(oldZoom: Double, newZoom: Double, width: CGFloat) {
        let oldScale = width * oldZoom / max(model.duration, 0.1)
        let newScale = width * newZoom / max(model.duration, 0.1)
        let playX = model.currentTime * oldScale
        let onScreen = playX >= offsetX && playX <= offsetX + width
        let anchorTime = onScreen ? model.currentTime : (offsetX + width / 2) / oldScale
        let screenX = anchorTime * oldScale - offsetX
        let contentWidth = width * newZoom
        let target = min(max(anchorTime * newScale - screenX, 0), max(contentWidth - width, 0))
        scrollPosition.scrollTo(x: target)
    }

    // MARK: - Ruler and scrubbing

    /// Time labels, spaced at least 60 points apart, with minor ticks between. Click or
    /// drag it to scrub, like the filmstrip.
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

    private func scrubGesture(scale: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0).onChanged { value in
            model.player?.pause()
            model.seek(to: min(max(value.location.x / scale, 0), model.duration))
        }
    }

    // MARK: - Blocks

    private func block(_ cap: Caption, scale: CGFloat) -> some View {
        let showing = model.currentCaptionID == cap.id
        let selected = model.selectedCaptionID == cap.id
        let width = max((cap.end - cap.start) * scale, 6)
        let showText = !(wordMode && !cap.timedWords.isEmpty)
        return RoundedRectangle(cornerRadius: 6)
            .fill(Color.accentColor.opacity(selected ? 0.28 : showing ? 0.5 : 0.38))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(.white.opacity(showing ? 0.9 : 0.35), lineWidth: showing ? 1.5 : 1)
            }
            .overlay(alignment: .leading) {
                if showText {
                    Text(cap.text.isEmpty ? "…" : cap.text)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.8), radius: 2)
                        .lineLimit(1)
                        .padding(.horizontal, gripWidth + 2)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .topLeading) {
                if wordMode { words(cap, scale: scale) }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .gesture(dragGesture(cap, kind: .move, scale: scale))
            .pointerStyle(drag?.id == cap.id && drag?.kind == .move ? .grabActive : .grabIdle)
            .overlay { if selected { selectionFrame } }
            .overlay(alignment: .leading) { grip(cap, kind: .start, selected: selected, scale: scale) }
            .overlay(alignment: .trailing) { grip(cap, kind: .end, selected: selected, scale: scale) }
            .frame(width: width, height: lane - 4)
            .offset(x: cap.start * scale, y: rulerHeight + 2)
            .help(cap.text.isEmpty ? "Empty line" : cap.text)
    }

    /// The yellow frame around the selected caption, as in Photos' trim bar.
    private var selectionFrame: some View {
        RoundedRectangle(cornerRadius: 6)
            .strokeBorder(Color.yellow, lineWidth: 3)
            .allowsHitTesting(false)
    }

    /// Edge handles. On the selected caption they're chunky yellow grips with a chevron;
    /// on the others they're invisible but still draggable.
    private func grip(_ cap: Caption, kind: Drag.Kind, selected: Bool, scale: CGFloat) -> some View {
        let leading = kind == .start
        return ZStack {
            if selected {
                UnevenRoundedRectangle(topLeadingRadius: leading ? 6 : 0, bottomLeadingRadius: leading ? 6 : 0,
                                       bottomTrailingRadius: leading ? 0 : 6, topTrailingRadius: leading ? 0 : 6)
                    .fill(Color.yellow)
                Image(systemName: leading ? "chevron.compact.left" : "chevron.compact.right")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(.black.opacity(0.75))
            } else {
                Rectangle().fill(.white.opacity(0.001))
            }
        }
        .frame(width: gripWidth)
        .contentShape(Rectangle())
        .gesture(dragGesture(cap, kind: kind, scale: scale))
        .pointerStyle(.columnResize)
    }

    /// The caption's words as segments, with a draggable divider before each word but the
    /// first. The word on screen is highlighted.
    private func words(_ cap: Caption, scale: CGFloat) -> some View {
        let words = cap.timedWords
        let currentWord = model.currentCaptionID == cap.id ? model.currentWordIndex : nil
        return ZStack(alignment: .topLeading) {
            ForEach(Array(words.enumerated()), id: \.offset) { i, word in
                let x = (word.start - cap.start) * scale
                let width = max((word.end - word.start) * scale, 1)
                ZStack {
                    Rectangle().fill(.white.opacity(currentWord == i ? 0.3 : 0))
                    if width > 9 {
                        Text(word.text)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.8), radius: 2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .padding(.horizontal, 1)
                    }
                }
                .frame(width: width, height: lane - 4)
                .offset(x: x)
                .allowsHitTesting(false)
                if i > 0 {
                    wordDivider(cap, index: i, scale: scale)
                        .offset(x: x - 4)
                }
            }
        }
    }

    private func wordDivider(_ cap: Caption, index: Int, scale: CGFloat) -> some View {
        Rectangle()
            .fill(.white.opacity(0.001))
            .overlay { Rectangle().fill(.white.opacity(0.6)).frame(width: 1) }
            .frame(width: 8, height: lane - 4)
            .contentShape(Rectangle())
            .gesture(dragGesture(cap, kind: .word(index), scale: scale))
            .pointerStyle(.columnResize)
            .help("Drag to change when this word appears")
    }

    // MARK: - Dragging

    private func dragGesture(_ cap: Caption, kind: Drag.Kind, scale: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
            .onChanged { value in
                if drag == nil {
                    model.player?.pause()
                    model.selectedCaptionID = cap.id
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
                    let clicked = value.startLocation.x / scale
                    let word = wordMode && drag.kind == .move
                        ? cap.timedWords.last { clicked >= $0.start }?.start : nil
                    model.select(drag.id, at: word)
                }
                drag = nil
            }
    }
}

// MARK: - Playhead

/// The white playhead, as in Photos. The only part of the timeline that reads the
/// playhead time, so it alone re-renders as the video plays. It also keeps itself in view
/// when zoomed: when it leaves the view (and nothing's being dragged), the timeline
/// scrolls so it sits a quarter of the way in.
private struct TimelinePlayhead: View {
    @Bindable var model: AppModel
    let scale: CGFloat
    let height: CGFloat
    let contentWidth: CGFloat
    let offsetX: CGFloat
    let visibleWidth: CGFloat
    let isDragging: Bool
    @Binding var scrollPosition: ScrollPosition

    var body: some View {
        let x = min(max(model.currentTime, 0), model.duration) * scale
        VStack(spacing: 0) {
            Capsule()
                .fill(.white)
                .frame(width: 9, height: 9)
            RoundedRectangle(cornerRadius: 1.5)
                .fill(.white)
                .frame(width: 3, height: height - 6)
                .offset(y: -3)
        }
        .shadow(color: .black.opacity(0.5), radius: 2)
        .offset(x: x - 4.5)
        .allowsHitTesting(false)
        .onChange(of: model.currentTime) { _, time in follow(time) }
    }

    private func follow(_ time: Double) {
        guard !isDragging, model.timelineZoom > 1.01, visibleWidth > 0 else { return }
        let x = time * scale
        guard x < offsetX + 8 || x > offsetX + visibleWidth - 8 else { return }
        let target = min(max(x - visibleWidth * 0.25, 0), max(contentWidth - visibleWidth, 0))
        scrollPosition.scrollTo(x: target)
    }
}

// MARK: - Filmstrip

/// Video thumbnails for the timeline, made on demand for the part that's visible.
/// Frames are keyed by time in milliseconds; a newer request cancels an older one.
@MainActor @Observable
final class Filmstrip {
    private(set) var images: [Int: CGImage] = [:]
    @ObservationIgnored private var generator: AVAssetImageGenerator?
    @ObservationIgnored private weak var asset: AVAsset?
    @ObservationIgnored private var task: Task<Void, Never>?

    func load(_ asset: AVAsset?, height: CGFloat) {
        guard asset !== self.asset else { return }
        task?.cancel()
        images = [:]
        self.asset = asset
        generator = asset.map {
            let generator = AVAssetImageGenerator(asset: $0)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 0, height: height * 2)  // Retina
            return generator
        }
    }

    /// Makes any missing frames for `times` (milliseconds), close enough within `tolerance`
    /// seconds, which makes generation much faster than exact frames.
    func request(_ times: [Int], tolerance: Double) {
        guard let generator else { return }
        let missing = times.filter { images[$0] == nil }
        guard !missing.isEmpty else { return }
        task?.cancel()
        let window = CMTime(seconds: tolerance, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = window
        generator.requestedTimeToleranceAfter = window
        task = Task { [weak self] in
            for await result in generator.images(for: missing.map { CMTime(value: Int64($0), timescale: 1000) }) {
                if Task.isCancelled { break }
                guard let image = try? result.image else { continue }
                let requested = result.requestedTime
                self?.images[Int((requested.seconds * 1000).rounded())] = image
            }
        }
    }

    /// The frame for `ms`, or the nearest one made so far within `within` ms, so zooming
    /// shows something straight away while the exact frames are made.
    func image(near ms: Int, within: Int) -> CGImage? {
        if let exact = images[ms] { return exact }
        var best: (distance: Int, image: CGImage)?
        for (key, image) in images {
            let distance = abs(key - ms)
            if distance <= within, distance < (best?.distance ?? .max) { best = (distance, image) }
        }
        return best?.image
    }
}

/// The thumbnails behind the caption blocks: tiles the height of the lane, in the video's
/// shape, laid across the timeline. Only the visible tiles (plus a couple either side)
/// are drawn and requested.
private struct FilmstripView: View {
    let filmstrip: Filmstrip
    let frameSize: CGSize
    let duration: Double
    let scale: CGFloat
    let contentWidth: CGFloat
    let height: CGFloat
    let visibleRange: ClosedRange<CGFloat>

    private var tileWidth: CGFloat {
        guard frameSize.height > 0 else { return height * 16 / 9 }
        return max(height * frameSize.width / frameSize.height, 16)
    }

    private var tiles: Range<Int> {
        guard contentWidth > 0 else { return 0..<0 }
        let count = Int((contentWidth / tileWidth).rounded(.up))
        let first = max(Int(visibleRange.lowerBound / tileWidth) - 2, 0)
        let last = min(Int(visibleRange.upperBound / tileWidth) + 2, count)
        return first..<max(last, first)
    }

    /// The time (ms) a tile shows: its middle.
    private func time(of tile: Int) -> Int {
        let seconds = min((CGFloat(tile) + 0.5) * tileWidth / max(scale, 0.001), duration)
        return Int((seconds * 1000).rounded())
    }

    var body: some View {
        let span = Int(tileWidth / max(scale, 0.001) * 1000)
        ZStack(alignment: .topLeading) {
            Rectangle().fill(.quaternary.opacity(0.6))
            ForEach(tiles, id: \.self) { tile in
                if let image = filmstrip.image(near: time(of: tile), within: span) {
                    Image(decorative: image, scale: 2)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: tileWidth, height: height)
                        .clipped()
                        .offset(x: CGFloat(tile) * tileWidth)
                }
            }
        }
        .frame(width: contentWidth, height: height, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .task(id: RequestKey(tiles: tiles, tileWidth: tileWidth, scale: scale)) {
            filmstrip.request(tiles.map(time(of:)), tolerance: Double(tileWidth / max(scale, 0.001)) / 2)
        }
    }

    private struct RequestKey: Equatable {
        let tiles: Range<Int>
        let tileWidth: CGFloat
        let scale: CGFloat
    }
}
