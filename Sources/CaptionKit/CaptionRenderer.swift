import AppKit
import AVFoundation
import CoreImage

/// The captions to draw, read by the video compositor on its own thread. Caption images
/// are rendered when first needed and cached by text, frame size and style, so a style
/// change (like dragging the size slider) only re-renders the caption on screen.
public final class CaptionOverlay: @unchecked Sendable {
    private struct Key: Hashable {
        let text: String
        let width: Int
        let height: Int
        let style: CaptionStyle
    }

    private let lock = NSLock()
    private var captions: [Caption] = []
    private var size: CGSize = .zero
    private var style = CaptionStyle.default
    private var cache: [Key: CIImage] = [:]

    public init() {}

    public func update(_ captions: [Caption], size: CGSize, style: CaptionStyle) {
        let visible = captions.filter { $0.end > $0.start && !Self.trimmed($0.text).isEmpty }
        let texts: Set<String> = style.display == .word
            ? Set(visible.flatMap { $0.timedWords.map(\.text) })
            : Set(visible.map { Self.trimmed($0.text) })
        lock.withLock {
            self.captions = visible
            self.size = size
            self.style = style
            cache = cache.filter {
                $0.key.style == style && $0.key.width == Int(size.width) && $0.key.height == Int(size.height)
                    && texts.contains($0.key.text)
            }
        }
    }

    /// The text on screen at `time`: the caption's line, or in one-word display, the word
    /// being spoken.
    func displayText(at time: Double) -> String? {
        lock.lock()
        let caption = captions.first { time >= $0.start && time < $0.end }
        let display = style.display
        lock.unlock()
        guard let caption else { return nil }
        return display == .word ? caption.word(at: time) : Self.trimmed(caption.text)
    }

    public func image(at time: Double) -> CIImage? {
        guard let text = displayText(at: time) else { return nil }
        lock.lock()
        let frameSize = size, currentStyle = style
        lock.unlock()

        let key = Key(text: text, width: Int(frameSize.width), height: Int(frameSize.height), style: currentStyle)
        if let cached = lock.withLock({ cache[key] }) { return cached }
        guard let cg = CaptionRenderer.image(text: key.text, size: frameSize, style: currentStyle) else { return nil }
        let image = CIImage(cgImage: cg)
        lock.withLock { cache[key] = image }
        return image
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum CaptionRenderer {
    /// Draws `text` in the style: optional box behind it, optional outline (with round
    /// joins, or sharp letters like Impact's M grow spikes), optional soft shadow, then the
    /// fill. Centred horizontally at the style's position. The image is the size of the
    /// video frame, transparent outside the caption.
    public static func image(text: String, size: CGSize, style: CaptionStyle) -> CGImage? {
        let width = Int(size.width), height = Int(size.height)
        guard width > 0, height > 0,
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }

        let text = style.allCaps ? text.uppercased(with: .current) : text
        let fontSize = min(size.width, size.height) * 0.096 * style.scale
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.lineBreakMode = .byWordWrapping
        let base: [NSAttributedString.Key: Any] = [.font: style.font(size: fontSize), .paragraphStyle: para]

        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.8)
        shadow.shadowBlurRadius = fontSize * 0.12
        shadow.shadowOffset = NSSize(width: fontSize * 0.055, height: -fontSize * 0.075)

        let hasOutline = style.outlineWidth > 0
        var fillAttributes = base
        fillAttributes[.foregroundColor] = style.textColor.nsColor
        if style.shadow && !hasOutline { fillAttributes[.shadow] = shadow }
        let fill = NSAttributedString(string: text, attributes: fillAttributes)

        // Box padding, so a boxed caption keeps the same margin from the frame's edge.
        let padX = style.box ? fontSize * 0.32 : 0
        let padY = style.box ? fontSize * 0.14 : 0
        let maxWidth = size.width * 0.9 - padX * 2
        let bounds = fill.boundingRect(with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
                                       options: [.usesLineFragmentOrigin, .usesFontLeading])
        let textHeight = ceil(bounds.height)
        let margin = size.height * 0.07 + padY
        // Core Graphics origin is bottom-left.
        let y: CGFloat = switch style.position {
        case .bottom: margin
        case .middle: (size.height - textHeight) / 2
        case .top: size.height - margin - textHeight
        }
        let rect = CGRect(x: (size.width - maxWidth) / 2, y: y, width: maxWidth, height: textHeight)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        if style.box {
            let textWidth = ceil(bounds.width)
            let boxRect = CGRect(x: (size.width - textWidth) / 2 - padX, y: y - padY,
                                 width: textWidth + padX * 2, height: textHeight + padY * 2)
            ctx.setFillColor(style.boxColor.nsColor.cgColor)
            ctx.addPath(CGPath(roundedRect: boxRect, cornerWidth: fontSize * 0.22, cornerHeight: fontSize * 0.22,
                               transform: nil))
            ctx.fillPath()
        }
        if hasOutline {
            var outlineAttributes = base
            outlineAttributes[.foregroundColor] = style.outlineColor.nsColor
            outlineAttributes[.strokeColor] = style.outlineColor.nsColor
            // Negative stroke width = fill and stroke, in percent of the font size. The stroke
            // is centred on the glyph edge, so double it to get the visible width.
            outlineAttributes[.strokeWidth] = -style.outlineWidth * 2 * 100
            if style.shadow { outlineAttributes[.shadow] = shadow }
            ctx.setLineJoin(.round)
            NSAttributedString(string: text, attributes: outlineAttributes)
                .draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading])
        }
        fill.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading])
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }

    /// The composition that draws captions over the video, for both the preview and export.
    /// With a `crop`, frames are cut to it; with `maxLongSide`, they're then scaled down so
    /// the longer side is at most that many pixels. Update the overlay with the result's
    /// `renderSize`, so captions sit in the cropped, scaled frame.
    public static func composition(for asset: AVAsset, overlay: CaptionOverlay, crop: Crop = .full,
                                   maxLongSide: CGFloat? = nil) async throws -> AVVideoComposition {
        let natural = try await composition(for: asset, overlay: overlay, transform: nil)
        let frame = natural.renderSize
        let cropRect = crop.isFull ? CGRect(origin: .zero, size: frame) : crop.pixelRect(in: frame)
        let target = ExportNaming.exportSize(for: cropRect.size, maxLongSide: maxLongSide)
        guard target != frame else { return natural }
        let transform = FrameTransform(crop: cropRect, scale: target.width / cropRect.width, size: target)
        let transformed = try await composition(for: asset, overlay: overlay, transform: transform)
        return (LegacyComposition.self as RenderSizing.Type).withRenderSize(transformed, target) ?? natural
    }

    /// Cut each frame to `crop` (pixels, Core Image coordinates), move it to the origin,
    /// scale it, and trim to the output `size`.
    private struct FrameTransform: Sendable {
        let crop: CGRect
        let scale: CGFloat
        let size: CGSize

        func apply(to image: CIImage) -> CIImage {
            image.cropped(to: crop)
                .transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
                .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                .cropped(to: CGRect(origin: .zero, size: size))
        }
    }

    private static func composition(for asset: AVAsset, overlay: CaptionOverlay,
                                     transform: FrameTransform?) async throws -> AVVideoComposition {
        try await AVVideoComposition.videoComposition(with: asset, applyingCIFiltersWithHandler: { request in
            var image = request.sourceImage
            if let transform { image = transform.apply(to: image) }
            if let caption = overlay.image(at: request.compositionTime.seconds) {
                image = caption.composited(over: image)
            }
            request.finish(with: image, context: nil)
        })
    }

    public static func export(asset: AVAsset, composition: AVVideoComposition, to url: URL) async throws {
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw CaptionError.exportFailed
        }
        session.videoComposition = composition
        session.shouldOptimizeForNetworkUse = true
        try? FileManager.default.removeItem(at: url)
        try await session.export(to: url, as: .mp4)
    }
}

/// AVVideoComposition.Configuration (macOS 26) can't express a Core Image filter handler,
/// so changing a filtering composition's render size still needs the deprecated mutable
/// copy. Calling it through a protocol keeps the deprecation warning out of the build
/// without silencing any others.
private protocol RenderSizing {
    static func withRenderSize(_ composition: AVVideoComposition, _ size: CGSize) -> AVVideoComposition?
}

private enum LegacyComposition: RenderSizing {
    @available(macOS, deprecated: 26.0)
    static func withRenderSize(_ composition: AVVideoComposition, _ size: CGSize) -> AVVideoComposition? {
        guard let mutable = composition.mutableCopy() as? AVMutableVideoComposition else { return nil }
        mutable.renderSize = size
        return mutable
    }
}
