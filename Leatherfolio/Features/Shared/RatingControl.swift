import SwiftUI

/// Star rating, 0–5. Tap a star to set it; tap the current rating again to
/// clear. To VoiceOver it is ONE adjustable element: swipe up/down to change,
/// value announced via AccessibilityText.ratingLabel.
struct RatingControl: View {
    @Binding var rating: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: star <= rating ? "star.fill" : "star")
                    .foregroundStyle(star <= rating ? Theme.accent : .secondary)
                    .onTapGesture {
                        rating = (rating == star) ? 0 : star
                    }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rating")
        .accessibilityValue(AccessibilityText.ratingLabel(rating))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: rating = min(rating + 1, 5)
            case .decrement: rating = max(rating - 1, 0)
            @unknown default: break
            }
        }
    }
}
