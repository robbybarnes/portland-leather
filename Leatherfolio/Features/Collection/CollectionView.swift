import SwiftUI
import SwiftData

struct CollectionView: View {
    @Query(sort: \Item.createdAt, order: .reverse) private var items: [Item]
    @Environment(AppRouter.self) private var router
    @State private var showingAdd = false
    @State private var showingScanner = false
    @State private var scanPrefill: ScanPrefill?

    struct ScanPrefill: Identifiable {
        let id = UUID()
        let code: String
        let isQR: Bool
    }

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
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showingScanner = true
                } label: {
                    Label("Scan", systemImage: "qrcode.viewfinder")
                }
                .accessibilityLabel("Scan a QR label or barcode")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAdd = true
                } label: {
                    Label("Add Item", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAdd) {
            AddEditItemView(item: nil)
        }
        .sheet(isPresented: $showingScanner) {
            ScannerSheet(onScan: handleScan)
        }
        .sheet(item: $scanPrefill) { prefill in
            AddEditItemView(model: {
                let model = AddEditItemModel(item: nil)
                model.applyScanPrefill(code: prefill.code, isQR: prefill.isQR)
                return model
            }())
        }
    }

    private func handleScan(payload: String, isQR: Bool) {
        showingScanner = false
        let route = ScanRouter.route(
            payload: payload,
            isQR: isQR,
            existingItemIDs: Set(items.map(\.id)))
        switch route {
        case .existingItem(let id):
            router.open(itemID: id)
        case .newItem(let code, let isQR):
            scanPrefill = ScanPrefill(code: code, isQR: isQR)
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
