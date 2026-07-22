import SwiftUI

/// Full-size QR label for an item, with export via ShareLink (print it, stick
/// it in the dust bag — scanning it later jumps straight to this item).
struct QRLabelSheet: View {
    let item: Item
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if let uiImage = QRService.qrImage(for: item.id, scale: 16) {
                    let image = Image(uiImage: uiImage)
                    image
                        .interpolation(.none)   // keep modules crisp when SwiftUI scales
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 280)
                        .accessibilityLabel(AccessibilityText.qrLabel(itemName: item.name))
                    Text(displayName)
                        .font(.headline)
                    ShareLink(
                        item: image,
                        preview: SharePreview("Leatherfolio label — \(displayName)", image: image)
                    ) {
                        Label("Export Label", systemImage: "square.and.arrow.up")
                    }
                } else {
                    ContentUnavailableView("Could not generate QR label",
                                           systemImage: "qrcode")
                }
            }
            .padding()
            .navigationTitle("QR Label")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var displayName: String {
        item.name.isEmpty ? "Untitled item" : item.name
    }
}
