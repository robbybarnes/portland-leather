import SwiftUI
import SwiftData

@main
struct LeatherfolioApp: App {
    @State private var router = AppRouter()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(Theme.accent)
                .foregroundStyle(Theme.textPrimary)
                .environment(router)
                .onOpenURL { url in
                    router.handle(url: url)
                }
        }
        .modelContainer(AppModelContainer.shared)
    }
}
