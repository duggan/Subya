import AppKit
import AVFoundation
import CoreImage

/// Thread-safe store of rendered caption images, read by the video compositor on its own thread.
public final class CaptionOverlay: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [(start: Double, end: Double, image: CIImage)] = []

    public init() {}

    public func update(_ captions: [Caption], size: CGSize, scale: Double) {
        let rendered = captions.compactMap { cap -> (Double, Double, CIImage)? in
            let text = cap.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, cap.end > cap.start,
                  let img = CaptionRenderer.image(text: text, size: size, scale: scale) else { return nil }
            return (cap.start, cap.end, CIImage(cgImage: img))
        }
        lock.withLock { items = rendered }
    }

    public func image(at time: Double) -> CIImage? {
        lock.withLock { items.first { time >= $0.start && time < $0.end }?.image }
    }
}

public enum CaptionRenderer {
    /// Bold white text, thick black outline, soft drop shadow, centred near the bottom.
    public static func image(text: String, size: CGSize, scale: Double) -> CGImage? {
        let width = Int(size.width), height = Int(size.height)
        guard width > 0, height > 0,
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }

        let fontSize = min(size.width, size.height) * 0.096 * scale
        let font = NSFont(name: "HelveticaNeue-Bold", size: fontSize) ?? .boldSystemFont(ofSize: fontSize)
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
        let rect = CGRect(x: (size.width - maxWidth) / 2, y: size.height * 0.07,
                          width: maxWidth, height: ceil(bounds.height))

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
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
