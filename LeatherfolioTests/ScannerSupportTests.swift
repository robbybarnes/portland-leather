import XCTest
import Vision
@testable import Leatherfolio

final class ScannerSupportTests: XCTestCase {

    func testQRSymbologiesMapToIsQRTrue() {
        XCTAssertTrue(ScannerSupport.isQR(.qr))
        XCTAssertTrue(ScannerSupport.isQR(.microQR))
    }

    func testRetailSymbologiesMapToIsQRFalse() {
        XCTAssertFalse(ScannerSupport.isQR(.ean13))
        XCTAssertFalse(ScannerSupport.isQR(.ean8))
        XCTAssertFalse(ScannerSupport.isQR(.upce))
        XCTAssertFalse(ScannerSupport.isQR(.code128))
        XCTAssertFalse(ScannerSupport.isQR(.code39))
        XCTAssertFalse(ScannerSupport.isQR(.itf14))
        XCTAssertFalse(ScannerSupport.isQR(.dataMatrix))
        XCTAssertFalse(ScannerSupport.isQR(.aztec))
        XCTAssertFalse(ScannerSupport.isQR(.pdf417))
    }
}
