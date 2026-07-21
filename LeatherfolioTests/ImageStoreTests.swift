import XCTest
import UIKit
@testable import Leatherfolio

@MainActor
final class ImageStoreTests: XCTestCase {

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

    func testDownsampledJPEGCapsMaxDimensionAndKeepsAspect() throws {
        let data = try makeTestJPEGData()
        let result = try XCTUnwrap(store.downsampledJPEG(from: data, maxDimension: 400))
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

        store.deleteThumbnail(for: photoID)

        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        let afterDelete = await store.thumbnail(for: photoID, imageData: nil)
        XCTAssertNil(afterDelete, "no cache layer may survive deleteThumbnail")
    }

    func testDownsampledJPEGReturnsNilForGarbageData() {
        XCTAssertNil(store.downsampledJPEG(from: Data([0x00, 0x01, 0x02]), maxDimension: 400))
    }
}
