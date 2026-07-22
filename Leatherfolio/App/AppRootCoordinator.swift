import Combine
import Foundation
import SwiftData

/// Keeps launch and navigation state alive across the unavailable-to-ready
/// transition. URLs route immediately into the retained AppRouter; retry only
/// reopens the same persistent-store factory.
@MainActor
final class AppRootCoordinator: ObservableObject {
    let router = AppRouter()
    @Published private(set) var container: ModelContainer?
    private let launchModel: AppLaunchModel

    var unavailableTitle: String { launchModel.unavailableTitle }
    var unavailableMessage: String { launchModel.unavailableMessage }
    var retryButtonTitle: String { launchModel.retryButtonTitle }

    init(containerFactory: @escaping AppLaunchModel.ContainerFactory) {
        let launchModel = AppLaunchModel(containerFactory: containerFactory)
        self.launchModel = launchModel
        container = launchModel.container
    }

    func handle(url: URL) {
        router.handle(url: url)
    }

    func retry() {
        launchModel.retry()
        container = launchModel.container
    }
}
