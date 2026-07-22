import XCTest
@testable import Leatherfolio

final class CurrencyFormatTests: XCTestCase {
    private let enUS = Locale(identifier: "en_US")

    func testFormatsDecimalInLocaleCurrency() {
        XCTAssertEqual(
            CurrencyFormat.string(from: Decimal(string: "1234.56")!, locale: enUS),
            "$1,234.56"
        )
        XCTAssertEqual(
            CurrencyFormat.string(from: Decimal(string: "0")!, locale: enUS),
            "$0.00"
        )
    }

    func testSignedStringShowsExplicitSign() {
        let formatted = CurrencyFormat.signedString(from: Decimal(string: "120")!, locale: enUS)
        XCTAssertTrue(formatted.contains("+") && formatted.contains("120.00"), "expected positive signed string, got \(formatted)")
        let negativeFormatted = CurrencyFormat.signedString(from: Decimal(string: "-35")!, locale: enUS)
        XCTAssertTrue(negativeFormatted.contains("35.00") && !negativeFormatted.hasPrefix("+"), "expected negative signed string, got \(negativeFormatted)")
    }

    func testNonUSLocale() {
        let deDE = Locale(identifier: "de_DE")
        let formatted = CurrencyFormat.string(from: Decimal(string: "1234.56")!, locale: deDE)
        XCTAssertTrue(formatted.contains("€"), "expected euro symbol in \(formatted)")
    }
}
