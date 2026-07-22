import XCTest
@testable import Leatherfolio

final class StatsFormattingTests: XCTestCase {
    func testAverageRatingUsesLocaleDecimalSeparator() {
        XCTAssertEqual(
            StatsFormatting.averageRating(3.5, locale: Locale(identifier: "en_US")),
            "3.5 of 5"
        )
        XCTAssertEqual(
            StatsFormatting.averageRating(3.5, locale: Locale(identifier: "de_DE")),
            "3,5 of 5"
        )
    }
}
