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

    func testEveryFontRendersAndScaleGrowsText() throws {
        for font in CaptionStyle.Font.allCases {
            let small = try XCTUnwrap(CaptionRenderer.image(text: "Hi", size: size, style: CaptionStyle(font: font, scale: 0.8)))
            let big = try XCTUnwrap(CaptionRenderer.image(text: "Hi", size: size, style: CaptionStyle(font: font, scale: 1.6)))
            XCTAssertGreaterThan(opaqueRows(big, rows: 0..<562), opaqueRows(small, rows: 0..<562), font.rawValue)
        }
    }

    func testOverlayRerendersWhenStyleChanges() throws {
        let overlay = CaptionOverlay()
        let caps = [Caption(start: 0, end: 5, text: "Hi")]
        overlay.update(caps, size: size, style: CaptionStyle(scale: 0.8))
        let small = try XCTUnwrap(overlay.image(at: 1)).extent
        overlay.update(caps, size: size, style: CaptionStyle(scale: 1.6))
        let ctx = CIContext()
        let a = try XCTUnwrap(ctx.createCGImage(try XCTUnwrap(overlay.image(at: 1)), from: small))
        overlay.update(caps, size: size, style: CaptionStyle(scale: 0.8))
        let b = try XCTUnwrap(ctx.createCGImage(try XCTUnwrap(overlay.image(at: 1)), from: small))
        XCTAssertGreaterThan(opaqueRows(a, rows: 0..<562), opaqueRows(b, rows: 0..<562))
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
        let style = CaptionStyle(font: .meme, position: .top, scale: 1.3, allCaps: true)
        XCTAssertEqual(try JSONDecoder().decode(CaptionStyle.self, from: JSONEncoder().encode(style)), style)
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
