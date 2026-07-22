import SwiftUI
import SwiftData

struct CollectionView: View {
    @Query(sort: \Item.createdAt, order: .reverse) private var items: [Item]
    @State private var showingAdd = false

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 12)]

    var body: some View {
        Group {
            if items.isEmpty {
                emptyState
            } else {
                grid
            }
        }
        .navigationTitle("Leatherfolio")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAdd = true
                } label: {
                    Label("Add Item", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAdd) {
            // Task 5 replaces this stub with AddEditItemView(item: nil).
            Text("Add flow arrives in the next task.")
                .padding()
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(items) { item in
                    NavigationLink(value: item.id) {
                        ItemCell(item: item)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No items yet", systemImage: "bag")
        } description: {
            Text("Your leather collection starts here.")
        } actions: {
            Button("Add your first item") {
                showingAdd = true
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
