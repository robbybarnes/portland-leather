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
    @State private var launchModel: AppLaunchModel
    @State private var router = AppRouter()

    @MainActor
    init(
        containerFactory: @escaping AppLaunchModel.ContainerFactory = {
            try AppModelContainer.make(inMemory: false)
        }
    ) {
        _launchModel = State(
            initialValue: AppLaunchModel(containerFactory: containerFactory))
    }

    var body: some View {
        Group {
            if let container = launchModel.container {
                ContentView()
                    .modelContainer(container)
                    .environment(router)
                    .onOpenURL { url in
                        router.handle(url: url)
                    }
            } else {
                ContentUnavailableView {
                    Label(
                        launchModel.unavailableTitle,
                        systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text(launchModel.unavailableMessage)
                } actions: {
                    Button(launchModel.retryButtonTitle) {
                        launchModel.retry()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .background(Theme.background)
            }
        }
        .tint(Theme.accent)
        .foregroundStyle(Theme.textPrimary)
    }
}
