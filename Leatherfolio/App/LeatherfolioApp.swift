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
                    if let itemID = QRService.itemID(fromPayload: url.absoluteString) {
                        router.open(itemID: itemID)
                    }
                }
        }
        .modelContainer(AppModelContainer.shared)
    }
}
