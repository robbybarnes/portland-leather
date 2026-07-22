import XCTest
@testable import Leatherfolio

@MainActor
final class AddEditItemModelScanTests: XCTestCase {

    func testRetailBarcodePrefillsUPC() {
        let model = AddEditItemModel(item: nil)
        model.applyScanPrefill(code: "012345678905", isQR: false)
        XCTAssertEqual(model.upc, "012345678905")
        XCTAssertEqual(model.notes, "", "retail codes go to upc, not notes")
    }

    func testUnknownQRAttachesCodeToNotesNotUPC() {
        let model = AddEditItemModel(item: nil)
        let payload = QRService.payload(for: UUID())
        model.applyScanPrefill(code: payload, isQR: true)
        XCTAssertEqual(model.upc, "", "QR payloads are not UPCs")
        XCTAssertEqual(model.notes, "Scanned code: \(payload)")
    }

    func testQRPrefillAppendsToExistingNotes() {
        let model = AddEditItemModel(item: nil)
        model.notes = "Bought at the tannery sale"
        model.applyScanPrefill(code: "some-qr-content", isQR: true)
        XCTAssertEqual(model.notes, "Bought at the tannery sale\nScanned code: some-qr-content")
    }
}
