import XCTest
@testable import CaptionKit

final class VerticalPositionTests: XCTestCase {
    func testPositionsMapToVertical() {
        XCTAssertEqual(CaptionStyle(position: .top).vertical, 0)
        XCTAssertEqual(CaptionStyle(position: .middle).vertical, 0.5)
        XCTAssertEqual(CaptionStyle().vertical, 1)
        XCTAssertEqual(CaptionStyle(vertical: 0.3).position, nil)
        XCTAssertEqual(CaptionStyle(vertical: 0.5).position, .middle)
        XCTAssertEqual(CaptionStyle(vertical: 7).vertical, 1)  // clamped
    }

    func testSettingPositionMovesText() {
        var style = CaptionStyle(vertical: 0.3)
        style.position = .top
        XCTAssertEqual(style.vertical, 0)
    }

    func testSnapping() {
        XCTAssertEqual(CaptionStyle.snapped(0.52), 0.5)
        XCTAssertEqual(CaptionStyle.snapped(0.03), 0)
        XCTAssertEqual(CaptionStyle.snapped(0.97), 1)
        XCTAssertEqual(CaptionStyle.snapped(0.3), 0.3)
        XCTAssertEqual(CaptionStyle.snapped(-2), 0)
        XCTAssertEqual(CaptionStyle.snapped(1.5), 1)
    }

    func testStylesSavedWithOnlyAPositionStillLoad() throws {
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(CaptionStyle(name: "Old"))) as! [String: Any]
        json.removeValue(forKey: "vertical")
        json["position"] = "middle"
        let style = try JSONDecoder().decode(CaptionStyle.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(style.vertical, 0.5)
    }

    func testCustomVerticalRoundTrips() throws {
        let style = CaptionStyle(vertical: 0.33)
        XCTAssertEqual(try JSONDecoder().decode(CaptionStyle.self, from: JSONEncoder().encode(style)).vertical, 0.33)
    }

    func testRendersBetweenTopAndMiddle() throws {
        let size = CGSize(width: 1280, height: 562)
        func firstOpaqueRow(_ vertical: Double) throws -> Int {
            let image = try XCTUnwrap(CaptionRenderer.image(text: "Here", size: size,
                                                            style: CaptionStyle(outlineWidth: 0, shadow: false, vertical: vertical)))
            var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
            let ctx = CGContext(data: &data, width: image.width, height: image.height, bitsPerComponent: 8,
                                bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return (0..<image.height).first { y in (0..<image.width).contains { data[(y * image.width + $0) * 4 + 3] > 0 } } ?? -1
        }
        let top = try firstOpaqueRow(0), quarter = try firstOpaqueRow(0.25), middle = try firstOpaqueRow(0.5)
        XCTAssertLessThan(top, quarter)
        XCTAssertLessThan(quarter, middle)
        XCTAssertEqual(Double(quarter), Double(top + middle) / 2, accuracy: 3)
    }
}

final class TextBlockTests: XCTestCase {
    let size = CGSize(width: 1280, height: 562)

    func testMovingVerticallyOnlyOffsetsTheBlock() throws {
        let overlay = CaptionOverlay()
        let caps = [Caption(start: 0, end: 5, text: "Move me")]
        overlay.update(caps, size: size, style: CaptionStyle(vertical: 1))
        let bottom = try XCTUnwrap(overlay.image(at: 1)).extent
        overlay.update(caps, size: size, style: CaptionStyle(vertical: 0))
        let top = try XCTUnwrap(overlay.image(at: 1)).extent
        XCTAssertEqual(top.size, bottom.size)
        XCTAssertEqual(top.minX, bottom.minX)
        XCTAssertGreaterThan(top.minY, bottom.minY + 200)  // higher up (y grows upwards)
    }

    func testBlockMatchesTheFullFrameImage() throws {
        let style = CaptionStyle(vertical: 0.3)
        let block = try XCTUnwrap(CaptionRenderer.textBlock(text: "Same", size: size, style: style))
        let full = try XCTUnwrap(CaptionRenderer.image(text: "Same", size: size, style: style))
        // Moving the block's rect by its travel gives the same rect as rendering there.
        let moved = block.rect(at: 0.8, from: 0.3)
        let direct = try XCTUnwrap(CaptionRenderer.textBlock(text: "Same", size: size,
                                                             style: CaptionStyle(vertical: 0.8))).rect
        XCTAssertEqual(moved.minY, direct.minY, accuracy: 1)
        XCTAssertEqual(full.width, 1280)
        XCTAssertLessThan(block.rect.width, 1280)
        XCTAssertLessThan(block.rect.height, 300)
    }
}
