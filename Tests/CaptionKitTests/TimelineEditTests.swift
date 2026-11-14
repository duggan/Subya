import XCTest
@testable import CaptionKit

final class TimelineEditTests: XCTestCase {
    var caps = [
        Caption(start: 1, end: 2, text: "a"),
        Caption(start: 3, end: 4, text: "b"),
        Caption(start: 6, end: 7, text: "c"),
    ]

    func testMoveKeepsLength() {
        caps.moveCaption(caps[1].id, toStart: 4.5, videoEnd: 10)
        XCTAssertEqual(caps[1].start, 4.5)
        XCTAssertEqual(caps[1].end, 5.5)
    }

    func testMoveStopsAtNeighbours() {
        caps.moveCaption(caps[1].id, toStart: 0, videoEnd: 10)
        XCTAssertEqual(caps[1].start, 2)   // previous caption's end
        caps.moveCaption(caps[1].id, toStart: 9, videoEnd: 10)
        XCTAssertEqual(caps[1].end, 6)     // next caption's start
        XCTAssertEqual(caps[1].start, 5)
    }

    func testMoveStopsAtVideoEnds() {
        caps.moveCaption(caps[0].id, toStart: -3, videoEnd: 10)
        XCTAssertEqual(caps[0].start, 0)
        caps.moveCaption(caps[2].id, toStart: 20, videoEnd: 10)
        XCTAssertEqual(caps[2].start, 9)
        XCTAssertEqual(caps[2].end, 10)
    }

    func testStartEdgeClampsToNeighbourAndMinimumLength() {
        caps.setEdge(.start, of: caps[1].id, to: 0, videoEnd: 10)
        XCTAssertEqual(caps[1].start, 2)
        caps.setEdge(.start, of: caps[1].id, to: 5, videoEnd: 10)
        XCTAssertEqual(caps[1].start, 3.8, accuracy: 0.0001)
        XCTAssertEqual(caps[1].end, 4)
    }

    func testEndEdgeClampsToNeighbourAndMinimumLength() {
        caps.setEdge(.end, of: caps[1].id, to: 9, videoEnd: 10)
        XCTAssertEqual(caps[1].end, 6)
        caps.setEdge(.end, of: caps[1].id, to: 0, videoEnd: 10)
        XCTAssertEqual(caps[1].end, 3.2, accuracy: 0.0001)
        XCTAssertEqual(caps[1].start, 3)
    }

    func testLastCaptionEndStopsAtVideoEnd() {
        caps.setEdge(.end, of: caps[2].id, to: 30, videoEnd: 10)
        XCTAssertEqual(caps[2].end, 10)
    }

    func testUnknownIDDoesNothing() {
        let before = caps
        caps.moveCaption(UUID(), toStart: 5, videoEnd: 10)
        caps.setEdge(.end, of: UUID(), to: 5, videoEnd: 10)
        XCTAssertEqual(caps, before)
    }
}
