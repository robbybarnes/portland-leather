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

    func testPhotoEditorContextTrimsCaptionAndFallsBackToCombinedPosition() {
        XCTAssertEqual(
            AccessibilityText.photoEditorContext(
                caption: "  Front pocket detail \n",
                index: 0,
                count: 4),
            "Front pocket detail, Photo 1 of 4")
        XCTAssertEqual(
            AccessibilityText.photoEditorContext(
                caption: " \n ",
                index: 1,
                count: 4),
            "Photo 2 of 4")
    }

    func testQRLabelIdentifiesNamedAndUntitledItems() {
        XCTAssertEqual(
            AccessibilityText.qrLabel(itemName: "Willow Tote"),
            "QR label for Willow Tote"
        )
        XCTAssertEqual(
            AccessibilityText.qrLabel(itemName: ""),
            "QR label for Untitled item"
        )
    }

    func testPhotoEditorPrimaryActionDistinguishesCurrentAndMakePrimary() {
        let current = AccessibilityText.photoPrimaryAction(
            context: "Front pocket detail, Photo 1 of 4",
            isPrimary: true)
        XCTAssertEqual(
            current.label,
            "Front pocket detail, Photo 1 of 4, primary photo")
        XCTAssertEqual(current.value, "Current primary")
        XCTAssertEqual(current.hint, "This photo appears first.")

        let available = AccessibilityText.photoPrimaryAction(
            context: "Photo 2 of 4",
            isPrimary: false)
        XCTAssertEqual(available.label, "Make Photo 2 of 4 primary")
        XCTAssertEqual(available.value, "Not primary")
        XCTAssertEqual(available.hint, "Makes this photo appear first.")
    }

    func testPhotoEditorRemovalActionDistinguishesSavedAndNewPhotos() {
        let saved = AccessibilityText.photoRemovalAction(
            context: "Front pocket detail, Photo 1 of 4",
            isStored: true)
        XCTAssertEqual(
            saved.label,
            "Remove saved photo, Front pocket detail, Photo 1 of 4")
        XCTAssertEqual(saved.value, "Saved photo")
        XCTAssertEqual(saved.hint, "Removes this photo when you save the item.")

        let newlyAdded = AccessibilityText.photoRemovalAction(
            context: "Photo 2 of 4",
            isStored: false)
        XCTAssertEqual(newlyAdded.label, "Remove new photo, Photo 2 of 4")
        XCTAssertEqual(newlyAdded.value, "New photo")
        XCTAssertEqual(newlyAdded.hint, "Removes this photo before it is saved.")
    }

    func testPhotoEditorActionsAreDistinctAcrossBlankCaptionPhotos() {
        let firstContext = AccessibilityText.photoEditorContext(
            caption: nil,
            index: 0,
            count: 2)
        let secondContext = AccessibilityText.photoEditorContext(
            caption: " ",
            index: 1,
            count: 2)

        let firstPrimary = AccessibilityText.photoPrimaryAction(
            context: firstContext,
            isPrimary: false)
        let secondPrimary = AccessibilityText.photoPrimaryAction(
            context: secondContext,
            isPrimary: false)
        let firstRemoval = AccessibilityText.photoRemovalAction(
            context: firstContext,
            isStored: true)
        let secondRemoval = AccessibilityText.photoRemovalAction(
            context: secondContext,
            isStored: false)

        XCTAssertEqual(firstPrimary.label, "Make Photo 1 of 2 primary")
        XCTAssertEqual(secondPrimary.label, "Make Photo 2 of 2 primary")
        XCTAssertNotEqual(firstPrimary.label, secondPrimary.label)
        XCTAssertEqual(firstRemoval.label, "Remove saved photo, Photo 1 of 2")
        XCTAssertEqual(secondRemoval.label, "Remove new photo, Photo 2 of 2")
        XCTAssertNotEqual(firstRemoval.label, secondRemoval.label)
    }

    func testDuplicateCaptionSavedAndQueuedActionsRetainDistinctOrdinals() {
        let savedContext = AccessibilityText.photoEditorContext(
            caption: "  Front pocket detail ",
            index: 0,
            count: 2)
        let queuedContext = AccessibilityText.photoEditorContext(
            caption: "Front pocket detail",
            index: 1,
            count: 2)

        let savedPrimary = AccessibilityText.photoPrimaryAction(
            context: savedContext,
            isPrimary: false)
        let queuedPrimary = AccessibilityText.photoPrimaryAction(
            context: queuedContext,
            isPrimary: false)
        let savedRemoval = AccessibilityText.photoRemovalAction(
            context: savedContext,
            isStored: true)
        let queuedRemoval = AccessibilityText.photoRemovalAction(
            context: queuedContext,
            isStored: false)

        XCTAssertEqual(savedContext, "Front pocket detail, Photo 1 of 2")
        XCTAssertEqual(queuedContext, "Front pocket detail, Photo 2 of 2")
        XCTAssertNotEqual(savedPrimary.label, queuedPrimary.label)
        XCTAssertNotEqual(savedRemoval.label, queuedRemoval.label)
    }
}
