import UIKit
import ImageIO

/// Thumbnails cached as ~400px JPEGs in Caches/thumbnails/<photo-uuid>.jpg.
/// SwiftData source bytes are requested on the main actor only after both
/// memory and disk caches miss. All cache-file and ImageIO work is isolated
/// to a non-main actor.
final class ImageStore: @unchecked Sendable {
    static let shared = ImageStore()

    static let thumbnailMaxDimension: CGFloat = 400
    static let storedOriginalMaxDimension: CGFloat = 2_048
    static let detailMaxDimension: CGFloat = 1_200

    private let worker: ImageStoreWorker
    private let directory: URL
    private let originalPreparer: (@Sendable (Data) async -> Data?)?

    /// `executionObserver` is a dependency/execution seam used to verify that
    /// disk I/O and ImageIO work execute outside the main actor.
    init(
        directory: URL? = nil,
        executionObserver: @escaping @Sendable () -> Void = {},
        originalPreparer: (@Sendable (Data) async -> Data?)? = nil
    ) {
        self.directory = directory ?? FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("thumbnails", isDirectory: true)
        worker = ImageStoreWorker(
            directory: self.directory,
            executionObserver: executionObserver)
        self.originalPreparer = originalPreparer
    }

    func thumbnailFileURL(for photoID: UUID) -> URL {
        directory.appendingPathComponent("\(photoID.uuidString).jpg")
    }

    /// Memory cache -> disk cache -> request SwiftData source bytes -> decode.
    /// The autoclosure-like source accessor is deliberately evaluated only
    /// after the cache lookup, preventing collection rows from faulting large
    /// external-storage blobs when a thumbnail is already cached.
    @MainActor
    func thumbnail(
        for photoID: UUID,
        sourceData: () -> Data?
    ) async -> UIImage? {
        if let cached = await worker.cachedThumbnail(for: photoID) {
            return cached
        }
        guard let data = sourceData() else { return nil }
        return await worker.makeThumbnail(for: photoID, sourceData: data)
    }

    /// Compatibility for non-model callers. Collection views must use the
    /// cached-first source accessor above so source data is evaluated lazily.
    @MainActor
    func thumbnail(for photoID: UUID, imageData: Data?) async -> UIImage? {
        await thumbnail(for: photoID) { imageData }
    }

    /// Bounded ImageIO decode for detail and editor previews.
    func displayImage(
        from data: Data,
        maxDimension: CGFloat = ImageStore.detailMaxDimension
    ) async -> UIImage? {
        await worker.displayImage(from: data, maxDimension: maxDimension)
    }

    /// Downsamples an imported original before any SwiftData transaction.
    func prepareOriginal(from data: Data) async -> Data? {
        if let originalPreparer {
            return await originalPreparer(data)
        }
        return await downsampledJPEG(
            from: data, maxDimension: ImageStore.storedOriginalMaxDimension)
    }

    func downsampledJPEG(from data: Data, maxDimension: CGFloat) async -> Data? {
        await worker.downsampledJPEG(from: data, maxDimension: maxDimension)
    }

    /// Async cache removal used by transactional item/photo cleanup paths.
    func removeThumbnail(for photoID: UUID) async {
        await worker.removeThumbnail(for: photoID)
    }

    fileprivate static func makeDownsampledJPEG(
        from data: Data,
        maxDimension: CGFloat
    ) -> Data? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
            source, 0, thumbnailOptions) else {
            return nil
        }
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.8)
    }
}

private actor ImageStoreWorker {
    private let memoryCache = NSCache<NSString, UIImage>()
    private let directory: URL
    private let executionObserver: @Sendable () -> Void

    init(directory: URL, executionObserver: @escaping @Sendable () -> Void) {
        self.directory = directory
        self.executionObserver = executionObserver
    }

    func cachedThumbnail(for photoID: UUID) -> UIImage? {
        executionObserver()
        let key = photoID.uuidString as NSString
        if let cached = memoryCache.object(forKey: key) {
            return cached
        }
        let fileURL = thumbnailFileURL(for: photoID)
        guard let diskData = try? Data(contentsOf: fileURL),
              let image = UIImage(data: diskData) else {
            return nil
        }
        memoryCache.setObject(image, forKey: key)
        return image
    }

    func makeThumbnail(for photoID: UUID, sourceData: Data) -> UIImage? {
        executionObserver()
        guard let jpegData = ImageStore.makeDownsampledJPEG(
            from: sourceData,
            maxDimension: ImageStore.thumbnailMaxDimension),
              let image = UIImage(data: jpegData) else {
            return nil
        }
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            try jpegData.write(to: thumbnailFileURL(for: photoID), options: .atomic)
        } catch {
            // A disk-cache failure degrades to the memory cache. The caller's
            // original/photo remains valid and visible for this process.
        }
        memoryCache.setObject(image, forKey: photoID.uuidString as NSString)
        return image
    }

    func displayImage(from data: Data, maxDimension: CGFloat) -> UIImage? {
        executionObserver()
        guard let jpegData = ImageStore.makeDownsampledJPEG(
            from: data, maxDimension: maxDimension) else {
            return nil
        }
        return UIImage(data: jpegData)
    }

    func downsampledJPEG(from data: Data, maxDimension: CGFloat) -> Data? {
        executionObserver()
        return ImageStore.makeDownsampledJPEG(
            from: data, maxDimension: maxDimension)
    }

    func removeThumbnail(for photoID: UUID) {
        executionObserver()
        memoryCache.removeObject(forKey: photoID.uuidString as NSString)
        try? FileManager.default.removeItem(at: thumbnailFileURL(for: photoID))
    }

    private func thumbnailFileURL(for photoID: UUID) -> URL {
        directory.appendingPathComponent("\(photoID.uuidString).jpg")
    }
}
