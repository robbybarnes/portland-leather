import XCTest
import SwiftData
import UIKit
@testable import Leatherfolio

@MainActor
final class ItemDeletionTests: XCTestCase {

    private enum ForcedDeleteError: Error { case expected }

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

    private func makeTestJPEGData() throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: 800, height: 600), format: format)
        let image = renderer.image { context in
            UIColor.brown.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 800, height: 600))
        }
        return try XCTUnwrap(image.jpegData(compressionQuality: 0.9))
    }

    func testDeleteCascadesPhotosAndRemovesThumbnails() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ItemDeletionTests-\(UUID().uuidString)",
                                    isDirectory: true)
        let store = ImageStore(directory: tempDirectory)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        // Item with one photo whose thumbnail is materialized on disk.
        let item = Item()
        item.name = "Coldbrew Crossbody"
        let photo = Photo()
        photo.imageData = try makeTestJPEGData()
        photo.isPrimary = true
        photo.item = item
        context.insert(item)
        context.insert(photo)
        try context.save()
        _ = await store.thumbnail(for: photo.id, imageData: photo.imageData)
        let thumbnailURL = store.thumbnailFileURL(for: photo.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: thumbnailURL.path))

        try await item.deleteWithCleanup(in: context, imageStore: store)

        XCTAssertEqual(try context.fetch(FetchDescriptor<Item>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Photo>()).count, 0,
                       "cascade rule must delete photos with the item")
        XCTAssertFalse(FileManager.default.fileExists(atPath: thumbnailURL.path),
                       "delete must also purge the disk thumbnail")
    }

    func testDeleteItemWithoutPhotosJustDeletes() async throws {
        let item = Item()
        item.name = "No photos"
        context.insert(item)
        try context.save()

        try await item.deleteWithCleanup(in: context)

        XCTAssertEqual(try context.fetch(FetchDescriptor<Item>()).count, 0)
    }

    func testFailedDeleteRollsBackAndPreservesItemPhotosAndThumbnail() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ItemDeletionTests-\(UUID().uuidString)",
                                    isDirectory: true)
        let store = ImageStore(directory: tempDirectory)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let item = Item()
        item.name = "Keep me"
        let photo = Photo()
        photo.imageData = try makeTestJPEGData()
        photo.isPrimary = true
        photo.item = item
        context.insert(item)
        context.insert(photo)
        try context.save()
        _ = await store.thumbnail(for: photo.id) { photo.imageData }
        let thumbnailURL = store.thumbnailFileURL(for: photo.id)

        do {
            try await item.deleteWithCleanup(
                in: context,
                imageStore: store,
                saveOperation: { context in
                    context.processPendingChanges()
                    throw ForcedDeleteError.expected
                })
            XCTFail("Expected deterministic delete failure")
        } catch ForcedDeleteError.expected {}

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Item>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Photo>()), 1)
        XCTAssertEqual(item.photos?.map(\.id), [photo.id])
        XCTAssertEqual(photo.item?.id, item.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: thumbnailURL.path))
        XCTAssertFalse(context.hasChanges)
    }

    func testDeletionControllerReportsFailureAndDoesNotRequestDismissal() async throws {
        let item = Item()
        item.name = "Still here"
        context.insert(item)
        try context.save()
        let controller = ItemDeletionController()

        let shouldDismiss = await controller.delete(
            item,
            in: context,
            saveOperation: { context in
                context.processPendingChanges()
                throw ForcedDeleteError.expected
            })

        XCTAssertFalse(shouldDismiss)
        XCTAssertNotNil(controller.errorMessage)
        XCTAssertFalse(controller.isDeleting)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Item>()), 1)
    }
}
