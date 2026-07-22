import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            CollectionView()
                .navigationDestination(for: UUID.self) { itemID in
                    // Task 6 replaces this stub with
                    // ItemDetailLoaderView(itemID: itemID).
                    Text("Item \(itemID.uuidString)")
                }
        }
    }
}
