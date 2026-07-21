import XCTest
import SwiftData
@testable import Leatherfolio

/// Swift 6 concurrency: SwiftData's mainContext is main-actor-bound, so the
/// whole test class runs on @MainActor.
@MainActor
final class CloudKitRulesTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let container = try AppModelContainer.make(inMemory: true)
        return container.mainContext
    }

    /// CloudKit rule: every property optional or defaulted. If a bare Item()
    /// inserts and saves with no arguments, the rule holds for the schema.
    func testItemWithOnlyDefaultsSaves() throws {
        let context = try makeContext()
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
        let context = try makeContext()
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
