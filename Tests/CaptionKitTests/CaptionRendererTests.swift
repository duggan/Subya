import XCTest
@testable import CaptionKit

final class CaptionRendererTests: XCTestCase {
    let size = CGSize(width: 1280, height: 562)

    func testImageMatchesVideoSizeAndHasTextNearBottom() throws {
        let image = try XCTUnwrap(CaptionRenderer.image(text: "Hello there", size: size, scale: 1))
        XCTAssertEqual(image.width, 1280)
        XCTAssertEqual(image.height, 562)
        XCTAssertGreaterThan(opaqueRows(image, rows: 450..<562), 0)  // bottom of the frame
        XCTAssertEqual(opaqueRows(image, rows: 0..<250), 0)           // top stays clear
    }

    func testOverlayShowsCaptionOnlyInItsTimeRange() {
        let overlay = CaptionOverlay()
        overlay.update([Caption(start: 1, end: 2, text: "Hi"), Caption(start: 3, end: 4, text: "  ")], size: size, scale: 1)
        XCTAssertNil(overlay.image(at: 0.5))
        XCTAssertNotNil(overlay.image(at: 1.5))
        XCTAssertNil(overlay.image(at: 2.0))
        XCTAssertNil(overlay.image(at: 3.5))  // blank captions are skipped
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
