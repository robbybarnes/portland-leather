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
    @StateObject private var coordinator: AppRootCoordinator

    @MainActor
    init(
        containerFactory: @escaping AppLaunchModel.ContainerFactory = {
            try AppModelContainer.make(inMemory: false)
        }
    ) {
        _coordinator = StateObject(
            wrappedValue: AppRootCoordinator(containerFactory: containerFactory))
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
                        coordinator.unavailableTitle,
                        systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text(coordinator.unavailableMessage)
                } actions: {
                    Button(coordinator.retryButtonTitle) {
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
