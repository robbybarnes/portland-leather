import UIKit
import ImageIO

/// Thumbnails cached as ~400px JPEGs in Caches/thumbnails/<photo-uuid>.jpg.
/// Originals live in Photo.imageData (externalStorage). Detail views load
/// originals directly; every grid/list goes through thumbnail(for:).
///
/// `@unchecked Sendable`: both stored properties are immutable references to
/// types Apple documents as thread-safe (NSCache; FileManager.default).
final class ImageStore: @unchecked Sendable {
    static let shared = ImageStore()

    static let thumbnailMaxDimension: CGFloat = 400

    private let memoryCache = NSCache<NSString, UIImage>()
    private let directory: URL

    /// Pass a custom directory in tests; defaults to Caches/thumbnails.
    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: self.directory, withIntermediateDirectories: true)
    }

    func thumbnailFileURL(for photoID: UUID) -> URL {
        directory.appendingPathComponent("\(photoID.uuidString).jpg")
    }

    /// Memory cache → disk cache → generate-from-original, in that order.
    /// Returns nil only when no cached thumbnail exists and imageData is nil
    /// or undecodable.
    func thumbnail(for photoID: UUID, imageData: Data?) async -> UIImage? {
        let key = photoID.uuidString as NSString
        if let cached = memoryCache.object(forKey: key) {
            return cached
        }
        let fileURL = thumbnailFileURL(for: photoID)
        if let diskData = try? Data(contentsOf: fileURL),
           let image = UIImage(data: diskData) {
            memoryCache.setObject(image, forKey: key)
            return image
        }
        guard let imageData,
              let jpegData = downsampledJPEG(
                  from: imageData, maxDimension: Self.thumbnailMaxDimension),
              let image = UIImage(data: jpegData) else {
            return nil
        }
        try? jpegData.write(to: fileURL, options: .atomic)
        memoryCache.setObject(image, forKey: key)
        return image
    }

    func deleteThumbnail(for photoID: UUID) {
        memoryCache.removeObject(forKey: photoID.uuidString as NSString)
        try? FileManager.default.removeItem(at: thumbnailFileURL(for: photoID))
    }

    /// ImageIO downsampling: decodes at most maxDimension pixels on the long
    /// edge without ever inflating the full-size bitmap into memory. Used
    /// both for thumbnails (400) and for shrinking imports before storage
    /// (2048, see AddEditItemModel.save).
    func downsampledJPEG(from data: Data, maxDimension: CGFloat) -> Data? {
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
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            return nil
        }
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.8)
    }
}
