import SwiftUI
import SwiftData

/// Grid/list layout choice, persisted via @AppStorage.
enum CollectionLayout: String, CaseIterable {
    case grid, list
}

struct CollectionView: View {
    @Query(sort: \Item.createdAt, order: .reverse) private var allItems: [Item]
    @Environment(AppRouter.self) private var router
    @State private var filter = ItemFilter()
    @State private var showingFilterSheet = false
    @State private var showingStats = false
    @State private var showingAdd = false
    @State private var showingScanner = false
    @State private var scanPrefill: ScanPrefill?
    @AppStorage("collectionLayout") private var layoutRaw = CollectionLayout.grid.rawValue
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    struct ScanPrefill: Identifiable {
        let id = UUID()
        let code: String
        let isQR: Bool
    }

    private var layout: CollectionLayout { CollectionLayout(rawValue: layoutRaw) ?? .grid }
    private var items: [Item] { filter.apply(to: allItems) }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Scope", selection: $filter.scope) {
                ForEach(CollectionScope.allCases) { scope in
                    Text(scope.rawValue).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)

            if !filter.activeChips.isEmpty {
                FilterChipsRow(filter: $filter)
            }

            content
        }
        .navigationTitle("Collection")
        .background(Theme.background)
        .searchable(text: $filter.query, prompt: "Search name, notes, tags")
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
            organizeToolbar
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
        .sheet(isPresented: $showingFilterSheet) {
            FilterSheetView(filter: $filter,
                            options: FilterOptions.make(items: allItems))
        }
        .sheet(isPresented: $showingStats) {
            NavigationStack {
                StatsView(stats: CollectionStats(
                    items: allItems.filter { !$0.isWishlist },
                    catalog: .shared
                ))
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showingStats = false }
                    }
                }
            }
        }
    }

    private func handleScan(payload: String, isQR: Bool) {
        showingScanner = false
        let route = ScanRouter.route(
            payload: payload,
            isQR: isQR,
            existingItemIDs: Set(allItems.map(\.id)))
        switch route {
        case .existingItem(let id):
            router.open(itemID: id)
        case .newItem(let code, let isQR):
            scanPrefill = ScanPrefill(code: code, isQR: isQR)
        }
    }

    // MARK: - Content

    @ViewBuilder private var content: some View {
        if items.isEmpty {
            ContentUnavailableView(
                filter.scope == .wishlist ? "No Wishlist Items" : "No Items",
                systemImage: "bag",
                description: Text(filter.activeFilterCount > 0 || !filter.query.isEmpty
                                  ? "Try clearing filters or search."
                                  : "Tap + to add your first item.")
            )
            .frame(maxHeight: .infinity)
        } else if layout == .grid {
            ScrollView {
                LazyVGrid(columns: gridColumns, spacing: 12) {
                    ForEach(items) { item in
                        NavigationLink(value: item.id) {
                            ItemCell(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
        } else {
            List(items) { item in
                NavigationLink(value: item.id) {
                    ItemRow(item: item)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
        }
    }

    private var gridColumns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.adaptive(minimum: 150), spacing: 12)]
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder private var organizeToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                showingStats = true
            } label: {
                Label("Stats", systemImage: "chart.bar")
            }

            Menu {
                Picker("Sort by", selection: $filter.sortKey) {
                    ForEach(SortKey.allCases) { key in
                        Text(key.rawValue).tag(key)
                    }
                }
                Divider()
                Picker("Direction", selection: $filter.sortAscending) {
                    Text("Ascending").tag(true)
                    Text("Descending").tag(false)
                }
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }

            Button {
                layoutRaw = (layout == .grid ? CollectionLayout.list : .grid).rawValue
            } label: {
                Label(layout == .grid ? "Switch to list layout" : "Switch to grid layout",
                      systemImage: layout == .grid ? "list.bullet" : "square.grid.2x2")
            }

            Button {
                showingFilterSheet = true
            } label: {
                Label("Filters",
                      systemImage: filter.activeFilterCount > 0
                      ? "line.3.horizontal.decrease.circle.fill"
                      : "line.3.horizontal.decrease.circle")
            }
        }
    }
}

/// Compact row for the list layout. Thumbnails only — never Photo.imageData
/// decoded at full size in a list.
struct ItemRow: View {
    let item: Item
    @State private var thumbnail: UIImage?

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "bag")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 56, height: 56)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name.isEmpty ? "Untitled" : item.name)
                    .font(.headline)
                Text([item.size, item.color, item.leatherType?.rawValue]
                        .compactMap { $0 }
                        .joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if item.favorite {
                Image(systemName: "heart.fill").foregroundStyle(.pink)
                    .accessibilityHidden(true)
            }
            if item.isUnicorn {
                Image(systemName: "sparkles").foregroundStyle(.purple)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AccessibilityText.label(for: item))
        .task(id: item.primaryPhoto?.id) {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        let requestedPhotoID = item.primaryPhoto?.id
        guard let requestedPhotoID,
              let photo = item.primaryPhoto,
              photo.id == requestedPhotoID else {
            guard !Task.isCancelled, item.primaryPhoto?.id == requestedPhotoID else { return }
            thumbnail = nil
            return
        }
        let loadedThumbnail = await ImageStore.shared.thumbnail(for: requestedPhotoID) {
            photo.imageData
        }
        guard !Task.isCancelled, item.primaryPhoto?.id == requestedPhotoID else { return }
        thumbnail = loadedThumbnail
    }
}
