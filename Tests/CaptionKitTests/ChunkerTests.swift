import XCTest
@testable import CaptionKit

final class ChunkerTests: XCTestCase {
    func w(_ text: String, _ start: Double, _ end: Double) -> Word { Word(text: text, start: start, end: end) }

    func testBreaksAfterPunctuation() {
        let words = [w("Hello,", 0, 0.4), w("there", 0.4, 0.8), w("friend.", 0.8, 1.2), w("Bye", 1.3, 1.6)]
        let caps = Chunker.captions(from: words, videoEnd: 10)
        XCTAssertEqual(caps.map(\.text), ["Hello,", "there friend.", "Bye"])
    }

    func testBreaksOnLongPause() {
        let caps = Chunker.captions(from: [w("one", 0, 0.5), w("two", 2.0, 2.5)], videoEnd: 10)
        XCTAssertEqual(caps.map(\.text), ["one", "two"])
    }

    func testBreaksAtMaxChars() {
        let words = (0..<12).map { w("word", Double($0) * 0.3, Double($0) * 0.3 + 0.25) }
        let caps = Chunker.captions(from: words, videoEnd: 10, maxChars: 20)
        XCTAssertTrue(caps.allSatisfy { $0.text.count <= 20 })
        XCTAssertEqual(caps.map(\.text).joined(separator: " ").split(separator: " ").count, 12)
    }

    func testLingersWithoutOverlappingNextCaption() {
        let caps = Chunker.captions(from: [w("a.", 0, 1.0), w("b.", 1.2, 2.0)], videoEnd: 2.3)
        XCTAssertEqual(caps[0].end, 1.15, accuracy: 0.001)  // next start minus 0.05
        XCTAssertEqual(caps[1].end, 2.3, accuracy: 0.001)   // capped at the video's end
    }

    func testNoWordsNoCaptions() {
        XCTAssertTrue(Chunker.captions(from: [], videoEnd: 5).isEmpty)
    }
}
