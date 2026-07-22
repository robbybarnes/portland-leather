import Observation
import SwiftData

/// Owns persistent-store startup without guessing at recovery. A failed open
/// never deletes, relocates, or replaces the user's store; retry invokes the
/// same injected factory again.
@MainActor
@Observable
final class AppLaunchModel {
    typealias ContainerFactory = @MainActor () throws -> ModelContainer

    let unavailableTitle = "Collection Unavailable"
    let unavailableMessage =
        "My PLG Collection couldn't open your collection. Your data was not changed. Try again to reopen the same collection."
    let retryButtonTitle = "Try Again"

    private let containerFactory: ContainerFactory
    private(set) var container: ModelContainer?

    init(containerFactory: @escaping ContainerFactory) {
        self.containerFactory = containerFactory
        retry()
    }

    func retry() {
        do {
            container = try containerFactory()
        } catch {
            container = nil
        }
    }
}
