import XCTest
@testable import Leatherfolio

final class SmokeTests: XCTestCase {
    /// Proves the test target builds, links against the app target, and runs.
    func testTargetBuildsAndLinks() {
        XCTAssertEqual(1 + 1, 2)
    }
}
