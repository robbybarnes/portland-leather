import UIKit
import ImageIO

/// Thumbnails cached as ~400px JPEGs in Caches/thumbnails/<photo-uuid>.jpg.
/// SwiftData source bytes are requested on the main actor only after both
/// memory and disk caches miss. All cache-file and ImageIO work is isolated
/// to a non-main actor.
final class ImageStore: @unchecked Sendable {
    enum OperationStage: Sendable, Equatable {
        case cacheLookup
        case thumbnailDecode
        case displayDecode
        case originalPreparation
    }

    static let shared = ImageStore()

    static let thumbnailMaxDimension: CGFloat = 400
    static let storedOriginalMaxDimension: CGFloat = 2_048
    static let detailMaxDimension: CGFloat = 1_200

    private let worker: ImageStoreWorker
    private let directory: URL
    private let operationHook: @Sendable (OperationStage) async -> Void
    private let originalPreparer: (@Sendable (Data) async -> Data?)?

    /// `executionObserver` is a dependency/execution seam used to verify that
    /// disk I/O and ImageIO work execute outside the main actor.
    init(
        directory: URL? = nil,
        executionObserver: @escaping @Sendable () -> Void = {},
        operationHook: @escaping @Sendable (OperationStage) async -> Void = { _ in },
        originalPreparer: (@Sendable (Data) async -> Data?)? = nil
    ) {
        self.directory = directory ?? FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("thumbnails", isDirectory: true)
        worker = ImageStoreWorker(
            directory: self.directory,
            executionObserver: executionObserver,
            operationHook: operationHook)
        self.operationHook = operationHook
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
        guard !Task.isCancelled else { return nil }
        let cached = await worker.cachedThumbnail(for: photoID)
        guard !Task.isCancelled else { return nil }
        if let cached {
            return cached
        }
        guard !Task.isCancelled else { return nil }
        guard let data = sourceData() else { return nil }
        guard !Task.isCancelled else { return nil }
        let thumbnail = await worker.makeThumbnail(for: photoID, sourceData: data)
        guard !Task.isCancelled else { return nil }
        return thumbnail
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
        guard !Task.isCancelled else { return nil }
        let image = await worker.displayImage(from: data, maxDimension: maxDimension)
        guard !Task.isCancelled else { return nil }
        return image
    }

    /// Downsamples an imported original before any SwiftData transaction.
    func prepareOriginal(from data: Data) async -> Data? {
        guard !Task.isCancelled else { return nil }
        await operationHook(.originalPreparation)
        guard !Task.isCancelled else { return nil }
        if let originalPreparer {
            let prepared = await originalPreparer(data)
            guard !Task.isCancelled else { return nil }
            return prepared
        }
        let prepared = await downsampledJPEG(
            from: data, maxDimension: ImageStore.storedOriginalMaxDimension)
        guard !Task.isCancelled else { return nil }
        return prepared
    }

    func downsampledJPEG(from data: Data, maxDimension: CGFloat) async -> Data? {
        guard !Task.isCancelled else { return nil }
        let jpegData = await worker.downsampledJPEG(from: data, maxDimension: maxDimension)
        guard !Task.isCancelled else { return nil }
        return jpegData
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
    private let operationHook: @Sendable (ImageStore.OperationStage) async -> Void

    init(
        directory: URL,
        executionObserver: @escaping @Sendable () -> Void,
        operationHook: @escaping @Sendable (ImageStore.OperationStage) async -> Void
    ) {
        self.directory = directory
        self.executionObserver = executionObserver
        self.operationHook = operationHook
    }

    func cachedThumbnail(for photoID: UUID) async -> UIImage? {
        guard !Task.isCancelled else { return nil }
        await operationHook(.cacheLookup)
        guard !Task.isCancelled else { return nil }
        executionObserver()
        let key = photoID.uuidString as NSString
        if let cached = memoryCache.object(forKey: key) {
            return Task.isCancelled ? nil : cached
        }
        let fileURL = thumbnailFileURL(for: photoID)
        guard let diskData = try? Data(contentsOf: fileURL),
              let image = UIImage(data: diskData) else {
            return nil
        }
        guard !Task.isCancelled else { return nil }
        memoryCache.setObject(image, forKey: key)
        guard !Task.isCancelled else {
            memoryCache.removeObject(forKey: key)
            return nil
        }
        return image
    }

    func makeThumbnail(for photoID: UUID, sourceData: Data) async -> UIImage? {
        guard !Task.isCancelled else { return nil }
        await operationHook(.thumbnailDecode)
        guard !Task.isCancelled else { return nil }
        executionObserver()
        guard let jpegData = ImageStore.makeDownsampledJPEG(
            from: sourceData,
            maxDimension: ImageStore.thumbnailMaxDimension),
              let image = UIImage(data: jpegData) else {
            return nil
        }
        guard !Task.isCancelled else { return nil }
        let fileURL = thumbnailFileURL(for: photoID)
        var wroteFile = false
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            guard !Task.isCancelled else { return nil }
            try jpegData.write(to: fileURL, options: .atomic)
            wroteFile = true
        } catch {
            // A disk-cache failure degrades to the memory cache. The caller's
            // original/photo remains valid and visible for this process.
        }
        guard !Task.isCancelled else {
            if wroteFile { try? FileManager.default.removeItem(at: fileURL) }
            return nil
        }
        let key = photoID.uuidString as NSString
        memoryCache.setObject(image, forKey: key)
        guard !Task.isCancelled else {
            memoryCache.removeObject(forKey: key)
            if wroteFile { try? FileManager.default.removeItem(at: fileURL) }
            return nil
        }
        return image
    }

    func displayImage(from data: Data, maxDimension: CGFloat) async -> UIImage? {
        guard !Task.isCancelled else { return nil }
        await operationHook(.displayDecode)
        guard !Task.isCancelled else { return nil }
        executionObserver()
        guard let jpegData = ImageStore.makeDownsampledJPEG(
            from: data, maxDimension: maxDimension) else {
            return nil
        }
        guard !Task.isCancelled else { return nil }
        let image = UIImage(data: jpegData)
        guard !Task.isCancelled else { return nil }
        return image
    }

    func downsampledJPEG(from data: Data, maxDimension: CGFloat) -> Data? {
        guard !Task.isCancelled else { return nil }
        executionObserver()
        let jpegData = ImageStore.makeDownsampledJPEG(
            from: data, maxDimension: maxDimension)
        guard !Task.isCancelled else { return nil }
        return jpegData
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
