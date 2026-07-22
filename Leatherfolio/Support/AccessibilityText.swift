import Foundation

struct AccessibilityActionText: Equatable {
    let label: String
    let value: String
    let hint: String
}

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

    static func qrLabel(itemName: String) -> String {
        let name = itemName.trimmingCharacters(in: .whitespacesAndNewlines)
        return "QR label for \(name.isEmpty ? "Untitled item" : name)"
    }

    static func photoPrimaryAction(isPrimary: Bool) -> AccessibilityActionText {
        if isPrimary {
            AccessibilityActionText(
                label: "Primary photo",
                value: "Current primary",
                hint: "This photo appears first.")
        } else {
            AccessibilityActionText(
                label: "Make photo primary",
                value: "Not primary",
                hint: "Makes this photo appear first.")
        }
    }

    static func photoRemovalAction(isStored: Bool) -> AccessibilityActionText {
        if isStored {
            AccessibilityActionText(
                label: "Remove saved photo",
                value: "Saved photo",
                hint: "Removes this photo when you save the item.")
        } else {
            AccessibilityActionText(
                label: "Remove new photo",
                value: "New photo",
                hint: "Removes this photo before it is saved.")
        }
    }
}
