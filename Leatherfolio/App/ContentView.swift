import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            CollectionView()
                .navigationDestination(for: UUID.self) { itemID in
                    ItemDetailLoaderView(itemID: itemID)
                }
        }
    }
}
