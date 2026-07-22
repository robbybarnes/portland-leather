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

    var size: String {
        get { sizeText }
        set { sizeText = newValue }
    }
    var color: String {
        get { colorText }
        set { colorText = newValue }
    }

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
    var upc = ""

    /// JPEG/HEIC data of photos picked this session, in pick order.
    var newPhotoDatas: [Data] = []

    // MARK: - Scan capture (Phase 3)

    /// Prefill from a scan: retail barcodes become the UPC (stable identifier,
    /// spec decision #2 — capture, no lookup in v1); unknown QR payloads are
    /// attached to notes so no scanned data is ever dropped.
    func applyScanPrefill(code: String, isQR: Bool) {
        if isQR {
            let line = "Scanned code: \(code)"
            notes = notes.isEmpty ? line : notes + "\n" + line
        } else {
            upc = code
        }
    }

    // MARK: - UPC lookup seam (v2; NoOp in v1)

    /// Injection seam: tests assign a stub; v2 assigns a real lookup backend.
    var lookup: any ProductLookupService = NoOpProductLookup()

    /// If a UPC was captured, ask the lookup service and prefill name/notes —
    /// only fields the user hasn't filled, and only non-nil results. With
    /// NoOpProductLookup this is a no-op, so v1 behavior is unchanged.
    func lookupUPCIfNeeded() async {
        guard !upc.isEmpty else { return }
        guard let info = await lookup.lookup(upc: upc) else { return }
        if let lookedUpName = info.name, name.isEmpty { name = lookedUpName }
        if let lookedUpDescription = info.description, notes.isEmpty { notes = lookedUpDescription }
    }

    // MARK: - Catalog-driven picker options (Phase 2)

    /// Injection seam: tests assign a CatalogSeed(data:) fixture.
    var catalog: CatalogSeed = .shared

    /// Name of the selected catalog line; nil = free-form item.
    var selectedLineName: String?

    var lineOptions: [CatalogLine] { catalog.lines(in: category) }
    var selectedLine: CatalogLine? { selectedLineName.flatMap { catalog.line(named: $0) } }
    var sizeOptions: [String] { selectedLine?.sizes ?? [] }
    var colorOptions: [String] { selectedLine?.colors ?? [] }
    var leatherTypeOptions: [LeatherType] {
        (selectedLine?.leatherTypes ?? []).compactMap(LeatherType.init(rawValue:))
    }

    /// Select (or deselect with nil) a catalog line. Prefills the name when the
    /// user hasn't typed one (or typed exactly another line's name), and clears
    /// any picker choices the new line doesn't offer.
    func selectLine(_ line: CatalogLine?) {
        selectedLineName = line?.name
        guard let line else { return }
        if name.isEmpty || catalog.line(named: name) != nil {
            name = line.name
        }
        if !size.isEmpty, !line.sizes.contains(size) { size = "" }
        if !color.isEmpty, !line.colors.contains(color) { color = "" }
        if let leatherType, !line.leatherTypes.contains(leatherType.rawValue) {
            self.leatherType = nil
        }
    }

    /// Call after `category` changes: a line from another category can't stay selected.
    func categoryDidChange() {
        if let selectedLine, selectedLine.category != category.rawValue {
            selectLine(nil)
        }
    }

    /// Call when loading an existing item for editing: re-links the line whose
    /// name the item carries so the cascading pickers light up.
    func syncSelectedLineFromName() {
        selectedLineName = catalog.line(named: name)?.name
    }

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
        upc = item.upc ?? ""
        syncSelectedLineFromName()
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
        item.upc = normalized(upc)
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
