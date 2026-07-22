import Foundation

/// One curated product line from the bundled seed (Resources/plg_catalog.json).
struct CatalogLine: Decodable, Identifiable, Equatable {
    let name: String            // e.g. "Crossbody Tote"
    let category: String        // ItemCategory rawValue
    let sizes: [String]
    let colors: [String]
    let leatherTypes: [String]  // LeatherType rawValues
    var id: String { name }
}

/// Loads and queries the bundled catalog seed. Never crashes on missing or
/// malformed data — pickers degrade to free-text when `lines` is empty.
final class CatalogSeed: Sendable {
    static let shared = CatalogSeed()

    let lines: [CatalogLine]

    /// Loads Resources/plg_catalog.json from the app bundle.
    convenience init() {
        let data = Bundle.main.url(forResource: "plg_catalog", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) }
        self.init(data: data ?? Data())
    }

    /// Test seam: decode from raw data; malformed input falls back to [].
    init(data: Data) {
        self.lines = (try? JSONDecoder().decode([CatalogLine].self, from: data)) ?? []
    }

    func lines(in category: ItemCategory) -> [CatalogLine] {
        lines.filter { $0.category == category.rawValue }
    }

    func line(named name: String) -> CatalogLine? {
        lines.first { $0.name == name }
    }

    /// Deduped, sorted union of every line's colors.
    var allColors: [String] {
        Array(Set(lines.flatMap(\.colors))).sorted()
    }
}
