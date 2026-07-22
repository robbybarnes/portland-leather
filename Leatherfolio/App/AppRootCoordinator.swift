import Foundation
import SwiftData

/// Keeps launch and navigation state alive across the unavailable-to-ready
/// transition. URLs route immediately into the retained AppRouter; retry only
/// reopens the same persistent-store factory.
@MainActor
final class AppRootCoordinator {
    let launchModel: AppLaunchModel
    let router = AppRouter()

    var container: ModelContainer? {
        launchModel.container
    }

    init(containerFactory: @escaping AppLaunchModel.ContainerFactory) {
        launchModel = AppLaunchModel(containerFactory: containerFactory)
    }

    func handle(url: URL) {
        router.handle(url: url)
    }

    func retry() {
        launchModel.retry()
    }
}
