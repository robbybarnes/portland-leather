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
