import CaptionKit
import SwiftUI

/// Caption placement on the video preview. Drag the caption up or down (anywhere across
/// the band where it sits), or the handle on the position track at the video's right
/// edge. Top, Middle and Bottom are snap points. Clicking the video still plays and
/// pauses it.
///
/// While dragging, the video shows no captions and this view draws the caption itself
/// (rendered once, tightly, at the start) and slides it with the pointer, so it moves
/// smoothly. When the drag ends, the video takes over at the new position.
struct VideoControls: View {
    @Bindable var model: AppModel
    @State private var ghost: Ghost?

    private struct Ghost {
        let block: CaptionRenderer.TextBlock
        /// The vertical position the block was rendered at.
        let vertical: Double
    }
    /// `--hover-controls` (a developer option) shows the position track as if hovered.
    @State private var hovering = CommandLine.arguments.contains("--hover-controls")
    @State private var dragStart: Double?

    private static let space = "video"

    var body: some View {
        GeometryReader { geo in
            let video = CropOverlay.fit(model.previewSize, in: geo.size)
            let track = trackRange(in: video)
            let y = track.lowerBound + (track.upperBound - track.lowerBound) * model.choice.vertical
            ZStack(alignment: .topLeading) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { model.togglePlay() }

                if let ghost { ghostCaption(ghost, video: video) }

                if !model.captions.isEmpty {
                    captionBand(at: y, video: video, track: track)
                    if hovering || dragStart != nil {
                        positionTrack(handleY: y, video: video, track: track)
                            .transition(.opacity)
                    }
                }

            }
            .coordinateSpace(name: Self.space)
            .onHover { inside in withAnimation(.easeOut(duration: 0.15)) { hovering = inside } }
        }
    }

    // MARK: - Caption placement

    /// Where the middle of the caption can go, in view points: from its Top position to its
    /// Bottom one. Estimated from the font size, which is close enough to put the handle by
    /// the text; dragging works on changes, so the estimate doesn't affect accuracy.
    private func trackRange(in video: CGRect) -> ClosedRange<CGFloat> {
        guard model.previewSize.height > 0 else { return video.minY...video.maxY }
        let pointsPerPixel = video.height / model.previewSize.height
        let fontSize = min(model.previewSize.width, model.previewSize.height) * 0.096 * model.choice.scale
        let textHeight = fontSize * 1.25 * pointsPerPixel
        let margin = video.height * 0.07 + textHeight / 2
        let top = video.minY + margin, bottom = video.maxY - margin
        return top...max(bottom, top)
    }

    /// An invisible band across the video where the caption sits. Drag it up or down.
    private func captionBand(at y: CGFloat, video: CGRect, track: ClosedRange<CGFloat>) -> some View {
        let height = max(model.previewSize.height > 0
            ? min(model.previewSize.width, model.previewSize.height) * 0.096 * model.choice.scale
                * 1.6 * video.height / model.previewSize.height
            : 40, 28)
        return Rectangle()
            .fill(.white.opacity(dragStart != nil ? 0.06 : 0.001))
            .frame(width: video.width, height: height)
            .position(x: video.midX, y: y)
            .contentShape(Rectangle())
            .gesture(placementDrag(track: track))
            .onTapGesture { model.togglePlay() }
            .pointerStyle(dragStart == nil ? .grabIdle : .grabActive)
            .help("Drag to move the captions up or down")
    }

    /// Changes in the drag move the text; measured in the video's own coordinates so the
    /// text keeps up with the pointer.
    private func placementDrag(track: ClosedRange<CGFloat>) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(Self.space))
            .onChanged { value in
                if dragStart == nil { beginPlacing() }
                let start = dragStart ?? model.choice.vertical
                let length = max(track.upperBound - track.lowerBound, 1)
                model.choice.vertical = CaptionStyle.snapped(start + value.translation.height / length)
            }
            .onEnded { _ in endPlacing() }
    }

    private func beginPlacing() {
        let start = model.choice.vertical
        dragStart = start
        if let text = model.placementText,
           let block = CaptionRenderer.textBlock(text: text, size: model.previewSize, style: model.style) {
            ghost = Ghost(block: block, vertical: start)
        }
        model.isPlacingCaption = true
    }

    private func endPlacing() {
        dragStart = nil
        model.isPlacingCaption = false
        // Keep the live copy up while the video redraws with the caption, so it doesn't blink.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            if dragStart == nil { ghost = nil }
        }
    }

    /// The live copy of the caption, placed exactly where the video will draw it.
    private func ghostCaption(_ ghost: Ghost, video: CGRect) -> some View {
        let frame = model.previewSize
        let pointsPerPixel = frame.height > 0 ? video.height / frame.height : 1
        let rect = ghost.block.rect(at: model.choice.vertical, from: ghost.vertical)
        let width = rect.width * pointsPerPixel, height = rect.height * pointsPerPixel
        return Image(decorative: ghost.block.image, scale: 1)
            .resizable()
            .frame(width: width, height: height)
            .position(x: video.minX + rect.minX * pointsPerPixel + width / 2,
                      y: video.minY + (frame.height - rect.maxY) * pointsPerPixel + height / 2)
            .allowsHitTesting(false)
    }

    /// The slim track at the right edge: snap dots for Top, Middle and Bottom, and a handle
    /// at the caption's height. Shows the snap point's name while it's on one.
    private func positionTrack(handleY: CGFloat, video: CGRect, track: ClosedRange<CGFloat>) -> some View {
        let x = video.maxX - 24
        let snapped = model.choice.position
        return ZStack(alignment: .topLeading) {
            Capsule()
                .fill(.black.opacity(0.4))
                .overlay(Capsule().strokeBorder(.white.opacity(0.55), lineWidth: 1))
                .frame(width: 8, height: track.upperBound - track.lowerBound + 16)
                .position(x: x, y: (track.lowerBound + track.upperBound) / 2)
            ForEach(CaptionStyle.Position.allCases) { position in
                let dotY = track.lowerBound + (track.upperBound - track.lowerBound) * position.vertical
                Circle()
                    .fill(snapped == position ? Color.yellow : .white.opacity(0.85))
                    .frame(width: 9, height: 9)
                    .position(x: x, y: dotY)
            }
            // The handle: big enough to grab easily, with a larger invisible hit area.
            RoundedRectangle(cornerRadius: 9)
                .fill(Color.yellow)
                .overlay {
                    VStack(spacing: 3) {
                        Image(systemName: "chevron.compact.up")
                        ForEach(0..<3, id: \.self) { _ in
                            Capsule().fill(.black.opacity(0.55)).frame(width: 12, height: 2)
                        }
                        Image(systemName: "chevron.compact.down")
                    }
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(.black.opacity(0.65))
                }
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.black.opacity(0.2)))
                .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
                .frame(width: 28, height: 54)
                .frame(width: 48, height: 74)
                .contentShape(Rectangle())
                .position(x: x, y: handleY)
                .gesture(placementDrag(track: track))
                .pointerStyle(.rowResize)
                .help("Drag to move the captions up or down")
            if let snapped, dragStart != nil {
                Text(snapped.displayName)
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(.regularMaterial, in: Capsule())
                    .fixedSize()
                    .position(x: x - 62, y: handleY)
            }
        }
    }
}

/// The Crop button, pinned to the top-left corner of the video panel. Shows the crop once
/// one is set.
struct CropButton: View {
    @Bindable var model: AppModel

    private var cropTitle: String {
        if model.crop.isFull { return "Crop" }
        if model.cropAspect != .free { return "Crop \(model.cropAspect.displayName)" }
        let px = model.crop.pixelRect(in: model.frameSize)
        return "Crop \(Int(px.width))×\(Int(px.height))"
    }

    var body: some View {
        Button { model.startCropping() } label: {
            Label(cropTitle, systemImage: "crop")
                .font(.callout.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.25)))
        }
        .buttonStyle(.plain)
        .fixedSize()
        .disabled(model.isBusy)
        .help("Crop the video, for example to 9:16 for Stories or 1:1")
    }
}
