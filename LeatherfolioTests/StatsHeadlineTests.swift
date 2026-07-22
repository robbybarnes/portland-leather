import XCTest
@testable import Leatherfolio

final class StatsHeadlineTests: XCTestCase {
    func testFullHeadline() {
        XCTAssertEqual(
            StatsHeadline.text(itemCount: 12, colorCount: 5, leatherTypeCount: 3, unicornCount: 2),
            "12 items · 5 colors · 3 leather types · 2 unicorns"
        )
    }

    func testSingularForms() {
        XCTAssertEqual(
            StatsHeadline.text(itemCount: 1, colorCount: 1, leatherTypeCount: 1, unicornCount: 1),
            "1 item · 1 color · 1 leather type · 1 unicorn"
        )
    }

    func testZeroUnicornsOmitsUnicornSegment() {
        XCTAssertEqual(
            StatsHeadline.text(itemCount: 3, colorCount: 2, leatherTypeCount: 1, unicornCount: 0),
            "3 items · 2 colors · 1 leather type"
        )
    }
}
