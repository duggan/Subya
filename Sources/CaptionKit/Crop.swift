import CoreGraphics

/// A crop of the video frame, as fractions of the frame (0…1) with the origin at the
/// top left, as on screen. Fractions keep it independent of the video's pixel size.
public struct Crop: Equatable, Hashable, Codable, Sendable {
    public var rect: CGRect

    public init(rect: CGRect) {
        self.rect = rect
    }

    public static let full = Crop(rect: CGRect(x: 0, y: 0, width: 1, height: 1))

    public var isFull: Bool {
        rect.minX <= 0.0005 && rect.minY <= 0.0005 && rect.maxX >= 0.9995 && rect.maxY >= 0.9995
    }

    /// The smallest a crop side can get, as a fraction of the frame.
    public static let minSide: CGFloat = 0.08

    /// Common shapes. `ratio` is width over height in pixels; nil means free.
    public enum Aspect: String, CaseIterable, Identifiable, Sendable {
        case free, original, square, portrait, fourByFive, landscape

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .free: "Free"
            case .original: "Original"
            case .square: "1:1"
            case .portrait: "9:16"
            case .fourByFive: "4:5"
            case .landscape: "16:9"
            }
        }

        public func ratio(for frame: CGSize) -> CGFloat? {
            switch self {
            case .free: nil
            case .original: frame.height > 0 ? frame.width / frame.height : nil
            case .square: 1
            case .portrait: 9.0 / 16
            case .fourByFive: 4.0 / 5
            case .landscape: 16.0 / 9
            }
        }

        /// Parses "1:1", "9:16", "4:5", "16:9", "original" or "free".
        public init?(name: String) {
            guard let match = Self.allCases.first(where: {
                $0.displayName.lowercased() == name.lowercased() || $0.rawValue.lowercased() == name.lowercased()
            }) else { return nil }
            self = match
        }
    }

    /// The largest centred crop with the given pixel `ratio` (width / height) in a frame.
    public static func centered(ratio: CGFloat, in frame: CGSize) -> Crop {
        guard frame.width > 0, frame.height > 0, ratio > 0 else { return .full }
        let frameRatio = frame.width / frame.height
        let width = ratio < frameRatio ? ratio / frameRatio : 1
        let height = ratio < frameRatio ? 1 : frameRatio / ratio
        return Crop(rect: CGRect(x: (1 - width) / 2, y: (1 - height) / 2, width: width, height: height))
    }

    /// The crop in pixels, in Core Image coordinates (origin at the bottom left), with
    /// whole, even sides as H.264 needs.
    public func pixelRect(in frame: CGSize) -> CGRect {
        func even(_ x: CGFloat) -> CGFloat { Swift.max(2, (x / 2).rounded(.down) * 2) }
        let width = Swift.min(even(rect.width * frame.width), even(frame.width))
        let height = Swift.min(even(rect.height * frame.height), even(frame.height))
        let x = Swift.min(Swift.max((rect.minX * frame.width).rounded(), 0), frame.width - width)
        let yFromTop = Swift.min(Swift.max((rect.minY * frame.height).rounded(), 0), frame.height - height)
        return CGRect(x: x, y: frame.height - yFromTop - height, width: width, height: height)
    }

    /// Moved by a fraction of the frame, staying inside it.
    public func moved(dx: CGFloat, dy: CGFloat) -> Crop {
        var r = rect
        r.origin.x = Swift.min(Swift.max(r.minX + dx, 0), 1 - r.width)
        r.origin.y = Swift.min(Swift.max(r.minY + dy, 0), 1 - r.height)
        return Crop(rect: r)
    }

    public enum Corner: CaseIterable, Sendable {
        case topLeft, topRight, bottomLeft, bottomRight
    }

    /// Resized by dragging `corner` to `point` (fractions of the frame), with the opposite
    /// corner fixed. With a pixel `ratio`, the shape is kept. Stays inside the frame and
    /// at least `minSide` across.
    public func resized(_ corner: Corner, to point: CGPoint, ratio: CGFloat? = nil, frame: CGSize) -> Crop {
        let left = corner == .topLeft || corner == .bottomLeft
        let top = corner == .topLeft || corner == .topRight
        let anchor = CGPoint(x: left ? rect.maxX : rect.minX, y: top ? rect.maxY : rect.minY)
        let maxWidth = left ? anchor.x : 1 - anchor.x
        let maxHeight = top ? anchor.y : 1 - anchor.y
        var width = Swift.min(Swift.max(left ? anchor.x - point.x : point.x - anchor.x, Self.minSide), maxWidth)
        var height = Swift.min(Swift.max(top ? anchor.y - point.y : point.y - anchor.y, Self.minSide), maxHeight)
        if let ratio, frame.width > 0, frame.height > 0 {
            // In fractions of the frame, width / height = pixel ratio × frame height / frame width.
            let k = ratio * frame.height / frame.width
            if width / height > k { width = height * k } else { height = width / k }
        }
        let x = left ? anchor.x - width : anchor.x
        let y = top ? anchor.y - height : anchor.y
        return Crop(rect: CGRect(x: x, y: y, width: width, height: height))
    }
}
