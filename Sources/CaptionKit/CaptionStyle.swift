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
    /// The snap points for where text sits. `vertical` runs from the Top position (0) to
    /// the Bottom one (1); Middle is exactly halfway between them for any text height.
    public enum Position: String, CaseIterable, Identifiable, Sendable, Codable {
        case top, middle, bottom

        public var id: String { rawValue }
        public var displayName: String { rawValue.capitalized }

        public var vertical: Double {
            switch self {
            case .top: 0
            case .middle: 0.5
            case .bottom: 1
            }
        }
    }

    /// `vertical` pulled onto a snap point when it's within `threshold`, for dragging.
    public static func snapped(_ vertical: Double, threshold: Double = 0.04) -> Double {
        let clamped = Swift.min(Swift.max(vertical, 0), 1)
        let nearest = Position.allCases.map(\.vertical).min { abs($0 - clamped) < abs($1 - clamped) }!
        return abs(nearest - clamped) <= threshold ? nearest : clamped
    }

    /// Whole lines (the default), or one word at a time as each is spoken.
    public enum Display: String, CaseIterable, Identifiable, Sendable, Codable {
        case line, word

        public var id: String { rawValue }
        public var displayName: String { self == .line ? "Whole line" : "One word at a time" }
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
    /// Where text sits, from the Top position (0) to the Bottom one (1), each with a 7%
    /// margin from the frame's edge; 0.5 is Middle.
    public var vertical: Double

    /// The snap point the text is at, or nil when it's somewhere in between. Setting it
    /// moves the text there.
    public var position: Position? {
        get { Position.allCases.first { abs($0.vertical - vertical) < 0.0005 } }
        set { if let newValue { vertical = newValue.vertical } }
    }
    /// Text size relative to the default (1.0 is 9.6% of the frame's shorter side).
    public var scale: Double
    public var allCaps: Bool
    public var display: Display

    public init(id: UUID = UUID(), name: String = "Classic", fontName: String = "HelveticaNeue-Bold",
                textColor: RGBA = .white, outlineColor: RGBA = .black, outlineWidth: Double = 0.093,
                shadow: Bool = true, box: Bool = false, boxColor: RGBA = RGBA(0, 0, 0, 0.75),
                position: Position = .bottom, vertical: Double? = nil, scale: Double = 1.0,
                allCaps: Bool = false, display: Display = .line) {
        self.id = id
        self.name = name
        self.fontName = fontName
        self.textColor = textColor
        self.outlineColor = outlineColor
        self.outlineWidth = outlineWidth
        self.shadow = shadow
        self.box = box
        self.boxColor = boxColor
        self.vertical = Swift.min(Swift.max(vertical ?? position.vertical, 0), 1)
        self.scale = scale
        self.allCaps = allCaps
        self.display = display
    }

    // Every field decodes with a default, so styles saved by earlier versions (before a
    // field existed) still load instead of being dropped. Styles from before `vertical`
    // have only `position`, which is still written for them.
    private enum CodingKeys: String, CodingKey {
        case id, name, fontName, textColor, outlineColor, outlineWidth, shadow, box, boxColor, position, vertical,
             scale, allCaps, display
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(fontName, forKey: .fontName)
        try c.encode(textColor, forKey: .textColor)
        try c.encode(outlineColor, forKey: .outlineColor)
        try c.encode(outlineWidth, forKey: .outlineWidth)
        try c.encode(shadow, forKey: .shadow)
        try c.encode(box, forKey: .box)
        try c.encode(boxColor, forKey: .boxColor)
        try c.encode(position ?? (vertical < 0.5 ? .top : .bottom), forKey: .position)
        try c.encode(vertical, forKey: .vertical)
        try c.encode(scale, forKey: .scale)
        try c.encode(allCaps, forKey: .allCaps)
        try c.encode(display, forKey: .display)
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = CaptionStyle()
        self.init(id: try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
                  name: try c.decodeIfPresent(String.self, forKey: .name) ?? "Untitled",
                  fontName: try c.decodeIfPresent(String.self, forKey: .fontName) ?? d.fontName,
                  textColor: try c.decodeIfPresent(RGBA.self, forKey: .textColor) ?? d.textColor,
                  outlineColor: try c.decodeIfPresent(RGBA.self, forKey: .outlineColor) ?? d.outlineColor,
                  outlineWidth: try c.decodeIfPresent(Double.self, forKey: .outlineWidth) ?? d.outlineWidth,
                  shadow: try c.decodeIfPresent(Bool.self, forKey: .shadow) ?? d.shadow,
                  box: try c.decodeIfPresent(Bool.self, forKey: .box) ?? d.box,
                  boxColor: try c.decodeIfPresent(RGBA.self, forKey: .boxColor) ?? d.boxColor,
                  position: try c.decodeIfPresent(Position.self, forKey: .position) ?? .bottom,
                  vertical: try c.decodeIfPresent(Double.self, forKey: .vertical),
                  scale: try c.decodeIfPresent(Double.self, forKey: .scale) ?? d.scale,
                  allCaps: try c.decodeIfPresent(Bool.self, forKey: .allCaps) ?? d.allCaps,
                  display: try c.decodeIfPresent(Display.self, forKey: .display) ?? d.display)
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
        CaptionStyle(id: builtInID(9), name: "One Word", fontName: systemRounded, outlineWidth: 0.11,
                     position: .middle, scale: 1.7, allCaps: true, display: .word),
    ]

    public static let `default` = builtIns[0]
}
