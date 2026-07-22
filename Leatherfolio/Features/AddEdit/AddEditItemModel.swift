import Foundation
import Observation
import SwiftData

/// Form state + save logic for both add and edit, extracted from the view so
/// the save path is unit-testable without any UI.
@MainActor
@Observable
final class AddEditItemModel {

    // MARK: Form fields
    var name = ""
    var category: ItemCategory = .other
    var sizeText = ""
    var colorText = ""
    var leatherType: LeatherType?
    var condition: ItemCondition?
    var rating = 0
    var isUnicorn = false
    var favorite = false
    var isWishlist = false
    var myCostText = ""
    var retailCostText = ""
    var estimatedValueText = ""
    var hasDateAcquired = false
    var dateAcquired = Date.now
    var notes = ""

    /// JPEG/HEIC data of photos picked this session, in pick order.
    var newPhotoDatas: [Data] = []

    // MARK: Phase 2 injection point (cascading pickers)
    // Phase 2's CatalogSeed fills these from plg_catalog.json. Empty means
    // "no curated options" and the form falls back to free-text fields —
    // which is the entire Phase 1 behavior. Do not rename.
    var sizeOptions: [String] = []
    var colorOptions: [String] = []

    private(set) var existingItem: Item?
    var isEditing: Bool { existingItem != nil }
    var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    init(item: Item?) {
        existingItem = item
        guard let item else { return }
        name = item.name
        category = item.category
        sizeText = item.size ?? ""
        colorText = item.color ?? ""
        leatherType = item.leatherType
        condition = item.condition
        rating = item.rating
        isUnicorn = item.isUnicorn
        favorite = item.favorite
        isWishlist = item.isWishlist
        myCostText = DecimalParsing.text(from: item.myCost)
        retailCostText = DecimalParsing.text(from: item.retailCost)
        estimatedValueText = DecimalParsing.text(from: item.estimatedValue)
        hasDateAcquired = item.dateAcquired != nil
        dateAcquired = item.dateAcquired ?? .now
        notes = item.notes ?? ""
    }

    /// Writes the form into a new or existing Item, downsampling (2048 max
    /// dimension) and attaching any newly picked photos. The first photo an
    /// item ever gets becomes primary. Photos that fail to decode are
    /// skipped so the item still saves (spec: never lose user input over an
    /// image failure).
    @discardableResult
    func save(in context: ModelContext, imageStore: ImageStore = .shared) throws -> Item {
        let item = existingItem ?? Item()
        if existingItem == nil {
            context.insert(item)
        }
        item.name = name.trimmingCharacters(in: .whitespaces)
        item.category = category
        item.size = normalized(sizeText)
        item.color = normalized(colorText)
        item.leatherType = leatherType
        item.condition = condition
        item.rating = rating
        item.isUnicorn = isUnicorn
        item.favorite = favorite
        item.isWishlist = isWishlist
        item.myCost = DecimalParsing.decimal(from: myCostText)
        item.retailCost = DecimalParsing.decimal(from: retailCostText)
        item.estimatedValue = DecimalParsing.decimal(from: estimatedValueText)
        item.dateAcquired = hasDateAcquired ? dateAcquired : nil
        item.notes = normalized(notes)
        item.updatedAt = .now

        var hasPrimary = (item.photos ?? []).contains(where: \.isPrimary)
        for data in newPhotoDatas {
            guard let jpeg = imageStore.downsampledJPEG(from: data, maxDimension: 2_048) else {
                continue  // undecodable photo: skip it, keep the item
            }
            let photo = Photo()
            photo.imageData = jpeg
            photo.isPrimary = !hasPrimary
            hasPrimary = true
            photo.item = item
            context.insert(photo)
        }
        newPhotoDatas = []
        try context.save()
        return item
    }

    private func normalized(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
