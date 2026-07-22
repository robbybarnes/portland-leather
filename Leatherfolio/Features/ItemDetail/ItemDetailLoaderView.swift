import SwiftUI
import SwiftData

/// Resolves a UUID navigation value to the live Item. Grid taps and deep
/// links (Task 7) both push UUIDs, so this is the single destination type.
struct ItemDetailLoaderView: View {
    private let itemID: UUID
    @Query private var items: [Item]

    init(itemID: UUID) {
        self.itemID = itemID
        _items = Query(filter: #Predicate<Item> { $0.id == itemID })
    }

    var body: some View {
        if let item = items.first {
            ItemDetailView(item: item)
        } else {
            ContentUnavailableView("Item not found",
                                   systemImage: "questionmark.circle")
        }
    }
}
