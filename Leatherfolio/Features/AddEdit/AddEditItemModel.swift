import Foundation
import Observation
import SwiftData

typealias PhotoDataLoader = @Sendable () async throws -> Data

enum PhotoWorkflowError: Error, Equatable {
    case busy
}

struct QueuedPhoto: Identifiable, Equatable {
    let id: UUID
    var data: Data
    var caption: String

    init(id: UUID = UUID(), data: Data, caption: String = "") {
        self.id = id
        self.data = data
        self.caption = caption
    }
}

struct ExistingPhotoDraft: Identifiable, Equatable {
    let id: UUID
    var caption: String
    var isPrimary: Bool
}

/// Form state + save logic for both add and edit. SwiftData model access stays
/// on the main actor; imported bytes cross to ImageStore's worker only as Data.
@MainActor
@Observable
final class AddEditItemModel {
    private let locale: Locale

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

    // MARK: Pending photo state

    private(set) var queuedPhotos: [QueuedPhoto] = []
    private(set) var existingPhotos: [ExistingPhotoDraft] = []
    private var removedExistingPhotoIDs: Set<UUID> = []
    private(set) var primaryPhotoID: UUID?
    private(set) var isImporting = false
    private(set) var isSaving = false
    var photoImportErrorMessage: String?

    /// Compatibility with Task A's retry contract. Direct assignments are
    /// represented as queued photo drafts and survive every failed save.
    var newPhotoDatas: [Data] {
        get { queuedPhotos.map(\.data) }
        set {
            queuedPhotos = newValue.map { QueuedPhoto(data: $0) }
            normalizePrimarySelection()
        }
    }

    var visibleExistingPhotos: [ExistingPhotoDraft] {
        existingPhotos.filter { !removedExistingPhotoIDs.contains($0.id) }
    }

    var isBusy: Bool { isImporting || isSaving }

    func queuePhoto(_ data: Data) {
        let queued = QueuedPhoto(data: data)
        queuedPhotos.append(queued)
        if primaryPhotoID == nil { primaryPhotoID = queued.id }
    }

    func removeQueuedPhoto(id: UUID) {
        queuedPhotos.removeAll { $0.id == id }
        normalizePrimarySelection()
    }

    func removeExistingPhoto(id: UUID) {
        guard existingPhotos.contains(where: { $0.id == id }) else { return }
        removedExistingPhotoIDs.insert(id)
        normalizePrimarySelection()
    }

    func isExistingPhotoRemoved(_ id: UUID) -> Bool {
        removedExistingPhotoIDs.contains(id)
    }

    func choosePrimary(photoID: UUID) {
        guard visibleExistingPhotos.contains(where: { $0.id == photoID })
                || queuedPhotos.contains(where: { $0.id == photoID }) else { return }
        primaryPhotoID = photoID
    }

    func updateCaption(_ caption: String, for photoID: UUID) {
        if let index = existingPhotos.firstIndex(where: { $0.id == photoID }) {
            existingPhotos[index].caption = caption
        } else if let index = queuedPhotos.firstIndex(where: { $0.id == photoID }) {
            queuedPhotos[index].caption = caption
        }
    }

    func caption(for photoID: UUID) -> String {
        existingPhotos.first(where: { $0.id == photoID })?.caption
            ?? queuedPhotos.first(where: { $0.id == photoID })?.caption
            ?? ""
    }

    func existingPhoto(for id: UUID) -> Photo? {
        existingItem?.photos?.first { $0.id == id }
    }

    /// Imports sequentially so one picker batch has exactly one tracked owner.
    /// Failures are accumulated and reported without dropping successful data.
    func importPhotos(
        using loaders: [PhotoDataLoader],
        imageStore: ImageStore = .shared
    ) async {
        guard !isBusy else { return }
        isImporting = true
        photoImportErrorMessage = nil
        defer { isImporting = false }

        var failureCount = 0
        for load in loaders {
            do {
                let sourceData = try await load()
                guard let prepared = await imageStore.prepareOriginal(from: sourceData) else {
                    failureCount += 1
                    continue
                }
                queuePhoto(prepared)
            } catch {
                failureCount += 1
            }
        }
        if failureCount > 0 {
            let noun = failureCount == 1 ? "photo" : "photos"
            photoImportErrorMessage = "\(failureCount) \(noun) couldn't be imported. Your other photos and item details are unchanged."
        }
    }

    // MARK: - Scan capture (Phase 3)

    func applyScanPrefill(code: String, isQR: Bool) {
        if isQR {
            let line = "Scanned code: \(code)"
            notes = notes.isEmpty ? line : notes + "\n" + line
        } else {
            upc = code
        }
    }

    // MARK: - UPC lookup seam (v2; NoOp in v1)

    var lookup: any ProductLookupService = NoOpProductLookup()

    func lookupUPCIfNeeded() async {
        guard !upc.isEmpty else { return }
        guard let info = await lookup.lookup(upc: upc) else { return }
        if let lookedUpName = info.name, name.isEmpty { name = lookedUpName }
        if let lookedUpDescription = info.description, notes.isEmpty { notes = lookedUpDescription }
    }

    // MARK: - Catalog-driven picker options (Phase 2)

    var catalog: CatalogSeed = .shared
    var selectedLineName: String?

    var lineOptions: [CatalogLine] { catalog.lines(in: category) }
    var selectedLine: CatalogLine? { selectedLineName.flatMap { catalog.line(named: $0) } }
    var sizeOptions: [String] { selectedLine?.sizes ?? [] }
    var colorOptions: [String] { selectedLine?.colors ?? [] }
    var leatherTypeOptions: [LeatherType] {
        (selectedLine?.leatherTypes ?? []).compactMap(LeatherType.init(rawValue:))
    }

    func selectLine(_ line: CatalogLine?) {
        selectedLineName = line?.name
        guard let line else { return }
        if name.isEmpty || catalog.line(named: name) != nil { name = line.name }
        if !size.isEmpty, !line.sizes.contains(size) { size = "" }
        if !color.isEmpty, !line.colors.contains(color) { color = "" }
        if let leatherType, !line.leatherTypes.contains(leatherType.rawValue) {
            self.leatherType = nil
        }
    }

    func categoryDidChange() {
        guard let selectedLine, selectedLine.category != category.rawValue else { return }
        if name == selectedLine.name { name = "" }
        if selectedLine.sizes.contains(size) { size = "" }
        if selectedLine.colors.contains(color) { color = "" }
        if let leatherType, selectedLine.leatherTypes.contains(leatherType.rawValue) {
            self.leatherType = nil
        }
        selectLine(nil)
    }

    func syncSelectedLineFromName() {
        selectedLineName = catalog.line(named: name)?.name
    }

    private(set) var existingItem: Item?
    var isEditing: Bool { existingItem != nil }
    var canSave: Bool {
        !isBusy && !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    init(item: Item?, locale: Locale = .current) {
        self.locale = locale
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
        myCostText = DecimalParsing.text(from: item.myCost, locale: locale)
        retailCostText = DecimalParsing.text(from: item.retailCost, locale: locale)
        estimatedValueText = DecimalParsing.text(from: item.estimatedValue, locale: locale)
        hasDateAcquired = item.dateAcquired != nil
        dateAcquired = item.dateAcquired ?? .now
        notes = item.notes ?? ""
        upc = item.upc ?? ""
        selectedLineName = item.catalogLineName
        if selectedLineName == nil { syncSelectedLineFromName() }
        loadExistingPhotoDrafts(from: item)
    }

    /// Prepares queued bytes on ImageStore's worker, then applies every item
    /// and photo mutation in the existing SwiftData transaction on MainActor.
    /// Cache cleanup is deliberately delayed until commit succeeds.
    @discardableResult
    func save(
        in context: ModelContext,
        imageStore: ImageStore = .shared,
        saveOperation: (ModelContext) throws -> Void = { try $0.save() }
    ) async throws -> Item {
        guard !isBusy else { throw PhotoWorkflowError.busy }
        isSaving = true
        defer { isSaving = false }

        let queuedSnapshot = queuedPhotos
        var preparedQueued: [(draft: QueuedPhoto, data: Data)] = []
        for draft in queuedSnapshot {
            if let prepared = await imageStore.prepareOriginal(from: draft.data) {
                preparedQueued.append((draft, prepared))
            }
        }

        let item = existingItem ?? Item()
        let original = existingItem.map(ItemSaveSnapshot.init)
        let originalPhotos = (existingItem?.photos ?? []).map(PhotoSaveSnapshot.init)
        let removedIDs = removedExistingPhotoIDs

        do {
            try context.transaction {
                if existingItem == nil { context.insert(item) }
                applyForm(to: item)

                let currentPhotos = item.photos ?? []
                let removedPhotos = currentPhotos.filter { removedIDs.contains($0.id) }
                let survivingPhotos = currentPhotos.filter { !removedIDs.contains($0.id) }
                for photo in removedPhotos { context.delete(photo) }

                for photo in survivingPhotos {
                    if let draft = existingPhotos.first(where: { $0.id == photo.id }) {
                        photo.caption = normalized(draft.caption)
                    }
                    photo.isPrimary = false
                }

                var insertedPhotos: [Photo] = []
                for prepared in preparedQueued {
                    let photo = Photo()
                    photo.id = prepared.draft.id
                    photo.imageData = prepared.data
                    photo.caption = normalized(prepared.draft.caption)
                    photo.item = item
                    context.insert(photo)
                    insertedPhotos.append(photo)
                }

                let allSavedPhotos = survivingPhotos + insertedPhotos
                let validIDs = Set(allSavedPhotos.map(\.id))
                let selectedPrimary = primaryPhotoID.flatMap {
                    validIDs.contains($0) ? $0 : nil
                } ?? allSavedPhotos.first?.id
                for photo in allSavedPhotos {
                    photo.isPrimary = photo.id == selectedPrimary
                }
                item.photos = allSavedPhotos
                try saveOperation(context)
            }
        } catch {
            originalPhotos.forEach { $0.restore() }
            original?.restore(item)
            context.processPendingChanges()
            context.rollback()
            throw error
        }

        existingItem = item
        queuedPhotos.removeAll()
        removedExistingPhotoIDs.removeAll()
        loadExistingPhotoDrafts(from: item)
        for photoID in removedIDs {
            await imageStore.removeThumbnail(for: photoID)
        }
        return item
    }

    private func applyForm(to item: Item) {
        item.name = name.trimmingCharacters(in: .whitespaces)
        item.catalogLineName = selectedLineName
        item.category = category
        item.size = normalized(sizeText)
        item.color = normalized(colorText)
        item.leatherType = leatherType
        item.condition = condition
        item.rating = rating
        item.isUnicorn = isUnicorn
        item.favorite = favorite
        item.isWishlist = isWishlist
        item.myCost = DecimalParsing.decimal(from: myCostText, locale: locale)
        item.retailCost = DecimalParsing.decimal(from: retailCostText, locale: locale)
        item.estimatedValue = DecimalParsing.decimal(from: estimatedValueText, locale: locale)
        item.dateAcquired = hasDateAcquired ? dateAcquired : nil
        item.notes = normalized(notes)
        item.upc = normalized(upc)
        item.updatedAt = .now
    }

    private func loadExistingPhotoDrafts(from item: Item) {
        existingPhotos = (item.photos ?? [])
            .sorted { $0.createdAt < $1.createdAt }
            .map {
                ExistingPhotoDraft(
                    id: $0.id,
                    caption: $0.caption ?? "",
                    isPrimary: $0.isPrimary)
            }
        primaryPhotoID = item.primaryPhoto?.id
        normalizePrimarySelection()
    }

    private func normalizePrimarySelection() {
        let validIDs = Set(visibleExistingPhotos.map(\.id) + queuedPhotos.map(\.id))
        if let primaryPhotoID, validIDs.contains(primaryPhotoID) { return }
        primaryPhotoID = visibleExistingPhotos.first?.id ?? queuedPhotos.first?.id
    }

    private struct PhotoSaveSnapshot {
        let photo: Photo
        let caption: String?
        let isPrimary: Bool
        let item: Item?

        init(_ photo: Photo) {
            self.photo = photo
            caption = photo.caption
            isPrimary = photo.isPrimary
            item = photo.item
        }

        func restore() {
            photo.caption = caption
            photo.isPrimary = isPrimary
            photo.item = item
        }
    }

    /// SwiftData rollback clears pending bookkeeping but does not reliably
    /// refresh already-referenced models, so restore values before rollback.
    private struct ItemSaveSnapshot {
        let name: String
        let catalogLineName: String?
        let categoryRaw: String
        let size: String?
        let color: String?
        let leatherTypeRaw: String?
        let isUnicorn: Bool
        let isWishlist: Bool
        let favorite: Bool
        let myCost: Decimal?
        let retailCost: Decimal?
        let estimatedValue: Decimal?
        let rating: Int
        let upc: String?
        let conditionRaw: String?
        let dateAcquired: Date?
        let notes: String?
        let updatedAt: Date
        let photos: [Photo]?

        init(_ item: Item) {
            name = item.name
            catalogLineName = item.catalogLineName
            categoryRaw = item.categoryRaw
            size = item.size
            color = item.color
            leatherTypeRaw = item.leatherTypeRaw
            isUnicorn = item.isUnicorn
            isWishlist = item.isWishlist
            favorite = item.favorite
            myCost = item.myCost
            retailCost = item.retailCost
            estimatedValue = item.estimatedValue
            rating = item.rating
            upc = item.upc
            conditionRaw = item.conditionRaw
            dateAcquired = item.dateAcquired
            notes = item.notes
            updatedAt = item.updatedAt
            photos = item.photos
        }

        func restore(_ item: Item) {
            item.name = name
            item.catalogLineName = catalogLineName
            item.categoryRaw = categoryRaw
            item.size = size
            item.color = color
            item.leatherTypeRaw = leatherTypeRaw
            item.isUnicorn = isUnicorn
            item.isWishlist = isWishlist
            item.favorite = favorite
            item.myCost = myCost
            item.retailCost = retailCost
            item.estimatedValue = estimatedValue
            item.rating = rating
            item.upc = upc
            item.conditionRaw = conditionRaw
            item.dateAcquired = dateAcquired
            item.notes = notes
            item.updatedAt = updatedAt
            item.photos = photos
        }
    }

    private func normalized(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
