import SwiftUI
import SwiftData

struct ItemDetailView: View {
    @Bindable var item: Item
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showingEdit = false
    @State private var showingDeleteConfirmation = false

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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { showingEdit = true }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
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
    }

    // MARK: Sections

    private var sortedPhotos: [Photo] {
        (item.photos ?? []).sorted { first, second in
            if first.isPrimary != second.isPrimary { return first.isPrimary }
            return first.createdAt < second.createdAt
        }
    }

    /// The detail view is the one place full-res originals (Photo.imageData)
    /// load — grids stay on ImageStore thumbnails.
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
                    if let data = photo.imageData, let image = UIImage(data: data) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color(.secondarySystemBackground)
                    }
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
                .font(.title.bold())
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

    /// Shipping intermediate, not a placeholder: this card is the QR-label
    /// section. Phase 3 replaces ONLY its body with the CIFilter-generated
    /// QR image (QRService.qrImage) encoding leatherfolio://item/<uuid>.
    /// Until then it shows the same stable UUID the QR will encode.
    private var qrLabelCard: some View {
        infoCard("QR Label") {
            VStack(alignment: .leading, spacing: 6) {
                Text(item.id.uuidString)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                Text("Printable QR code arrives with scanning support.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
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
        try? item.deleteWithCleanup(in: modelContext)
        dismiss()
    }
}
