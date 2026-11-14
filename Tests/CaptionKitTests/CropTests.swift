import XCTest
@testable import CaptionKit

final class CropTests: XCTestCase {
    let hd = CGSize(width: 1920, height: 1080)

    func testCenteredPortraitInLandscape() {
        let crop = Crop.centered(ratio: 9.0 / 16, in: hd)
        XCTAssertEqual(crop.rect.height, 1)
        XCTAssertEqual(crop.rect.width * hd.width, 607.5, accuracy: 0.01)
        XCTAssertEqual(crop.rect.midX, 0.5, accuracy: 0.0001)
        let px = crop.pixelRect(in: hd)
        XCTAssertEqual(px.width, 606)   // even
        XCTAssertEqual(px.height, 1080)
        XCTAssertEqual(px.minY, 0)
    }

    func testCenteredWideInPortrait() {
        let crop = Crop.centered(ratio: 16.0 / 9, in: CGSize(width: 1080, height: 1920))
        XCTAssertEqual(crop.rect.width, 1)
        XCTAssertEqual(crop.rect.midY, 0.5, accuracy: 0.0001)
    }

    func testFull() {
        XCTAssertTrue(Crop.full.isFull)
        XCTAssertEqual(Crop.full.pixelRect(in: hd), CGRect(origin: .zero, size: hd))
        XCTAssertTrue(Crop.centered(ratio: 16.0 / 9, in: hd).isFull)
        XCTAssertFalse(Crop.centered(ratio: 1, in: hd).isFull)
    }

    func testPixelRectFlipsToBottomLeftOrigin() {
        // Top quarter of the frame on screen is the top of the CI image (high y).
        let px = Crop(rect: CGRect(x: 0, y: 0, width: 0.5, height: 0.25)).pixelRect(in: hd)
        XCTAssertEqual(px, CGRect(x: 0, y: 810, width: 960, height: 270))
    }

    func testMoveStaysInside() {
        let crop = Crop(rect: CGRect(x: 0.2, y: 0.2, width: 0.5, height: 0.5))
        let moved = crop.moved(dx: 0.1, dy: -0.1).rect.origin
        XCTAssertEqual(moved.x, 0.3, accuracy: 0.0001)
        XCTAssertEqual(moved.y, 0.1, accuracy: 0.0001)
        XCTAssertEqual(crop.moved(dx: 9, dy: 9).rect.origin, CGPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(crop.moved(dx: -9, dy: -9).rect.origin, .zero)
    }

    func testFreeResizeFromBottomRight() {
        let crop = Crop.full.resized(.bottomRight, to: CGPoint(x: 0.6, y: 0.4), frame: hd)
        XCTAssertEqual(crop.rect, CGRect(x: 0, y: 0, width: 0.6, height: 0.4))
    }

    func testResizeKeepsTheOppositeCornerAndStaysInFrame() {
        let start = Crop(rect: CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6))
        let crop = start.resized(.topLeft, to: CGPoint(x: -0.5, y: -0.5), frame: hd)
        XCTAssertEqual(crop.rect.maxX, 0.8, accuracy: 0.0001)
        XCTAssertEqual(crop.rect.maxY, 0.8, accuracy: 0.0001)
        XCTAssertEqual(crop.rect.minX, 0, accuracy: 0.0001)
        XCTAssertEqual(crop.rect.minY, 0, accuracy: 0.0001)
    }

    func testResizeWithRatioKeepsPixelShape() {
        let start = Crop.centered(ratio: 1, in: hd)
        let crop = start.resized(.bottomRight, to: CGPoint(x: 0.9, y: 0.6), ratio: 1, frame: hd)
        let px = CGSize(width: crop.rect.width * hd.width, height: crop.rect.height * hd.height)
        XCTAssertEqual(px.width / px.height, 1, accuracy: 0.001)
        XCTAssertEqual(crop.rect.minX, start.rect.minX, accuracy: 0.0001)
        XCTAssertLessThanOrEqual(crop.rect.maxY, 1.0001)
    }

    func testResizeHasAMinimumSize() {
        let crop = Crop.full.resized(.bottomRight, to: .zero, frame: hd)
        XCTAssertEqual(crop.rect.width, Crop.minSide, accuracy: 0.0001)
        XCTAssertEqual(crop.rect.height, Crop.minSide, accuracy: 0.0001)
    }

    func testAspectNames() {
        XCTAssertEqual(Crop.Aspect(name: "9:16"), .portrait)
        XCTAssertEqual(Crop.Aspect(name: "ORIGINAL"), .original)
        XCTAssertNil(Crop.Aspect(name: "3:2"))
        XCTAssertEqual(Crop.Aspect.original.ratio(for: hd)!, 16.0 / 9, accuracy: 0.0001)
        XCTAssertNil(Crop.Aspect.free.ratio(for: hd))
    }
}
