# Leatherfolio Phase 4: Polish (Organize, Stats, Design, Accessibility) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish Leatherfolio v1 by adding filter/sort/search with the Owned/Wishlist scope, a stats screen over the existing `CollectionStats`, the warm editorial design language, a full accessibility pass, the app icon, and release-readiness docs.

**Architecture:** Pure, unit-tested value types (`ItemFilter`, `FilterOptions`, `AccessibilityText`, `CurrencyFormat`, `StatsHeadline`) do all the logic; SwiftUI views stay thin renderers over them. Filtering happens in Swift over `@Query` results (fine at personal-collection scale — hundreds of items); no `#Predicate` composition beyond what already exists. A `Theme` enum plus asset-catalog colorsets carry the design language.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, Swift Charts, XCTest, XcodeGen, xcodebuild. Zero third-party dependencies in the app target.

**Prerequisites (assumed complete per the master plan):** Phases 0–3 — models with typed accessors (`category`, `leatherType`, `condition`, `valueDelta`, `primaryPhoto`), `ImageStore`, `CollectionView` grid with `ItemCell`, `AddEditItemView` with cascading `CatalogSeed` pickers, `ItemDetailView` with QR label card, `ScannerView` + `ScanRouter` + `QRService`, `AppRouter`, and a fully-tested `CollectionStats` value type.

## Global Constraints

- **iOS deployment target:** 18.0. Swift language mode 6.
- **Bundle ID:** `com.robbybarnes.leatherfolio`. **Display name:** Leatherfolio. **URL scheme:** `leatherfolio`.
- **No third-party dependencies** in the app target. Dev tooling allowed: XcodeGen (via Homebrew), SwiftLint optional.
- **Project generation:** `project.yml` (XcodeGen) is source of truth; `Leatherfolio.xcodeproj` is generated and **gitignored**. Regenerate with `xcodegen generate` after any file add/remove.
- **Build/test loop:** `xcodegen generate && xcodebuild -project Leatherfolio.xcodeproj -scheme Leatherfolio -destination 'platform=iOS Simulator,name=iPhone 16' build` (tests: `test` action, same destination; substitute any available iPhone simulator via `xcrun simctl list devices available`).
- **CloudKit schema rules (every model, every phase):** every property optional or with a default; every relationship optional; no `@Attribute(.unique)`; no `.deny` delete rules. Sync itself stays OFF (`cloudKitDatabase: .none`) until signing exists; do not add the iCloud capability yet.
- **Photos:** never store image bytes in queries/lists. Originals via `@Attribute(.externalStorage)`; grids use `ImageStore` thumbnails only.
- **Money:** `Decimal` everywhere; render with the user's locale currency.
- **Naming/copy:** no "Portland Leather Goods" trademark in app name, bundle ID, or App Store-facing strings; in-app reference data may name product lines (research-permission caveat is in the spec). Scraped data stays in `research/` (repo), curated seed ships as `Leatherfolio/Resources/plg_catalog.json`.
- **Commits:** small, per task, conventional-commit style (`feat:`, `test:`, `chore:`).

All commands below run from the repo root: `/Users/robbybarnes/GitHub/portland-leather`.

## File map (this phase)

| File | Responsibility |
|---|---|
| `Leatherfolio/Features/Collection/ItemFilter.swift` | Pure filter/sort/search engine over `[Item]` (Task 1) |
| `Leatherfolio/Features/Collection/FilterOptions.swift` | Picker option lists = seed values ∪ values present in collection (Task 2) |
| `Leatherfolio/Features/Collection/CollectionView.swift` | Rewritten home screen: scope, search, chips, grid/list toggle (Task 2) |
| `Leatherfolio/Features/Collection/FilterSheetView.swift` | Filter sheet form (Task 2) |
| `Leatherfolio/Features/Collection/FilterChipsRow.swift` | Active-filter chips + clear-all (Task 2) |
| `Leatherfolio/Support/CurrencyFormat.swift` | Locale-aware Decimal currency strings (Task 3) |
| `Leatherfolio/Features/Stats/StatsHeadline.swift` | Pure headline string composition (Task 3) |
| `Leatherfolio/Features/Stats/StatsView.swift` | Stats screen over `CollectionStats` (Task 3) |
| `Leatherfolio/Support/Theme.swift` | Palette, spacing, serif display fonts, card style (Task 4) |
| `Leatherfolio/Resources/Assets.xcassets/*.colorset` | 7 light/dark colorsets (Task 4) |
| `Leatherfolio/Resources/Assets.xcassets/AppIcon.appiconset` | Generated 1024px icon (Task 4) |
| `Scripts/generate_app_icon.swift` | Repeatable icon generator (Task 4) |
| `Leatherfolio/Support/AccessibilityText.swift` | Pure VoiceOver label composition (Task 5) |
| `Leatherfolio/Features/ItemDetail/RatingControl.swift` | Accessible star control (Task 5) |
| `README.md`, `CHANGELOG.md` | Release-readiness docs (Task 6) |

Tests live in `LeatherfolioTests/` (existing unit-test target, hosted by the app so `Bundle.main` resources like `plg_catalog.json` and asset-catalog colors resolve).

---

### Task 1: Filter/sort engine (`ItemFilter`)

**Files:**
- Create: `Leatherfolio/Features/Collection/ItemFilter.swift`
- Test: `LeatherfolioTests/ItemFilterTests.swift`

**Interfaces:**
- Consumes: `Item` (Phase 1 model — `name`, `notes`, `tags`, `color`, `size`, `favorite`, `isUnicorn`, `isWishlist`, `rating`, `createdAt`, `dateAcquired`, `estimatedValue`, and typed accessors `category: ItemCategory`, `leatherType: LeatherType?`, `condition: ItemCondition?`), enums from `Leatherfolio/Models/Enums.swift`.
- Produces (Tasks 2–3 rely on these exact names):
  - `enum CollectionScope: String, CaseIterable, Identifiable { case owned, wishlist }`
  - `enum SortKey: String, CaseIterable, Identifiable { case createdAt, name, dateAcquired, estimatedValue, rating }`
  - `struct FilterChip: Equatable, Identifiable { enum Kind; let kind: Kind; let label: String }`
  - `struct ItemFilter: Equatable` with vars `scope, category, leatherType, color, size, condition, favoritesOnly, unicornsOnly, minRating, query, sortKey, sortAscending`; funcs `matches(_ item: Item) -> Bool`, `apply(to items: [Item]) -> [Item]`, `mutating remove(_ kind: FilterChip.Kind)`, `mutating clearFilters()`; computed `activeChips: [FilterChip]`, `activeFilterCount: Int`; `static func normalized(_ s: String) -> String`.

`ItemFilter` is a plain `Equatable` value type. Views hold it in `@State` (that *is* the observable holder — no separate `@Observable` class needed for a struct) and pass `Binding<ItemFilter>` into sheets/rows.

- [ ] **Step 1: Write the failing tests**

Create `LeatherfolioTests/ItemFilterTests.swift`:

```swift
import XCTest
import SwiftData
@testable import Leatherfolio

@MainActor
final class ItemFilterTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        // In-memory container: fixtures behave exactly like real SwiftData objects
        // (relationships included) without touching disk.
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: Item.self, Photo.self, Tag.self,
            configurations: config
        )
        context = ModelContext(container)
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
```

- [ ] **Step 2: Run tests to verify they fail to compile**

Run:

```bash
cd /Users/robbybarnes/GitHub/portland-leather
xcodegen generate && xcodebuild -project Leatherfolio.xcodeproj -scheme Leatherfolio \
  -destination 'platform=iOS Simulator,name=iPhone 16' test 2>&1 | tail -30
```

Expected: **BUILD FAILED** — errors like `cannot find 'ItemFilter' in scope`. (Substitute an available simulator name from `xcrun simctl list devices available` if iPhone 16 is absent — this applies to every test step in this plan.)

- [ ] **Step 3: Implement `ItemFilter`**

Create `Leatherfolio/Features/Collection/ItemFilter.swift`:

```swift
import Foundation

/// Which half of the collection is shown (spec decision #8).
enum CollectionScope: String, CaseIterable, Identifiable {
    case owned = "Owned"
    case wishlist = "Wishlist"
    var id: String { rawValue }
}

/// Sort keys for the collection. Raw values are the menu labels.
enum SortKey: String, CaseIterable, Identifiable {
    case createdAt = "Date Added"
    case name = "Name"
    case dateAcquired = "Date Acquired"
    case estimatedValue = "Est. Value"
    case rating = "Rating"
    var id: String { rawValue }
}

/// One active filter, renderable as a removable chip.
struct FilterChip: Equatable, Identifiable {
    enum Kind: String {
        case category, leatherType, color, size, condition
        case favorites, unicorns, minRating
    }
    let kind: Kind
    let label: String
    var id: String { kind.rawValue }   // at most one chip per kind
}

/// Pure filter/sort/search criteria over `[Item]`. Views hold this in
/// `@State` and pass bindings into the filter sheet and chips row.
/// Every function here is pure — no SwiftData queries, no side effects.
struct ItemFilter: Equatable {
    var scope: CollectionScope = .owned
    var category: ItemCategory?
    var leatherType: LeatherType?
    var color: String?
    var size: String?
    var condition: ItemCondition?
    var favoritesOnly: Bool = false
    var unicornsOnly: Bool = false
    var minRating: Int = 0            // 0 = no minimum
    var query: String = ""
    var sortKey: SortKey = .createdAt
    var sortAscending: Bool = false   // default: newest first

    // MARK: - Matching

    func matches(_ item: Item) -> Bool {
        guard item.isWishlist == (scope == .wishlist) else { return false }
        if let category, item.category != category { return false }
        if let leatherType, item.leatherType != leatherType { return false }
        if let color,
           Self.normalized(item.color ?? "") != Self.normalized(color) { return false }
        if let size,
           Self.normalized(item.size ?? "") != Self.normalized(size) { return false }
        if let condition, item.condition != condition { return false }
        if favoritesOnly && !item.favorite { return false }
        if unicornsOnly && !item.isUnicorn { return false }
        if minRating > 0 && item.rating < minRating { return false }
        return matchesQuery(item)
    }

    /// Case- and diacritic-insensitive token search over name, notes, and tag
    /// names. Every whitespace-separated token must match somewhere.
    func matchesQuery(_ item: Item) -> Bool {
        let tokens = Self.normalized(query)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard !tokens.isEmpty else { return true }
        let haystack = Self.normalized(
            ([item.name, item.notes ?? ""] + (item.tags ?? []).map(\.name))
                .joined(separator: " ")
        )
        return tokens.allSatisfy { haystack.contains($0) }
    }

    // MARK: - Filter + sort pipeline

    func apply(to items: [Item]) -> [Item] {
        items.filter(matches).sorted(by: areInIncreasingOrder)
    }

    /// Strict-weak-ordering comparator. Descending is expressed by swapping
    /// operands (never `!(a < b)`, which breaks the ordering on equal keys).
    /// Optional keys (dateAcquired, estimatedValue) sort missing-values-last
    /// in BOTH directions.
    func areInIncreasingOrder(_ a: Item, _ b: Item) -> Bool {
        switch sortKey {
        case .createdAt:
            return sortAscending ? a.createdAt < b.createdAt
                                 : b.createdAt < a.createdAt
        case .name:
            let cmp = a.name.localizedStandardCompare(b.name)
            return sortAscending ? cmp == .orderedAscending
                                 : cmp == .orderedDescending
        case .rating:
            return sortAscending ? a.rating < b.rating : b.rating < a.rating
        case .dateAcquired:
            return compareNilsLast(a.dateAcquired, b.dateAcquired)
        case .estimatedValue:
            return compareNilsLast(a.estimatedValue, b.estimatedValue)
        }
    }

    private func compareNilsLast<T: Comparable>(_ a: T?, _ b: T?) -> Bool {
        switch (a, b) {
        case let (x?, y?): return sortAscending ? x < y : y < x
        case (_?, nil):    return true    // value before nil, both directions
        case (nil, _?):    return false
        case (nil, nil):   return false
        }
    }

    // MARK: - Active filters (chips)

    /// Scope, query, and sort are navigation state, not "filters" — they never
    /// produce chips and survive `clearFilters()`.
    var activeChips: [FilterChip] {
        var chips: [FilterChip] = []
        if let category { chips.append(.init(kind: .category, label: category.rawValue)) }
        if let leatherType { chips.append(.init(kind: .leatherType, label: leatherType.rawValue)) }
        if let color { chips.append(.init(kind: .color, label: color)) }
        if let size { chips.append(.init(kind: .size, label: size)) }
        if let condition { chips.append(.init(kind: .condition, label: condition.rawValue)) }
        if favoritesOnly { chips.append(.init(kind: .favorites, label: "Favorites")) }
        if unicornsOnly { chips.append(.init(kind: .unicorns, label: "Unicorns")) }
        if minRating > 0 { chips.append(.init(kind: .minRating, label: "\(minRating)+ stars")) }
        return chips
    }

    var activeFilterCount: Int { activeChips.count }

    mutating func remove(_ kind: FilterChip.Kind) {
        switch kind {
        case .category:    category = nil
        case .leatherType: leatherType = nil
        case .color:       color = nil
        case .size:        size = nil
        case .condition:   condition = nil
        case .favorites:   favoritesOnly = false
        case .unicorns:    unicornsOnly = false
        case .minRating:   minRating = 0
        }
    }

    mutating func clearFilters() {
        for chip in activeChips { remove(chip.kind) }
    }

    // MARK: - Text normalization

    /// Case- and diacritic-insensitive canonical form ("Café" -> "cafe").
    static func normalized(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:

```bash
cd /Users/robbybarnes/GitHub/portland-leather
xcodegen generate && xcodebuild -project Leatherfolio.xcodeproj -scheme Leatherfolio \
  -destination 'platform=iOS Simulator,name=iPhone 16' test 2>&1 | tail -30
```

Expected: **TEST SUCCEEDED**, including all 12 `ItemFilterTests`.

- [ ] **Step 5: Commit**

```bash
cd /Users/robbybarnes/GitHub/portland-leather
git add Leatherfolio/Features/Collection/ItemFilter.swift LeatherfolioTests/ItemFilterTests.swift
git commit -m "feat: add ItemFilter pure filter/sort/search engine"
```

---

### Task 2: Filter/sort/search UI (CollectionView rewrite)

**Files:**
- Create: `Leatherfolio/Features/Collection/FilterOptions.swift`
- Create: `Leatherfolio/Features/Collection/FilterSheetView.swift`
- Create: `Leatherfolio/Features/Collection/FilterChipsRow.swift`
- Modify: `Leatherfolio/Features/Collection/CollectionView.swift` (full rewrite shown below)
- Test: `LeatherfolioTests/FilterOptionsTests.swift`

**Interfaces:**
- Consumes: `ItemFilter`, `CollectionScope`, `SortKey`, `FilterChip` (Task 1); `ItemCell(item:)` (Phase 1); `ImageStore.shared.thumbnail(for:imageData:)` (Phase 1); `CatalogSeed.shared` with `lines: [CatalogLine]` and `allColors: [String]` (Phase 2).
- Produces (Tasks 3–5 rely on these exact names): `FilterOptions` (`static func make(items:seed:)`, `static func make(itemColors:itemSizes:seedColors:seedSizes:)`, `var colors: [String]`, `var sizes: [String]`), `enum CollectionLayout: String, CaseIterable { case grid, list }`, `struct ItemRow: View` (list-layout row), and the rewritten `CollectionView` (Task 3 adds a stats button to it; Task 5 edits its `gridColumns`).

**Adaptation note (Phase-1 seam, the only one in this task):** the rewrite below navigates with `NavigationLink(value: item.id)`, matching the master plan's `AppRouter.open(itemID: UUID)` deep-link contract (a `navigationDestination(for: UUID.self)` is registered where `AppRouter`'s `NavigationPath` lives, in `Leatherfolio/App/`). It also assumes Phase 1's Add (+) and Scan toolbar buttons exist in `CollectionView`'s toolbar. When rewriting the file, **carry over Phase 1's existing Add/Scan `ToolbarItem`s verbatim** into the marked spot, and if Phase 1's cells navigated with a different link value (e.g. `NavigationLink(value: item)`), keep Phase 1's value type in both `NavigationLink`s. Everything else in the file below stands as written.

- [ ] **Step 1: Write the failing test for `FilterOptions`**

Create `LeatherfolioTests/FilterOptionsTests.swift`:

```swift
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
```

- [ ] **Step 2: Run test to verify it fails to compile**

Run:

```bash
cd /Users/robbybarnes/GitHub/portland-leather
xcodegen generate && xcodebuild -project Leatherfolio.xcodeproj -scheme Leatherfolio \
  -destination 'platform=iOS Simulator,name=iPhone 16' test 2>&1 | tail -20
```

Expected: **BUILD FAILED** — `cannot find 'FilterOptions' in scope`.

- [ ] **Step 3: Implement `FilterOptions`**

Create `Leatherfolio/Features/Collection/FilterOptions.swift`:

```swift
import Foundation

/// Option lists for the filter sheet's Color and Size pickers: the curated
/// catalog-seed values merged with whatever distinct values are actually
/// present in the collection (free-text entries included).
struct FilterOptions: Equatable {
    var colors: [String]
    var sizes: [String]

    /// Pure core — unit-tested directly.
    static func make(
        itemColors: [String?], itemSizes: [String?],
        seedColors: [String], seedSizes: [String]
    ) -> FilterOptions {
        FilterOptions(
            colors: merged(seed: seedColors, present: itemColors),
            sizes: merged(seed: seedSizes, present: itemSizes)
        )
    }

    /// Convenience used by the UI.
    static func make(items: [Item], seed: CatalogSeed = .shared) -> FilterOptions {
        make(
            itemColors: items.map(\.color),
            itemSizes: items.map(\.size),
            seedColors: seed.allColors,
            seedSizes: seed.lines.flatMap(\.sizes)
        )
    }

    private static func merged(seed: [String], present: [String?]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in seed + present.compactMap({ $0 }) {
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if seen.insert(ItemFilter.normalized(trimmed)).inserted {
                result.append(trimmed)
            }
        }
        return result.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Same command as Step 2. Expected: **TEST SUCCEEDED** including both `FilterOptionsTests`.

- [ ] **Step 5: Create the chips row and filter sheet**

Create `Leatherfolio/Features/Collection/FilterChipsRow.swift`:

```swift
import SwiftUI

/// Horizontal row of removable chips for every active filter, plus Clear All.
struct FilterChipsRow: View {
    @Binding var filter: ItemFilter

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(filter.activeChips) { chip in
                    Button {
                        filter.remove(chip.kind)
                    } label: {
                        HStack(spacing: 4) {
                            Text(chip.label)
                            Image(systemName: "xmark")
                                .font(.caption2)
                                .accessibilityHidden(true)
                        }
                        .font(.footnote)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color(.secondarySystemBackground)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove filter: \(chip.label)")
                }
                Button("Clear All") { filter.clearFilters() }
                    .font(.footnote.weight(.semibold))
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
}
```

Create `Leatherfolio/Features/Collection/FilterSheetView.swift`:

```swift
import SwiftUI

/// Filter sheet. Enum pickers list all cases; Color/Size pickers list
/// FilterOptions (seed values plus distinct values in the collection).
struct FilterSheetView: View {
    @Binding var filter: ItemFilter
    let options: FilterOptions
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Product") {
                    Picker("Category", selection: $filter.category) {
                        Text("Any").tag(ItemCategory?.none)
                        ForEach(ItemCategory.allCases) { Text($0.rawValue).tag(Optional($0)) }
                    }
                    Picker("Leather", selection: $filter.leatherType) {
                        Text("Any").tag(LeatherType?.none)
                        ForEach(LeatherType.allCases) { Text($0.rawValue).tag(Optional($0)) }
                    }
                    Picker("Color", selection: $filter.color) {
                        Text("Any").tag(String?.none)
                        ForEach(options.colors, id: \.self) { Text($0).tag(Optional($0)) }
                    }
                    Picker("Size", selection: $filter.size) {
                        Text("Any").tag(String?.none)
                        ForEach(options.sizes, id: \.self) { Text($0).tag(Optional($0)) }
                    }
                    Picker("Condition", selection: $filter.condition) {
                        Text("Any").tag(ItemCondition?.none)
                        ForEach(ItemCondition.allCases) { Text($0.rawValue).tag(Optional($0)) }
                    }
                }
                Section("Flags") {
                    Toggle("Favorites only", isOn: $filter.favoritesOnly)
                    Toggle("Unicorns only", isOn: $filter.unicornsOnly)
                }
                Section("Rating") {
                    Stepper(value: $filter.minRating, in: 0...5) {
                        Text(filter.minRating == 0
                             ? "Any rating"
                             : "At least \(filter.minRating) star\(filter.minRating == 1 ? "" : "s")")
                    }
                }
                Section {
                    Button("Clear All Filters", role: .destructive) { filter.clearFilters() }
                        .disabled(filter.activeFilterCount == 0)
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
```

- [ ] **Step 6: Rewrite `CollectionView`**

Replace the contents of `Leatherfolio/Features/Collection/CollectionView.swift` with (see the adaptation note above for the two Phase-1 splice points, both marked with `// PHASE 1:` comments):

```swift
import SwiftUI
import SwiftData

/// Grid/list layout choice, persisted via @AppStorage.
enum CollectionLayout: String, CaseIterable {
    case grid, list
}

struct CollectionView: View {
    @Query(sort: \Item.createdAt, order: .reverse) private var allItems: [Item]
    @State private var filter = ItemFilter()
    @State private var showingFilterSheet = false
    @AppStorage("collectionLayout") private var layoutRaw = CollectionLayout.grid.rawValue

    private var layout: CollectionLayout { CollectionLayout(rawValue: layoutRaw) ?? .grid }
    private var items: [Item] { filter.apply(to: allItems) }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Scope", selection: $filter.scope) {
                ForEach(CollectionScope.allCases) { scope in
                    Text(scope.rawValue).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)

            if !filter.activeChips.isEmpty {
                FilterChipsRow(filter: $filter)
            }

            content
        }
        .navigationTitle("Collection")
        .searchable(text: $filter.query, prompt: "Search name, notes, tags")
        .toolbar {
            // PHASE 1: keep the existing Add (+) and Scan ToolbarItems here,
            // exactly as they were before this rewrite.
            organizeToolbar
        }
        .sheet(isPresented: $showingFilterSheet) {
            FilterSheetView(filter: $filter,
                            options: FilterOptions.make(items: allItems))
        }
    }

    // MARK: - Content

    @ViewBuilder private var content: some View {
        if items.isEmpty {
            ContentUnavailableView(
                filter.scope == .wishlist ? "No Wishlist Items" : "No Items",
                systemImage: "bag",
                description: Text(filter.activeFilterCount > 0 || !filter.query.isEmpty
                                  ? "Try clearing filters or search."
                                  : "Tap + to add your first item.")
            )
            .frame(maxHeight: .infinity)
        } else if layout == .grid {
            ScrollView {
                LazyVGrid(columns: gridColumns, spacing: 12) {
                    ForEach(items) { item in
                        // PHASE 1: keep the link-value type Phase 1 used.
                        NavigationLink(value: item.id) {
                            ItemCell(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
        } else {
            List(items) { item in
                NavigationLink(value: item.id) {
                    ItemRow(item: item)
                }
            }
            .listStyle(.plain)
        }
    }

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 150), spacing: 12)]
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder private var organizeToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Menu {
                Picker("Sort by", selection: $filter.sortKey) {
                    ForEach(SortKey.allCases) { key in
                        Text(key.rawValue).tag(key)
                    }
                }
                Divider()
                Picker("Direction", selection: $filter.sortAscending) {
                    Text("Ascending").tag(true)
                    Text("Descending").tag(false)
                }
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }

            Button {
                layoutRaw = (layout == .grid ? CollectionLayout.list : .grid).rawValue
            } label: {
                Label(layout == .grid ? "Switch to list layout" : "Switch to grid layout",
                      systemImage: layout == .grid ? "list.bullet" : "square.grid.2x2")
            }

            Button {
                showingFilterSheet = true
            } label: {
                Label("Filters",
                      systemImage: filter.activeFilterCount > 0
                      ? "line.3.horizontal.decrease.circle.fill"
                      : "line.3.horizontal.decrease.circle")
            }
        }
    }
}

/// Compact row for the list layout. Thumbnails only — never Photo.imageData
/// decoded at full size in a list.
struct ItemRow: View {
    let item: Item
    @State private var thumbnail: UIImage?

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "bag")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 56, height: 56)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name.isEmpty ? "Untitled" : item.name)
                    .font(.headline)
                Text([item.size, item.color, item.leatherType?.rawValue]
                        .compactMap { $0 }
                        .joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if item.favorite {
                Image(systemName: "heart.fill").foregroundStyle(.pink)
            }
            if item.isUnicorn {
                Image(systemName: "sparkles").foregroundStyle(.purple)
            }
        }
        .task(id: item.primaryPhoto?.id) {
            if let photo = item.primaryPhoto {
                thumbnail = await ImageStore.shared.thumbnail(for: photo.id,
                                                              imageData: photo.imageData)
            } else {
                thumbnail = nil
            }
        }
    }
}
```

- [ ] **Step 7: Build and run the full test suite**

Run:

```bash
cd /Users/robbybarnes/GitHub/portland-leather
xcodegen generate && xcodebuild -project Leatherfolio.xcodeproj -scheme Leatherfolio \
  -destination 'platform=iOS Simulator,name=iPhone 16' test 2>&1 | tail -20
```

Expected: **TEST SUCCEEDED** (all prior phase tests plus Tasks 1–2 tests). If the Phase-1 UI smoke test asserts on the old CollectionView layout, update its assertions to the new structure (grid cells are unchanged `ItemCell`s, so it should pass as-is).

- [ ] **Step 8: Manual smoke in simulator**

Launch the app (Xcode or `xcrun simctl`), then verify: segmented Owned/Wishlist toggle switches scope; searching "honey" narrows the grid; the filter sheet's pickers show seed colors plus any free-text colors you entered; picking filters shows chips; tapping a chip's ✕ removes it; Clear All keeps the search text; the layout toolbar button flips grid↔list and the choice survives app relaunch.

- [ ] **Step 9: Commit**

```bash
cd /Users/robbybarnes/GitHub/portland-leather
git add Leatherfolio/Features/Collection/FilterOptions.swift \
        Leatherfolio/Features/Collection/FilterSheetView.swift \
        Leatherfolio/Features/Collection/FilterChipsRow.swift \
        Leatherfolio/Features/Collection/CollectionView.swift \
        LeatherfolioTests/FilterOptionsTests.swift
git commit -m "feat: searchable collection with filter sheet, chips, sort menu, grid/list toggle"
```

---

### Task 3: Stats screen

**Files:**
- Create: `Leatherfolio/Support/CurrencyFormat.swift`
- Create: `Leatherfolio/Features/Stats/StatsHeadline.swift`
- Create: `Leatherfolio/Features/Stats/StatsView.swift`
- Modify: `Leatherfolio/Features/Collection/CollectionView.swift` (add stats entry point)
- Test: `LeatherfolioTests/CurrencyFormatTests.swift`, `LeatherfolioTests/StatsHeadlineTests.swift`, `LeatherfolioTests/StatsViewRenderTests.swift`

**Interfaces:**
- Consumes: `CollectionStats` from Phase 2 (`Leatherfolio/Services/CollectionStats.swift`, already implemented and fully unit-tested there). Authoritative surface — matches the Phase 2/3 plan and the master plan verbatim:

```swift
struct LineCompleteness: Equatable, Identifiable {
    let lineName: String
    let ownedColors: [String]   // distinct owned colors that exist in the line's palette
    let totalColors: Int        // the line's full palette size
    var id: String { lineName }
}

struct CategoryCount: Equatable, Identifiable {
    let category: ItemCategory
    let count: Int
    var id: String { category.rawValue }
}

struct CollectionStats: Equatable {
    init(items: [Item], catalog: CatalogSeed)
    let itemCount: Int
    let distinctColorCount: Int
    let distinctLeatherTypeCount: Int
    let unicornCount: Int
    let totalSpent: Decimal           // sum of myCost where present
    let totalEstimatedValue: Decimal  // sum of estimatedValue where present
    let unrealizedDelta: Decimal      // per-item valueDelta summed where both sides present
    let averageRating: Double?        // over items rated >= 1; nil if none
    let itemsByCategory: [CategoryCount]      // ordered by ItemCategory.allCases; empty categories omitted
    let lineCompleteness: [LineCompleteness]  // sorted by lineName
}
```

- Produces (Task 4 edits these; Task 6 smoke-tests them): `CurrencyFormat.string(from:locale:)`, `CurrencyFormat.signedString(from:locale:)`, `StatsHeadline.text(itemCount:colorCount:leatherTypeCount:unicornCount:)`, `StatsView(stats:)`.

The screen is tasteful per the spec — counts, money, a single bar chart, completeness progress. **No streaks, no badges, no gamification.**

- [ ] **Step 1: Write the failing formatter and headline tests**

Create `LeatherfolioTests/CurrencyFormatTests.swift`:

```swift
import XCTest
@testable import Leatherfolio

final class CurrencyFormatTests: XCTestCase {
    private let enUS = Locale(identifier: "en_US")

    func testFormatsDecimalInLocaleCurrency() {
        XCTAssertEqual(
            CurrencyFormat.string(from: Decimal(string: "1234.56")!, locale: enUS),
            "$1,234.56"
        )
        XCTAssertEqual(
            CurrencyFormat.string(from: Decimal(string: "0")!, locale: enUS),
            "$0.00"
        )
    }

    func testSignedStringShowsExplicitSign() {
        XCTAssertEqual(
            CurrencyFormat.signedString(from: Decimal(string: "120")!, locale: enUS),
            "+$120.00"
        )
        XCTAssertEqual(
            CurrencyFormat.signedString(from: Decimal(string: "-35")!, locale: enUS),
            "-$35.00"
        )
    }

    func testNonUSLocale() {
        let deDE = Locale(identifier: "de_DE")
        let formatted = CurrencyFormat.string(from: Decimal(string: "1234.56")!, locale: deDE)
        XCTAssertTrue(formatted.contains("€"), "expected euro symbol in \(formatted)")
    }
}
```

Create `LeatherfolioTests/StatsHeadlineTests.swift`:

```swift
import XCTest
@testable import Leatherfolio

final class StatsHeadlineTests: XCTestCase {
    func testFullHeadline() {
        XCTAssertEqual(
            StatsHeadline.text(itemCount: 12, colorCount: 5, leatherTypeCount: 3, unicornCount: 2),
            "12 items · 5 colors · 3 leather types · 2 unicorns"
        )
    }

    func testSingularForms() {
        XCTAssertEqual(
            StatsHeadline.text(itemCount: 1, colorCount: 1, leatherTypeCount: 1, unicornCount: 1),
            "1 item · 1 color · 1 leather type · 1 unicorn"
        )
    }

    func testZeroUnicornsOmitsUnicornSegment() {
        XCTAssertEqual(
            StatsHeadline.text(itemCount: 3, colorCount: 2, leatherTypeCount: 1, unicornCount: 0),
            "3 items · 2 colors · 1 leather type"
        )
    }
}
```

- [ ] **Step 2: Run tests to verify they fail to compile**

Run:

```bash
cd /Users/robbybarnes/GitHub/portland-leather
xcodegen generate && xcodebuild -project Leatherfolio.xcodeproj -scheme Leatherfolio \
  -destination 'platform=iOS Simulator,name=iPhone 16' test 2>&1 | tail -20
```

Expected: **BUILD FAILED** — `cannot find 'CurrencyFormat' in scope`, `cannot find 'StatsHeadline' in scope`.

- [ ] **Step 3: Implement `CurrencyFormat` and `StatsHeadline`**

Create `Leatherfolio/Support/CurrencyFormat.swift`:

```swift
import Foundation

/// Locale-aware currency rendering for Decimal money values (Global
/// Constraints: Decimal everywhere, user's locale currency).
enum CurrencyFormat {
    /// e.g. "$1,234.56" in en_US, "1.234,56 €" in de_DE.
    static func string(from value: Decimal, locale: Locale = .current) -> String {
        let code = locale.currency?.identifier ?? "USD"
        return value.formatted(.currency(code: code).locale(locale))
    }

    /// Delta rendering with an explicit sign, e.g. "+$120.00" / "-$35.00".
    static func signedString(from value: Decimal, locale: Locale = .current) -> String {
        let code = locale.currency?.identifier ?? "USD"
        return value.formatted(
            .currency(code: code).locale(locale).sign(strategy: .always())
        )
    }
}
```

Create `Leatherfolio/Features/Stats/StatsHeadline.swift`:

```swift
import Foundation

/// Pure composition of the stats headline, e.g.
/// "12 items · 5 colors · 3 leather types · 2 unicorns".
enum StatsHeadline {
    static func text(itemCount: Int, colorCount: Int,
                     leatherTypeCount: Int, unicornCount: Int) -> String {
        var parts = [
            counted(itemCount, "item"),
            counted(colorCount, "color"),
            counted(leatherTypeCount, "leather type"),
        ]
        if unicornCount > 0 {
            parts.append(counted(unicornCount, "unicorn"))
        }
        return parts.joined(separator: " · ")
    }

    private static func counted(_ n: Int, _ noun: String) -> String {
        "\(n) \(noun)\(n == 1 ? "" : "s")"
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Same command as Step 2. Expected: **TEST SUCCEEDED** including all 6 new formatter/headline tests. If `testSignedStringShowsExplicitSign` fails on the exact minus glyph (Foundation may emit U+2212 "−" instead of ASCII "-" on some OS versions), change the assertion to `XCTAssertTrue(result.hasSuffix("$35.00") && !result.hasPrefix("+"))` and note why in a comment.

- [ ] **Step 5: Write the failing StatsView smoke test**

Create `LeatherfolioTests/StatsViewRenderTests.swift`:

```swift
import XCTest
import SwiftUI
import SwiftData
@testable import Leatherfolio

/// Lightweight rendering smoke test: the math is covered by Phase 2's
/// CollectionStats tests; this just proves StatsView renders real stats
/// without crashing (bad ForEach IDs, force unwraps, Chart misuse).
@MainActor
final class StatsViewRenderTests: XCTestCase {
    func testStatsViewRendersWithoutCrashing() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Item.self, Photo.self, Tag.self, configurations: config
        )
        let context = ModelContext(container)

        let tote = Item()
        tote.name = "Willow Tote"
        tote.category = .tote
        tote.color = "Honey"
        tote.leatherType = .smooth
        tote.myCost = Decimal(180)
        tote.estimatedValue = Decimal(220)
        tote.rating = 4
        context.insert(tote)

        let wallet = Item()
        wallet.name = "Luxe Wallet"
        wallet.category = .wallet
        wallet.isUnicorn = true
        context.insert(wallet)

        let stats = CollectionStats(items: [tote, wallet], catalog: .shared)
        let renderer = ImageRenderer(
            content: StatsView(stats: stats).frame(width: 390, height: 1400)
        )
        XCTAssertNotNil(renderer.uiImage, "StatsView failed to render")
    }

    func testStatsViewRendersEmptyCollection() throws {
        let stats = CollectionStats(items: [], catalog: .shared)
        let renderer = ImageRenderer(
            content: StatsView(stats: stats).frame(width: 390, height: 800)
        )
        XCTAssertNotNil(renderer.uiImage)
    }
}
```

- [ ] **Step 6: Run test to verify it fails to compile**

Same command as Step 2. Expected: **BUILD FAILED** — `cannot find 'StatsView' in scope`.

- [ ] **Step 7: Implement `StatsView`**

Create `Leatherfolio/Features/Stats/StatsView.swift`:

```swift
import SwiftUI
import Charts

/// Renders CollectionStats (Phase 2 value type — all math lives there and is
/// unit-tested there). Tasteful per the spec: counts, money, one chart,
/// completeness. No streaks, no badges.
struct StatsView: View {
    let stats: CollectionStats

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headline
                moneyBlock
                ratingBlock
                categoryChart
                completenessBlock
            }
            .padding()
        }
        .navigationTitle("Stats")
    }

    // MARK: - Blocks

    private var headline: some View {
        Text(StatsHeadline.text(
            itemCount: stats.itemCount,
            colorCount: stats.distinctColorCount,
            leatherTypeCount: stats.distinctLeatherTypeCount,
            unicornCount: stats.unicornCount
        ))
        .font(.headline)
    }

    private var moneyBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("Total spent",
                           value: CurrencyFormat.string(from: stats.totalSpent))
            LabeledContent("Estimated value",
                           value: CurrencyFormat.string(from: stats.totalEstimatedValue))
            LabeledContent("Unrealized delta") {
                Text(CurrencyFormat.signedString(from: stats.unrealizedDelta))
                    .fontWeight(.semibold)
                    .foregroundStyle(stats.unrealizedDelta >= 0 ? Color.green : Color.red)
            }
        }
    }

    private var ratingBlock: some View {
        LabeledContent("Average rating") {
            if let average = stats.averageRating {
                Text(String(format: "%.1f of 5", average))
            } else {
                Text("No ratings yet")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var categoryChart: some View {
        if !stats.itemsByCategory.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Items by category")
                    .font(.headline)
                Chart(stats.itemsByCategory, id: \.category) { entry in
                    BarMark(
                        x: .value("Items", entry.count),
                        y: .value("Category", entry.category.rawValue)
                    )
                }
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
                .frame(height: CGFloat(stats.itemsByCategory.count) * 36 + 24)
                .accessibilityLabel("Bar chart of items by category")
            }
        }
    }

    @ViewBuilder private var completenessBlock: some View {
        if !stats.lineCompleteness.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Line completeness")
                    .font(.headline)
                ForEach(stats.lineCompleteness) { line in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(line.ownedColors.count) of \(line.totalColors) \(line.lineName) colors")
                            .font(.subheadline)
                        ProgressView(
                            value: Double(line.ownedColors.count),
                            total: Double(max(line.totalColors, 1))
                        )
                        .accessibilityLabel("\(line.lineName): \(line.ownedColors.count) of \(line.totalColors) colors")
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 8: Wire the stats entry point into `CollectionView`**

In `Leatherfolio/Features/Collection/CollectionView.swift` (the Task 2 rewrite), make these two exact edits.

Edit 1 — add state below the existing `@State private var showingFilterSheet = false`:

```swift
    @State private var showingFilterSheet = false
    @State private var showingStats = false
```

Edit 2 — add a second sheet after the filter sheet, and a stats toolbar button. Replace:

```swift
        .sheet(isPresented: $showingFilterSheet) {
            FilterSheetView(filter: $filter,
                            options: FilterOptions.make(items: allItems))
        }
```

with:

```swift
        .sheet(isPresented: $showingFilterSheet) {
            FilterSheetView(filter: $filter,
                            options: FilterOptions.make(items: allItems))
        }
        .sheet(isPresented: $showingStats) {
            NavigationStack {
                StatsView(stats: CollectionStats(
                    items: allItems.filter { !$0.isWishlist },
                    seed: .shared
                ))
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showingStats = false }
                    }
                }
            }
        }
```

Edit 3 — inside `organizeToolbar`'s `ToolbarItemGroup`, add before the sort `Menu`:

```swift
            Button {
                showingStats = true
            } label: {
                Label("Stats", systemImage: "chart.bar")
            }
```

- [ ] **Step 9: Run the full test suite**

Same command as Step 2. Expected: **TEST SUCCEEDED** including both `StatsViewRenderTests`.

- [ ] **Step 10: Manual smoke in simulator**

With a few items (some with costs/values, one wishlist item): tap the chart toolbar button → stats sheet shows the headline, money rows (delta green when value > spent), average rating, a horizontal bar chart, and "N of M <line> colors" progress rows. Wishlist items must NOT count toward totals.

- [ ] **Step 11: Commit**

```bash
cd /Users/robbybarnes/GitHub/portland-leather
git add Leatherfolio/Support/CurrencyFormat.swift \
        Leatherfolio/Features/Stats/StatsHeadline.swift \
        Leatherfolio/Features/Stats/StatsView.swift \
        Leatherfolio/Features/Collection/CollectionView.swift \
        LeatherfolioTests/CurrencyFormatTests.swift \
        LeatherfolioTests/StatsHeadlineTests.swift \
        LeatherfolioTests/StatsViewRenderTests.swift
git commit -m "feat: stats screen rendering CollectionStats with chart and completeness"
```

---

### Task 4: Design language pass (Theme, palette, serif type, card style, app icon)

**Files:**
- Create: `Leatherfolio/Support/Theme.swift`
- Create: `Leatherfolio/Resources/Assets.xcassets/{Cream,Parchment,Espresso,Nutmeg,Cognac,Gain,Loss}.colorset/Contents.json` (script-generated)
- Create: `Scripts/generate_app_icon.swift` + `Leatherfolio/Resources/Assets.xcassets/AppIcon.appiconset/{Contents.json,AppIcon.png}`
- Modify: `Leatherfolio/App/LeatherfolioApp.swift`, `Leatherfolio/Features/Collection/CollectionView.swift`, `Leatherfolio/Features/Collection/ItemCell.swift`, `Leatherfolio/Features/Stats/StatsView.swift`, `Leatherfolio/Features/ItemDetail/ItemDetailView.swift`, `project.yml`
- Test: `LeatherfolioTests/ThemeContrastTests.swift`

**Interfaces:**
- Consumes: the Task 2/3 view files (exact edit targets shown below).
- Produces (Task 5 uses `Theme.accent`): `enum Theme` (`background`, `card`, `textPrimary`, `textSecondary`, `accent`, `gain`, `loss` as `Color`; `Spacing.xs/s/m/l/xl: CGFloat`; `cardCornerRadius: CGFloat`), `extension Font { static func display(_:) -> Font }`, `extension View { func cardStyle() -> some View }`.

**Palette** — warm editorial, *derived from* the PLG staple names (Honey, Cognac, Nutmeg, Coldbrew — see `research/plg_catalog_notes.md`) but generic values we own. All text pairs meet WCAG AA (≥ 4.5:1); ratios below are computed from the WCAG relative-luminance formula (the Step 1 test re-computes them at test time):

| Colorset | Role | Light | Dark | Contrast vs. background |
|---|---|---|---|---|
| `Cream` | screen background | `#F7F2E9` | `#1E1A16` | — |
| `Parchment` | card background | `#FFFBF4` | `#2A241E` | — |
| `Espresso` | primary text | `#3B2A20` | `#F1E9DC` | ≈12.2:1 light, ≈14.4:1 dark |
| `Nutmeg` | secondary text | `#6E5138` | `#C4B29E` | ≈6.5:1 light, ≈8.4:1 dark |
| `Cognac` | accent/tint | `#8A4B2A` | `#D08A5A` | ≈6.0:1 light, ≈6.2:1 dark |
| `Gain` | positive delta | `#2E7D4F` | `#5FBF8A` | ≈4.5:1 light, ≈7.7:1 dark |
| `Loss` | negative delta | `#B3372F` | `#E07A6E` | ≈5.4:1 light, ≈5.9:1 dark |

- [ ] **Step 1: Write the failing contrast + asset tests**

Create `LeatherfolioTests/ThemeContrastTests.swift`:

```swift
import XCTest
import UIKit
@testable import Leatherfolio

/// Executable proof that the chosen palette meets WCAG AA (4.5:1) for every
/// text-on-background pair, and that every colorset exists in the asset
/// catalog. Hex values here are the palette's source of truth alongside the
/// colorset JSON — keep them in sync.
final class ThemeContrastTests: XCTestCase {
    // MARK: WCAG math

    private func luminance(_ hex: UInt32) -> Double {
        func channel(_ v: UInt32) -> Double {
            let c = Double(v) / 255.0
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel((hex >> 16) & 0xFF)
             + 0.7152 * channel((hex >> 8) & 0xFF)
             + 0.0722 * channel(hex & 0xFF)
    }

    private func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let (l1, l2) = (luminance(a), luminance(b))
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    // MARK: Light mode (text on Cream #F7F2E9 / Parchment #FFFBF4)

    func testLightModeTextPairsMeetAA() {
        XCTAssertGreaterThanOrEqual(contrast(0x3B2A20, 0xF7F2E9), 4.5, "Espresso on Cream")
        XCTAssertGreaterThanOrEqual(contrast(0x6E5138, 0xF7F2E9), 4.5, "Nutmeg on Cream")
        XCTAssertGreaterThanOrEqual(contrast(0x8A4B2A, 0xF7F2E9), 4.5, "Cognac on Cream")
        XCTAssertGreaterThanOrEqual(contrast(0x2E7D4F, 0xF7F2E9), 4.5, "Gain on Cream")
        XCTAssertGreaterThanOrEqual(contrast(0xB3372F, 0xF7F2E9), 4.5, "Loss on Cream")
        XCTAssertGreaterThanOrEqual(contrast(0x3B2A20, 0xFFFBF4), 4.5, "Espresso on Parchment")
        XCTAssertGreaterThanOrEqual(contrast(0x6E5138, 0xFFFBF4), 4.5, "Nutmeg on Parchment")
    }

    // MARK: Dark mode (text on Cream-dark #1E1A16 / Parchment-dark #2A241E)

    func testDarkModeTextPairsMeetAA() {
        XCTAssertGreaterThanOrEqual(contrast(0xF1E9DC, 0x1E1A16), 4.5, "Espresso on Cream")
        XCTAssertGreaterThanOrEqual(contrast(0xC4B29E, 0x1E1A16), 4.5, "Nutmeg on Cream")
        XCTAssertGreaterThanOrEqual(contrast(0xD08A5A, 0x1E1A16), 4.5, "Cognac on Cream")
        XCTAssertGreaterThanOrEqual(contrast(0x5FBF8A, 0x1E1A16), 4.5, "Gain on Cream")
        XCTAssertGreaterThanOrEqual(contrast(0xE07A6E, 0x1E1A16), 4.5, "Loss on Cream")
        XCTAssertGreaterThanOrEqual(contrast(0xF1E9DC, 0x2A241E), 4.5, "Espresso on Parchment")
        XCTAssertGreaterThanOrEqual(contrast(0xC4B29E, 0x2A241E), 4.5, "Nutmeg on Parchment")
    }

    // MARK: Asset catalog

    func testAssetCatalogColorsResolve() {
        for name in ["Cream", "Parchment", "Espresso", "Nutmeg", "Cognac", "Gain", "Loss"] {
            XCTAssertNotNil(UIColor(named: name), "Missing colorset: \(name)")
        }
    }
}
```

- [ ] **Step 2: Run tests — WCAG tests pass, asset test fails**

Run:

```bash
cd /Users/robbybarnes/GitHub/portland-leather
xcodegen generate && xcodebuild -project Leatherfolio.xcodeproj -scheme Leatherfolio \
  -destination 'platform=iOS Simulator,name=iPhone 16' test 2>&1 | tail -20
```

Expected: **TEST FAILED** — `testAssetCatalogColorsResolve` fails on every name ("Missing colorset: Cream" …); the two contrast tests pass (they only do math).

- [ ] **Step 3: Generate the seven colorsets**

Run this from the repo root (writes light+dark `Contents.json` for each colorset):

```bash
cd /Users/robbybarnes/GitHub/portland-leather
python3 - <<'PY'
import json, os

palette = {
    "Cream":     ("F7F2E9", "1E1A16"),
    "Parchment": ("FFFBF4", "2A241E"),
    "Espresso":  ("3B2A20", "F1E9DC"),
    "Nutmeg":    ("6E5138", "C4B29E"),
    "Cognac":    ("8A4B2A", "D08A5A"),
    "Gain":      ("2E7D4F", "5FBF8A"),
    "Loss":      ("B3372F", "E07A6E"),
}
root = "Leatherfolio/Resources/Assets.xcassets"

def components(hex6):
    return {"alpha": "1.000",
            "red": f"0x{hex6[0:2]}",
            "green": f"0x{hex6[2:4]}",
            "blue": f"0x{hex6[4:6]}"}

for name, (light, dark) in palette.items():
    d = os.path.join(root, f"{name}.colorset")
    os.makedirs(d, exist_ok=True)
    contents = {
        "colors": [
            {"idiom": "universal",
             "color": {"color-space": "srgb", "components": components(light)}},
            {"idiom": "universal",
             "appearances": [{"appearance": "luminosity", "value": "dark"}],
             "color": {"color-space": "srgb", "components": components(dark)}},
        ],
        "info": {"author": "xcode", "version": 1},
    }
    with open(os.path.join(d, "Contents.json"), "w") as f:
        json.dump(contents, f, indent=2)
print(f"wrote {len(palette)} colorsets under {root}")
PY
```

Expected output: `wrote 7 colorsets under Leatherfolio/Resources/Assets.xcassets`. Spot-check one generated file — `Leatherfolio/Resources/Assets.xcassets/Cream.colorset/Contents.json` must look like:

```json
{
  "colors": [
    {
      "idiom": "universal",
      "color": {
        "color-space": "srgb",
        "components": { "alpha": "1.000", "red": "0xF7", "green": "0xF2", "blue": "0xE9" }
      }
    },
    {
      "idiom": "universal",
      "appearances": [{ "appearance": "luminosity", "value": "dark" }],
      "color": {
        "color-space": "srgb",
        "components": { "alpha": "1.000", "red": "0x1E", "green": "0x1A", "blue": "0x16" }
      }
    }
  ],
  "info": { "author": "xcode", "version": 1 }
}
```

- [ ] **Step 4: Run tests to verify the asset test now passes**

Same command as Step 2. Expected: **TEST SUCCEEDED** — all three `ThemeContrastTests` pass.

- [ ] **Step 5: Implement `Theme`**

Create `Leatherfolio/Support/Theme.swift`:

```swift
import SwiftUI

/// Warm editorial design language: cream backgrounds, cognac accents,
/// espresso text, serif display type. Colors resolve from the asset catalog
/// (light/dark variants; WCAG AA verified by ThemeContrastTests).
enum Theme {
    static let background = Color("Cream")
    static let card = Color("Parchment")
    static let textPrimary = Color("Espresso")
    static let textSecondary = Color("Nutmeg")
    static let accent = Color("Cognac")
    static let gain = Color("Gain")
    static let loss = Color("Loss")

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 32
    }

    static let cardCornerRadius: CGFloat = 14
}

extension Font {
    /// Serif display type (New York) for titles and headline moments.
    /// Built on system text styles, so Dynamic Type scaling is preserved.
    static func display(_ style: Font.TextStyle) -> Font {
        .system(style, design: .serif)
    }
}

/// Card treatment used by grid cells and detail/stat blocks: parchment
/// surface, rounded corners, hairline shadow.
struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(Theme.Spacing.m)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .fill(Theme.card)
                    .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
            )
    }
}

extension View {
    func cardStyle() -> some View { modifier(CardStyle()) }
}
```

- [ ] **Step 6: Apply the theme across the app**

Six exact edits:

**6a — `Leatherfolio/App/LeatherfolioApp.swift`:** attach the global tint and text color to the WindowGroup's root view — the same view that already carries `.modelContainer(...)` and `.onOpenURL` (keep those untouched). Add these two modifiers to that root view:

```swift
                .tint(Theme.accent)
                .foregroundStyle(Theme.textPrimary)
```

**6b — `Leatherfolio/Features/Collection/CollectionView.swift`:** in `body`, replace:

```swift
        .navigationTitle("Collection")
```

with:

```swift
        .navigationTitle("Collection")
        .background(Theme.background)
```

and in the list branch of `content`, replace:

```swift
            .listStyle(.plain)
```

with:

```swift
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
```

**6c — `Leatherfolio/Features/Collection/ItemCell.swift`** (Phase 1 file): append `.cardStyle()` to the cell's outermost container (the top-level `VStack`/`ZStack` returned by `body`), and remove any ad-hoc background/cornerRadius/shadow modifiers it previously carried so the card treatment isn't doubled:

```swift
        // end of ItemCell's outermost container:
        .cardStyle()
```

**6d — `Leatherfolio/Features/Stats/StatsView.swift`:** replace:

```swift
        .navigationTitle("Stats")
```

with:

```swift
        .navigationTitle("Stats")
        .background(Theme.background)
```

replace the delta color line:

```swift
                    .foregroundStyle(stats.unrealizedDelta >= 0 ? Color.green : Color.red)
```

with:

```swift
                    .foregroundStyle(stats.unrealizedDelta >= 0 ? Theme.gain : Theme.loss)
```

replace the headline font:

```swift
        .font(.headline)
```

(first occurrence only — the `headline` block) with:

```swift
        .font(.display(.title3))
```

and wrap the money block in the card treatment by replacing `moneyBlock`'s closing brace region:

```swift
    private var moneyBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
```

with:

```swift
    private var moneyBlock: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
```

and appending `.cardStyle()` to that `VStack`'s closing brace:

```swift
        }
        .cardStyle()
    }
```

**6e — `Leatherfolio/Features/ItemDetail/ItemDetailView.swift`** (Phase 1 file): add to the outermost `ScrollView` (or root container) of `body`:

```swift
        .background(Theme.background)
```

and change the item-name title `Text` to serif display type by appending:

```swift
        .font(.display(.largeTitle))
```

**6f — `project.yml`:** ensure the app target's settings include the app-icon compiler flag (add it under the existing `settings:` block if missing; if already present, leave as-is):

```yaml
    settings:
      base:
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
```

- [ ] **Step 7: Generate the app icon**

Create `Scripts/generate_app_icon.swift` (macOS host script — run with `swift`, not part of the app target):

```swift
#!/usr/bin/env swift
// Generates the 1024px app icon: a cream serif "L" monogram on a cognac
// field. No SF Symbols, no PLG imagery. Re-run any time; output is
// deterministic apart from font rendering.
import AppKit

let pixels = 1024
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
    bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { fatalError("Could not create bitmap rep") }
rep.size = NSSize(width: pixels, height: pixels)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Cognac field (light-mode accent #8A4B2A)
NSColor(red: 0x8A / 255.0, green: 0x4B / 255.0, blue: 0x2A / 255.0, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: pixels, height: pixels).fill()

// Cream serif "L" (#F7F2E9), New York via the serif system design
let serifDescriptor = NSFontDescriptor
    .preferredFontDescriptor(forTextStyle: .largeTitle)
    .withDesign(.serif) ?? NSFontDescriptor(name: "Georgia", size: 640)
let font = NSFont(descriptor: serifDescriptor, size: 640) ?? .systemFont(ofSize: 640)
let text = NSAttributedString(string: "L", attributes: [
    .font: font,
    .foregroundColor: NSColor(red: 0xF7 / 255.0, green: 0xF2 / 255.0,
                              blue: 0xE9 / 255.0, alpha: 1),
])
let textSize = text.size()
text.draw(at: NSPoint(x: (CGFloat(pixels) - textSize.width) / 2,
                      y: (CGFloat(pixels) - textSize.height) / 2))

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("PNG encode failed")
}
let out = URL(fileURLWithPath:
    "Leatherfolio/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
try FileManager.default.createDirectory(at: out.deletingLastPathComponent(),
                                        withIntermediateDirectories: true)
try png.write(to: out)
print("Wrote \(out.path) (\(png.count) bytes)")
```

Write the appiconset manifest (single 1024px universal icon; overwrites any empty Phase-0 placeholder):

```bash
cd /Users/robbybarnes/GitHub/portland-leather
mkdir -p Leatherfolio/Resources/Assets.xcassets/AppIcon.appiconset
cat > Leatherfolio/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json <<'ICON_EOF'
{
  "images" : [
    {
      "filename" : "AppIcon.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
ICON_EOF
```

Then generate the PNG:

```bash
cd /Users/robbybarnes/GitHub/portland-leather
swift Scripts/generate_app_icon.swift
```

Expected output: `Wrote Leatherfolio/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png (<N> bytes)`. Verify: `file` reports `PNG image data, 1024 x 1024` and the image is fully opaque (no alpha — App Store icons reject alpha; the bitmap was created with `hasAlpha: false`).

- [ ] **Step 8: Build, test, and eyeball**

Run the full suite (same command as Step 2). Expected: **TEST SUCCEEDED**. Then launch in the simulator, light and dark mode: cream/espresso-dark backgrounds everywhere, cognac tint on buttons/toggles, parchment cards in the grid and stats money block, serif item titles, and the cognac "L" icon on the home screen.

- [ ] **Step 9: Commit**

```bash
cd /Users/robbybarnes/GitHub/portland-leather
git add Leatherfolio/Support/Theme.swift \
        Leatherfolio/Resources/Assets.xcassets \
        Scripts/generate_app_icon.swift \
        Leatherfolio/App/LeatherfolioApp.swift \
        Leatherfolio/Features/Collection/CollectionView.swift \
        Leatherfolio/Features/Collection/ItemCell.swift \
        Leatherfolio/Features/Stats/StatsView.swift \
        Leatherfolio/Features/ItemDetail/ItemDetailView.swift \
        project.yml \
        LeatherfolioTests/ThemeContrastTests.swift
git commit -m "feat: warm editorial theme, WCAG-verified palette, serif display type, app icon"
```

---

### Task 5: Accessibility pass

**Files:**
- Create: `Leatherfolio/Support/AccessibilityText.swift`
- Create (replacing the Phase-1 star control): `Leatherfolio/Features/ItemDetail/RatingControl.swift`
- Modify: `Leatherfolio/Features/Collection/CollectionView.swift`, `Leatherfolio/Features/Collection/ItemCell.swift`, `Leatherfolio/Features/ItemDetail/ItemDetailView.swift`
- Test: `LeatherfolioTests/AccessibilityTextTests.swift`

**Interfaces:**
- Consumes: `Item` (Phase 1), `Theme.accent` (Task 4), the Task 2 `CollectionView`/`ItemRow`.
- Produces: `AccessibilityText.label(for:)`, `AccessibilityText.ratingLabel(_:)`, `AccessibilityText.photoLabel(caption:index:count:)`; `RatingControl(rating: Binding<Int>)`.

**Adaptation note:** Phase 1 built some star-rating UI in the detail/add-edit screens. Replace it with the `RatingControl` below (same `Binding<Int>` shape). If Phase 1's control had a different name, delete it and update its call sites to `RatingControl(rating: $...)`.

- [ ] **Step 1: Write the failing label-composition tests**

Create `LeatherfolioTests/AccessibilityTextTests.swift`:

```swift
import XCTest
import SwiftData
@testable import Leatherfolio

@MainActor
final class AccessibilityTextTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: Item.self, Photo.self, Tag.self, configurations: config
        )
        context = ModelContext(container)
    }

    private func makeItem() -> Item {
        let item = Item()
        context.insert(item)
        return item
    }

    func testFullLabelComposition() {
        let item = makeItem()
        item.name = "Willow Tote"
        item.size = "Medium"
        item.color = "Honey"
        item.leatherType = .suede
        item.favorite = true
        item.isUnicorn = true
        item.rating = 3
        XCTAssertEqual(
            AccessibilityText.label(for: item),
            "Willow Tote, Medium, Honey, Suede leather, favorite, unicorn, rated 3 of 5 stars"
        )
    }

    func testMinimalItemLabel() {
        let item = makeItem()   // empty name, no attributes
        XCTAssertEqual(AccessibilityText.label(for: item), "Untitled item")
    }

    func testWishlistAndOtherLeatherHandling() {
        let item = makeItem()
        item.name = "Dream Backpack"
        item.leatherType = .other       // "Other leather" is noise — omitted
        item.isWishlist = true
        XCTAssertEqual(AccessibilityText.label(for: item),
                       "Dream Backpack, wishlist")
    }

    func testRatingLabel() {
        XCTAssertEqual(AccessibilityText.ratingLabel(0), "not rated")
        XCTAssertEqual(AccessibilityText.ratingLabel(1), "rated 1 of 5 stars")
        XCTAssertEqual(AccessibilityText.ratingLabel(5), "rated 5 of 5 stars")
    }

    func testPhotoLabelPrefersCaption() {
        XCTAssertEqual(
            AccessibilityText.photoLabel(caption: "Front pocket detail", index: 1, count: 4),
            "Front pocket detail"
        )
        XCTAssertEqual(
            AccessibilityText.photoLabel(caption: nil, index: 1, count: 4),
            "Photo 2 of 4"
        )
        XCTAssertEqual(
            AccessibilityText.photoLabel(caption: "  ", index: 0, count: 1),
            "Photo 1 of 1"
        )
    }
}
```

- [ ] **Step 2: Run tests to verify they fail to compile**

Run:

```bash
cd /Users/robbybarnes/GitHub/portland-leather
xcodegen generate && xcodebuild -project Leatherfolio.xcodeproj -scheme Leatherfolio \
  -destination 'platform=iOS Simulator,name=iPhone 16' test 2>&1 | tail -20
```

Expected: **BUILD FAILED** — `cannot find 'AccessibilityText' in scope`.

- [ ] **Step 3: Implement `AccessibilityText`**

Create `Leatherfolio/Support/AccessibilityText.swift`:

```swift
import Foundation

/// Pure composition of VoiceOver strings, so label wording is unit-testable
/// and identical wherever it's spoken.
enum AccessibilityText {
    /// Cell label, e.g. "Willow Tote, Medium, Honey, Suede leather, favorite,
    /// unicorn, rated 3 of 5 stars". Empty/irrelevant parts are omitted.
    static func label(for item: Item) -> String {
        var parts: [String] = [item.name.isEmpty ? "Untitled item" : item.name]
        if let size = item.size, !size.isEmpty { parts.append(size) }
        if let color = item.color, !color.isEmpty { parts.append(color) }
        if let leather = item.leatherType, leather != .other {
            parts.append("\(leather.rawValue) leather")
        }
        if item.favorite { parts.append("favorite") }
        if item.isUnicorn { parts.append("unicorn") }
        if item.isWishlist { parts.append("wishlist") }
        if item.rating > 0 { parts.append(ratingLabel(item.rating)) }
        return parts.joined(separator: ", ")
    }

    /// "rated 3 of 5 stars"; "not rated" for 0.
    static func ratingLabel(_ rating: Int) -> String {
        rating > 0 ? "rated \(rating) of 5 stars" : "not rated"
    }

    /// Carousel photo label: the caption when present, else "Photo 2 of 4".
    static func photoLabel(caption: String?, index: Int, count: Int) -> String {
        if let caption, !caption.trimmingCharacters(in: .whitespaces).isEmpty {
            return caption
        }
        return "Photo \(index + 1) of \(count)"
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Same command as Step 2. Expected: **TEST SUCCEEDED** including all 5 `AccessibilityTextTests`.

- [ ] **Step 5: Replace the star control with an adjustable `RatingControl`**

Create `Leatherfolio/Features/ItemDetail/RatingControl.swift` (delete Phase 1's star control and point its call sites here — see the adaptation note):

```swift
import SwiftUI

/// Star rating, 0–5. Tap a star to set it; tap the current rating again to
/// clear. To VoiceOver it is ONE adjustable element: swipe up/down to change,
/// value announced via AccessibilityText.ratingLabel.
struct RatingControl: View {
    @Binding var rating: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: star <= rating ? "star.fill" : "star")
                    .foregroundStyle(star <= rating ? Theme.accent : .secondary)
                    .onTapGesture {
                        rating = (rating == star) ? 0 : star
                    }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rating")
        .accessibilityValue(AccessibilityText.ratingLabel(rating))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: rating = min(rating + 1, 5)
            case .decrement: rating = max(rating - 1, 0)
            @unknown default: break
            }
        }
    }
}
```

- [ ] **Step 6: Wire VoiceOver labels into cells, rows, and the carousel**

Four exact edits:

**6a — `Leatherfolio/Features/Collection/ItemCell.swift`:** append to the cell's outermost container (after the `.cardStyle()` added in Task 4), and add `.accessibilityHidden(true)` to the cell's thumbnail `Image`:

```swift
        .cardStyle()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AccessibilityText.label(for: item))
```

**6b — `Leatherfolio/Features/Collection/CollectionView.swift`**, `ItemRow`: replace the trailing badge icons:

```swift
            Spacer()
            if item.favorite {
                Image(systemName: "heart.fill").foregroundStyle(.pink)
            }
            if item.isUnicorn {
                Image(systemName: "sparkles").foregroundStyle(.purple)
            }
        }
```

with (badges become decorative; the row speaks one composed label):

```swift
            Spacer()
            if item.favorite {
                Image(systemName: "heart.fill").foregroundStyle(.pink)
                    .accessibilityHidden(true)
            }
            if item.isUnicorn {
                Image(systemName: "sparkles").foregroundStyle(.purple)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AccessibilityText.label(for: item))
```

**6c — `Leatherfolio/Features/ItemDetail/ItemDetailView.swift`:** in the hero photo carousel's `ForEach` (Phase 1 iterates the item's photos, typically `Array(photos.enumerated())` or an indexed `ForEach`), attach to each photo `Image`:

```swift
                .accessibilityLabel(AccessibilityText.photoLabel(
                    caption: photo.caption, index: index, count: photos.count))
```

(`photo`/`index`/`photos` are the carousel's own loop variables.) Also mark purely decorative images in the detail view — spec-chip icons, the QR card's corner flourish if any — with `.accessibilityHidden(true)`. The QR code image itself is NOT decorative; give it `.accessibilityLabel("QR label for \(item.name)")`.

**6d — `Leatherfolio/Features/Collection/CollectionView.swift`**, Dynamic Type grid adaptation. Add the environment below the `@AppStorage` property:

```swift
    @AppStorage("collectionLayout") private var layoutRaw = CollectionLayout.grid.rawValue
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
```

and replace:

```swift
    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 150), spacing: 12)]
    }
```

with:

```swift
    private var gridColumns: [GridItem] {
        // At accessibility text sizes a multi-column grid truncates badly;
        // collapse to a single full-width column instead.
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.adaptive(minimum: 150), spacing: 12)]
    }
```

- [ ] **Step 7: Fixed-font-size audit**

Run:

```bash
cd /Users/robbybarnes/GitHub/portland-leather
grep -rn --include='*.swift' -E '\.font\(\s*\.system\(size:' Leatherfolio/ ; echo "exit: $?"
```

Expected: no matches (`exit: 1`). Every `.font(...)` in the app must use a text style (`.headline`, `.display(.title3)`, …), never a fixed point size. If any match appears, replace it with the nearest text style and re-run until clean.

- [ ] **Step 8: Run the full suite + manual VoiceOver/Dynamic Type smoke**

Run the full test suite (same command as Step 2). Expected: **TEST SUCCEEDED**.

Manual, in the simulator:
- Settings → Accessibility → Larger Text → largest accessibility size: collection collapses to one column; no clipped/truncated labels on cells, filter sheet, or stats.
- Accessibility Inspector (Xcode → Open Developer Tool) pointed at a grid cell reads the full composed label ("Willow Tote, Medium, Honey, …"); thumbnails and badge icons are not separate stops.
- On the detail screen, the rating control is a single adjustable element; swipe up/down changes the value and announces "rated N of 5 stars".
- Carousel photos announce captions (or "Photo 2 of 4").

- [ ] **Step 9: Commit**

```bash
cd /Users/robbybarnes/GitHub/portland-leather
git add Leatherfolio/Support/AccessibilityText.swift \
        Leatherfolio/Features/ItemDetail/RatingControl.swift \
        Leatherfolio/Features/Collection/CollectionView.swift \
        Leatherfolio/Features/Collection/ItemCell.swift \
        Leatherfolio/Features/ItemDetail/ItemDetailView.swift \
        LeatherfolioTests/AccessibilityTextTests.swift
git commit -m "feat: accessibility pass - VoiceOver labels, adjustable rating, Dynamic Type grid"
```

---

### Task 6: Final QA + release-readiness checklist

**Files:**
- Modify: `README.md` (repo root — currently a one-line stub)
- Create: `CHANGELOG.md` (repo root)

**Interfaces:**
- Consumes: everything — this task verifies the whole app.
- Produces: release-readiness docs; nothing downstream.

- [ ] **Step 1: Run the full test suite**

Run:

```bash
cd /Users/robbybarnes/GitHub/portland-leather
xcodegen generate && xcodebuild -project Leatherfolio.xcodeproj -scheme Leatherfolio \
  -destination 'platform=iOS Simulator,name=iPhone 16' test 2>&1 | tail -20
```

Expected: **TEST SUCCEEDED** — every test from Phases 0–4 (models/CloudKit-rules reflection, ImageStore, QRService, ScanRouter, CatalogSeed, CollectionStats, ItemFilter, FilterOptions, CurrencyFormat, StatsHeadline, StatsView render, ThemeContrast, AccessibilityText, UI smoke). Zero failures, zero skips other than any explicitly `XCTSkip`-gated camera tests.

- [ ] **Step 2: Manual release smoke (simulator, both light and dark mode)**

Work through every line; fix and re-run anything that fails before proceeding:

- [ ] Add an item with two photos, name, size, color, leather, cost, value, rating → appears in grid with thumbnail.
- [ ] Edit the item (change color, toggle favorite) → grid cell updates.
- [ ] Delete an item → gone from grid; its photos/thumbnails cleaned up (no orphan warnings in console).
- [ ] Detail view: carousel swipes, spec chips, value delta, QR label card visible.
- [ ] Scan the item's QR (second device camera on the simulator screen, or the in-sim test hook from Phase 3) → routes to that item's detail.
- [ ] Scan an unknown barcode → add flow opens with the code pre-attached.
- [ ] Camera permission denied → inline explainer with Settings link (no crash).
- [ ] Search, each filter, sort asc/desc, chips, Clear All, grid↔list toggle (persists across relaunch).
- [ ] Owned/Wishlist segmented toggle; a wishlist item is excluded from stats totals.
- [ ] Stats sheet: headline, money block with signed colored delta, chart, completeness rows.
- [ ] Dynamic Type at largest accessibility size + VoiceOver labels (Task 5 checklist spot-check).
- [ ] Fresh install (delete app from simulator, reinstall): seed pickers populated, empty states correct.

- [ ] **Step 3: Write the README**

Replace the contents of `README.md` (repo root) with:

````markdown
# Leatherfolio

A personal-catalog iOS app for cataloging a collection of leather bags and
accessories from one brand's ecosystem — name, size, color, leather type,
photos, cost/value, ratings — with QR self-labeling and barcode capture.
Local-first SwiftData storage with a CloudKit-ready schema.

**Status:** v1 feature-complete, local/personal use only. This is an
unofficial fan project; see Release gate below.

## Features

- Add/edit/delete items with photos (photo-first flow, external-storage originals, cached thumbnails)
- Curated cascading pickers (line → size → color → leather) seeded from bundled catalog data, free-text escape hatches everywhere
- Grid/list collection with search, filters, sort, active-filter chips, and an Owned/Wishlist scope
- Rich detail view: photo carousel, spec chips, rating, costs and value delta, per-item QR label
- QR self-labeling: scan an item's label to jump to it; unknown codes start the add flow (UPC captured, no lookup in v1)
- Stats: counts, total spent, estimated value, unrealized delta, average rating, items-by-category chart, per-line color completeness
- Warm editorial design language (WCAG AA palette, light/dark), full Dynamic Type and VoiceOver support

## Build

Requirements: macOS with Xcode 16+, an iOS 18 simulator, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
cd portland-leather
xcodegen generate
xcodebuild -project Leatherfolio.xcodeproj -scheme Leatherfolio \
  -destination 'platform=iOS Simulator,name=iPhone 16' build
```

Run tests:

```bash
xcodebuild -project Leatherfolio.xcodeproj -scheme Leatherfolio \
  -destination 'platform=iOS Simulator,name=iPhone 16' test
```

`Leatherfolio.xcodeproj` is generated and gitignored — `project.yml` is the
source of truth. Substitute any available simulator
(`xcrun simctl list devices available`). No third-party dependencies.

## Research-data provenance

`research/` contains reference data scraped from the brand's public Shopify
catalog (2026-07-20) for development only — it is not redistributed and not
shipped. The app bundles a hand-curated seed
(`Leatherfolio/Resources/plg_catalog.json`) derived from it.

## Release gate

**The app will not be released** (App Store or public TestFlight) until
Portland Leather Goods grants permission to use their product names and
imagery. Until then it is a local/personal project; the working title
"Leatherfolio" deliberately contains no brand trademark.

## Post-v1: CloudKit sync milestone

The schema is CloudKit-shaped from day one; sync is off
(`cloudKitDatabase: .none`). When Apple Developer Program signing exists:

- [ ] Add the iCloud capability + CloudKit container to `project.yml`, regenerate
- [ ] Flip `AppConfig.cloudKitEnabled` so the ModelConfiguration uses `.automatic`
- [ ] Two-device sync test (add/edit/delete propagate both directions)
- [ ] Verify the iCloud account-switch / signed-out warning UI ("your collection is on this device only")
````

- [ ] **Step 4: Write the CHANGELOG**

Create `CHANGELOG.md` (repo root):

```markdown
# Changelog

## v1.0.0 — 2026-07-20 (unreleased; personal builds only)

First feature-complete build of Leatherfolio.

### Added
- SwiftData models (Item/Photo/Tag) with CloudKit-safe schema, typed enum accessors, computed value delta
- ImageStore (external-storage originals, ~400px cached thumbnails), photo-first add/edit flow
- Bundled catalog seed with cascading line/size/color/leather pickers and free-text escape hatches
- QR self-labeling (leatherfolio://item/<uuid>), VisionKit scanner, scan routing, UPC capture (lookup deferred behind ProductLookupService)
- Collection home: grid/list layouts, search, filter sheet, chips, sort menu, Owned/Wishlist scope
- Stats screen: counts headline, spend/value/delta, average rating, category chart, line completeness
- Warm editorial theme (WCAG AA light/dark palette, serif display type, card styling) and generated app icon
- Accessibility: composed VoiceOver labels, adjustable rating control, Dynamic Type–adaptive grid

### Explicit non-goals (v1)
- No App Store submission until PLG grants naming/imagery permission
- No UPC lookup APIs, sharing/social, widgets, export, Watch app, or App Clips
- CloudKit sync off until signing exists (tracked as a post-v1 milestone in README.md)
```

- [ ] **Step 5: Regenerate, build once more, and commit**

Run:

```bash
cd /Users/robbybarnes/GitHub/portland-leather
xcodegen generate && xcodebuild -project Leatherfolio.xcodeproj -scheme Leatherfolio \
  -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5
```

Expected: **BUILD SUCCEEDED**. Then:

```bash
cd /Users/robbybarnes/GitHub/portland-leather
git add README.md CHANGELOG.md
git commit -m "chore: release-readiness docs (README build guide, changelog, CloudKit milestone)"
```

---

## Non-goals (restated for the whole phase)

- **No App Store submission** — release is gated on PLG's written permission for product names/imagery. Until then: local builds / personal TestFlight only.
- **No CloudKit sync in this phase** — the flip to `.automatic` is a tracked post-v1 milestone with its own mini-checklist (see README, "Post-v1: CloudKit sync milestone"): iCloud capability in `project.yml` → flip `AppConfig.cloudKitEnabled` → two-device sync test → account-switch warning UI.
- **No gamification** in stats (no streaks, badges, or leaderboards), no UPC lookup, no sharing/social/widgets/export/Watch/App Clips — all per the spec's v2+ list.

## Self-review (completed by the plan author)

1. **Spec coverage:** filter/sort/search + wishlist scope (Tasks 1–2, spec decision #8), stats (Task 3, "tasteful"), warm editorial design + Dynamic Type + VoiceOver (Tasks 4–5), app icon (Task 4), release gate + provenance + CloudKit milestone (Task 6). No v1 spec line for this phase is unimplemented.
2. **Placeholder scan:** no TBD/TODO; every code step contains complete code; the three Phase-1 seams (CollectionView toolbar/link value, ItemCell root, carousel loop variables) are explicit adaptation notes with the exact code to splice, not deferred work.
3. **Type consistency:** `ItemFilter`/`FilterChip.Kind`/`CollectionScope`/`SortKey` names match across Tasks 1→2→3; `FilterOptions.make` signatures match between test and implementation; `Theme.gain`/`Theme.loss`/`Theme.accent` (Task 4) match their uses in Tasks 4–5; `AccessibilityText` function names match between tests, views, and `RatingControl`; `CurrencyFormat`/`StatsHeadline`/`StatsView(stats:)` consistent between Task 3 steps. The `CollectionStats` surface consumed in Task 3 is spelled out with a verify-against-Phase-2 instruction because the master plan's shared-interface contract does not define it.
