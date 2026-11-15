import CaptionKit
import SwiftUI

/// Drawn over the preview while editing the crop: the whole frame, dimmed outside the
/// crop, with a rule-of-thirds grid. Drag inside the crop to move it, or a corner to
/// resize it (keeping the chosen shape).
struct CropOverlay: View {
    @Bindable var model: AppModel
    @State private var dragStart: Crop?

    private let handleSize: CGFloat = 16

    var body: some View {
        GeometryReader { geo in
            let video = Self.fit(model.frameSize, in: geo.size)
            let r = CGRect(x: video.minX + model.crop.rect.minX * video.width,
                           y: video.minY + model.crop.rect.minY * video.height,
                           width: model.crop.rect.width * video.width,
                           height: model.crop.rect.height * video.height)
            ZStack(alignment: .topLeading) {
                Path { path in
                    path.addRect(video)
                    path.addRect(r)
                }
                .fill(.black.opacity(0.6), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)

                grid(in: r)

                Rectangle()
                    .fill(.white.opacity(0.001))
                    .frame(width: r.width, height: r.height)
                    .offset(x: r.minX, y: r.minY)
                    // Measured in the overlay's fixed space: the rectangle moves with the drag,
                    // so its own coordinates would make it lag behind the pointer.
                    .gesture(DragGesture(coordinateSpace: .named("crop"))
                        .onChanged { value in
                            let start = dragStart ?? model.crop
                            dragStart = start
                            model.crop = start.moved(dx: value.translation.width / video.width,
                                                     dy: value.translation.height / video.height)
                        }
                        .onEnded { _ in dragStart = nil })
                    .pointerStyle(dragStart == nil ? .grabIdle : .grabActive)

                ForEach(Crop.Corner.allCases, id: \.self) { corner in
                    cornerHandle(corner, crop: r, video: video)
                }
            }
            .coordinateSpace(name: "crop")
        }
    }

    private func grid(in r: CGRect) -> some View {
        Path { path in
            path.addRect(r)
            for i in 1...2 {
                let x = r.minX + r.width * CGFloat(i) / 3
                let y = r.minY + r.height * CGFloat(i) / 3
                path.move(to: CGPoint(x: x, y: r.minY))
                path.addLine(to: CGPoint(x: x, y: r.maxY))
                path.move(to: CGPoint(x: r.minX, y: y))
                path.addLine(to: CGPoint(x: r.maxX, y: y))
            }
        }
        .stroke(.white.opacity(0.7), lineWidth: 1)
        .overlay {
            Rectangle()
                .strokeBorder(.white, lineWidth: 2)
                .frame(width: r.width, height: r.height)
                .position(x: r.midX, y: r.midY)
        }
        .allowsHitTesting(false)
    }

    private func cornerHandle(_ corner: Crop.Corner, crop r: CGRect, video: CGRect) -> some View {
        let left = corner == .topLeft || corner == .bottomLeft
        let top = corner == .topLeft || corner == .topRight
        let point = CGPoint(x: left ? r.minX : r.maxX, y: top ? r.minY : r.maxY)
        return RoundedRectangle(cornerRadius: 3)
            .fill(.white)
            .shadow(radius: 2)
            .frame(width: handleSize, height: handleSize)
            .position(point)
            .gesture(DragGesture(coordinateSpace: .named("crop"))
                .onChanged { value in
                    let p = CGPoint(x: (value.location.x - video.minX) / video.width,
                                    y: (value.location.y - video.minY) / video.height)
                    model.crop = model.crop.resized(corner, to: p, ratio: model.cropRatio, frame: model.frameSize)
                })
            .pointerStyle(.frameResize(position: Self.position(corner)))
    }

    private static func position(_ corner: Crop.Corner) -> FrameResizePosition {
        switch corner {
        case .topLeft: .topLeading
        case .topRight: .topTrailing
        case .bottomLeft: .bottomLeading
        case .bottomRight: .bottomTrailing
        }
    }

    /// Where an aspect-fit video of `size` sits in a view of `bounds` (as AVPlayerView
    /// draws it).
    static func fit(_ size: CGSize, in bounds: CGSize) -> CGRect {
        guard size.width > 0, size.height > 0, bounds.width > 0, bounds.height > 0 else {
            return CGRect(origin: .zero, size: bounds)
        }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(x: (bounds.width - fitted.width) / 2, y: (bounds.height - fitted.height) / 2,
                      width: fitted.width, height: fitted.height)
    }
}

/// Shape presets and the buttons for finishing, shown over the preview while cropping.
struct CropToolbar: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            Picker("Shape", selection: Binding(get: { model.cropAspect }, set: { model.setCropAspect($0) })) {
                ForEach(Crop.Aspect.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Button("Reset") { model.resetCrop() }
            Button("Cancel") { model.finishCropping(keep: false) }
                .keyboardShortcut(.cancelAction)
            Button("Done") { model.finishCropping() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding(10)
    }
}
