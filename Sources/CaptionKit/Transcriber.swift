import AVFoundation
import Speech

public enum CaptionError: LocalizedError {
    case noAudio, noLanguage, exportFailed
    public var errorDescription: String? {
        switch self {
        case .noAudio: "This video has no audio track."
        case .noLanguage: "Speech recognition isn't available for your language on this Mac."
        case .exportFailed: "Couldn't create the export session for this video."
        }
    }
}

/// On-device transcription with SpeechAnalyzer/SpeechTranscriber (macOS 26). Unlike
/// SFSpeechRecognizer, this needs no speech-recognition permission, so it also works
/// from the CLI.
public enum Transcriber {
    /// Transcribes the video's audio and returns words with timings. `status` reports
    /// progress ("Downloading speech model…" the first time a language is used). With a
    /// `range`, only that part is transcribed (much quicker for a long video); word times
    /// are still in the video's time.
    public static func words(for videoURL: URL, locale preferred: Locale = .current, range: Trim? = nil,
                             status: @escaping @Sendable (String) -> Void = { _ in }) async throws -> [Word] {
        let asset = AVURLAsset(url: videoURL)
        guard try await !asset.loadTracks(withMediaType: .audio).isEmpty else { throw CaptionError.noAudio }

        status("Extracting audio…")
        let audioURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".m4a")
        defer { try? FileManager.default.removeItem(at: audioURL) }
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw CaptionError.exportFailed
        }
        if let range { export.timeRange = range.timeRange }
        try await export.export(to: audioURL, as: .m4a)
        try Task.checkCancellation()

        var locale = await SpeechTranscriber.supportedLocale(equivalentTo: preferred)
        if locale == nil { locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-US")) }
        guard let locale else { throw CaptionError.noLanguage }

        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [],
                                            reportingOptions: [], attributeOptions: [.audioTimeRange])
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            status("Downloading speech model…")
            try await request.downloadAndInstall()
        }

        status("Transcribing…")
        let collector = Task { () throws -> [Word] in
            var words: [Word] = []
            for try await result in transcriber.results {
                words += Self.words(from: result.text)
            }
            return words
        }
        let file = try AVAudioFile(forReading: audioURL)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        if let last = try await analyzer.analyzeSequence(from: file) {
            try await analyzer.finalizeAndFinish(through: last)
        } else {
            await analyzer.cancelAndFinishNow()
        }
        let offset = range?.start ?? 0
        return try await collector.value
            .map { Word(text: $0.text, start: $0.start + offset, end: $0.end + offset) }
            .sorted { $0.start < $1.start }
    }

    /// Splits a result's attributed text into words using its per-run audio time ranges.
    /// Punctuation-only runs, and runs without a time range, attach to the previous word.
    static func words(from text: AttributedString) -> [Word] {
        var words: [Word] = []
        for run in text.runs {
            let piece = String(text[run.range].characters).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !piece.isEmpty else { continue }
            guard let range = run.audioTimeRange else {
                if !words.isEmpty { words[words.count - 1].text += piece }
                continue
            }
            if piece.allSatisfy({ $0.isPunctuation }), !words.isEmpty {
                words[words.count - 1].text += piece
                continue
            }
            // Rare multi-word runs split the run's time range evenly.
            let tokens = piece.split(separator: " ")
            let start = range.start.seconds
            let step = (range.end.seconds - start) / Double(tokens.count)
            for (i, token) in tokens.enumerated() {
                words.append(Word(text: String(token), start: start + step * Double(i), end: start + step * Double(i + 1)))
            }
        }
        return words
    }
}
