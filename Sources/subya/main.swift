import AVFoundation
import CaptionKit
import Foundation

// Developer CLI for CaptionKit. Same transcription and rendering as the app.

/// Built-in styles plus the ones made in the app's Settings.
let styles = StyleLibrary.all(from: UserDefaults(suiteName: StyleLibrary.appDomain) ?? .standard)

let usage = """
    usage: subya transcribe <video> [--srt] [--language <id>]
           subya burn <video> <output.mp4> [--captions <file.srt>] [--language <id>]
                      [--style <name>] [--position top|middle|bottom|0…1] [--caps|--no-caps]
                      [--scale <n>] [--words|--lines] [--crop <aspect>] [--trim <from-to>]
                      [--small]
           subya styles

    transcribe  Print the captions Subya would make (as SRT with --srt).
    burn        Burn captions into a copy of the video. Uses --captions if given
                (e.g. an edited `transcribe --srt`), otherwise transcribes first.
                --style picks a style by name, including your own from the app's
                Settings (default: Classic). --position, --caps, --scale and --words
                (one word at a time) or --lines override it.
                --crop cuts the largest centred 1:1, 9:16, 4:5 or 16:9 frame.
                --trim keeps only part of the video: seconds, m:ss or h:mm:ss,
                either side optional (1:05-1:20, 30-, -12.5). Transcribes only
                that part; --captions times are in the original video's time.
                --small scales the video down to 720p for messaging.
    styles      List the style names --style accepts.
    --language  A locale like en-IE or fr-FR (default: this Mac's language).
    """

func log(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

func fail(_ message: String) -> Never {
    log(message)
    exit(1)
}

var args = Array(CommandLine.arguments.dropFirst())

func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name) else { return nil }
    guard i + 1 < args.count else { fail("\(name) needs a value") }
    let value = args[i + 1]
    args.removeSubrange(i...i + 1)
    return value
}

func flag(_ name: String) -> Bool {
    guard let i = args.firstIndex(of: name) else { return false }
    args.remove(at: i)
    return true
}

func transcribe(_ url: URL, language: String?, trim: Trim? = nil) async throws -> [Caption] {
    let locale = language.map { Locale(identifier: $0) } ?? .current
    let words = try await Transcriber.words(for: url, locale: locale, range: trim) { log($0) }
    let duration = try await AVURLAsset(url: url).load(.duration).seconds
    return Chunker.captions(from: words, videoEnd: trim?.end ?? duration)
}

func describe(_ captions: [Caption]) -> String {
    captions.map { String(format: "%6.2f – %6.2f  %@", $0.start, $0.end, $0.text) }.joined(separator: "\n")
}

do {
    switch args.first {
    case "transcribe":
        let srt = flag("--srt")
        let language = option("--language")
        guard args.count == 2 else { fail(usage) }
        let captions = try await transcribe(URL(fileURLWithPath: args[1]), language: language)
        print(srt ? SRT.format(captions) : describe(captions))

    case "burn":
        let captionsPath = option("--captions")
        let language = option("--language")
        let small = flag("--small")
        let trimText = option("--trim")
        var cropAspect: Crop.Aspect?
        if let value = option("--crop") {
            guard let aspect = Crop.Aspect(name: value), aspect != .free else {
                fail("--crop must be 1:1, 9:16, 4:5, 16:9 or original")
            }
            cropAspect = aspect
        }
        var style = CaptionStyle.default
        if let name = option("--style") {
            guard let found = StyleLibrary.style(named: name, in: styles) else {
                fail("No style called “\(name)”. Try: \(styles.map(\.name).joined(separator: ", "))")
            }
            style = found
        }
        if let value = option("--scale") {
            guard let n = Double(value) else { fail("--scale must be a number") }
            style.scale = n
        }
        if let value = option("--position") {
            // A name, or a number from the Top position (0) to the Bottom one (1).
            if let position = CaptionStyle.Position(rawValue: value.lowercased()) {
                style.position = position
            } else if let vertical = Double(value), (0...1).contains(vertical) {
                style.vertical = vertical
            } else {
                fail("--position must be top, middle, bottom or a number from 0 to 1")
            }
        }
        if flag("--words") { style.display = .word }
        if flag("--lines") { style.display = .line }
        if flag("--caps") { style.allCaps = true }
        if flag("--no-caps") { style.allCaps = false }
        guard args.count == 3 else { fail(usage) }
        let input = URL(fileURLWithPath: args[1]), output = URL(fileURLWithPath: args[2])
        var trim: Trim?
        if let trimText {
            let duration = try await AVURLAsset(url: input).load(.duration).seconds
            guard let parsed = Trim(parsing: trimText, duration: duration) else {
                fail("--trim must be like 1:05-1:20, 30- or -12.5, at least \(Trim.minLength) s long, inside the video")
            }
            trim = parsed
        }
        let captions: [Caption]
        if let captionsPath {
            captions = try SRT.parse(String(contentsOfFile: captionsPath, encoding: .utf8))
        } else {
            captions = try await transcribe(input, language: language, trim: trim)
        }
        log(describe(captions))

        let asset = AVURLAsset(url: input)
        let overlay = CaptionOverlay()
        var crop = Crop.full
        if let cropAspect {
            // The frame size, before cropping, from an uncropped composition.
            let frame = try await CaptionRenderer.composition(for: asset, overlay: overlay).renderSize
            if let ratio = cropAspect.ratio(for: frame) { crop = Crop.centered(ratio: ratio, in: frame) }
        }
        let composition = try await CaptionRenderer.composition(for: asset, overlay: overlay, crop: crop,
                                                                maxLongSide: small ? 1280 : nil)
        overlay.update(captions, size: composition.renderSize, style: style)
        log("Exporting…")
        try await CaptionRenderer.export(asset: asset, composition: composition, trim: trim, to: output)
        log("Wrote \(output.path)")

    case "styles":
        for style in styles {
            print("\(style.name)\(style.isBuiltIn ? "" : "  (yours)")  –  \(style.fontDisplayName)")
        }

    default:
        fail(usage)
    }
} catch {
    fail("error: \(error.localizedDescription)")
}
