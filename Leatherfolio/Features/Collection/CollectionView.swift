import SwiftUI
import SwiftData

/// Grid/list layout choice, persisted via @AppStorage.
enum CollectionLayout: String, CaseIterable {
    case grid, list
}

struct CollectionScanPrefill: Equatable {
    let code: String
    let isQR: Bool
}

struct AddItemPrefill: Identifiable, Equatable {
    let id = UUID()
    let isWishlist: Bool
    let scan: CollectionScanPrefill?

    init(isWishlist: Bool, scan: CollectionScanPrefill? = nil) {
        self.isWishlist = isWishlist
        self.scan = scan
    }
}

enum CollectionModalDestination: Identifiable, Equatable {
    case add(AddItemPrefill)
    case scanner
    case filter
    case stats

    var id: String {
        switch self {
        case .add(let prefill): "add-\(prefill.id)"
        case .scanner: "scanner"
        case .filter: "filter"
        case .stats: "stats"
        }
    }
}

/// Pure presentation state keeps scanner handoffs behind sheet dismissal so
/// navigation and the next modal never compete with the scanner presentation.
struct CollectionPresentationState: Equatable {
    var modal: CollectionModalDestination?
    private var pendingScanRoute: ScanRoute?
    private var pendingScope: CollectionScope?

    mutating func presentAdd(in scope: CollectionScope) {
        modal = .add(AddItemPrefill(isWishlist: scope == .wishlist))
    }

    mutating func presentScanner() {
        modal = .scanner
    }

    mutating func receiveScan(_ route: ScanRoute, in scope: CollectionScope) {
        pendingScanRoute = route
        pendingScope = scope
        modal = nil
    }

    /// Returns the item to navigate to, or installs the next modal after the
    /// scanner has fully dismissed.
    mutating func didDismissModal() -> UUID? {
        guard let route = pendingScanRoute else { return nil }
        let scope = pendingScope ?? .owned
        pendingScanRoute = nil
        pendingScope = nil
        switch route {
        case .existingItem(let id):
            return id
        case .newItem(let code, let isQR):
            modal = .add(AddItemPrefill(
                isWishlist: scope == .wishlist,
                scan: CollectionScanPrefill(code: code, isQR: isQR)))
            return nil
        }
    }
}

struct CollectionView: View {
    @Query(sort: \Item.createdAt, order: .reverse) private var allItems: [Item]
    @Environment(AppRouter.self) private var router
    @State private var filter = ItemFilter()
    @State private var presentation = CollectionPresentationState()
    @AppStorage("collectionLayout") private var layoutRaw = CollectionLayout.grid.rawValue
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
                    presentation.presentScanner()
                } label: {
                    Label("Scan", systemImage: "qrcode.viewfinder")
                }
                .accessibilityLabel("Scan a QR label or barcode")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    presentation.presentAdd(in: filter.scope)
                } label: {
                    Label("Add Item", systemImage: "plus")
                }
            }
            organizeToolbar
        }
        .sheet(item: $presentation.modal, onDismiss: completeModalTransition) { destination in
            switch destination {
            case .add(let prefill):
                AddEditItemView(model: makeAddModel(prefill: prefill))
            case .scanner:
                ScannerSheet(onScan: handleScan)
            case .filter:
                FilterSheetView(
                    filter: $filter,
                    options: FilterOptions.make(items: allItems))
            case .stats:
                StatsSheet(items: allItems)
            }
        }
    }

    private func handleScan(payload: String, isQR: Bool) {
        let route = ScanRouter.route(
            payload: payload,
            isQR: isQR,
            existingItemIDs: Set(allItems.map(\.id)))
        presentation.receiveScan(route, in: filter.scope)
    }

    private func completeModalTransition() {
        if let itemID = presentation.didDismissModal() {
            router.open(itemID: itemID)
        }
    }

    private func makeAddModel(prefill: AddItemPrefill) -> AddEditItemModel {
        let model = AddEditItemModel(item: nil)
        model.isWishlist = prefill.isWishlist
        if let scan = prefill.scan {
            model.applyScanPrefill(code: scan.code, isQR: scan.isQR)
        }
        return model
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
                presentation.modal = .stats
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
                presentation.modal = .filter
            } label: {
                Label("Filters",
                      systemImage: filter.activeFilterCount > 0
                      ? "line.3.horizontal.decrease.circle.fill"
                      : "line.3.horizontal.decrease.circle")
            }
        }
    }
}

private struct StatsSheet: View {
    let items: [Item]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            StatsView(stats: CollectionStats(
                items: items.filter { !$0.isWishlist },
                catalog: .shared
            ))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// Compact row for the list layout. Thumbnails only — never Photo.imageData
/// decoded at full size in a list.
struct ItemRow: View {
    let item: Item
    @State private var thumbnailState = ThumbnailLoadState()

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let thumbnail = thumbnailState.image {
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
        .task(id: item.primaryPhoto?.id) { [requestedPhotoID = item.primaryPhoto?.id] in
            await loadThumbnail(for: requestedPhotoID)
        }
    }

    private func loadThumbnail(for requestedPhotoID: UUID?) async {
        guard thumbnailState.begin(
            requestedPhotoID: requestedPhotoID,
            currentPhotoID: item.primaryPhoto?.id,
            isCancelled: Task.isCancelled) else { return }
        guard let requestedPhotoID,
              let photo = item.primaryPhoto,
              photo.id == requestedPhotoID else { return }
        let loadedThumbnail = await ImageStore.shared.thumbnail(for: requestedPhotoID) {
            photo.imageData
        }
        thumbnailState.finish(
            image: loadedThumbnail,
            requestedPhotoID: requestedPhotoID,
            currentPhotoID: item.primaryPhoto?.id,
            isCancelled: Task.isCancelled)
    }
}
