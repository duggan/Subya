import XCTest
@testable import CaptionKit

final class TrimTests: XCTestCase {
    func testFull() {
        XCTAssertTrue(Trim.full(20).isFull(duration: 20))
        XCTAssertFalse(Trim(start: 1, end: 20).isFull(duration: 20))
        XCTAssertFalse(Trim(start: 0, end: 19).isFull(duration: 20))
        XCTAssertEqual(Trim(start: 2, end: 7).length, 5)
    }

    func testEdgesStayInsideAndApart() {
        let trim = Trim(start: 2, end: 10)
        XCTAssertEqual(trim.settingStart(-3).start, 0)
        XCTAssertEqual(trim.settingStart(12).start, 10 - Trim.minLength)
        XCTAssertEqual(trim.settingStart(4), Trim(start: 4, end: 10))
        XCTAssertEqual(trim.settingEnd(30, duration: 20).end, 20)
        XCTAssertEqual(trim.settingEnd(0, duration: 20).end, 2 + Trim.minLength)
        XCTAssertEqual(trim.settingEnd(8, duration: 20), Trim(start: 2, end: 8))
    }

    func testShowsCaptionsThatOverlap() {
        let trim = Trim(start: 5, end: 10)
        XCTAssertTrue(trim.shows(Caption(start: 4, end: 6, text: "a")))
        XCTAssertTrue(trim.shows(Caption(start: 9, end: 12, text: "b")))
        XCTAssertFalse(trim.shows(Caption(start: 1, end: 5, text: "c")))
        XCTAssertFalse(trim.shows(Caption(start: 10, end: 11, text: "d")))
    }

    func testParsing() {
        XCTAssertEqual(Trim(parsing: "4-11", duration: 20), Trim(start: 4, end: 11))
        XCTAssertEqual(Trim(parsing: "1:05-1:20.5", duration: 100), Trim(start: 65, end: 80.5))
        XCTAssertEqual(Trim(parsing: "30-", duration: 100), Trim(start: 30, end: 100))
        XCTAssertEqual(Trim(parsing: "-12.5", duration: 100), Trim(start: 0, end: 12.5))
        XCTAssertEqual(Trim(parsing: "1:00:00-1:00:30", duration: 4000), Trim(start: 3600, end: 3630))
        XCTAssertEqual(Trim(parsing: "5-999", duration: 20), Trim(start: 5, end: 20))
        XCTAssertNil(Trim(parsing: "10-5", duration: 20))
        XCTAssertNil(Trim(parsing: "5-5.2", duration: 20))
        XCTAssertNil(Trim(parsing: "25-", duration: 20))
        XCTAssertNil(Trim(parsing: "1:75-2:00", duration: 200))
        XCTAssertNil(Trim(parsing: "abc", duration: 20))
        XCTAssertNil(Trim(parsing: "x-5", duration: 20))
    }

    func testSeconds() {
        XCTAssertEqual(Trim.seconds("12.5"), 12.5)
        XCTAssertEqual(Trim.seconds("2:03"), 123)
        XCTAssertNil(Trim.seconds("1:2:3:4"))
        XCTAssertNil(Trim.seconds(""))
    }

    func testMissingParts() {
        let trim = Trim(start: 0, end: 30)
        XCTAssertEqual(trim.missing(from: []), [trim])
        XCTAssertEqual(trim.missing(from: [Trim(start: 10, end: 20)]),
                       [Trim(start: 0, end: 10), Trim(start: 20, end: 30)])
        XCTAssertEqual(trim.missing(from: [Trim(start: 20, end: 40), Trim(start: -5, end: 10)]),
                       [Trim(start: 10, end: 20)])
        XCTAssertEqual(trim.missing(from: [Trim(start: 0, end: 29.5)]), [])  // sliver
        XCTAssertEqual(Trim(start: 12, end: 18).missing(from: [Trim(start: 10, end: 20)]), [])
    }

    func testMergeKeepsOrderAndClearsOverlaps() {
        var captions = [Caption(start: 10, end: 12.6, text: "b")]
        captions.merge([Caption(start: 1, end: 3, text: "a"), Caption(start: 12, end: 14, text: "c")])
        XCTAssertEqual(captions.map(\.text), ["a", "b", "c"])
        XCTAssertEqual(captions[1].end, 12)
        XCTAssertEqual(captions[0].end, 3)
    }
}
