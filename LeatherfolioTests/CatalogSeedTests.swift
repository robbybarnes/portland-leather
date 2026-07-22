import XCTest
@testable import Leatherfolio

final class CatalogSeedTests: XCTestCase {

    func testSharedDecodesBundledJSON() {
        // Tests are hosted in the app, so Bundle.main resolves the app bundle.
        XCTAssertFalse(CatalogSeed.shared.lines.isEmpty, "bundled plg_catalog.json should decode to non-empty lines")
        XCTAssertGreaterThanOrEqual(CatalogSeed.shared.lines.count, 15)
    }

    func testEveryLineUsesValidCategoryAndLeatherTypeRawValues() {
        for line in CatalogSeed.shared.lines {
            XCTAssertNotNil(ItemCategory(rawValue: line.category),
                            "\(line.name) has invalid category \(line.category)")
            for lt in line.leatherTypes {
                XCTAssertNotNil(LeatherType(rawValue: lt),
                                "\(line.name) has invalid leather type \(lt)")
            }
        }
    }

    func testLinesInToteCategoryNonEmpty() {
        let totes = CatalogSeed.shared.lines(in: .tote)
        XCTAssertFalse(totes.isEmpty)
        XCTAssertTrue(totes.allSatisfy { $0.category == ItemCategory.tote.rawValue })
    }

    func testLineNamedExactMatch() {
        let line = CatalogSeed.shared.line(named: "Crossbody Tote")
        XCTAssertNotNil(line)
        XCTAssertEqual(line?.sizes, ["Mini", "Medium", "Original"])
        XCTAssertNil(CatalogSeed.shared.line(named: "crossbody tote"), "match is exact, not case-insensitive")
        XCTAssertNil(CatalogSeed.shared.line(named: "Nonexistent Bag"))
    }

    func testAllColorsDedupedAndSorted() {
        let colors = CatalogSeed.shared.allColors
        XCTAssertFalse(colors.isEmpty)
        XCTAssertEqual(colors, Array(Set(colors)).sorted(), "allColors must be deduped and sorted")
        XCTAssertTrue(colors.contains("Honey"))
        XCTAssertEqual(colors.filter { $0 == "Nutmeg" }.count, 1, "staple colors appear once despite being on many lines")
    }

    func testMalformedDataFallsBackToEmpty() {
        let malformed = CatalogSeed(data: Data("{ not json".utf8))
        XCTAssertTrue(malformed.lines.isEmpty)
        XCTAssertTrue(malformed.allColors.isEmpty)
        XCTAssertNil(malformed.line(named: "Leather Tote Bag"))
        XCTAssertTrue(malformed.lines(in: .tote).isEmpty)
    }
}
