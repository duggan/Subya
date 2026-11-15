import XCTest
@testable import CaptionKit

final class CaptionRendererTests: XCTestCase {
    let size = CGSize(width: 1280, height: 562)

    func testImageMatchesVideoSizeAndHasTextNearBottom() throws {
        let image = try XCTUnwrap(CaptionRenderer.image(text: "Hello there", size: size, style: .default))
        XCTAssertEqual(image.width, 1280)
        XCTAssertEqual(image.height, 562)
        XCTAssertGreaterThan(opaqueRows(image, rows: 450..<562), 0)  // bottom of the frame
        XCTAssertEqual(opaqueRows(image, rows: 0..<250), 0)           // top stays clear
    }

    func testOverlayShowsCaptionOnlyInItsTimeRange() {
        let overlay = CaptionOverlay()
        overlay.update([Caption(start: 1, end: 2, text: "Hi"), Caption(start: 3, end: 4, text: "  ")], size: size, style: .default)
        XCTAssertNil(overlay.image(at: 0.5))
        XCTAssertNotNil(overlay.image(at: 1.5))
        XCTAssertNil(overlay.image(at: 2.0))
        XCTAssertNil(overlay.image(at: 3.5))  // blank captions are skipped
    }

    func testPositionsPlaceTextInTheRightBand() throws {
        func rows(_ position: CaptionStyle.Position) throws -> (top: Int, middle: Int, bottom: Int) {
            let image = try XCTUnwrap(CaptionRenderer.image(text: "Where am I", size: size,
                                                            style: CaptionStyle(position: position)))
            return (opaqueRows(image, rows: 0..<150), opaqueRows(image, rows: 220..<340), opaqueRows(image, rows: 412..<562))
        }
        let top = try rows(.top), middle = try rows(.middle), bottom = try rows(.bottom)
        XCTAssertTrue(top.top > 0 && top.middle == 0 && top.bottom == 0, "top: \(top)")
        XCTAssertTrue(middle.top == 0 && middle.middle > 0 && middle.bottom == 0, "middle: \(middle)")
        XCTAssertTrue(bottom.top == 0 && bottom.middle == 0 && bottom.bottom > 0, "bottom: \(bottom)")
    }

    func testEveryBuiltInRendersAndScaleGrowsText() throws {
        for var style in CaptionStyle.builtIns {
            style.scale = 0.8
            let small = try XCTUnwrap(CaptionRenderer.image(text: "Hi", size: size, style: style))
            style.scale = 1.6
            let big = try XCTUnwrap(CaptionRenderer.image(text: "Hi", size: size, style: style))
            XCTAssertGreaterThan(opaqueRows(big, rows: 0..<562), opaqueRows(small, rows: 0..<562), style.name)
        }
    }

    func testBoxFillsBehindTheText() throws {
        let plain = CaptionStyle(outlineWidth: 0, shadow: false)
        var boxed = plain
        boxed.box = true
        boxed.boxColor = RGBA(1, 0, 0)
        let a = pixels(try XCTUnwrap(CaptionRenderer.image(text: "I I", size: size, style: plain)))
        let b = pixels(try XCTUnwrap(CaptionRenderer.image(text: "I I", size: size, style: boxed)))
        XCTAssertGreaterThan(count(b) { $0.r > 200 && $0.g < 40 && $0.b < 40 && $0.a > 200 }, 1000)  // red box
        XCTAssertEqual(count(a) { $0.r > 200 && $0.g < 40 }, 0)
    }

    func testTextAndOutlineColours() throws {
        let style = CaptionStyle(textColor: RGBA(0, 0, 1), outlineColor: RGBA(0, 1, 0), outlineWidth: 0.12, shadow: false)
        let px = pixels(try XCTUnwrap(CaptionRenderer.image(text: "HELLO", size: size, style: style)))
        XCTAssertGreaterThan(count(px) { $0.b > 200 && $0.r < 40 && $0.g < 40 }, 200, "blue fill")
        XCTAssertGreaterThan(count(px) { $0.g > 200 && $0.r < 40 && $0.b < 40 }, 200, "green outline")
    }

    func testNoOutlineDrawsOnlyTheFill() throws {
        let style = CaptionStyle(outlineWidth: 0, shadow: false)
        let px = pixels(try XCTUnwrap(CaptionRenderer.image(text: "HELLO", size: size, style: style)))
        XCTAssertGreaterThan(count(px) { $0.r > 240 && $0.g > 240 && $0.b > 240 && $0.a > 240 }, 200, "white fill")
        XCTAssertEqual(count(px) { $0.a > 200 && $0.r < 30 && $0.g < 30 && $0.b < 30 }, 0, "no black outline")
    }

    func testOverlayRerendersWhenStyleChanges() throws {
        let overlay = CaptionOverlay()
        let caps = [Caption(start: 0, end: 5, text: "Hi")]
        overlay.update(caps, size: size, style: CaptionStyle(scale: 0.8))
        let small = try XCTUnwrap(overlay.image(at: 1)).extent
        overlay.update(caps, size: size, style: CaptionStyle(scale: 1.6))
        let big = try XCTUnwrap(overlay.image(at: 1)).extent
        XCTAssertGreaterThan(big.height, small.height)
        XCTAssertGreaterThan(big.width, small.width)
        overlay.update(caps, size: size, style: CaptionStyle(scale: 0.8))
        XCTAssertEqual(try XCTUnwrap(overlay.image(at: 1)).extent, small)
    }

    func testAllCapsUppercasesText() throws {
        // Same text, caps on vs off, gives different images.
        let lower = try XCTUnwrap(CaptionRenderer.image(text: "abc", size: size, style: CaptionStyle()))
        let upper = try XCTUnwrap(CaptionRenderer.image(text: "abc", size: size, style: CaptionStyle(allCaps: true)))
        let explicit = try XCTUnwrap(CaptionRenderer.image(text: "ABC", size: size, style: CaptionStyle()))
        XCTAssertNotEqual(pixels(lower), pixels(upper))
        XCTAssertEqual(pixels(upper), pixels(explicit))
    }

    func testStyleRoundTripsThroughJSON() throws {
        let style = CaptionStyle(name: "Mine", fontName: "Impact", textColor: RGBA(1, 0.5, 0), box: true,
                                 position: .top, scale: 1.3, allCaps: true)
        XCTAssertEqual(try JSONDecoder().decode(CaptionStyle.self, from: JSONEncoder().encode(style)), style)
    }

    private struct Pixel { let r, g, b, a: UInt8 }

    private func count(_ data: [UInt8], where match: (Pixel) -> Bool) -> Int {
        stride(from: 0, to: data.count, by: 4).filter {
            match(Pixel(r: data[$0], g: data[$0 + 1], b: data[$0 + 2], a: data[$0 + 3]))
        }.count
    }

    private func pixels(_ image: CGImage) -> [UInt8] {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let ctx = CGContext(data: &data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return data
    }

    /// Counts rows (top-down) in `rows` that contain any non-transparent pixel.
    private func opaqueRows(_ image: CGImage, rows: Range<Int>) -> Int {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let ctx = CGContext(data: &data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return rows.filter { y in (0..<width).contains { x in data[(y * width + x) * 4 + 3] > 0 } }.count
    }
}
