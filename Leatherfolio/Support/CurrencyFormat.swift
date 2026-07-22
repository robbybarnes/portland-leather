import Foundation

/// Locale-aware currency rendering for Decimal money values (Global
/// Constraints: Decimal everywhere, user's locale currency).
enum CurrencyFormat {
    /// e.g. "$1,234.56" in en_US, "1.234,56 €" in de_DE.
    static func string(from value: Decimal, locale: Locale = .current) -> String {
        let code = locale.currency?.identifier ?? "USD"
        return value.formatted(.currency(code: code).locale(locale))
    }

    /// Delta rendering with an explicit sign, e.g. "+$120.00" / "-$35.00".
    static func signedString(from value: Decimal, locale: Locale = .current) -> String {
        let code = locale.currency?.identifier ?? "USD"
        return value.formatted(
            .currency(code: code).locale(locale).sign(strategy: .always())
        )
    }
}
