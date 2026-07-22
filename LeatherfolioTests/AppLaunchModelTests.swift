import SwiftData
import XCTest
@testable import Leatherfolio

@MainActor
final class AppLaunchModelTests: XCTestCase {
    private enum TestError: Error {
        case storeUnavailable
    }

    func testFailureShowsNonDestructiveUnavailableCopy() {
        let model = AppLaunchModel {
            throw TestError.storeUnavailable
        }

        XCTAssertNil(model.container)
        XCTAssertEqual(model.unavailableTitle, "Collection Unavailable")
        XCTAssertEqual(
            model.unavailableMessage,
            "Leatherfolio couldn't open your collection. Your data was not changed. Try again to reopen the same collection."
        )
        XCTAssertEqual(model.retryButtonTitle, "Try Again")
    }

    func testRetryUsesSameFactoryAndPublishesItsSuccessfulContainer() throws {
        let expectedContainer = try AppModelContainer.make(inMemory: true)
        var attempts = 0
        let model = AppLaunchModel {
            attempts += 1
            if attempts == 1 {
                throw TestError.storeUnavailable
            }
            return expectedContainer
        }

        XCTAssertNil(model.container)
        XCTAssertEqual(attempts, 1)

        model.retry()

        XCTAssertTrue(model.container === expectedContainer)
        XCTAssertEqual(attempts, 2)
    }
}
