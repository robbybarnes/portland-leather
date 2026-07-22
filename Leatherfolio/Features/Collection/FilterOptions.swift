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
