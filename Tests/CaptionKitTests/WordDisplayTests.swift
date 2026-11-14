import XCTest
@testable import CaptionKit

final class WordDisplayTests: XCTestCase {
    func testChunkerKeepsTranscriptWordTimings() {
        let words = [Word(text: "keep", start: 1.0, end: 1.3), Word(text: "it", start: 1.4, end: 1.5),
                     Word(text: "clean.", start: 1.7, end: 2.2)]
        let caps = Chunker.captions(from: words, videoEnd: 10)
        XCTAssertEqual(caps[0].wordStarts, [1.0, 1.4, 1.7])
    }

    func testUsesTranscriptTimings() {
        let cap = Caption(start: 1, end: 3, text: "keep it clean", wordStarts: [1.2, 1.6, 2.0])
        XCTAssertEqual(cap.timedWords.map(\.text), ["keep", "it", "clean"])
        XCTAssertEqual(cap.timedWords.map(\.start), [1, 1.6, 2.0])  // first word from the caption's start
        XCTAssertEqual(cap.timedWords.map(\.end), [1.6, 2.0, 3])
        XCTAssertEqual(cap.word(at: 1.0), "keep")
        XCTAssertEqual(cap.word(at: 1.7), "it")
        XCTAssertEqual(cap.word(at: 2.9), "clean")
        XCTAssertNil(cap.word(at: 3.0))
        XCTAssertNil(cap.word(at: 0.5))
    }

    func testTypoFixKeepsTimingsButChangingWordCountSpreadsThem() {
        var cap = Caption(start: 0, end: 3, text: "teh cat sat", wordStarts: [0, 2.5, 2.8])
        cap.text = "the cat sat"
        XCTAssertEqual(cap.timedWords[1].start, 2.5)
        cap.text = "the big cat sat"
        XCTAssertEqual(cap.timedWords.count, 4)
        XCTAssertNotEqual(cap.timedWords[1].start, 2.5)
    }

    func testSpreadsByLengthWithoutTimings() {
        let cap = Caption(start: 0, end: 10, text: "a abcdefgh")  // weights 3 and 10
        let words = cap.timedWords
        XCTAssertEqual(words[0].end, 10 * 3 / 13, accuracy: 0.0001)
        XCTAssertEqual(words[1].start, words[0].end)
        XCTAssertEqual(words[1].end, 10)
    }

    func testEmptyTextHasNoWords() {
        XCTAssertTrue(Caption(start: 0, end: 1, text: "   ").timedWords.isEmpty)
    }

    func testMoveShiftsAndResizeStretchesWordTimings() {
        var caps = [Caption(start: 1, end: 3, text: "a b", wordStarts: [1, 2])]
        caps.moveCaption(caps[0].id, toStart: 4, videoEnd: 10)
        XCTAssertEqual(caps[0].wordStarts, [4, 5])
        caps.setEdge(.end, of: caps[0].id, to: 8, videoEnd: 10)  // 4–6 becomes 4–8
        XCTAssertEqual(caps[0].wordStarts, [4, 6])
        XCTAssertEqual(caps[0].timedWords.map(\.text), ["a", "b"])
    }

    func testOverlayShowsTheCurrentWordInWordMode() {
        let overlay = CaptionOverlay()
        let caps = [Caption(start: 0, end: 2, text: "one two", wordStarts: [0, 1])]
        let size = CGSize(width: 640, height: 360)
        overlay.update(caps, size: size, style: CaptionStyle(display: .word))
        XCTAssertEqual(overlay.displayText(at: 0.5), "one")
        XCTAssertEqual(overlay.displayText(at: 1.5), "two")
        XCTAssertNotNil(overlay.image(at: 1.5))
        overlay.update(caps, size: size, style: CaptionStyle())
        XCTAssertEqual(overlay.displayText(at: 1.5), "one two")
    }

    func testStylesSavedBeforeDisplayExistedStillLoad() throws {
        var style = CaptionStyle(name: "Old", fontName: "Impact", scale: 1.4)
        style.display = .word
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(style)) as! [String: Any]
        json.removeValue(forKey: "display")
        let old = try JSONDecoder().decode(CaptionStyle.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(old.name, "Old")
        XCTAssertEqual(old.scale, 1.4)
        XCTAssertEqual(old.display, .line)
    }

    func testOneWordBuiltIn() {
        let style = CaptionStyle.builtIns.first { $0.name == "One Word" }
        XCTAssertEqual(style?.display, .word)
        XCTAssertEqual(CaptionStyle.default.display, .line)
    }
}

final class WordRetimingTests: XCTestCase {
    func testMovesOneWordAndClampsBetweenNeighbours() {
        var caps = [Caption(start: 0, end: 3, text: "a b c", wordStarts: [0, 1, 2])]
        let id = caps[0].id
        caps.setWordStart(1, of: id, to: 1.5)
        XCTAssertEqual(caps[0].wordStarts, [0, 1.5, 2])
        caps.setWordStart(1, of: id, to: 5)
        XCTAssertEqual(caps[0].wordStarts![1], 1.92, accuracy: 0.0001)  // next word's start minus 0.08
        caps.setWordStart(2, of: id, to: -1)
        XCTAssertEqual(caps[0].wordStarts![2], 2.0, accuracy: 0.0001)    // previous word plus 0.08
        caps.setWordStart(2, of: id, to: 9)
        XCTAssertEqual(caps[0].wordStarts![2], 2.92, accuracy: 0.0001)   // caption end minus 0.08
    }

    func testFixesSpreadTimingsBeforeMovingAWord() {
        var caps = [Caption(start: 0, end: 4, text: "aa bb cc")]  // spread evenly: 0, 1.33, 2.67
        let before = caps[0].timedWords.map(\.start)
        caps.setWordStart(2, of: caps[0].id, to: 3)
        let after = caps[0].timedWords.map(\.start)
        XCTAssertEqual(after[0], before[0])
        XCTAssertEqual(after[1], before[1], accuracy: 0.0001)  // untouched
        XCTAssertEqual(after[2], 3)
    }

    func testIgnoresTheFirstWordAndOutOfRangeIndexes() {
        var caps = [Caption(start: 0, end: 2, text: "a b", wordStarts: [0, 1])]
        caps.setWordStart(0, of: caps[0].id, to: 0.5)
        caps.setWordStart(5, of: caps[0].id, to: 0.5)
        XCTAssertEqual(caps[0].wordStarts, [0, 1])
    }
}
