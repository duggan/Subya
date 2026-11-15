import AppKit
import AVFoundation
import CoreImage

/// The captions to draw, read by the video compositor on its own thread. Caption images
/// are rendered tightly around the text when first needed and cached by text, frame size
/// and look. Position isn't part of the cache: moving captions up or down just places the
/// cached image elsewhere, with no re-rendering.
public final class CaptionOverlay: @unchecked Sendable {
    private struct Key: Hashable {
        let text: String
        let width: Int
        let height: Int
        /// The style with `vertical` left out.
        let look: CaptionStyle
    }

    private struct Entry {
        let image: CIImage
        let block: CaptionRenderer.TextBlock
        /// The vertical position the block was rendered at.
        let vertical: Double
    }

    private let lock = NSLock()
    private var captions: [Caption] = []
    private var size: CGSize = .zero
    private var style = CaptionStyle.default
    private var cache: [Key: Entry] = [:]

    public init() {}

    private static func look(of style: CaptionStyle) -> CaptionStyle {
        var look = style
        look.vertical = 0
        return look
    }

    public func update(_ captions: [Caption], size: CGSize, style: CaptionStyle) {
        let visible = captions.filter { $0.end > $0.start && !Self.trimmed($0.text).isEmpty }
        let texts: Set<String> = style.display == .word
            ? Set(visible.flatMap { $0.timedWords.map(\.text) })
            : Set(visible.map { Self.trimmed($0.text) })
        let look = Self.look(of: style)
        lock.withLock {
            self.captions = visible
            self.size = size
            self.style = style
            cache = cache.filter {
                $0.key.look == look && $0.key.width == Int(size.width) && $0.key.height == Int(size.height)
                    && texts.contains($0.key.text)
            }
        }
    }

    /// The text on screen at `time`: the caption's line, or in one-word display, the word
    /// being spoken.
    public func displayText(at time: Double) -> String? {
        lock.lock()
        let caption = captions.first { time >= $0.start && time < $0.end }
        let display = style.display
        lock.unlock()
        guard let caption else { return nil }
        return display == .word ? caption.word(at: time) : Self.trimmed(caption.text)
    }

    /// The caption showing at `time`, placed in the frame, or nil if none is.
    public func image(at time: Double) -> CIImage? {
        guard let text = displayText(at: time) else { return nil }
        lock.lock()
        let frameSize = size, currentStyle = style
        lock.unlock()

        let key = Key(text: text, width: Int(frameSize.width), height: Int(frameSize.height),
                      look: Self.look(of: currentStyle))
        var entry = lock.withLock { cache[key] }
        if entry == nil {
            guard let block = CaptionRenderer.textBlock(text: text, size: frameSize, style: currentStyle) else {
                return nil
            }
            let made = Entry(image: CIImage(cgImage: block.image), block: block, vertical: currentStyle.vertical)
            lock.withLock { cache[key] = made }
            entry = made
        }
        guard let entry else { return nil }
        let rect = entry.block.rect(at: currentStyle.vertical, from: entry.vertical)
        return entry.image.transformed(by: CGAffineTransform(translationX: rect.minX, y: rect.minY))
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum CaptionRenderer {
    /// A caption rendered tightly around its text (with room for the outline, shadow and
    /// box), and where that sits in the frame. `rect` is in pixels with the origin at the
    /// bottom left (Core Image and Core Graphics coordinates).
    public struct TextBlock: @unchecked Sendable {
        public let image: CGImage
        public let rect: CGRect
        /// How far the block moves (in pixels, along y) from the Top position (vertical 0)
        /// to the Bottom one (1). Negative, since y grows upwards.
        public let travel: CGFloat

        /// Where the block sits for another vertical position. Moving a caption up or down
        /// needs no re-rendering, just this offset.
        public func rect(at vertical: Double, from current: Double) -> CGRect {
            rect.offsetBy(dx: 0, dy: CGFloat(vertical - current) * travel)
        }
    }

    /// Draws `text` in the style: optional box behind it, optional outline (with round
    /// joins, or sharp letters like Impact's M grow spikes), optional soft shadow, then the
    /// fill, centred horizontally at the style's vertical position. Only the area around the
    /// text is rendered; see `TextBlock`.
    public static func textBlock(text: String, size: CGSize, style: CaptionStyle) -> TextBlock? {
        guard size.width > 0, size.height > 0 else { return nil }
        let text = style.allCaps ? text.uppercased(with: .current) : text
        var fontSize = min(size.width, size.height) * 0.096 * style.scale
        // Wrap between words, never inside one: if the longest word (a single word in
        // one-word display, say, in a narrow 9:16 crop) is wider than the line, shrink the
        // text until it fits.
        let available = size.width * 0.9 - (style.box ? fontSize * 0.64 : 0)
        let widest = text.split(whereSeparator: \.isWhitespace).map {
            NSAttributedString(string: String($0), attributes: [.font: style.font(size: fontSize)]).size().width
        }.max() ?? 0
        if widest > available, widest > 0 { fontSize *= available / widest * 0.97 }
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
        let textHeight = ceil(bounds.height), textWidth = ceil(bounds.width)
        let margin = size.height * 0.07 + padY
        // From the Top position (0) to the Bottom one (1); Middle (0.5) is exactly centred.
        let topY = size.height - margin - textHeight, bottomY = margin
        let y = topY + (bottomY - topY) * CGFloat(style.vertical)
        let textRect = CGRect(x: (size.width - maxWidth) / 2, y: y, width: maxWidth, height: textHeight)
        let boxRect = CGRect(x: (size.width - textWidth) / 2 - padX, y: y - padY,
                             width: textWidth + padX * 2, height: textHeight + padY * 2)

        // Room around the text for the outline, the shadow's blur and offset, and overhangs.
        let extra = fontSize * (0.3 + style.outlineWidth * 2)
        let block = boxRect.insetBy(dx: -extra, dy: -extra).integral
        guard let ctx = CGContext(data: nil, width: Int(block.width), height: Int(block.height), bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.translateBy(x: -block.minX, y: -block.minY)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        if style.box {
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
                .draw(with: textRect, options: [.usesLineFragmentOrigin, .usesFontLeading])
        }
        fill.draw(with: textRect, options: [.usesLineFragmentOrigin, .usesFontLeading])
        NSGraphicsContext.restoreGraphicsState()
        guard let image = ctx.makeImage() else { return nil }
        return TextBlock(image: image, rect: block, travel: bottomY - topY)
    }

    /// The caption as a full-frame image, transparent outside the text.
    public static func image(text: String, size: CGSize, style: CaptionStyle) -> CGImage? {
        guard let block = textBlock(text: text, size: size, style: style),
              let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(block.image, in: block.rect)
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

    /// Exports the video with the composition's captions. With a `trim`, only that part is
    /// written (the composition still sees source times, so captions need no shifting).
    public static func export(asset: AVAsset, composition: AVVideoComposition, trim: Trim? = nil,
                              to url: URL) async throws {
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw CaptionError.exportFailed
        }
        session.videoComposition = composition
        if let trim { session.timeRange = trim.timeRange }
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
