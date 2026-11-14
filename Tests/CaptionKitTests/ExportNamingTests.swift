import XCTest
@testable import CaptionKit

final class ExportNamingTests: XCTestCase {
    func testUniqueURLNeverOverwrites() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let video = URL(fileURLWithPath: "/somewhere/clip.mov")

        let first = ExportNaming.url(for: video, in: folder, suffix: "-captioned")
        XCTAssertEqual(first.lastPathComponent, "clip-captioned.mp4")
        try Data().write(to: first)
        XCTAssertEqual(ExportNaming.url(for: video, in: folder, suffix: "-captioned").lastPathComponent,
                       "clip-captioned 2.mp4")
        XCTAssertEqual(ExportNaming.url(for: video, in: folder, suffix: "").lastPathComponent, "clip.mp4")
    }

    func testExportSize() {
        XCTAssertEqual(ExportNaming.exportSize(for: CGSize(width: 1920, height: 1080), maxLongSide: nil),
                       CGSize(width: 1920, height: 1080))
        XCTAssertEqual(ExportNaming.exportSize(for: CGSize(width: 1920, height: 1080), maxLongSide: 1280),
                       CGSize(width: 1280, height: 720))
        XCTAssertEqual(ExportNaming.exportSize(for: CGSize(width: 1080, height: 1920), maxLongSide: 1280),
                       CGSize(width: 720, height: 1280))
        // Odd results round down to even; small videos are left alone.
        XCTAssertEqual(ExportNaming.exportSize(for: CGSize(width: 1280, height: 562), maxLongSide: 1000),
                       CGSize(width: 1000, height: 438))
        XCTAssertEqual(ExportNaming.exportSize(for: CGSize(width: 640, height: 360), maxLongSide: 1280),
                       CGSize(width: 640, height: 360))
    }
}
