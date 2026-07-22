import Foundation

struct ProductInfo: Equatable { let name: String?; let description: String? }

protocol ProductLookupService: Sendable {
    func lookup(upc: String) async -> ProductInfo?
}

/// v1 implementation. The brief concluded PLG products likely aren't in public
/// UPC databases; v1 captures the raw code only. A v2 lookup backend replaces
/// this by assigning AddEditItemModel.lookup — nothing else changes.
struct NoOpProductLookup: ProductLookupService {
    func lookup(upc: String) async -> ProductInfo? { nil }
}
