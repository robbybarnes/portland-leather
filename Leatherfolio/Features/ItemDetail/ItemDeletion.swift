import Foundation
import SwiftData

extension Item {
    /// The one delete path in the app: removes the item, its cascade of
    /// Photos (SwiftData .cascade rule on Item.photos), and every cached
    /// thumbnail (memory + Caches/thumbnails/<uuid>.jpg) so thumbnails
    /// never leak after deletion.
    @MainActor
    func deleteWithCleanup(in context: ModelContext,
                           imageStore: ImageStore = .shared) throws {
        for photo in photos ?? [] {
            imageStore.deleteThumbnail(for: photo.id)
        }
        context.delete(self)
        try context.save()
    }
}
