import XCTest
import SwiftData
import UIKit
@testable import Leatherfolio

@MainActor
final class AddEditItemModelTests: XCTestCase {

    private enum ForcedSaveError: Error {
        case expected
    }

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

    /// 2000x1000 solid-color JPEG at scale 1 (same shape as a picked photo).
    private func makeTestJPEGData() throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: 2_000, height: 1_000), format: format)
        let image = renderer.image { context in
            UIColor.brown.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2_000, height: 1_000))
        }
        return try XCTUnwrap(image.jpegData(compressionQuality: 0.9))
    }

    func testSaveWithNameOnlyProducesValidItem() async throws {
        let model = AddEditItemModel(item: nil)
        model.name = "  Honey Tote  "

        let item = try await model.save(in: context)

        XCTAssertEqual(item.name, "Honey Tote")
        XCTAssertEqual(item.category, .other)
        XCTAssertNil(item.size)
        XCTAssertNil(item.color)
        XCTAssertNil(item.myCost)
        XCTAssertNil(item.dateAcquired)
        XCTAssertNil(item.notes)
        XCTAssertTrue((item.photos ?? []).isEmpty)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Item>()).count, 1)
    }

    func testCanSaveRequiresNonBlankName() throws {
        let model = AddEditItemModel(item: nil)
        XCTAssertFalse(model.canSave)
        model.name = "   "
        XCTAssertFalse(model.canSave)
        model.name = "Wallet"
        XCTAssertTrue(model.canSave)
    }

    func testSaveParsesDecimalCurrencyFields() async throws {
        let model = AddEditItemModel(item: nil)
        model.name = "Wallet"
        model.myCostText = "125.50"
        model.estimatedValueText = "180"

        let item = try await model.save(in: context)

        XCTAssertEqual(item.myCost, Decimal(string: "125.50", locale: .current))
        XCTAssertEqual(item.estimatedValue, 180)
        XCTAssertEqual(item.valueDelta, Decimal(string: "54.50", locale: .current))
        XCTAssertNil(item.retailCost)
    }

    func testDecimalHelpersRoundTripGermanLocale() throws {
        let german = Locale(identifier: "de_DE")
        let original = try XCTUnwrap(Decimal(string: "1234.56", locale: Locale(identifier: "en_US_POSIX")))

        let text = DecimalParsing.text(from: original, locale: german)

        XCTAssertEqual(text, "1234,56")
        XCTAssertEqual(DecimalParsing.decimal(from: text, locale: german), original)
    }

    func testUntouchedGermanLocaleEditPreservesDecimalValues() async throws {
        let german = Locale(identifier: "de_DE")
        let item = Item()
        item.name = "Wallet"
        item.myCost = Decimal(string: "1234.56", locale: Locale(identifier: "en_US_POSIX"))
        item.retailCost = Decimal(string: "99.95", locale: Locale(identifier: "en_US_POSIX"))
        item.estimatedValue = Decimal(string: "1500.01", locale: Locale(identifier: "en_US_POSIX"))
        context.insert(item)
        try context.save()

        let model = AddEditItemModel(item: item, locale: german)
        XCTAssertEqual(model.myCostText, "1234,56")
        XCTAssertEqual(model.retailCostText, "99,95")
        XCTAssertEqual(model.estimatedValueText, "1500,01")

        _ = try await model.save(in: context)

        XCTAssertEqual(item.myCost, Decimal(string: "1234.56", locale: Locale(identifier: "en_US_POSIX")))
        XCTAssertEqual(item.retailCost, Decimal(string: "99.95", locale: Locale(identifier: "en_US_POSIX")))
        XCTAssertEqual(item.estimatedValue,
                       Decimal(string: "1500.01", locale: Locale(identifier: "en_US_POSIX")))
    }

    func testSaveAttachesDownsampledPrimaryPhoto() async throws {
        let model = AddEditItemModel(item: nil)
        model.name = "Belt Bag"
        model.newPhotoDatas = [try makeTestJPEGData()]

        let item = try await model.save(in: context)

        XCTAssertEqual(item.photos?.count, 1)
        let photo = try XCTUnwrap(item.primaryPhoto)
        XCTAssertTrue(photo.isPrimary, "first photo becomes primary")
        let data = try XCTUnwrap(photo.imageData, "externalStorage data must be set")
        let image = try XCTUnwrap(UIImage(data: data))
        XCTAssertLessThanOrEqual(max(image.size.width, image.size.height), 2_048,
                                 "originals are stored downsampled to 2048")
    }

    func testUndecodablePhotoIsSkippedButItemStillSaves() async throws {
        let model = AddEditItemModel(item: nil)
        model.name = "Cardholder"
        model.newPhotoDatas = [Data([0x00, 0x01, 0x02])]

        let item = try await model.save(in: context)

        XCTAssertTrue((item.photos ?? []).isEmpty,
                      "bad image data must not block the item save")
        XCTAssertEqual(try context.fetch(FetchDescriptor<Item>()).count, 1)
    }

    func testEditingExistingItemUpdatesInPlace() async throws {
        let create = AddEditItemModel(item: nil)
        create.name = "Original"
        let item = try await create.save(in: context)
        let firstUpdatedAt = item.updatedAt

        let edit = AddEditItemModel(item: item)
        XCTAssertTrue(edit.isEditing)
        XCTAssertEqual(edit.name, "Original")
        edit.name = "Renamed"
        edit.rating = 4
        edit.isUnicorn = true
        let saved = try await edit.save(in: context)

        XCTAssertEqual(saved.id, item.id)
        XCTAssertEqual(saved.name, "Renamed")
        XCTAssertEqual(saved.rating, 4)
        XCTAssertTrue(saved.isUnicorn)
        XCTAssertGreaterThanOrEqual(saved.updatedAt, firstUpdatedAt)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Item>()).count, 1,
                       "edit must not create a second item")
    }

    func testSecondPhotoDoesNotStealPrimary() async throws {
        let create = AddEditItemModel(item: nil)
        create.name = "Tote"
        create.newPhotoDatas = [try makeTestJPEGData()]
        let item = try await create.save(in: context)
        let originalPrimaryID = try XCTUnwrap(item.primaryPhoto?.id)

        let edit = AddEditItemModel(item: item)
        edit.newPhotoDatas = [try makeTestJPEGData()]
        _ = try await edit.save(in: context)

        XCTAssertEqual(item.photos?.count, 2)
        XCTAssertEqual(item.primaryPhoto?.id, originalPrimaryID)
        XCTAssertEqual(item.photos?.filter(\.isPrimary).count, 1)
    }

    func testFailedAddRollsBackPendingObjectsAndKeepsInputsForRetry() async throws {
        let photoData = try makeTestJPEGData()
        let model = AddEditItemModel(item: nil)
        model.name = "Retry Tote"
        model.color = "Honey"
        model.newPhotoDatas = [photoData]

        do {
            _ = try await model.save(in: context, saveOperation: forceSaveFailure)
            XCTFail("Expected deterministic save failure")
        } catch ForcedSaveError.expected {}
        XCTAssertEqual(model.name, "Retry Tote")
        XCTAssertEqual(model.color, "Honey")
        XCTAssertEqual(model.newPhotoDatas, [photoData])
        XCTAssertFalse(context.hasChanges)
        XCTAssertTrue(context.insertedModelsArray.isEmpty)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Item>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Photo>()), 0,
                       "A failed add must not leave an orphaned Photo")

        do {
            _ = try await model.save(in: context, saveOperation: forceSaveFailure)
            XCTFail("A second tap must not accumulate another pending Item")
        } catch ForcedSaveError.expected {}
        XCTAssertEqual(model.newPhotoDatas, [photoData],
                       "Queued photo input must survive every failed attempt")
        XCTAssertFalse(context.hasChanges)
        XCTAssertTrue(context.insertedModelsArray.isEmpty)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Item>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Photo>()), 0,
                       "Repeated failures must not accumulate orphaned Photos")

        let saved = try await model.save(in: context)
        let items = try context.fetch(FetchDescriptor<Item>())
        let photos = try context.fetch(FetchDescriptor<Photo>())
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(photos.count, 1)
        XCTAssertEqual(saved.name, "Retry Tote")
        XCTAssertEqual(saved.color, "Honey")
        XCTAssertEqual(saved.photos?.count, 1)
        let photo = try XCTUnwrap(saved.photos?.first)
        XCTAssertEqual(photo.id, photos.first?.id)
        XCTAssertEqual(photo.item?.id, saved.id,
                       "The Photo inverse must point to the saved Item")
        XCTAssertTrue(photo.isPrimary)
        XCTAssertEqual(saved.photos?.filter(\.isPrimary).count, 1)
        XCTAssertEqual(saved.primaryPhoto?.id, photo.id)
        XCTAssertTrue(model.newPhotoDatas.isEmpty)
    }

    func testFailedEditRollsBackItemAndKeepsEditedFormAndPhotoInput() async throws {
        let photoData = try makeTestJPEGData()
        let item = Item()
        item.name = "Original Name"
        item.rating = 2
        let originalPhoto = Photo()
        originalPhoto.imageData = photoData
        originalPhoto.isPrimary = true
        originalPhoto.item = item
        context.insert(item)
        context.insert(originalPhoto)
        try context.save()
        XCTAssertEqual(item.photos?.map(\.id), [originalPhoto.id])

        let model = AddEditItemModel(item: item)
        model.name = "Edited Name"
        model.rating = 5
        model.newPhotoDatas = [photoData]

        do {
            _ = try await model.save(in: context, saveOperation: forceSaveFailure)
            XCTFail("Expected deterministic save failure")
        } catch ForcedSaveError.expected {}
        XCTAssertEqual(item.name, "Original Name")
        XCTAssertEqual(item.rating, 2)
        XCTAssertEqual(item.photos?.map(\.id), [originalPhoto.id],
                       "A failed edit must restore the prior photo relationship")
        XCTAssertEqual(originalPhoto.item?.id, item.id)
        XCTAssertEqual(item.primaryPhoto?.id, originalPhoto.id)
        XCTAssertFalse(context.hasChanges)
        XCTAssertTrue(context.insertedModelsArray.isEmpty)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Item>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Photo>()), 1,
                       "The attempted photo must not survive as an orphan")
        XCTAssertEqual(model.name, "Edited Name")
        XCTAssertEqual(model.rating, 5)
        XCTAssertEqual(model.newPhotoDatas, [photoData])

        let saved = try await model.save(in: context)
        let items = try context.fetch(FetchDescriptor<Item>())
        let photos = try context.fetch(FetchDescriptor<Photo>())
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(photos.count, 2)
        XCTAssertEqual(saved.photos?.count, 2)
        XCTAssertEqual(originalPhoto.item?.id, saved.id)
        let addedPhoto = try XCTUnwrap(photos.first { $0.id != originalPhoto.id })
        XCTAssertEqual(addedPhoto.item?.id, saved.id)
        XCTAssertEqual(saved.photos?.filter(\.isPrimary).count, 1)
        XCTAssertEqual(saved.primaryPhoto?.id, originalPhoto.id,
                       "Retry must preserve the existing primary Photo")
        XCTAssertTrue(model.newPhotoDatas.isEmpty)
    }

    private func forceSaveFailure(_ context: ModelContext) throws {
        // Match ModelContext.save(): register mutations before surfacing the
        // deterministic failure so rollback exercises real tracked changes.
        context.processPendingChanges()
        throw ForcedSaveError.expected
    }
}
