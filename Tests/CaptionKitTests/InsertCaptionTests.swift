import XCTest
@testable import CaptionKit

final class InsertCaptionTests: XCTestCase {
    func testInsertsIntoAGapWithDefaultLength() {
        var caps = [Caption(start: 0, end: 1, text: "a"), Caption(start: 6, end: 7, text: "b")]
        let id = caps.insertCaption(at: 2, videoEnd: 10)
        XCTAssertEqual(caps.map(\.text), ["a", "", "b"])
        XCTAssertEqual(caps[1].id, id)
        XCTAssertEqual(caps[1].start, 2)
        XCTAssertEqual(caps[1].end, 4)
    }

    func testStopsAtTheNextCaption() {
        var caps = [Caption(start: 3, end: 4, text: "b")]
        caps.insertCaption(at: 2, videoEnd: 10)
        XCTAssertEqual(caps[0].end, 3)
    }

    func testEndsTheCaptionShowingAtThatTime() {
        var caps = [Caption(start: 0, end: 5, text: "long")]
        caps.insertCaption(at: 2, videoEnd: 10)
        XCTAssertEqual(caps.map(\.text), ["long", ""])
        XCTAssertEqual(caps[0].end, 2)
        XCTAssertEqual(caps[1].start, 2)
        XCTAssertEqual(caps[1].end, 4)
    }

    func testClampsToTheVideo() {
        var caps: [Caption] = []
        caps.insertCaption(at: 9.95, videoEnd: 10)
        XCTAssertEqual(caps[0].start, 9.8, accuracy: 0.0001)
        XCTAssertEqual(caps[0].end, 10, accuracy: 0.0001)

        var early: [Caption] = []
        early.insertCaption(at: -1, videoEnd: 10)
        XCTAssertEqual(early[0].start, 0)
    }

    func testKeepsAMinimumLengthWhenTheNextCaptionIsRightThere() {
        var caps = [Caption(start: 2.05, end: 3, text: "b")]
        caps.insertCaption(at: 2, videoEnd: 10)
        XCTAssertEqual(caps[0].text, "")
        XCTAssertEqual(caps[0].end, 2.2, accuracy: 0.0001)
    }

    func testWorksOnASilentVideoWithNoCaptions() {
        var caps: [Caption] = []
        caps.insertCaption(at: 0, videoEnd: 1.5)
        XCTAssertEqual(caps.count, 1)
        XCTAssertEqual(caps[0].end, 1.5)
    }
}
