import SwiftUI

/// Horizontal row of removable chips for every active filter, plus Clear All.
struct FilterChipsRow: View {
    @Binding var filter: ItemFilter

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(filter.activeChips) { chip in
                    Button {
                        filter.remove(chip.kind)
                    } label: {
                        HStack(spacing: 4) {
                            Text(chip.label)
                            Image(systemName: "xmark")
                                .font(.caption2)
                                .accessibilityHidden(true)
                        }
                        .font(.footnote)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color(.secondarySystemBackground)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove filter: \(chip.label)")
                }
                Button("Clear All") { filter.clearFilters() }
                    .font(.footnote.weight(.semibold))
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
}
