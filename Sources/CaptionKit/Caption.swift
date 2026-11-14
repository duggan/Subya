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

extension Array where Element == Caption {
    /// Inserts an empty caption at `time` (seconds), for text the transcript didn't give,
    /// like a line over a silent reaction shot, and returns its id.
    ///
    /// A caption that's showing at `time` now ends there. The new one runs for `length`
    /// seconds, or until the next caption or the end of the video if that's sooner (but
    /// never less than 0.2 s). The array stays sorted by start time.
    @discardableResult
    public mutating func insertCaption(at time: Double, videoEnd: Double, length: Double = 2.0) -> Caption.ID {
        let start = Swift.min(Swift.max(time, 0), Swift.max(videoEnd - 0.2, 0))
        for i in indices where self[i].start < start && self[i].end > start {
            self[i].end = start
        }
        let next = first { $0.start >= start }?.start ?? videoEnd
        let end = Swift.max(Swift.min(start + length, next, videoEnd), Swift.min(start + 0.2, videoEnd))
        let caption = Caption(start: start, end: end, text: "")
        insert(caption, at: firstIndex { $0.start > start } ?? endIndex)
        return caption.id
    }
}

/// Which end of a caption a timeline drag changes.
public enum CaptionEdge: Sendable {
    case start, end
}

extension Array where Element == Caption {
    /// The span a caption can use without overlapping the others: from the latest end
    /// of the captions before it to the earliest start of those after it (or the video's
    /// ends).
    func room(for index: Int, videoEnd: Double) -> (lower: Double, upper: Double) {
        let caption = self[index]
        var lower = 0.0, upper = videoEnd
        for (i, other) in enumerated() where i != index {
            if other.start < caption.start || (other.start == caption.start && i < index) {
                lower = Swift.max(lower, other.end)
            } else {
                upper = Swift.min(upper, other.start)
            }
        }
        return (lower, Swift.max(upper, lower))
    }

    /// Moves a caption so it starts at `start`, keeping its length, clamped so it doesn't
    /// overlap its neighbours or leave the video.
    public mutating func moveCaption(_ id: Caption.ID, toStart start: Double, videoEnd: Double) {
        guard let i = firstIndex(where: { $0.id == id }) else { return }
        let length = self[i].end - self[i].start
        let room = room(for: i, videoEnd: videoEnd)
        let newStart = Swift.min(Swift.max(start, room.lower), Swift.max(room.upper - length, room.lower))
        self[i].start = newStart
        self[i].end = Swift.min(newStart + length, room.upper)
    }

    /// Moves one end of a caption to `time`, keeping it at least `minLength` long and
    /// clear of its neighbours.
    public mutating func setEdge(_ edge: CaptionEdge, of id: Caption.ID, to time: Double, videoEnd: Double,
                                 minLength: Double = 0.2) {
        guard let i = firstIndex(where: { $0.id == id }) else { return }
        let room = room(for: i, videoEnd: videoEnd)
        switch edge {
        case .start:
            self[i].start = Swift.min(Swift.max(time, room.lower), Swift.max(self[i].end - minLength, room.lower))
        case .end:
            self[i].end = Swift.max(Swift.min(time, room.upper), Swift.min(self[i].start + minLength, room.upper))
        }
    }
}
