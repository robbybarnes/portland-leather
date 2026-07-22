import SwiftUI

struct ContentView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.path) {
            CollectionView()
                .navigationDestination(for: UUID.self) { itemID in
                    ItemDetailLoaderView(itemID: itemID)
                }
        }
    }
}
