import XCTest
@testable import Leatherfolio

final class FilterOptionsTests: XCTestCase {
    func testMergesSeedAndCollectionValuesDedupedCaseInsensitiveSorted() {
        let options = FilterOptions.make(
            itemColors: ["honey", "Chili Red", nil, "  ", "Bone"],
            itemSizes: ["Custom 40cm", nil, "medium"],
            seedColors: ["Honey", "Cognac", "Bone"],
            seedSizes: ["Mini", "Medium", "Large"]
        )
        // Seed spelling wins on case-insensitive duplicates ("Honey" not "honey");
        // collection-only values ("Chili Red", "Custom 40cm") are appended; blanks
        // and nils dropped; result sorted.
        XCTAssertEqual(options.colors, ["Bone", "Chili Red", "Cognac", "Honey"])
        XCTAssertEqual(options.sizes, ["Custom 40cm", "Large", "Medium", "Mini"])
    }

    func testEmptyInputsProduceEmptyOptions() {
        let options = FilterOptions.make(itemColors: [], itemSizes: [],
                                         seedColors: [], seedSizes: [])
        XCTAssertEqual(options.colors, [])
        XCTAssertEqual(options.sizes, [])
    }
}
