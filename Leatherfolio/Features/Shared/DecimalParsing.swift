import Foundation

/// Locale-aware Decimal <-> text helpers for the currency fields.
enum DecimalParsing {
    static func decimal(from text: String, locale: Locale = .current) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return Decimal(string: trimmed, locale: locale)
    }

    static func text(from decimal: Decimal?, locale: Locale = .current) -> String {
        guard let decimal else { return "" }
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 38
        formatter.generatesDecimalNumbers = true
        return formatter.string(from: NSDecimalNumber(decimal: decimal)) ?? "\(decimal)"
    }
}

extension Decimal {
    /// "$125.50"-style rendering in the user's locale currency
    /// (global constraint: money is Decimal, rendered per locale).
    var currencyDisplay: String {
        formatted(.currency(code: Locale.current.currency?.identifier ?? "USD"))
    }
}
