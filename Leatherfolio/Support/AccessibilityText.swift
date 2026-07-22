import Foundation

/// Pure composition of VoiceOver strings, so label wording is unit-testable
/// and identical wherever it's spoken.
enum AccessibilityText {
    /// Cell label, e.g. "Willow Tote, Medium, Honey, Suede leather, favorite,
    /// unicorn, rated 3 of 5 stars". Empty/irrelevant parts are omitted.
    static func label(for item: Item) -> String {
        var parts: [String] = [item.name.isEmpty ? "Untitled item" : item.name]
        if let size = item.size, !size.isEmpty { parts.append(size) }
        if let color = item.color, !color.isEmpty { parts.append(color) }
        if let leather = item.leatherType, leather != .other {
            parts.append("\(leather.rawValue) leather")
        }
        if item.favorite { parts.append("favorite") }
        if item.isUnicorn { parts.append("unicorn") }
        if item.isWishlist { parts.append("wishlist") }
        if item.rating > 0 { parts.append(ratingLabel(item.rating)) }
        return parts.joined(separator: ", ")
    }

    /// "rated 3 of 5 stars"; "not rated" for 0.
    static func ratingLabel(_ rating: Int) -> String {
        rating > 0 ? "rated \(rating) of 5 stars" : "not rated"
    }

    /// Carousel photo label: the caption when present, else "Photo 2 of 4".
    static func photoLabel(caption: String?, index: Int, count: Int) -> String {
        if let caption, !caption.trimmingCharacters(in: .whitespaces).isEmpty {
            return caption
        }
        return "Photo \(index + 1) of \(count)"
    }
}
