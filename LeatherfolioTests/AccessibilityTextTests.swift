import XCTest
import SwiftData
@testable import Leatherfolio

@MainActor
final class AccessibilityTextTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        container = try AppModelContainer.make(inMemory: true)
        context = container.mainContext
    }

    override func tearDown() {
        context = nil
        container = nil
    }

    private func makeItem() -> Item {
        let item = Item()
        context.insert(item)
        return item
    }

    func testFullLabelComposition() {
        let item = makeItem()
        item.name = "Willow Tote"
        item.size = "Medium"
        item.color = "Honey"
        item.leatherType = .suede
        item.favorite = true
        item.isUnicorn = true
        item.rating = 3
        XCTAssertEqual(
            AccessibilityText.label(for: item),
            "Willow Tote, Medium, Honey, Suede leather, favorite, unicorn, rated 3 of 5 stars"
        )
    }

    func testMinimalItemLabel() {
        let item = makeItem()   // empty name, no attributes
        XCTAssertEqual(AccessibilityText.label(for: item), "Untitled item")
    }

    func testWishlistAndOtherLeatherHandling() {
        let item = makeItem()
        item.name = "Dream Backpack"
        item.leatherType = .other       // "Other leather" is noise — omitted
        item.isWishlist = true
        XCTAssertEqual(AccessibilityText.label(for: item),
                       "Dream Backpack, wishlist")
    }

    func testRatingLabel() {
        XCTAssertEqual(AccessibilityText.ratingLabel(0), "not rated")
        XCTAssertEqual(AccessibilityText.ratingLabel(1), "rated 1 of 5 stars")
        XCTAssertEqual(AccessibilityText.ratingLabel(5), "rated 5 of 5 stars")
    }

    func testPhotoLabelPrefersCaption() {
        XCTAssertEqual(
            AccessibilityText.photoLabel(caption: "Front pocket detail", index: 1, count: 4),
            "Front pocket detail"
        )
        XCTAssertEqual(
            AccessibilityText.photoLabel(caption: nil, index: 1, count: 4),
            "Photo 2 of 4"
        )
        XCTAssertEqual(
            AccessibilityText.photoLabel(caption: "  ", index: 0, count: 1),
            "Photo 1 of 1"
        )
    }
}
