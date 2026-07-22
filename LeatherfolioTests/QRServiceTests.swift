import XCTest
@testable import Leatherfolio

final class QRServiceTests: XCTestCase {

    func testPayloadRoundTrip() {
        let id = UUID()
        let payload = QRService.payload(for: id)
        XCTAssertEqual(payload, "leatherfolio://item/\(id.uuidString)")
        XCTAssertEqual(QRService.itemID(fromPayload: payload), id)
    }

    func testParseIsCaseInsensitiveOnSchemeAndUUID() {
        let id = UUID(uuidString: "D9E0A2C4-1B7F-4E30-9A5C-2F6B8D1E4A7C")!
        XCTAssertEqual(
            QRService.itemID(fromPayload: "LEATHERFOLIO://item/d9e0a2c4-1b7f-4e30-9a5c-2f6b8d1e4a7c"),
            id)
    }

    func testRejectsGarbage() {
        XCTAssertNil(QRService.itemID(fromPayload: ""))
        XCTAssertNil(QRService.itemID(fromPayload: "not a url at all"))
        XCTAssertNil(QRService.itemID(fromPayload: "012345678905"))  // retail UPC digits
    }

    func testRejectsNonLeatherfolioURLs() {
        XCTAssertNil(QRService.itemID(fromPayload: "https://example.com/item/\(UUID().uuidString)"))
        XCTAssertNil(QRService.itemID(fromPayload: "otherapp://item/\(UUID().uuidString)"))
        XCTAssertNil(QRService.itemID(fromPayload: "leatherfolio://tag/\(UUID().uuidString)"))
    }

    func testRejectsBadUUIDs() {
        XCTAssertNil(QRService.itemID(fromPayload: "leatherfolio://item/not-a-uuid"))
        XCTAssertNil(QRService.itemID(fromPayload: "leatherfolio://item/"))
        XCTAssertNil(QRService.itemID(fromPayload: "leatherfolio://item/\(UUID().uuidString)/extra"))
    }

    func testQRImageGeneratedAtRequestedScale() throws {
        let image = try XCTUnwrap(QRService.qrImage(for: UUID(), scale: 8))
        let cgImage = try XCTUnwrap(image.cgImage)
        // Smallest QR is 21 modules; CIQRCodeGenerator output scaled 8x must be
        // at least 21 * 8 px on a side.
        XCTAssertGreaterThanOrEqual(cgImage.width, 21 * 8)
        XCTAssertEqual(cgImage.width, cgImage.height, "QR is square")
    }
}
