import AppKit

/// How captions look: typeface, where they sit in the frame, size and case.
/// The look is always white text with a thick black outline and a soft shadow.
public struct CaptionStyle: Equatable, Hashable, Sendable, Codable {
    public enum Font: String, CaseIterable, Identifiable, Sendable, Codable {
        case classic, meme, rounded, marker, typewriter, poster

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .classic: "Classic"
            case .meme: "Meme"
            case .rounded: "Rounded"
            case .marker: "Marker"
            case .typewriter: "Typewriter"
            case .poster: "Poster"
            }
        }

        /// Meme text is traditionally all caps; picking this font turns caps on in the app.
        public var prefersAllCaps: Bool { self == .meme }

        /// Evens out how big each face looks at the same point size.
        var sizeFactor: CGFloat {
            switch self {
            case .classic: 1.0
            case .meme: 1.12
            case .rounded: 0.98
            case .marker: 1.08
            case .typewriter: 0.95
            case .poster: 1.15
            }
        }

        public func nsFont(size: CGFloat) -> NSFont {
            let name: String? = switch self {
            case .classic: "HelveticaNeue-Bold"
            case .meme: "Impact"
            case .rounded: nil
            case .marker: "MarkerFelt-Wide"
            case .typewriter: "AmericanTypewriter-Bold"
            case .poster: "Futura-CondensedExtraBold"
            }
            if let name, let font = NSFont(name: name, size: size) { return font }
            let heavy = NSFont.systemFont(ofSize: size, weight: .black)
            if self == .rounded, let rounded = heavy.fontDescriptor.withDesign(.rounded) {
                return NSFont(descriptor: rounded, size: size) ?? heavy
            }
            return heavy
        }
    }

    public enum Position: String, CaseIterable, Identifiable, Sendable, Codable {
        case top, middle, bottom

        public var id: String { rawValue }
        public var displayName: String { rawValue.capitalized }
    }

    public var font: Font
    public var position: Position
    /// Text size relative to the default (1.0 is 9.6% of the frame's shorter side).
    public var scale: Double
    public var allCaps: Bool

    public init(font: Font = .classic, position: Position = .bottom, scale: Double = 1.0, allCaps: Bool = false) {
        self.font = font
        self.position = position
        self.scale = scale
        self.allCaps = allCaps
    }

    public static let `default` = CaptionStyle()
}
