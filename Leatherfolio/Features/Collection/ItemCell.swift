import SwiftUI

struct ItemCell: View {
    let item: Item
    @State private var thumbnail: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                thumbnailView
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                if item.isUnicorn {
                    UnicornBadge()
                        .padding(6)
                }
            }
            HStack(spacing: 4) {
                Text(item.name.isEmpty ? "Untitled" : item.name)
                    .font(.headline)
                    .lineLimit(1)
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
                .lineLimit(1)
        }
        .task(id: item.primaryPhoto?.id) {
            await loadThumbnail()
        }
        .cardStyle()
        .accessibilityElement(children: .combine)
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
        if let thumbnail {
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

    /// Grid cells only ever touch ImageStore thumbnails — never full-res
    /// Photo.imageData decoding in the scroll path beyond this one pass.
    private func loadThumbnail() async {
        guard let photo = item.primaryPhoto else {
            thumbnail = nil
            return
        }
        thumbnail = await ImageStore.shared.thumbnail(
            for: photo.id, imageData: photo.imageData)
    }
}

/// Star-on-unicorn badge treatment for one-of-one items.
struct UnicornBadge: View {
    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "star.fill")
                .font(.system(size: 9))
                .foregroundStyle(.yellow)
            Text("🦄")
                .font(.system(size: 11))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.thinMaterial, in: Capsule())
        .accessibilityLabel("Unicorn item")
    }
}
