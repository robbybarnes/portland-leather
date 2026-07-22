import SwiftUI
import SwiftData

@main
struct LeatherfolioApp: App {
    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
    }
}

struct AppRootView: View {
    @State private var coordinator: AppRootCoordinator

    @MainActor
    init(
        containerFactory: @escaping AppLaunchModel.ContainerFactory = {
            try AppModelContainer.make(inMemory: false)
        }
    ) {
        _coordinator = State(
            initialValue: AppRootCoordinator(containerFactory: containerFactory))
    }

    var body: some View {
        Group {
            if let container = coordinator.container {
                ContentView()
                    .modelContainer(container)
                    .environment(coordinator.router)
            } else {
                ContentUnavailableView {
                    Label(
                        coordinator.launchModel.unavailableTitle,
                        systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text(coordinator.launchModel.unavailableMessage)
                } actions: {
                    Button(coordinator.launchModel.retryButtonTitle) {
                        coordinator.retry()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .background(Theme.background)
            }
        }
        .onOpenURL { url in
            coordinator.handle(url: url)
        }
        .tint(Theme.accent)
        .foregroundStyle(Theme.textPrimary)
    }
}
