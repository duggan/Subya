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
        let texts = Set(visible.map { Self.trimmed($0.text) })
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

    public func image(at time: Double) -> CIImage? {
        lock.lock()
        let caption = captions.first { time >= $0.start && time < $0.end }
        let frameSize = size, currentStyle = style
        lock.unlock()

        guard let caption else { return nil }
        let key = Key(text: Self.trimmed(caption.text), width: Int(frameSize.width), height: Int(frameSize.height),
                      style: currentStyle)
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
    /// White text with a thick black outline and a soft drop shadow, centred horizontally,
    /// in the style's font and position. The image is the size of the video frame.
    public static func image(text: String, size: CGSize, style: CaptionStyle) -> CGImage? {
        let width = Int(size.width), height = Int(size.height)
        guard width > 0, height > 0,
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }

        let text = style.allCaps ? text.uppercased(with: .current) : text
        let fontSize = min(size.width, size.height) * 0.096 * style.scale * style.font.sizeFactor
        let font = style.font.nsFont(size: fontSize)
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.lineBreakMode = .byWordWrapping
        let outlineWidth = fontSize * 0.093

        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.8)
        shadow.shadowBlurRadius = fontSize * 0.12
        shadow.shadowOffset = NSSize(width: fontSize * 0.055, height: -fontSize * 0.075)

        let base: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: para]
        // Negative stroke width = fill and stroke; the stroke is centred on the glyph edge, so double it.
        let outline = NSAttributedString(string: text, attributes: base.merging([
            .foregroundColor: NSColor.black, .strokeColor: NSColor.black,
            .strokeWidth: -(outlineWidth * 2) / fontSize * 100, .shadow: shadow,
        ]) { $1 })
        let fill = NSAttributedString(string: text, attributes: base.merging([.foregroundColor: NSColor.white]) { $1 })

        let maxWidth = size.width * 0.9
        let bounds = fill.boundingRect(with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
                                       options: [.usesLineFragmentOrigin, .usesFontLeading])
        let textHeight = ceil(bounds.height)
        let margin = size.height * 0.07
        // Core Graphics origin is bottom-left.
        let y: CGFloat = switch style.position {
        case .bottom: margin
        case .middle: (size.height - textHeight) / 2
        case .top: size.height - margin - textHeight
        }
        let rect = CGRect(x: (size.width - maxWidth) / 2, y: y, width: maxWidth, height: textHeight)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        // Round joins: with the default miter joins, sharp letters (Impact's M, A, Y)
        // grow long spikes out of the outline.
        ctx.setLineJoin(.round)
        outline.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading])
        fill.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading])
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }

    public static func composition(for asset: AVAsset, overlay: CaptionOverlay) async throws -> AVVideoComposition {
        try await AVVideoComposition.videoComposition(with: asset, applyingCIFiltersWithHandler: { request in
            var image = request.sourceImage
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
