import AppKit

/// A colour as sRGB components, so styles can be saved as JSON.
public struct RGBA: Codable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(_ red: Double, _ green: Double, _ blue: Double, _ alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public init(_ color: NSColor) {
        let c = color.usingColorSpace(.sRGB) ?? .black
        self.init(c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent)
    }

    public var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }

    public static let white = RGBA(1, 1, 1)
    public static let black = RGBA(0, 0, 0)
}

/// How captions look. Built-in styles ship with the app; users make their own in
/// Settings, starting from a copy of one.
public struct CaptionStyle: Identifiable, Codable, Hashable, Sendable {
    public enum Position: String, CaseIterable, Identifiable, Sendable, Codable {
        case top, middle, bottom

        public var id: String { rawValue }
        public var displayName: String { rawValue.capitalized }
    }

    /// `fontName` for the system's rounded face (SF Rounded), which has no stable
    /// PostScript name.
    public static let systemRounded = "system-rounded"

    public var id: UUID
    public var name: String
    /// A PostScript font name, or `systemRounded`.
    public var fontName: String
    public var textColor: RGBA
    public var outlineColor: RGBA
    /// Outline thickness as a fraction of the font size; 0 for none.
    public var outlineWidth: Double
    public var shadow: Bool
    /// Draw a rounded box behind the text.
    public var box: Bool
    public var boxColor: RGBA
    public var position: Position
    /// Text size relative to the default (1.0 is 9.6% of the frame's shorter side).
    public var scale: Double
    public var allCaps: Bool

    public init(id: UUID = UUID(), name: String = "Classic", fontName: String = "HelveticaNeue-Bold",
                textColor: RGBA = .white, outlineColor: RGBA = .black, outlineWidth: Double = 0.093,
                shadow: Bool = true, box: Bool = false, boxColor: RGBA = RGBA(0, 0, 0, 0.75),
                position: Position = .bottom, scale: Double = 1.0, allCaps: Bool = false) {
        self.id = id
        self.name = name
        self.fontName = fontName
        self.textColor = textColor
        self.outlineColor = outlineColor
        self.outlineWidth = outlineWidth
        self.shadow = shadow
        self.box = box
        self.boxColor = boxColor
        self.position = position
        self.scale = scale
        self.allCaps = allCaps
    }

    public func font(size: CGFloat) -> NSFont { Self.font(named: fontName, size: size) }

    /// Resolves a style's font name. Unknown names (say, a font that was uninstalled)
    /// fall back to the heavy system font.
    public static func font(named name: String, size: CGFloat) -> NSFont {
        let heavy = NSFont.systemFont(ofSize: size, weight: .black)
        if name == systemRounded {
            return heavy.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? heavy
        }
        return NSFont(name: name, size: size) ?? heavy
    }

    /// The font's name as people know it, like "Impact" or "Helvetica Neue Bold".
    public var fontDisplayName: String {
        if fontName == Self.systemRounded { return "System Rounded" }
        return NSFont(name: fontName, size: 12)?.displayName ?? "\(fontName) (missing)"
    }

    public var isBuiltIn: Bool { Self.builtIns.contains { $0.id == id } }

    /// A copy with a new id, for "Duplicate".
    public func duplicate(named newName: String) -> CaptionStyle {
        var copy = self
        copy.id = UUID()
        copy.name = newName
        return copy
    }

    // MARK: - Built-in styles

    private static func builtInID(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "5B0BA000-0000-4000-8000-%012d", n))!
    }

    /// Sizes differ per face so they look about the same size at the default scale.
    public static let builtIns: [CaptionStyle] = [
        CaptionStyle(id: builtInID(1), name: "Classic"),
        CaptionStyle(id: builtInID(2), name: "Meme", fontName: "Impact", position: .top, scale: 1.12, allCaps: true),
        CaptionStyle(id: builtInID(3), name: "Rounded", fontName: systemRounded, scale: 0.98),
        CaptionStyle(id: builtInID(4), name: "Marker", fontName: "MarkerFelt-Wide", scale: 1.08),
        CaptionStyle(id: builtInID(5), name: "Typewriter", fontName: "AmericanTypewriter-Bold", scale: 0.95),
        CaptionStyle(id: builtInID(6), name: "Poster", fontName: "Futura-CondensedExtraBold", scale: 1.15),
        CaptionStyle(id: builtInID(7), name: "Boxed", outlineWidth: 0, shadow: false, box: true,
                     boxColor: RGBA(0, 0, 0, 0.72), scale: 0.9),
        CaptionStyle(id: builtInID(8), name: "Highlight", fontName: systemRounded, textColor: .black,
                     outlineWidth: 0, shadow: false, box: true, boxColor: .white, scale: 0.9),
    ]

    public static let `default` = builtIns[0]
}
