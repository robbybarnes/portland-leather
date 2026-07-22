import SwiftUI
import SwiftData

struct ItemDetailView: View {
    @Bindable var item: Item
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showingEdit = false
    @State private var showingDeleteConfirmation = false
    @State private var showingQRLabel = false
    @State private var deletionController = ItemDeletionController()
    @State private var deletionTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                photoCarousel
                header
                specChips
                ratingRow
                costsBlock
                if let notes = item.notes, !notes.isEmpty {
                    infoCard("Notes") { Text(notes) }
                }
                if let dateAcquired = item.dateAcquired {
                    infoCard("Acquired") {
                        Text(dateAcquired.formatted(date: .long, time: .omitted))
                    }
                }
                if let upc = item.upc, !upc.isEmpty {
                    infoCard("UPC") {
                        Text(upc).font(.body.monospaced())
                    }
                }
                qrLabelCard
            }
            .padding()
        }
        .navigationTitle(item.name.isEmpty ? "Item" : item.name)
        .navigationBarTitleDisplayMode(.inline)
        .background(Theme.background)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { showingEdit = true }
                    .disabled(deletionController.isDeleting)
            }
            ToolbarItem(placement: .secondaryAction) {
                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(deletionController.isDeleting)
            }
        }
        .sheet(isPresented: $showingEdit) {
            AddEditItemView(item: item)
        }
        .confirmationDialog("Delete this item?",
                            isPresented: $showingDeleteConfirmation,
                            titleVisibility: .visible) {
            Button("Delete Item", role: .destructive) { deleteItem() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its photos are deleted too. This can't be undone.")
        }
        .alert("Couldn't delete item", isPresented: deletionErrorPresented) {
            Button("OK", role: .cancel) {
                deletionController.errorMessage = nil
            }
        } message: {
            Text(deletionController.errorMessage ?? "Nothing was removed; please try again.")
        }
    }

    // MARK: Sections

    private var sortedPhotos: [Photo] {
        (item.photos ?? []).sorted { first, second in
            if first.isPrimary != second.isPrimary { return first.isPrimary }
            return first.createdAt < second.createdAt
        }
    }

    /// Each source blob is copied on the main actor, then ImageIO performs a
    /// bounded decode on ImageStore's worker actor.
    @ViewBuilder
    private var photoCarousel: some View {
        if sortedPhotos.isEmpty {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemBackground))
                Image(systemName: "bag")
                    .font(.system(size: 48))
                    .foregroundStyle(.tertiary)
            }
            .frame(height: 280)
        } else {
            TabView {
                ForEach(sortedPhotos) { photo in
                    DetailPhotoView(photo: photo)
                }
            }
            .tabViewStyle(.page)
            .frame(height: 320)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(item.name.isEmpty ? "Untitled" : item.name)
                .font(.display(.largeTitle))
            if item.isUnicorn { UnicornBadge() }
            Spacer()
            if item.favorite {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
                    .accessibilityLabel("Favorite")
            }
        }
    }

    private var specChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(item.category.rawValue)
                if let size = item.size { chip("Size \(size)") }
                if let color = item.color { chip(color) }
                if let leather = item.leatherType { chip("\(leather.rawValue) leather") }
                if let condition = item.condition { chip(condition.rawValue) }
            }
        }
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(.secondarySystemBackground), in: Capsule())
    }

    private var ratingRow: some View {
        HStack {
            Text("Rating").font(.headline)
            Spacer()
            RatingControl(rating: $item.rating)
                .onChange(of: item.rating) {
                    item.updatedAt = .now
                }
        }
    }

    private var costsBlock: some View {
        infoCard("Costs & Value") {
            VStack(spacing: 8) {
                costRow("My cost", item.myCost)
                costRow("Retail", item.retailCost)
                costRow("Estimated value", item.estimatedValue)
                if let delta = item.valueDelta {
                    Divider()
                    HStack {
                        Text("Value delta").font(.subheadline.bold())
                        Spacer()
                        Text((delta >= 0 ? "+" : "") + delta.currencyDisplay)
                            .font(.subheadline.bold())
                            .foregroundStyle(delta >= 0 ? .green : .red)
                    }
                }
            }
        }
    }

    private func costRow(_ label: String, _ value: Decimal?) -> some View {
        HStack {
            Text(label).font(.subheadline)
            Spacer()
            Text(value?.currencyDisplay ?? "—")
                .font(.subheadline)
                .foregroundStyle(value == nil ? .secondary : .primary)
        }
    }

    // QR label card — tap to enlarge/export
    private var qrLabelCard: some View {
        Button {
            showingQRLabel = true
        } label: {
            HStack(spacing: 16) {
                if let uiImage = QRService.qrImage(for: item.id, scale: 8) {
                    Image(uiImage: uiImage)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 88, height: 88)
                }
                VStack(alignment: .leading) {
                    Text("QR Label")
                        .font(.headline)
                    Text("Tap to enlarge or export")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("QR label. Tap to enlarge or export.")
        .sheet(isPresented: $showingQRLabel) {
            QRLabelSheet(item: item)
        }
    }

    private func infoCard(_ title: String,
                          @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: Actions

    private func deleteItem() {
        guard deletionTask == nil else { return }
        deletionTask = Task { @MainActor in
            let shouldDismiss = await deletionController.delete(item, in: modelContext)
            deletionTask = nil
            if shouldDismiss { dismiss() }
        }
    }

    private var deletionErrorPresented: Binding<Bool> {
        Binding(
            get: { deletionController.errorMessage != nil },
            set: { if !$0 { deletionController.errorMessage = nil } })
    }
}

private struct DetailPhotoView: View {
    let photo: Photo
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color(.secondarySystemBackground)
            }
        }
        .task(id: photo.id) {
            let requestedPhotoID = photo.id
            guard let sourceData = photo.imageData else {
                guard !Task.isCancelled,
                      photo.id == requestedPhotoID,
                      photo.imageData == nil else { return }
                image = nil
                return
            }
            let loadedImage = await ImageStore.shared.displayImage(from: sourceData)
            guard !Task.isCancelled,
                  photo.id == requestedPhotoID,
                  photo.imageData == sourceData else { return }
            image = loadedImage
        }
    }
}
