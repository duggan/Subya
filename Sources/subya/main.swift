import AVFoundation
import CaptionKit
import Foundation

// Developer CLI for CaptionKit. Same transcription and rendering as the app.

let usage = """
    usage: subya transcribe <video> [--srt]
           subya burn <video> <output.mp4> [--captions <file.srt>] [--scale <n>]
                      [--font <name>] [--position top|middle|bottom] [--caps]

    transcribe  Print the captions Subya would make (as SRT with --srt).
    burn        Burn captions into a copy of the video. Uses --captions if given
                (e.g. an edited `transcribe --srt`), otherwise transcribes first.
                --scale sets the text size (1.0 is the app's default).
                --font is one of: \(CaptionStyle.Font.allCases.map(\.rawValue).joined(separator: ", ")).
                --caps sets all caps (on by default for meme; --no-caps turns it off).
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

func transcribe(_ url: URL) async throws -> [Caption] {
    let words = try await Transcriber.words(for: url) { log($0) }
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
        guard args.count == 2 else { fail(usage) }
        let captions = try await transcribe(URL(fileURLWithPath: args[1]))
        print(srt ? SRT.format(captions) : describe(captions))

    case "burn":
        let captionsPath = option("--captions")
        var style = CaptionStyle()
        if let value = option("--scale") {
            guard let n = Double(value) else { fail("--scale must be a number") }
            style.scale = n
        }
        if let value = option("--font") {
            guard let font = CaptionStyle.Font(rawValue: value.lowercased()) else { fail(usage) }
            style.font = font
            style.allCaps = font.prefersAllCaps
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
            captions = try await transcribe(input)
        }
        log(describe(captions))

        let asset = AVURLAsset(url: input)
        let overlay = CaptionOverlay()
        let composition = try await CaptionRenderer.composition(for: asset, overlay: overlay)
        overlay.update(captions, size: composition.renderSize, style: style)
        log("Exporting…")
        try await CaptionRenderer.export(asset: asset, composition: composition, to: output)
        log("Wrote \(output.path)")

    default:
        fail(usage)
    }
} catch {
    fail("error: \(error.localizedDescription)")
}
