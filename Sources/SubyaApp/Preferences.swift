import CaptionKit
import Foundation
import Observation

/// UserDefaults keys for the General settings, with their defaults. Read where they're
/// used (transcription, splitting, export), so a change applies to the next one.
enum Pref {
    /// A locale identifier, or "" to follow the system language.
    static let language = "transcriptionLanguage"
    static let maxLineLength = "maxLineLength"
    static let splitPause = "splitPause"
    static let linger = "linger"
    static let exportLocation = "exportLocation"
    static let exportFolder = "exportFolder"
    static let exportSuffix = "exportSuffix"
    static let exportQuality = "exportQuality"
    static let revealAfterExport = "revealAfterExport"

    static func register() {
        UserDefaults.standard.register(defaults: [
            language: "",
            maxLineLength: 40,
            splitPause: 0.6,
            linger: 0.6,
            exportLocation: ExportLocation.beside.rawValue,
            exportFolder: "",
            exportSuffix: "-captioned",
            exportQuality: ExportQuality.high.rawValue,
            revealAfterExport: true,
        ])
    }

    static var defaults: UserDefaults { .standard }

    static var locale: Locale {
        let id = defaults.string(forKey: language) ?? ""
        return id.isEmpty ? .current : Locale(identifier: id)
    }

    static func captions(from words: [Word], videoEnd: Double) -> [Caption] {
        Chunker.captions(from: words, videoEnd: videoEnd,
                         maxChars: defaults.integer(forKey: maxLineLength),
                         maxGap: defaults.double(forKey: splitPause),
                         linger: defaults.double(forKey: linger))
    }
}

enum ExportLocation: String, CaseIterable, Identifiable {
    case beside, folder, ask
    var id: String { rawValue }
    var title: String {
        switch self {
        case .beside: "Next to the original"
        case .folder: "In a folder"
        case .ask: "Ask each time"
        }
    }
}

enum ExportQuality: String, CaseIterable, Identifiable {
    case high, messaging
    var id: String { rawValue }
    var title: String {
        switch self {
        case .high: "High (original size)"
        case .messaging: "Smaller for messaging (720p)"
        }
    }
    /// Longest side in pixels, or nil to keep the original size.
    var maxLongSide: CGFloat? { self == .messaging ? 1280 : nil }
}

/// The user's own caption styles, saved to UserDefaults as they change. The CLI reads
/// them from there too (see `StyleLibrary`).
@MainActor @Observable
final class StyleStore {
    var custom: [CaptionStyle] {
        didSet {
            guard custom != oldValue else { return }
            StyleLibrary.saveCustom(custom, to: .standard)
            onChange?(oldValue)
        }
    }

    /// Called with the previous custom styles after any change.
    @ObservationIgnored var onChange: (([CaptionStyle]) -> Void)?

    init() {
        custom = StyleLibrary.loadCustom(from: .standard)
    }

    var all: [CaptionStyle] { CaptionStyle.builtIns + custom }

    func style(id: CaptionStyle.ID) -> CaptionStyle? {
        all.first { $0.id == id }
    }

    /// Adds a copy of `style` under a fresh name and returns it.
    @discardableResult
    func duplicate(_ style: CaptionStyle) -> CaptionStyle {
        let base = style.isBuiltIn ? "My \(style.name)" : style.name
        let copy = style.duplicate(named: StyleLibrary.uniqueName(base, among: all))
        custom.append(copy)
        return copy
    }

    func delete(id: CaptionStyle.ID) {
        custom.removeAll { $0.id == id }
    }
}
