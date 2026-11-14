import Foundation

/// The built-in styles plus the user's own. The app saves custom styles in its
/// UserDefaults; the CLI reads them from the app's domain, so `--style` finds them too.
public enum StyleLibrary {
    public static let customStylesKey = "customStyles"
    /// The app's bundle identifier, which is also its UserDefaults domain.
    public static let appDomain = "ie.duggan.Subya"

    public static func loadCustom(from defaults: UserDefaults) -> [CaptionStyle] {
        guard let data = defaults.data(forKey: customStylesKey),
              let styles = try? JSONDecoder().decode([CaptionStyle].self, from: data) else { return [] }
        return styles
    }

    public static func saveCustom(_ styles: [CaptionStyle], to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(styles) { defaults.set(data, forKey: customStylesKey) }
    }

    public static func all(from defaults: UserDefaults) -> [CaptionStyle] {
        CaptionStyle.builtIns + loadCustom(from: defaults)
    }

    /// Finds a style by name, ignoring case. Custom styles win over built-ins of the same name.
    public static func style(named name: String, in styles: [CaptionStyle]) -> CaptionStyle? {
        styles.last { $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
    }

    /// "My Style", or "My Style 2" and so on if that's taken.
    public static func uniqueName(_ base: String, among styles: [CaptionStyle]) -> String {
        let names = Set(styles.map { $0.name.lowercased() })
        if !names.contains(base.lowercased()) { return base }
        var n = 2
        while names.contains("\(base) \(n)".lowercased()) { n += 1 }
        return "\(base) \(n)"
    }
}
