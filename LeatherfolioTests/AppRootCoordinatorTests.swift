import Foundation
import SwiftData
import XCTest
@testable import Leatherfolio

@MainActor
final class AppRootCoordinatorTests: XCTestCase {
    private enum TestError: Error {
        case storeUnavailable
    }

    func testDeepLinkReceivedDuringStoreFailureRemainsRoutedAfterRetrySucceeds() throws {
        let expectedContainer = try AppModelContainer.make(inMemory: true)
        var attempts = 0
        let coordinator = AppRootCoordinator {
            attempts += 1
            if attempts == 1 {
                throw TestError.storeUnavailable
            }
            return expectedContainer
        }
        let itemID = UUID()
        let url = try XCTUnwrap(
            URL(string: "leatherfolio://item/\(itemID.uuidString)"))

        XCTAssertNil(coordinator.container)

        coordinator.handle(url: url)
        XCTAssertEqual(coordinator.router.path.count, 1)

        coordinator.retry()

        XCTAssertTrue(coordinator.container === expectedContainer)
        XCTAssertEqual(coordinator.router.path.count, 1)
        XCTAssertEqual(attempts, 2)
    }
}
