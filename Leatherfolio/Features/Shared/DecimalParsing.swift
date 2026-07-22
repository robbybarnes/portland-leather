import Foundation

/// Locale-aware Decimal <-> text helpers for the currency fields.
enum DecimalParsing {
    static func decimal(from text: String) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return Decimal(string: trimmed, locale: .current)
    }

    static func text(from decimal: Decimal?) -> String {
        guard let decimal else { return "" }
        return "\(decimal)"
    }
}

extension Decimal {
    /// "$125.50"-style rendering in the user's locale currency
    /// (global constraint: money is Decimal, rendered per locale).
    var currencyDisplay: String {
        formatted(.currency(code: Locale.current.currency?.identifier ?? "USD"))
    }
}
