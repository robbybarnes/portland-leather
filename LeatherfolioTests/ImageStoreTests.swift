import XCTest
import UIKit
@testable import Leatherfolio

@MainActor
final class ImageStoreTests: XCTestCase {

    private actor OperationGate {
        private let targetStage: ImageStore.OperationStage
        private var isSuspended = false
        private var suspensionWaiters: [CheckedContinuation<Void, Never>] = []
        private var releaseContinuation: CheckedContinuation<Void, Never>?

        init(targetStage: ImageStore.OperationStage) {
            self.targetStage = targetStage
        }

        func hook(_ stage: ImageStore.OperationStage) async {
            guard stage == targetStage else { return }
            isSuspended = true
            suspensionWaiters.forEach { $0.resume() }
            suspensionWaiters.removeAll()
            await withCheckedContinuation { continuation in
                releaseContinuation = continuation
            }
        }

        func waitUntilSuspended() async {
            guard !isSuspended else { return }
            await withCheckedContinuation { continuation in
                suspensionWaiters.append(continuation)
            }
        }

        func open() {
            releaseContinuation?.resume()
            releaseContinuation = nil
        }
    }

    private final class InvocationRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var invocationCount = 0

        func record() {
            lock.lock()
            invocationCount += 1
            lock.unlock()
        }

        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return invocationCount
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

    // nonisolated: XCTestCase's setUpWithError/tearDownWithError overrides are
    // nonisolated even in a @MainActor subclass; they mutate these on a single
    // thread before any test runs, so unsafe opt-out is sound and warning-free.
    private nonisolated(unsafe) var tempDirectory: URL!
    private nonisolated(unsafe) var store: ImageStore!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageStoreTests-\(UUID().uuidString)", isDirectory: true)
        store = ImageStore(directory: tempDirectory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    /// 2000x1000 solid-color JPEG rendered at scale 1 so pixel math is exact.
    private func makeTestJPEGData(width: CGFloat = 2_000, height: CGFloat = 1_000) throws -> Data {
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

    func testDownsampledJPEGCapsMaxDimensionAndKeepsAspect() async throws {
        let data = try makeTestJPEGData()
        let downsampled = await store.downsampledJPEG(from: data, maxDimension: 400)
        let result = try XCTUnwrap(downsampled)
        let image = try XCTUnwrap(UIImage(data: result))
        XCTAssertLessThanOrEqual(max(image.size.width, image.size.height), 400)
        XCTAssertEqual(image.size.width / image.size.height, 2.0, accuracy: 0.05,
                       "aspect ratio must be preserved")
    }

    func testThumbnailGeneratesCachesAndPersistsToDisk() async throws {
        let data = try makeTestJPEGData()
        let photoID = UUID()

        // await is hoisted out of XCTUnwrap: its autoclosure is not async.
        let generated = await store.thumbnail(for: photoID, imageData: data)
        let thumbnail = try XCTUnwrap(generated)
        XCTAssertLessThanOrEqual(
            max(thumbnail.size.width * thumbnail.scale,
                thumbnail.size.height * thumbnail.scale), 400)

        let fileURL = store.thumbnailFileURL(for: photoID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path),
                      "thumbnail JPEG must be cached on disk")

        // Second call must serve without any source data (disk/NSCache hit).
        let cached = await store.thumbnail(for: photoID, imageData: nil)
        XCTAssertNotNil(cached)
    }

    func testDeleteThumbnailRemovesFileAndCacheEntry() async throws {
        let data = try makeTestJPEGData()
        let photoID = UUID()
        _ = await store.thumbnail(for: photoID, imageData: data)
        let fileURL = store.thumbnailFileURL(for: photoID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        await store.removeThumbnail(for: photoID)

        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        let afterDelete = await store.thumbnail(for: photoID, imageData: nil)
        XCTAssertNil(afterDelete, "no cache layer may survive deleteThumbnail")
    }

    func testDownsampledJPEGReturnsNilForGarbageData() async {
        let result = await store.downsampledJPEG(
            from: Data([0x00, 0x01, 0x02]), maxDimension: 400)
        XCTAssertNil(result)
    }

    func testCachedFirstThumbnailDoesNotRequestSourceDataOnMemoryOrDiskHit() async throws {
        let data = try makeTestJPEGData()
        let photoID = UUID()
        let generated = await store.thumbnail(for: photoID) { data }
        XCTAssertNotNil(generated)

        var memorySourceRequested = false
        let memoryCached = await store.thumbnail(for: photoID) {
            memorySourceRequested = true
            return nil
        }
        XCTAssertNotNil(memoryCached)
        XCTAssertFalse(memorySourceRequested)

        let diskStore = ImageStore(directory: tempDirectory)
        var diskSourceRequested = false
        let diskCached = await diskStore.thumbnail(for: photoID) {
            diskSourceRequested = true
            return nil
        }
        XCTAssertNotNil(diskCached)
        XCTAssertFalse(diskSourceRequested)
    }

    func testCancelledCacheLookupDoesNotRequestSourceData() async {
        let gate = OperationGate(targetStage: .cacheLookup)
        let sourceRequests = InvocationRecorder()
        let photoID = UUID()
        let hookedStore = ImageStore(
            directory: tempDirectory,
            operationHook: { stage in await gate.hook(stage) })

        let task = Task { @MainActor in
            await hookedStore.thumbnail(for: photoID) {
                sourceRequests.record()
                return nil
            }
        }
        await gate.waitUntilSuspended()
        task.cancel()
        await gate.open()

        let result = await task.value
        XCTAssertNil(result)
        XCTAssertEqual(sourceRequests.count, 0)
    }

    func testCancelledThumbnailDecodeDoesNotPublishDiskOrMemoryCache() async throws {
        let gate = OperationGate(targetStage: .thumbnailDecode)
        let photoID = UUID()
        let data = try makeTestJPEGData()
        let hookedStore = ImageStore(
            directory: tempDirectory,
            operationHook: { stage in await gate.hook(stage) })

        let task = Task { @MainActor in
            await hookedStore.thumbnail(for: photoID) { data }
        }
        await gate.waitUntilSuspended()
        task.cancel()
        await gate.open()

        let result = await task.value
        XCTAssertNil(result)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: hookedStore.thumbnailFileURL(for: photoID).path))

        let cached = await hookedStore.thumbnail(for: photoID, imageData: nil)
        XCTAssertNil(cached)
    }

    func testImageIODiskCacheAndDeletionExecuteOffMain() async throws {
        let recorder = ExecutionRecorder()
        let observedStore = ImageStore(
            directory: tempDirectory,
            executionObserver: { recorder.record() })
        let data = try makeTestJPEGData()
        let photoID = UUID()

        let thumbnail = await observedStore.thumbnail(for: photoID) { data }
        XCTAssertNotNil(thumbnail)
        let displayImage = await observedStore.displayImage(from: data, maxDimension: 960)
        XCTAssertNotNil(displayImage)
        await observedStore.removeThumbnail(for: photoID)

        XCTAssertGreaterThanOrEqual(recorder.count, 3)
        XCTAssertFalse(recorder.observedMainThread)
    }

    func testDisplayImageUsesBoundedDecodeSize() async throws {
        let data = try makeTestJPEGData(width: 3_000, height: 1_500)

        let decoded = await store.displayImage(from: data, maxDimension: 960)
        let image = try XCTUnwrap(decoded)

        XCTAssertLessThanOrEqual(
            max(image.size.width * image.scale, image.size.height * image.scale), 960)
    }
}
