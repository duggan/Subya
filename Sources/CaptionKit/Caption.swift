import Foundation

/// One recognised word and when it was spoken, in seconds from the start of the video.
public struct Word: Equatable, Sendable {
    public var text: String
    public var start: Double
    public var end: Double

    public init(text: String, start: Double, end: Double) {
        self.text = text
        self.start = start
        self.end = end
    }
}

/// One line of on-screen text, shown from `start` until `end` (seconds).
public struct Caption: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var start: Double
    public var end: Double
    public var text: String

    public init(start: Double, end: Double, text: String, id: UUID = UUID()) {
        self.id = id
        self.start = start
        self.end = end
        self.text = text
    }
}

/// Groups timed words into short, readable caption lines.
public enum Chunker {
    /// A new caption starts after a pause longer than `maxGap`, after a word ending in
    /// punctuation, or when the line would pass `maxChars`. Each caption then stays up
    /// to `linger` seconds after its last word, without overlapping the next one.
    public static func captions(from words: [Word], videoEnd: Double,
                                maxChars: Int = 40, maxGap: Double = 0.6, linger: Double = 0.6) -> [Caption] {
        var groups: [[Word]] = []
        var current: [Word] = []
        func length(_ ws: [Word]) -> Int { ws.map(\.text).joined(separator: " ").count }

        for word in words {
            if let last = current.last {
                let gap = word.start - last.end
                let endsClause = last.text.last.map { ".,?!;:".contains($0) } ?? false
                if gap > maxGap || endsClause || length(current + [word]) > maxChars {
                    groups.append(current)
                    current = []
                }
            }
            current.append(word)
        }
        if !current.isEmpty { groups.append(current) }

        var caps = groups.map {
            Caption(start: $0.first!.start, end: $0.last!.end, text: $0.map(\.text).joined(separator: " "))
        }
        for i in caps.indices {
            let limit = i + 1 < caps.count ? caps[i + 1].start - 0.05 : videoEnd
            caps[i].end = max(caps[i].end, min(caps[i].end + linger, limit))
        }
        return caps
    }
}
