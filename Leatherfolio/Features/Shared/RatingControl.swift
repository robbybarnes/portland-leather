import SwiftUI

/// Reusable 0–5 star control. Tapping the currently selected star clears the
/// rating back to 0 (0 = unrated, matching Item.rating's contract).
struct RatingControl: View {
    @Binding var rating: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: star <= rating ? "star.fill" : "star")
                    .foregroundStyle(star <= rating ? .yellow : .secondary)
                    .onTapGesture {
                        rating = (rating == star) ? 0 : star
                    }
                    .accessibilityLabel("\(star) star\(star == 1 ? "" : "s")")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(rating) of 5 stars")
    }
}
