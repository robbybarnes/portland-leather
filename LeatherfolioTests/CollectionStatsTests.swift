import XCTest
import SwiftData
@testable import Leatherfolio

@MainActor
final class CollectionStatsTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        container = try AppModelContainer.make(inMemory: true)
        context = container.mainContext
    }

    override func tearDown() async throws {
        context = nil
        container = nil
    }

    private func fixtureCatalog() -> CatalogSeed {
        let json = """
        [
          {"name": "Test Tote", "category": "Tote", "sizes": ["Small"],
           "colors": ["Honey", "Black", "Cobalt"], "leatherTypes": ["Smooth"]},
          {"name": "Test Wallet", "category": "Wallet", "sizes": [],
           "colors": ["Plum", "Honey"], "leatherTypes": ["Smooth"]}
        ]
        """
        return CatalogSeed(data: Data(json.utf8))
    }

    private func normalizationCatalog() -> CatalogSeed {
        let json = """
        [
          {"name": "Test Tote", "category": "Tote", "sizes": [],
           "colors": ["Honey", "Café"], "leatherTypes": ["Smooth"]}
        ]
        """
        return CatalogSeed(data: Data(json.utf8))
    }

    private func makeItem(name: String = "Test Tote", color: String? = nil,
                          leatherType: LeatherType? = nil, isUnicorn: Bool = false,
                          myCost: Decimal? = nil, estimatedValue: Decimal? = nil,
                          rating: Int = 0) -> Item {
        let item = Item()
        item.name = name
        item.color = color
        item.leatherType = leatherType
        item.isUnicorn = isUnicorn
        item.myCost = myCost
        item.estimatedValue = estimatedValue
        item.rating = rating
        context.insert(item)
        return item
    }

    func testEmptyCollection() {
        let stats = CollectionStats(items: [], catalog: fixtureCatalog())
        XCTAssertEqual(stats.itemCount, 0)
        XCTAssertEqual(stats.distinctColorCount, 0)
        XCTAssertEqual(stats.distinctLeatherTypeCount, 0)
        XCTAssertEqual(stats.unicornCount, 0)
        XCTAssertEqual(stats.totalSpent, 0)
        XCTAssertEqual(stats.totalEstimatedValue, 0)
        XCTAssertEqual(stats.unrealizedDelta, 0)
        XCTAssertNil(stats.averageRating)
        XCTAssertTrue(stats.itemsByCategory.isEmpty)
        XCTAssertTrue(stats.lineCompleteness.isEmpty)
    }

    func testCountsAndDistincts() {
        let a = makeItem(color: "Honey", leatherType: .smooth, isUnicorn: true)
        let b = makeItem(color: "Honey", leatherType: .pebbled)
        let c = makeItem(color: "Black", leatherType: nil)
        let d = makeItem(color: nil)
        let stats = CollectionStats(items: [a, b, c, d], catalog: fixtureCatalog())
        XCTAssertEqual(stats.itemCount, 4)
        XCTAssertEqual(stats.distinctColorCount, 2, "Honey + Black; nil colors don't count")
        XCTAssertEqual(stats.distinctLeatherTypeCount, 2, "Smooth + Pebbled; nil doesn't count")
        XCTAssertEqual(stats.unicornCount, 1)
    }

    func testDistinctColorsNormalizeCaseDiacriticsAndSurroundingWhitespace() {
        let items = [
            makeItem(color: "Honey"),
            makeItem(color: " honey "),
            makeItem(color: "HÖNEY"),
            makeItem(color: "Café"),
            makeItem(color: " CAFE ")
        ]

        let stats = CollectionStats(items: items, catalog: normalizationCatalog())

        XCTAssertEqual(stats.distinctColorCount, 2)
    }

    func testItemsByCategoryOrderedAndNonEmptyOnly() {
        let a = makeItem(); a.category = .tote
        let b = makeItem(); b.category = .tote
        let c = makeItem(); c.category = .wallet
        let stats = CollectionStats(items: [a, b, c], catalog: fixtureCatalog())
        XCTAssertEqual(stats.itemsByCategory,
                       [CategoryCount(category: .tote, count: 2),
                        CategoryCount(category: .wallet, count: 1)],
                       "Ordered by ItemCategory.allCases; empty categories omitted")
    }

    func testMoneyTotalsUseDecimalExactly() {
        let a = makeItem(myCost: Decimal(string: "129.99")!, estimatedValue: Decimal(string: "150.00")!)
        let b = makeItem(myCost: Decimal(string: "0.01")!, estimatedValue: Decimal(string: "0.03")!)
        let c = makeItem(myCost: nil, estimatedValue: Decimal(string: "40.00")!) // no cost: counts in value, not delta
        let stats = CollectionStats(items: [a, b, c], catalog: fixtureCatalog())
        XCTAssertEqual(stats.totalSpent, Decimal(string: "130.00")!)
        XCTAssertEqual(stats.totalEstimatedValue, Decimal(string: "190.03")!)
        // Delta sums per-item valueDelta only where BOTH sides exist:
        // (150.00 - 129.99) + (0.03 - 0.01) = 20.03
        XCTAssertEqual(stats.unrealizedDelta, Decimal(string: "20.03")!)
    }

    func testAverageRatingCountsRatedItemsOnly() {
        let a = makeItem(rating: 5)
        let b = makeItem(rating: 2)
        let c = makeItem(rating: 0) // unrated — excluded
        let stats = CollectionStats(items: [a, b, c], catalog: fixtureCatalog())
        XCTAssertEqual(stats.averageRating!, 3.5, accuracy: 0.0001)
    }

    func testAverageRatingNilWhenNothingRated() {
        let a = makeItem(rating: 0)
        let stats = CollectionStats(items: [a], catalog: fixtureCatalog())
        XCTAssertNil(stats.averageRating)
    }

    func testLineCompleteness() {
        _ = makeItem(name: "Test Tote", color: "Honey")
        _ = makeItem(name: "Test Tote", color: "Black")
        _ = makeItem(name: "Test Tote", color: "Honey")        // duplicate color counts once
        _ = makeItem(name: "Test Tote", color: "Custom Teal")  // off-catalog color ignored for completeness
        _ = makeItem(name: "Unlisted Bag", color: "Honey")     // not a catalog line → no entry
        let items = try! context.fetch(FetchDescriptor<Item>())
        let stats = CollectionStats(items: items, catalog: fixtureCatalog())
        XCTAssertEqual(stats.lineCompleteness.count, 1)
        let tote = stats.lineCompleteness[0]
        XCTAssertEqual(tote.lineName, "Test Tote")
        XCTAssertEqual(tote.ownedColors.sorted(), ["Black", "Honey"])
        XCTAssertEqual(tote.totalColors, 3)
        XCTAssertEqual(tote.summary, "You own 2 of 3 colors of Test Tote")
    }

    func testLineCompletenessSortedByName() {
        _ = makeItem(name: "Test Wallet", color: "Plum")
        _ = makeItem(name: "Test Tote", color: "Honey")
        let items = try! context.fetch(FetchDescriptor<Item>())
        let stats = CollectionStats(items: items, catalog: fixtureCatalog())
        XCTAssertEqual(stats.lineCompleteness.map(\.lineName), ["Test Tote", "Test Wallet"])
    }

    func testCustomItemNameUsesPersistedCatalogAssociationForCompleteness() {
        let item = makeItem(name: "My Road Trip Bag", color: "Honey")
        item.catalogLineName = "Test Tote"

        let stats = CollectionStats(items: [item], catalog: fixtureCatalog())

        XCTAssertEqual(stats.lineCompleteness,
                       [LineCompleteness(
                        lineName: "Test Tote",
                        ownedColors: ["Honey"],
                        totalColors: 3)])
    }

    func testLineCompletenessNormalizesOwnedColorsAndEmitsCatalogSpelling() {
        let honey = makeItem(name: "Test Tote", color: " honey ")
        let honeyWithDiacritic = makeItem(name: "Test Tote", color: "HÖNEY")
        let cafeDecomposed = makeItem(name: "Test Tote", color: " CAFE\u{301} ")

        let stats = CollectionStats(
            items: [honey, honeyWithDiacritic, cafeDecomposed],
            catalog: normalizationCatalog())

        XCTAssertEqual(stats.lineCompleteness,
                       [LineCompleteness(
                        lineName: "Test Tote",
                        ownedColors: ["Café", "Honey"],
                        totalColors: 2)])
    }
}
