import CoreMedia
import Speech
import XCTest
@testable import CaptionKit

final class TranscriberWordsTests: XCTestCase {
    func timed(_ text: String, _ start: Double, _ end: Double) -> AttributedString {
        var s = AttributedString(text)
        s.audioTimeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600),
                                       end: CMTime(seconds: end, preferredTimescale: 600))
        return s
    }

    func testWordsWithTimes() {
        let text = timed("Hello", 0, 0.5) + AttributedString(" ") + timed("world", 0.6, 1.0)
        let words = Transcriber.words(from: text)
        XCTAssertEqual(words.map(\.text), ["Hello", "world"])
        XCTAssertEqual(words[1].start, 0.6, accuracy: 0.01)
    }

    func testPunctuationAttachesToPreviousWord() {
        let text = timed("Hi", 0, 0.4) + AttributedString(".")
        XCTAssertEqual(Transcriber.words(from: text).map(\.text), ["Hi."])
    }

    func testMultiWordRunSplitsTimeEvenly() {
        let words = Transcriber.words(from: timed("in that", 1, 2))
        XCTAssertEqual(words.map(\.text), ["in", "that"])
        XCTAssertEqual(words[0].end, 1.5, accuracy: 0.01)
        XCTAssertEqual(words[1].start, 1.5, accuracy: 0.01)
    }
}
