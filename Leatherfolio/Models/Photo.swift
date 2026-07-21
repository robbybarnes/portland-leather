import SwiftData
import Foundation

@Model
final class Photo {
    var id: UUID = UUID()
    @Attribute(.externalStorage) var imageData: Data?
    var caption: String?
    var isPrimary: Bool = false
    var createdAt: Date = Date.now
    var item: Item?
    init() {}
}
