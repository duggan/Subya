import Foundation

/// Reads and writes SubRip (.srt) caption files.
public enum SRT {
    public enum ParseError: LocalizedError, Equatable {
        case badTiming(String)
        public var errorDescription: String? {
            switch self {
            case .badTiming(let line): "Couldn't read the SRT timing line “\(line)”."
            }
        }
    }

    public static func format(_ captions: [Caption]) -> String {
        captions.enumerated().map { i, c in
            "\(i + 1)\n\(timestamp(c.start)) --> \(timestamp(c.end))\n\(c.text)\n"
        }.joined(separator: "\n")
    }

    public static func parse(_ text: String) throws -> [Caption] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\u{FEFF}", with: "")
        var captions: [Caption] = []
        for block in normalized.components(separatedBy: "\n\n") {
            var lines = block.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            if let first = lines.first, first.allSatisfy(\.isNumber) { lines.removeFirst() }
            guard let timing = lines.first else { continue }
            let parts = timing.components(separatedBy: "-->")
            guard parts.count == 2,
                  let start = seconds(parts[0].trimmingCharacters(in: .whitespaces)),
                  let end = seconds(parts[1].trimmingCharacters(in: .whitespaces).components(separatedBy: " ")[0])
            else { throw ParseError.badTiming(timing) }
            captions.append(Caption(start: start, end: end, text: lines.dropFirst().joined(separator: "\n")))
        }
        return captions
    }

    static func timestamp(_ t: Double) -> String {
        let ms = Int((max(0, t) * 1000).rounded())
        return String(format: "%02d:%02d:%02d,%03d", ms / 3_600_000, ms / 60_000 % 60, ms / 1000 % 60, ms % 1000)
    }

    static func seconds(_ s: String) -> Double? {
        let parts = s.replacingOccurrences(of: ",", with: ".").split(separator: ":")
        guard parts.count == 3, let h = Double(parts[0]), let m = Double(parts[1]), let sec = Double(parts[2]) else {
            return nil
        }
        return h * 3600 + m * 60 + sec
    }
}
