import XCTest
import SwiftData
@testable import Leatherfolio

@MainActor
final class ItemFilterTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        container = try AppModelContainer.make(inMemory: true)
        context = container.mainContext
    }

    override func tearDown() {
        context = nil
        container = nil
    }

    // MARK: Fixture builder

    @discardableResult
    private func makeItem(
        name: String = "Item",
        category: ItemCategory = .other,
        leatherType: LeatherType? = nil,
        color: String? = nil,
        size: String? = nil,
        condition: ItemCondition? = nil,
        isWishlist: Bool = false,
        favorite: Bool = false,
        isUnicorn: Bool = false,
        rating: Int = 0,
        estimatedValue: Decimal? = nil,
        dateAcquired: Date? = nil,
        createdAt: Date = Date(timeIntervalSince1970: 0),
        notes: String? = nil,
        tags: [String] = []
    ) -> Item {
        let item = Item()
        item.name = name
        item.category = category
        item.leatherType = leatherType
        item.color = color
        item.size = size
        item.condition = condition
        item.isWishlist = isWishlist
        item.favorite = favorite
        item.isUnicorn = isUnicorn
        item.rating = rating
        item.estimatedValue = estimatedValue
        item.dateAcquired = dateAcquired
        item.createdAt = createdAt
        item.notes = notes
        context.insert(item)
        item.tags = tags.map { name in
            let tag = Tag(name: name)
            context.insert(tag)
            return tag
        }
        return item
    }

    // MARK: Scope

    func testDefaultScopeIsOwnedAndExcludesWishlist() {
        let owned = makeItem(name: "Owned")
        makeItem(name: "Wished", isWishlist: true)
        let filter = ItemFilter()
        XCTAssertEqual(filter.apply(to: fetchAll()).map(\.id), [owned.id])
    }

    func testWishlistScopeExcludesOwned() {
        makeItem(name: "Owned")
        let wished = makeItem(name: "Wished", isWishlist: true)
        var filter = ItemFilter()
        filter.scope = .wishlist
        XCTAssertEqual(filter.apply(to: fetchAll()).map(\.id), [wished.id])
    }

    // MARK: Field filters

    func testCategoryLeatherColorSizeConditionFilters() {
        let match = makeItem(name: "Match", category: .tote, leatherType: .suede,
                             color: "Honey", size: "Medium", condition: .excellent)
        makeItem(name: "WrongCategory", category: .wallet, leatherType: .suede,
                 color: "Honey", size: "Medium", condition: .excellent)
        makeItem(name: "WrongLeather", category: .tote, leatherType: .pebbled,
                 color: "Honey", size: "Medium", condition: .excellent)
        makeItem(name: "WrongColor", category: .tote, leatherType: .suede,
                 color: "Cognac", size: "Medium", condition: .excellent)
        makeItem(name: "WrongSize", category: .tote, leatherType: .suede,
                 color: "Honey", size: "Large", condition: .excellent)
        makeItem(name: "WrongCondition", category: .tote, leatherType: .suede,
                 color: "Honey", size: "Medium", condition: .worn)

        var filter = ItemFilter()
        filter.category = .tote
        filter.leatherType = .suede
        filter.color = "honey"   // case-insensitive match
        filter.size = "Medium"
        filter.condition = .excellent
        XCTAssertEqual(filter.apply(to: fetchAll()).map(\.id), [match.id])
    }

    func testFavoritesUnicornsAndMinRating() {
        let match = makeItem(name: "Match", favorite: true, isUnicorn: true, rating: 4)
        makeItem(name: "NotFavorite", isUnicorn: true, rating: 5)
        makeItem(name: "NotUnicorn", favorite: true, rating: 5)
        makeItem(name: "LowRating", favorite: true, isUnicorn: true, rating: 2)

        var filter = ItemFilter()
        filter.favoritesOnly = true
        filter.unicornsOnly = true
        filter.minRating = 3
        XCTAssertEqual(filter.apply(to: fetchAll()).map(\.id), [match.id])
    }

    // MARK: Full-text query

    func testQueryMatchesNameNotesAndTagsCaseAndDiacriticInsensitive() {
        let byName = makeItem(name: "Café Tote")
        let byNotes = makeItem(name: "A", notes: "bought at the cafe downtown")
        let byTag = makeItem(name: "B", tags: ["CAFE finds"])
        makeItem(name: "C", notes: "nothing relevant")

        var filter = ItemFilter()
        filter.query = "cafe"
        let ids = Set(filter.apply(to: fetchAll()).map(\.id))
        XCTAssertEqual(ids, [byName.id, byNotes.id, byTag.id])
    }

    func testQueryTokensAllMustMatch() {
        let match = makeItem(name: "Willow Tote", notes: "honey colorway")
        makeItem(name: "Willow Wallet", notes: "cognac")
        var filter = ItemFilter()
        filter.query = "willow honey"
        XCTAssertEqual(filter.apply(to: fetchAll()).map(\.id), [match.id])
    }

    func testBlankQueryMatchesEverything() {
        makeItem(name: "A")
        makeItem(name: "B")
        var filter = ItemFilter()
        filter.query = "   "
        XCTAssertEqual(filter.apply(to: fetchAll()).count, 2)
    }

    // MARK: Sorting

    func testSortByNameAscending() {
        makeItem(name: "banana")
        makeItem(name: "Apple")
        makeItem(name: "cherry")
        var filter = ItemFilter()
        filter.sortKey = .name
        filter.sortAscending = true
        XCTAssertEqual(filter.apply(to: fetchAll()).map(\.name),
                       ["Apple", "banana", "cherry"])
    }

    func testSortByCreatedAtDescendingIsDefault() {
        makeItem(name: "old", createdAt: Date(timeIntervalSince1970: 100))
        makeItem(name: "new", createdAt: Date(timeIntervalSince1970: 200))
        let filter = ItemFilter()
        XCTAssertEqual(filter.apply(to: fetchAll()).map(\.name), ["new", "old"])
    }

    func testSortByEstimatedValueNilsLastInBothDirections() {
        makeItem(name: "cheap", estimatedValue: Decimal(50))
        makeItem(name: "pricey", estimatedValue: Decimal(300))
        makeItem(name: "unknown", estimatedValue: nil)

        var filter = ItemFilter()
        filter.sortKey = .estimatedValue
        filter.sortAscending = true
        XCTAssertEqual(filter.apply(to: fetchAll()).map(\.name),
                       ["cheap", "pricey", "unknown"])
        filter.sortAscending = false
        XCTAssertEqual(filter.apply(to: fetchAll()).map(\.name),
                       ["pricey", "cheap", "unknown"])
    }

    func testSortByDateAcquiredNilsLast() {
        makeItem(name: "first", dateAcquired: Date(timeIntervalSince1970: 100))
        makeItem(name: "second", dateAcquired: Date(timeIntervalSince1970: 200))
        makeItem(name: "undated", dateAcquired: nil)
        var filter = ItemFilter()
        filter.sortKey = .dateAcquired
        filter.sortAscending = true
        XCTAssertEqual(filter.apply(to: fetchAll()).map(\.name),
                       ["first", "second", "undated"])
    }

    // MARK: Chips

    func testActiveChipsAndRemove() {
        var filter = ItemFilter()
        XCTAssertEqual(filter.activeFilterCount, 0)
        filter.category = .tote
        filter.color = "Honey"
        filter.favoritesOnly = true
        filter.minRating = 3
        XCTAssertEqual(filter.activeChips.map(\.label),
                       ["Tote", "Honey", "Favorites", "3+ stars"])
        filter.remove(.color)
        XCTAssertEqual(filter.activeChips.map(\.label),
                       ["Tote", "Favorites", "3+ stars"])
    }

    func testClearFiltersKeepsScopeQueryAndSort() {
        var filter = ItemFilter()
        filter.scope = .wishlist
        filter.query = "honey"
        filter.sortKey = .name
        filter.category = .tote
        filter.unicornsOnly = true
        filter.clearFilters()
        XCTAssertEqual(filter.activeFilterCount, 0)
        XCTAssertEqual(filter.scope, .wishlist)
        XCTAssertEqual(filter.query, "honey")
        XCTAssertEqual(filter.sortKey, .name)
    }

    // MARK: Helpers

    private func fetchAll() -> [Item] {
        (try? context.fetch(FetchDescriptor<Item>())) ?? []
    }
}
