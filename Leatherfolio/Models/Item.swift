import SwiftData
import Foundation

@Model
final class Item {
    var id: UUID = UUID()
    var name: String = ""
    var catalogLineName: String? = nil
    var categoryRaw: String = ItemCategory.other.rawValue
    var size: String?
    var color: String?
    var leatherTypeRaw: String?
    var isUnicorn: Bool = false
    var isWishlist: Bool = false
    var favorite: Bool = false
    var myCost: Decimal?
    var retailCost: Decimal?
    var estimatedValue: Decimal?
    var rating: Int = 0            // 0 = unrated, 1–5 stars
    var upc: String?
    var conditionRaw: String?
    var dateAcquired: Date?
    var notes: String?
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    @Relationship(deleteRule: .cascade, inverse: \Photo.item)
    var photos: [Photo]? = []
    @Relationship(inverse: \Tag.items)
    var tags: [Tag]? = []

    init() {}

    // Typed accessors over raw storage (SwiftData can't filter enums-in-Codable)
    var category: ItemCategory {
        get { ItemCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }
    var leatherType: LeatherType? {
        get { leatherTypeRaw.flatMap(LeatherType.init(rawValue:)) }
        set { leatherTypeRaw = newValue?.rawValue }
    }
    var condition: ItemCondition? {
        get { conditionRaw.flatMap(ItemCondition.init(rawValue:)) }
        set { conditionRaw = newValue?.rawValue }
    }
    var valueDelta: Decimal? {   // computed, never stored
        guard let estimatedValue, let myCost else { return nil }
        return estimatedValue - myCost
    }
    var primaryPhoto: Photo? {
        (photos ?? []).first(where: \.isPrimary) ?? photos?.first
    }
}
