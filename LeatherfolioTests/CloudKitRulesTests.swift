import XCTest
import SwiftData
@testable import Leatherfolio

/// Swift 6 concurrency: SwiftData's mainContext is main-actor-bound, so the
/// whole test class runs on @MainActor.
@MainActor
final class CloudKitRulesTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        container = try AppModelContainer.make(inMemory: true)
        context = container.mainContext
    }

    override func tearDownWithError() throws {
        context = nil
        container = nil
    }

    func testCloudKitDisabledUsesExplicitNoneInsteadOfSDKAutomaticDefault() throws {
        XCTAssertFalse(AppConfig.cloudKitEnabled)

        let configured = AppModelContainer.configuration(inMemory: true)
        let schema = try XCTUnwrap(configured.schema)
        let explicitNone = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none)
        let sdkDefault = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true)

        let configuredDatabase = String(reflecting: configured.cloudKitDatabase)
        let explicitNoneDatabase = String(reflecting: explicitNone.cloudKitDatabase)
        let sdkDefaultDatabase = String(reflecting: sdkDefault.cloudKitDatabase)
        XCTAssertEqual(configuredDatabase, explicitNoneDatabase)
        XCTAssertNotEqual(configuredDatabase, sdkDefaultDatabase,
                          "The SDK default is .automatic, which must stay disabled until signing exists")
    }

    func testDiskStoreReopensItemAndExternallyStoredPhotoData() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "LeatherfolioTests-" + UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }

        let storeURL = directory.appending(path: "collection.store")
        let itemID = UUID()
        let photoData = Data((0..<65_536).map { UInt8($0 % 251) })

        do {
            let diskContainer = try AppModelContainer.make(inMemory: false, storeURL: storeURL)
            let diskContext = diskContainer.mainContext
            let item = Item()
            item.id = itemID
            item.name = "Persistent Tote"
            let photo = Photo()
            photo.imageData = photoData
            photo.isPrimary = true
            photo.item = item
            diskContext.insert(item)
            diskContext.insert(photo)
            try diskContext.save()
        }

        do {
            let reopenedContainer = try AppModelContainer.make(inMemory: false, storeURL: storeURL)
            let reopenedContext = reopenedContainer.mainContext
            let saved = try XCTUnwrap(
                reopenedContext.fetch(FetchDescriptor<Item>()).first { $0.id == itemID })
            XCTAssertEqual(saved.name, "Persistent Tote")
            XCTAssertEqual(saved.photos?.count, 1)
            XCTAssertEqual(saved.primaryPhoto?.imageData, photoData)
        }
    }

    func testPreCatalogLineStoreMigratesWithoutLosingItemData() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "LeatherfolioLegacyTests-" + UUID().uuidString,
                       directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appending(path: "pre-catalog-line.store")
        let itemID = UUID()

        do {
            let legacyContainer = try LegacyPreCatalogSchema.make(storeURL: storeURL)
            let legacyItem = LegacyPreCatalogSchema.Item()
            legacyItem.id = itemID
            legacyItem.name = "Legacy Custom Name"
            legacyItem.categoryRaw = ItemCategory.tote.rawValue
            legacyItem.color = "Honey"
            legacyItem.notes = "Created before catalogLineName"
            legacyContainer.mainContext.insert(legacyItem)
            try legacyContainer.mainContext.save()
        }

        do {
            let migratedContainer = try AppModelContainer.make(
                inMemory: false,
                storeURL: storeURL)
            let migratedItem = try XCTUnwrap(
                migratedContainer.mainContext.fetch(FetchDescriptor<Item>())
                    .first { $0.id == itemID })
            XCTAssertEqual(migratedItem.name, "Legacy Custom Name")
            XCTAssertEqual(migratedItem.category, .tote)
            XCTAssertEqual(migratedItem.color, "Honey")
            XCTAssertEqual(migratedItem.notes, "Created before catalogLineName")
            XCTAssertNil(migratedItem.catalogLineName)
        }
    }

    /// CloudKit rule: every property optional or defaulted. If a bare Item()
    /// inserts and saves with no arguments, the rule holds for the schema.
    func testItemWithOnlyDefaultsSaves() throws {
        let item = Item()
        context.insert(item)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Item>())
        XCTAssertEqual(fetched.count, 1)
        let saved = try XCTUnwrap(fetched.first)
        XCTAssertEqual(saved.name, "")
        XCTAssertEqual(saved.category, .other)
        XCTAssertEqual(saved.rating, 0)
        XCTAssertFalse(saved.isUnicorn)
        XCTAssertFalse(saved.isWishlist)
        XCTAssertFalse(saved.favorite)
        XCTAssertNil(saved.size)
        XCTAssertNil(saved.color)
        XCTAssertNil(saved.catalogLineName)
        XCTAssertNil(saved.leatherType)
        XCTAssertNil(saved.condition)
        XCTAssertNil(saved.myCost)
        XCTAssertNil(saved.retailCost)
        XCTAssertNil(saved.estimatedValue)
        XCTAssertNil(saved.valueDelta)
        XCTAssertNil(saved.upc)
        XCTAssertNil(saved.dateAcquired)
        XCTAssertNil(saved.notes)
        XCTAssertTrue((saved.photos ?? []).isEmpty)
        XCTAssertTrue((saved.tags ?? []).isEmpty)
        XCTAssertNil(saved.primaryPhoto)
    }

    /// Relationships round-trip in both directions: Item -> Photo/Tag and
    /// the inverses Photo.item / Tag.items.
    func testPhotoAndTagRelationshipsRoundTrip() throws {
        let item = Item()
        item.name = "Medium Crossbody Tote"
        let photo = Photo()
        photo.isPrimary = true
        photo.item = item
        let tag = Tag(name: "work")
        item.tags = [tag]
        context.insert(item)
        context.insert(photo)
        context.insert(tag)
        try context.save()

        let items = try context.fetch(FetchDescriptor<Item>())
        let saved = try XCTUnwrap(items.first)
        XCTAssertEqual(saved.photos?.count, 1)
        XCTAssertEqual(saved.primaryPhoto?.id, photo.id)
        XCTAssertEqual(saved.tags?.first?.name, "work")
        XCTAssertEqual(photo.item?.id, saved.id)
        XCTAssertEqual(tag.items?.first?.id, saved.id)
    }

    /// Typed accessors map to/from raw string storage, and valueDelta is
    /// computed (never stored).
    func testTypedAccessorsMapRawStorage() throws {
        let item = Item()
        item.category = .tote
        XCTAssertEqual(item.categoryRaw, "Tote")
        item.leatherType = .pebbled
        XCTAssertEqual(item.leatherTypeRaw, "Pebbled")
        item.condition = .excellent
        XCTAssertEqual(item.conditionRaw, "Excellent")
        item.myCost = 100
        item.estimatedValue = 145
        XCTAssertEqual(item.valueDelta, 45)
        item.myCost = nil
        XCTAssertNil(item.valueDelta)
    }
}

/// A real on-disk schema matching the production Item/Photo/Tag shape before
/// commit 1808c08 added Item.catalogLineName. The migration test writes this
/// schema first and only then opens the store with the current app schema.
private enum LegacyPreCatalogSchema {
    @Model
    final class Item {
        var id: UUID = UUID()
        var name: String = ""
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
        var rating: Int = 0
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
    }

    @Model
    final class Photo {
        var id: UUID = UUID()
        @Attribute(.externalStorage) var imageData: Data?
        var caption: String?
        var isPrimary: Bool = false
        var createdAt: Date = Date.now
        var item: Item?

        init() {}
    }

    @Model
    final class Tag {
        var name: String = ""
        var items: [Item]? = []

        init(name: String = "") {
            self.name = name
        }
    }

    @MainActor
    static func make(storeURL: URL) throws -> ModelContainer {
        let schema = Schema([Item.self, Photo.self, Tag.self])
        let configuration = ModelConfiguration(
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
