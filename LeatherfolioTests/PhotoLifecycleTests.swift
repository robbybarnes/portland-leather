import XCTest
import SwiftData
import UIKit
@testable import Leatherfolio

@MainActor
final class PhotoLifecycleTests: XCTestCase {
    private enum TestError: Error { case expected }

    private actor ImportGate {
        private var continuation: CheckedContinuation<Void, Never>?
        private var isOpen = false

        func wait() async {
            if isOpen { return }
            await withCheckedContinuation { continuation = $0 }
        }

        func open() {
            isOpen = true
            continuation?.resume()
            continuation = nil
        }
    }

    private final class ExecutionRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [Bool] = []

        func record() {
            lock.lock()
            values.append(Thread.isMainThread)
            lock.unlock()
        }

        var observedMainThread: Bool {
            lock.lock()
            defer { lock.unlock() }
            return values.contains(true)
        }

        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return values.count
        }
    }

    private func makeStore() throws -> (ModelContainer, ModelContext) {
        let container = try AppModelContainer.make(inMemory: true)
        return (container, container.mainContext)
    }

    private func makeTestJPEGData(
        width: CGFloat = 2_400,
        height: CGFloat = 1_200
    ) throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: width, height: height), format: format)
        let image = renderer.image { context in
            UIColor.brown.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        return try XCTUnwrap(image.jpegData(compressionQuality: 0.9))
    }

    private func makeStoredItem(in context: ModelContext) throws -> (Item, Photo, Photo) {
        let item = Item()
        item.name = "Tote"
        let primary = Photo()
        primary.imageData = try makeTestJPEGData()
        primary.caption = "Front"
        primary.isPrimary = true
        primary.item = item
        let second = Photo()
        second.imageData = try makeTestJPEGData(width: 1_800, height: 900)
        second.caption = "Back"
        second.item = item
        context.insert(item)
        context.insert(primary)
        context.insert(second)
        try context.save()
        return (item, primary, second)
    }

    func testImportReportsFailuresWhilePreservingSuccessfulPhotosAndFormInput() async throws {
        let model = AddEditItemModel(item: nil)
        model.name = "Keep this name"
        let validData = try makeTestJPEGData()
        let loaders: [PhotoDataLoader] = [
            { validData },
            { throw TestError.expected },
            { Data([0x00, 0x01, 0x02]) },
        ]

        await model.importPhotos(using: loaders)

        XCTAssertEqual(model.name, "Keep this name")
        XCTAssertEqual(model.queuedPhotos.count, 1)
        XCTAssertNotNil(model.photoImportErrorMessage)
        XCTAssertFalse(model.isImporting)
    }

    func testImportDisablesSaveAndSaveCannotRaceIt() async throws {
        let (container, context) = try makeStore()
        defer { withExtendedLifetime(container) {} }
        let model = AddEditItemModel(item: nil)
        model.name = "Tote"
        let gate = ImportGate()
        let validData = try makeTestJPEGData()

        let importTask = Task {
            await model.importPhotos(using: [{
                await gate.wait()
                return validData
            }])
        }
        while !model.isImporting { await Task.yield() }

        XCTAssertTrue(model.isBusy)
        XCTAssertFalse(model.canSave)
        do {
            _ = try await model.save(in: context)
            XCTFail("Save must not start while photo transfer is active")
        } catch {
            XCTAssertEqual(error as? PhotoWorkflowError, .busy)
        }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Item>()), 0)

        await gate.open()
        await importTask.value
        XCTAssertFalse(model.isBusy)
        XCTAssertTrue(model.canSave)
    }

    func testQueuedPhotoCanBeRemovedAndChosenAsPrimary() throws {
        let model = AddEditItemModel(item: nil)
        let firstData = try makeTestJPEGData()
        let secondData = try makeTestJPEGData(width: 1_600, height: 800)
        model.queuePhoto(firstData)
        model.queuePhoto(secondData)
        let firstID = try XCTUnwrap(model.queuedPhotos.first?.id)
        let secondID = try XCTUnwrap(model.queuedPhotos.last?.id)

        model.choosePrimary(photoID: secondID)
        model.removeQueuedPhoto(id: firstID)

        XCTAssertEqual(model.queuedPhotos.map(\.id), [secondID])
        XCTAssertEqual(model.primaryPhotoID, secondID)
    }

    func testExistingPhotoChangesCommitTogetherAndCleanRemovedCacheAfterSave() async throws {
        let (container, context) = try makeStore()
        defer { withExtendedLifetime(container) {} }
        let (item, primary, second) = try makeStoredItem(in: context)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoLifecycleTests-\(UUID().uuidString)", isDirectory: true)
        let store = ImageStore(directory: directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = await store.thumbnail(for: primary.id) { primary.imageData }
        let removedCacheURL = store.thumbnailFileURL(for: primary.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: removedCacheURL.path))
        let model = AddEditItemModel(item: item)

        model.removeExistingPhoto(id: primary.id)
        model.updateCaption("Edited back", for: second.id)
        model.choosePrimary(photoID: second.id)
        _ = try await model.save(in: context, imageStore: store)

        XCTAssertEqual(item.photos?.map(\.id), [second.id])
        XCTAssertEqual(second.caption, "Edited back")
        XCTAssertTrue(second.isPrimary)
        XCTAssertFalse(FileManager.default.fileExists(atPath: removedCacheURL.path))
    }

    func testFailedPhotoEditRollsBackModelsKeepsPendingEditsAndCache() async throws {
        let (container, context) = try makeStore()
        defer { withExtendedLifetime(container) {} }
        let (item, primary, second) = try makeStoredItem(in: context)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoLifecycleTests-\(UUID().uuidString)", isDirectory: true)
        let store = ImageStore(directory: directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = await store.thumbnail(for: primary.id) { primary.imageData }
        let cacheURL = store.thumbnailFileURL(for: primary.id)
        let queuedData = try makeTestJPEGData(width: 1_200, height: 600)
        let model = AddEditItemModel(item: item)
        model.queuePhoto(queuedData)
        model.removeExistingPhoto(id: primary.id)
        model.updateCaption("Pending caption", for: second.id)
        model.choosePrimary(photoID: second.id)

        do {
            _ = try await model.save(
                in: context,
                imageStore: store,
                saveOperation: { context in
                    context.processPendingChanges()
                    throw TestError.expected
                })
            XCTFail("Expected deterministic save failure")
        } catch TestError.expected {}

        XCTAssertEqual(Set(item.photos?.map(\.id) ?? []), Set([primary.id, second.id]))
        XCTAssertEqual(primary.caption, "Front")
        XCTAssertTrue(primary.isPrimary)
        XCTAssertEqual(second.caption, "Back")
        XCTAssertFalse(second.isPrimary)
        XCTAssertTrue(model.isExistingPhotoRemoved(primary.id))
        XCTAssertEqual(model.caption(for: second.id), "Pending caption")
        XCTAssertEqual(model.queuedPhotos.map(\.data), [queuedData])
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheURL.path))
        XCTAssertFalse(context.hasChanges)
    }

    func testSavePreprocessingUsesOffMainImageIOAndStores2048Maximum() async throws {
        let (container, context) = try makeStore()
        defer { withExtendedLifetime(container) {} }
        let recorder = ExecutionRecorder()
        let store = ImageStore(
            directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("PhotoLifecycleTests-\(UUID().uuidString)"),
            executionObserver: { recorder.record() })
        let model = AddEditItemModel(item: nil)
        model.name = "Tote"
        model.queuePhoto(try makeTestJPEGData(width: 3_000, height: 1_500))

        let item = try await model.save(in: context, imageStore: store)

        let storedData = try XCTUnwrap(item.primaryPhoto?.imageData)
        let storedImage = try XCTUnwrap(UIImage(data: storedData))
        XCTAssertLessThanOrEqual(
            max(storedImage.size.width * storedImage.scale,
                storedImage.size.height * storedImage.scale), 2_048)
        XCTAssertGreaterThan(recorder.count, 0)
        XCTAssertFalse(recorder.observedMainThread)
    }
}
