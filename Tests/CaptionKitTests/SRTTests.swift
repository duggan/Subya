import XCTest
@testable import CaptionKit

final class SRTTests: XCTestCase {
    func testFormat() {
        let srt = SRT.format([Caption(start: 0, end: 1.5, text: "Hi"), Caption(start: 61.25, end: 3725.004, text: "Bye")])
        XCTAssertEqual(srt, """
            1
            00:00:00,000 --> 00:00:01,500
            Hi

            2
            00:01:01,250 --> 01:02:05,004
            Bye

            """)
    }

    func testRoundTrip() throws {
        let caps = [Caption(start: 0.25, end: 3.3, text: "You may face"), Caption(start: 3.3, end: 4.26, text: "two\nlines")]
        let parsed = try SRT.parse(SRT.format(caps))
        XCTAssertEqual(parsed.map(\.text), caps.map(\.text))
        for (a, b) in zip(parsed, caps) {
            XCTAssertEqual(a.start, b.start, accuracy: 0.0005)
            XCTAssertEqual(a.end, b.end, accuracy: 0.0005)
        }
    }

    func testParsesCRLFBOMAndDotMilliseconds() throws {
        let parsed = try SRT.parse("\u{FEFF}1\r\n00:00:01.000 --> 00:00:02.500\r\nHello\r\n\r\n")
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed[0].start, 1)
        XCTAssertEqual(parsed[0].end, 2.5)
        XCTAssertEqual(parsed[0].text, "Hello")
    }

    func testBadTimingThrows() {
        XCTAssertThrowsError(try SRT.parse("1\nnot a time\nHello")) {
            XCTAssertEqual($0 as? SRT.ParseError, .badTiming("not a time"))
        }
    }
}
