import SwiftUI

struct ThumbnailLoadState {
    private(set) var photoID: UUID?
    private(set) var image: UIImage?

    init(photoID: UUID? = nil, image: UIImage? = nil) {
        self.photoID = photoID
        self.image = image
    }

    mutating func begin(
        requestedPhotoID: UUID?,
        currentPhotoID: UUID?,
        isCancelled: Bool
    ) -> Bool {
        guard !isCancelled, requestedPhotoID == currentPhotoID else { return false }
        photoID = requestedPhotoID
        image = nil
        return true
    }

    mutating func finish(
        image: UIImage?,
        requestedPhotoID: UUID,
        currentPhotoID: UUID?,
        isCancelled: Bool
    ) {
        guard !isCancelled,
              requestedPhotoID == currentPhotoID,
              photoID == requestedPhotoID else { return }
        self.image = image
    }
}

struct ItemCell: View {
    let item: Item
    @State private var thumbnailState = ThumbnailLoadState()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                thumbnailView
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityHidden(true)
                if item.isUnicorn {
                    UnicornBadge()
                        .padding(6)
                        .accessibilityHidden(true)
                }
            }
            HStack(spacing: 4) {
                Text(item.name.isEmpty ? "Untitled" : item.name)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                if item.favorite {
                    Image(systemName: "heart.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .accessibilityLabel("Favorite")
                }
            }
            Text(specLine)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .task(id: item.primaryPhoto?.id) { [requestedPhotoID = item.primaryPhoto?.id] in
            await loadThumbnail(for: requestedPhotoID)
        }
        .cardStyle()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AccessibilityText.label(for: item))
    }

    /// "Medium · Honey" when size/color exist; falls back to the category.
    private var specLine: String {
        let parts = [item.size, item.color]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? item.category.rawValue : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let thumbnail = thumbnailState.image {
            Image(uiImage: thumbnail)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                Rectangle()
                    .fill(Color(.secondarySystemBackground))
                Image(systemName: "bag")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    /// Source bytes are accessed lazily only after ImageStore checks both
    /// memory and disk thumbnail caches.
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

/// Star-on-unicorn badge treatment for one-of-one items.
struct UnicornBadge: View {
    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "star.fill")
                .font(.caption2)
                .foregroundStyle(.yellow)
            Text("🦄")
                .font(.caption)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.thinMaterial, in: Capsule())
        .accessibilityLabel("Unicorn item")
    }
}
