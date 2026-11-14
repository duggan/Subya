import XCTest
@testable import CaptionKit

final class StyleLibraryTests: XCTestCase {
    var defaults: UserDefaults!
    var suite: String!

    override func setUp() {
        suite = "subya-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    func testBuiltInsHaveStableUniqueIDsAndNames() {
        let ids = CaptionStyle.builtIns.map(\.id), names = CaptionStyle.builtIns.map(\.name)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(Set(names).count, names.count)
        XCTAssertEqual(CaptionStyle.builtIns[0].id.uuidString, "5B0BA000-0000-4000-8000-000000000001")
        XCTAssertTrue(CaptionStyle.default.isBuiltIn)
    }

    func testSaveAndLoadCustomStyles() {
        let mine = CaptionStyle.builtIns[1].duplicate(named: "Loud")
        XCTAssertFalse(mine.isBuiltIn)
        StyleLibrary.saveCustom([mine], to: defaults)
        XCTAssertEqual(StyleLibrary.loadCustom(from: defaults), [mine])
        XCTAssertEqual(StyleLibrary.all(from: defaults).count, CaptionStyle.builtIns.count + 1)
    }

    func testLoadWithNothingSavedOrGarbage() {
        XCTAssertEqual(StyleLibrary.loadCustom(from: defaults), [])
        defaults.set(Data("nope".utf8), forKey: StyleLibrary.customStylesKey)
        XCTAssertEqual(StyleLibrary.loadCustom(from: defaults), [])
    }

    func testFindByNameIgnoringCaseCustomWins() {
        let custom = CaptionStyle.default.duplicate(named: "meme")
        let all = CaptionStyle.builtIns + [custom]
        XCTAssertEqual(StyleLibrary.style(named: "MEME", in: all)?.id, custom.id)
        XCTAssertEqual(StyleLibrary.style(named: "boxed", in: all)?.name, "Boxed")
        XCTAssertNil(StyleLibrary.style(named: "nope", in: all))
    }

    func testUniqueName() {
        let all = CaptionStyle.builtIns + [CaptionStyle.default.duplicate(named: "Meme 2")]
        XCTAssertEqual(StyleLibrary.uniqueName("Fresh", among: all), "Fresh")
        XCTAssertEqual(StyleLibrary.uniqueName("Meme", among: all), "Meme 3")
    }

    func testFontFallbacks() {
        XCTAssertEqual(CaptionStyle.font(named: "Impact", size: 20).fontName, "Impact")
        XCTAssertTrue(CaptionStyle.font(named: CaptionStyle.systemRounded, size: 20).fontName.contains("Rounded"))
        XCTAssertNotNil(CaptionStyle.font(named: "No-Such-Font", size: 20))
        XCTAssertTrue(CaptionStyle(fontName: "No-Such-Font").fontDisplayName.contains("missing"))
    }
}
