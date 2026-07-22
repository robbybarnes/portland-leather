import Foundation

/// "You own N of M colors of line X" — one entry per catalog line the user owns.
struct LineCompleteness: Equatable, Identifiable {
    let lineName: String
    let ownedColors: [String]   // distinct owned colors that exist in the line's palette
    let totalColors: Int        // the line's full palette size

    var id: String { lineName }
    var summary: String {
        "You own \(ownedColors.count) of \(totalColors) colors of \(lineName)"
    }
}

/// One bar of Phase 4's items-by-category chart.
struct CategoryCount: Equatable, Identifiable {
    let category: ItemCategory
    let count: Int
    var id: String { category.rawValue }
}

/// Pure stats engine over a snapshot of items. Computed, never stored (spec:
/// derived values are computed). Phase 4's stats screen renders this.
struct CollectionStats: Equatable {
    let itemCount: Int
    let distinctColorCount: Int
    let distinctLeatherTypeCount: Int
    let unicornCount: Int
    let totalSpent: Decimal           // sum of myCost where present
    let totalEstimatedValue: Decimal  // sum of estimatedValue where present
    let unrealizedDelta: Decimal      // sum of per-item valueDelta (both sides present)
    let averageRating: Double?        // over items with rating >= 1; nil if none rated
    let itemsByCategory: [CategoryCount]      // ordered by ItemCategory.allCases; empty categories omitted
    let lineCompleteness: [LineCompleteness]  // sorted by lineName

    init(items: [Item], catalog: CatalogSeed) {
        itemCount = items.count
        distinctColorCount = Set(items.compactMap { normalizedColorKey($0.color) }).count
        distinctLeatherTypeCount = Set(items.compactMap(\.leatherType)).count
        unicornCount = items.count(where: \.isUnicorn)
        totalSpent = items.compactMap(\.myCost).reduce(0, +)
        totalEstimatedValue = items.compactMap(\.estimatedValue).reduce(0, +)
        unrealizedDelta = items.compactMap(\.valueDelta).reduce(0, +)

        let ratings = items.map(\.rating).filter { $0 >= 1 }
        averageRating = ratings.isEmpty
            ? nil
            : Double(ratings.reduce(0, +)) / Double(ratings.count)

        let byCategory = Dictionary(grouping: items, by: \.category)
        itemsByCategory = ItemCategory.allCases.compactMap { cat in
            guard let count = byCategory[cat]?.count, count > 0 else { return nil }
            return CategoryCount(category: cat, count: count)
        }

        // Prefer the durable catalog association. Exact item-name matching is
        // retained for items created before catalogLineName existed.
        var ownedByLine: [String: Set<String>] = [:]
        for item in items {
            let associatedLine = item.catalogLineName.flatMap(catalog.line(named:))
            guard let line = associatedLine ?? catalog.line(named: item.name) else { continue }
            let owned = ownedByLine[line.name] ?? []
            let canonicalColors = canonicalColorMap(for: line.colors)
            if let key = normalizedColorKey(item.color), let canonical = canonicalColors[key] {
                ownedByLine[line.name] = owned.union([canonical])
            } else {
                ownedByLine[line.name] = owned  // owning the line with an off-palette color still lists the line
            }
        }
        lineCompleteness = ownedByLine.keys.sorted().compactMap { lineName in
            guard let line = catalog.line(named: lineName) else { return nil }
            return LineCompleteness(
                lineName: lineName,
                ownedColors: ownedByLine[lineName, default: []].sorted(),
                totalColors: canonicalColorMap(for: line.colors).count)
        }
    }
}

private func normalizedColorKey(_ color: String?) -> String? {
    guard let color else { return nil }
    let trimmed = color.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    let locale = Locale(identifier: "en_US_POSIX")
    return trimmed
        .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: locale)
        .lowercased(with: locale)
}

private func canonicalColorMap(for colors: [String]) -> [String: String] {
    var result: [String: String] = [:]
    for color in colors {
        guard let key = normalizedColorKey(color), result[key] == nil else { continue }
        result[key] = color
    }
    return result
}
