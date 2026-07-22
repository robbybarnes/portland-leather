import XCTest
@testable import Leatherfolio

final class ScanRouterTests: XCTestCase {

    func testQRWithKnownUUIDRoutesToExistingItem() {
        let known = UUID()
        let payload = QRService.payload(for: known)
        let route = ScanRouter.route(payload: payload, isQR: true, existingItemIDs: [known, UUID()])
        XCTAssertEqual(route, .existingItem(known))
    }

    func testQRWithUnknownUUIDRoutesToNewItemKeepingPayload() {
        let payload = QRService.payload(for: UUID())
        let route = ScanRouter.route(payload: payload, isQR: true, existingItemIDs: [UUID()])
        XCTAssertEqual(route, .newItem(code: payload, isQR: true))
    }

    func testForeignQRRoutesToNewItem() {
        let route = ScanRouter.route(payload: "https://example.com/x", isQR: true, existingItemIDs: [])
        XCTAssertEqual(route, .newItem(code: "https://example.com/x", isQR: true))
    }

    func testRetailBarcodeRoutesToNewItemAsNonQR() {
        let route = ScanRouter.route(payload: "012345678905", isQR: false, existingItemIDs: [UUID()])
        XCTAssertEqual(route, .newItem(code: "012345678905", isQR: false))
    }

    func testNonQRPayloadThatLooksLikeOurURLStillGoesToNewItem() {
        // A linear barcode can't carry our QR contract; isQR gates the lookup.
        let known = UUID()
        let payload = QRService.payload(for: known)
        let route = ScanRouter.route(payload: payload, isQR: false, existingItemIDs: [known])
        XCTAssertEqual(route, .newItem(code: payload, isQR: false))
    }
}
