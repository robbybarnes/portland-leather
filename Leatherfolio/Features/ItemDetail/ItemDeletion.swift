import Foundation
import Observation
import SwiftData

extension Item {
    /// Deletes the SwiftData graph first. Cache files are recoverable derived
    /// data and are removed only after the persistent save succeeds.
    @MainActor
    func deleteWithCleanup(
        in context: ModelContext,
        imageStore: ImageStore = .shared,
        saveOperation: (ModelContext) throws -> Void = { try $0.save() }
    ) async throws {
        let photoIDs = (photos ?? []).map(\.id)
        context.delete(self)
        do {
            try saveOperation(context)
        } catch {
            context.processPendingChanges()
            context.rollback()
            throw error
        }
        for photoID in photoIDs {
            await imageStore.removeThumbnail(for: photoID)
        }
    }
}

@MainActor
@Observable
final class ItemDeletionController {
    private(set) var isDeleting = false
    var errorMessage: String?

    /// Returns true only when the detail view may safely dismiss.
    func delete(
        _ item: Item,
        in context: ModelContext,
        imageStore: ImageStore = .shared,
        saveOperation: (ModelContext) throws -> Void = { try $0.save() }
    ) async -> Bool {
        guard !isDeleting else { return false }
        isDeleting = true
        errorMessage = nil
        defer { isDeleting = false }
        do {
            try await item.deleteWithCleanup(
                in: context,
                imageStore: imageStore,
                saveOperation: saveOperation)
            return true
        } catch {
            errorMessage = "The item couldn't be deleted. Nothing was removed; please try again."
            return false
        }
    }
}
