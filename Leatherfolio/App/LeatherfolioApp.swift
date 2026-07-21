import SwiftUI
import SwiftData

@main
struct LeatherfolioApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(AppModelContainer.shared)
    }
}
