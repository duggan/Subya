import CoreMedia
import Foundation

/// The part of the video to keep, in seconds of the source. Captions keep their source
/// times; export cuts to this range, so they land in the right place.
public struct Trim: Equatable, Sendable {
    public var start: Double
    public var end: Double

    /// The shortest clip a trim can make.
    public static let minLength = 0.5

    public init(start: Double, end: Double) {
        self.start = start
        self.end = end
    }

    /// The whole video.
    public static func full(_ duration: Double) -> Trim { Trim(start: 0, end: max(duration, 0)) }

    public var length: Double { end - start }
    public var range: ClosedRange<Double> { start...max(end, start) }

    public func isFull(duration: Double) -> Bool { start <= 0.001 && end >= duration - 0.001 }

    public var timeRange: CMTimeRange {
        CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600),
                    end: CMTime(seconds: end, preferredTimescale: 600))
    }

    /// Moves the start, keeping it inside the video and at least `minLength` before the end.
    public func settingStart(_ time: Double) -> Trim {
        Trim(start: min(max(time, 0), max(end - Self.minLength, 0)), end: end)
    }

    /// Moves the end, keeping it inside the video and at least `minLength` after the start.
    public func settingEnd(_ time: Double, duration: Double) -> Trim {
        Trim(start: start, end: max(min(time, duration), min(start + Self.minLength, duration)))
    }

    /// Whether any of the caption shows inside the trim.
    public func shows(_ caption: Caption) -> Bool { caption.end > start && caption.start < end }

    /// The parts of this range that `covered` doesn't cover, in order, leaving out slivers
    /// shorter than `minimum` seconds. Used to transcribe only what's new after a trim grows.
    public func missing(from covered: [Trim], minimum: Double = 1) -> [Trim] {
        var parts: [Trim] = []
        var cursor = start
        for done in covered.sorted(by: { $0.start < $1.start }) where done.end > cursor && done.start < end {
            if done.start > cursor { parts.append(Trim(start: cursor, end: done.start)) }
            cursor = max(cursor, done.end)
        }
        if cursor < end { parts.append(Trim(start: cursor, end: end)) }
        return parts.filter { $0.length >= minimum }
    }

    /// Parses `start-end` (either side may be empty, meaning the video's start or end) with
    /// times as seconds (`12.5`), `m:ss` or `h:mm:ss`. For example `1:05-1:20`, `30-`.
    public init?(parsing text: String, duration: Double) {
        let parts = text.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let startText = parts[0].trimmingCharacters(in: .whitespaces)
        let endText = parts[1].trimmingCharacters(in: .whitespaces)
        guard let start = startText.isEmpty ? 0 : Self.seconds(startText),
              let end = endText.isEmpty ? duration : Self.seconds(endText) else { return nil }
        let clampedEnd = min(end, duration)
        guard start >= 0, clampedEnd - start >= Self.minLength else { return nil }
        self.init(start: start, end: clampedEnd)
    }

    /// `12.5`, `1:05` or `1:02:05.5` as seconds.
    public static func seconds(_ text: String) -> Double? {
        let fields = text.split(separator: ":", omittingEmptySubsequences: false)
        guard (1...3).contains(fields.count) else { return nil }
        var total = 0.0
        for (i, field) in fields.enumerated() {
            guard let value = Double(field), value >= 0 else { return nil }
            if i > 0 && value >= 60 { return nil }
            total = total * 60 + value
        }
        return total
    }
}
