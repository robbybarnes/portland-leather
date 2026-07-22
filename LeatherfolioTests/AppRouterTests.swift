import XCTest
import Foundation
@testable import Leatherfolio

@MainActor
final class AppRouterTests: XCTestCase {

    func testOpenItemIDAppendsToPath() {
        let router = AppRouter()
        XCTAssertEqual(router.path.count, 0)
        router.open(itemID: UUID())
        XCTAssertEqual(router.path.count, 1)
    }

    func testHandleValidDeepLinkOpensItem() throws {
        let router = AppRouter()
        let id = UUID()
        let url = try XCTUnwrap(URL(string: "leatherfolio://item/\(id.uuidString)"))
        router.handle(url: url)
        XCTAssertEqual(router.path.count, 1)
    }

    func testHandleLowercasedUUIDStillParses() throws {
        let router = AppRouter()
        let lowered = UUID().uuidString.lowercased()
        let url = try XCTUnwrap(URL(string: "leatherfolio://item/\(lowered)"))
        router.handle(url: url)
        XCTAssertEqual(router.path.count, 1)
    }

    func testHandleUsesQRServiceCaseInsensitiveSchemeAndHostContract() throws {
        let router = AppRouter()
        let id = UUID()
        let url = try XCTUnwrap(URL(string: "LEATHERFOLIO://ITEM/\(id.uuidString)"))
        router.handle(url: url)
        XCTAssertEqual(router.path.count, 1)
    }

    func testHandleRejectsExtraPathComponents() throws {
        let router = AppRouter()
        let id = UUID()
        let url = try XCTUnwrap(URL(string: "leatherfolio://item/archive/\(id.uuidString)"))
        router.handle(url: url)
        XCTAssertEqual(router.path.count, 0)
    }

    func testHandleRejectsWrongScheme() throws {
        let router = AppRouter()
        let url = try XCTUnwrap(URL(string: "https://item/\(UUID().uuidString)"))
        router.handle(url: url)
        XCTAssertEqual(router.path.count, 0)
    }

    func testHandleRejectsWrongHost() throws {
        let router = AppRouter()
        let url = try XCTUnwrap(URL(string: "leatherfolio://tag/\(UUID().uuidString)"))
        router.handle(url: url)
        XCTAssertEqual(router.path.count, 0)
    }

    func testHandleRejectsMalformedUUID() throws {
        let router = AppRouter()
        let url = try XCTUnwrap(URL(string: "leatherfolio://item/not-a-uuid"))
        router.handle(url: url)
        XCTAssertEqual(router.path.count, 0)
    }
}
