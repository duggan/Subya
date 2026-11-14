import AVFoundation
import CaptionKit
import Foundation

// Developer CLI for CaptionKit. Same transcription and rendering as the app.

/// Built-in styles plus the ones made in the app's Settings.
let styles = StyleLibrary.all(from: UserDefaults(suiteName: StyleLibrary.appDomain) ?? .standard)

let usage = """
    usage: subya transcribe <video> [--srt] [--language <id>]
           subya burn <video> <output.mp4> [--captions <file.srt>] [--language <id>]
                      [--style <name>] [--position top|middle|bottom] [--caps|--no-caps]
                      [--scale <n>] [--small]
           subya styles

    transcribe  Print the captions Subya would make (as SRT with --srt).
    burn        Burn captions into a copy of the video. Uses --captions if given
                (e.g. an edited `transcribe --srt`), otherwise transcribes first.
                --style picks a style by name, including your own from the app's
                Settings (default: Classic). --position, --caps and --scale override it.
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

func transcribe(_ url: URL, language: String?) async throws -> [Caption] {
    let locale = language.map { Locale(identifier: $0) } ?? .current
    let words = try await Transcriber.words(for: url, locale: locale) { log($0) }
    let duration = try await AVURLAsset(url: url).load(.duration).seconds
    return Chunker.captions(from: words, videoEnd: duration)
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
            guard let position = CaptionStyle.Position(rawValue: value.lowercased()) else { fail(usage) }
            style.position = position
        }
        if flag("--caps") { style.allCaps = true }
        if flag("--no-caps") { style.allCaps = false }
        guard args.count == 3 else { fail(usage) }
        let input = URL(fileURLWithPath: args[1]), output = URL(fileURLWithPath: args[2])
        let captions: [Caption]
        if let captionsPath {
            captions = try SRT.parse(String(contentsOfFile: captionsPath, encoding: .utf8))
        } else {
            captions = try await transcribe(input, language: language)
        }
        log(describe(captions))

        let asset = AVURLAsset(url: input)
        let overlay = CaptionOverlay()
        let composition = try await CaptionRenderer.composition(for: asset, overlay: overlay,
                                                                maxLongSide: small ? 1280 : nil)
        overlay.update(captions, size: composition.renderSize, style: style)
        log("Exporting…")
        try await CaptionRenderer.export(asset: asset, composition: composition, to: output)
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
