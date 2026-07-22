import XCTest
import Vision
import VisionKit
import AVFoundation
@testable import Leatherfolio

@MainActor
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

    func testAvailabilityDistinguishesPermissionUnsupportedAndTemporaryStates() {
        XCTAssertEqual(
            ScannerSupport.availability(
                isSupported: true,
                isAvailable: false,
                authorizationStatus: .denied),
            .permissionDeniedOrRestricted)
        XCTAssertEqual(
            ScannerSupport.availability(
                isSupported: true,
                isAvailable: false,
                authorizationStatus: .restricted),
            .permissionDeniedOrRestricted)
        XCTAssertEqual(
            ScannerSupport.availability(
                isSupported: false,
                isAvailable: false,
                authorizationStatus: .denied),
            .unsupportedHardware)
        XCTAssertEqual(
            ScannerSupport.availability(
                isSupported: true,
                isAvailable: false,
                authorizationStatus: .authorized),
            .temporarilyUnavailable)
        XCTAssertEqual(
            ScannerSupport.availability(
                isSupported: true,
                isAvailable: true,
                authorizationStatus: .authorized),
            .ready)
    }

    func testOnlyPermissionFallbackOffersSettings() throws {
        XCTAssertTrue(try XCTUnwrap(ScannerAvailability.permissionDeniedOrRestricted.fallback).showsSettings)
        XCTAssertFalse(try XCTUnwrap(ScannerAvailability.unsupportedHardware.fallback).showsSettings)
        XCTAssertFalse(try XCTUnwrap(ScannerAvailability.temporarilyUnavailable.fallback).showsSettings)
        XCTAssertFalse(try XCTUnwrap(ScannerAvailability.runtimeError("Camera interrupted").fallback).showsSettings)
    }

    func testUnsupportedFallbackDoesNotSuggestChangingPermission() throws {
        let fallback = try XCTUnwrap(ScannerAvailability.unsupportedHardware.fallback)
        XCTAssertFalse(fallback.message.localizedCaseInsensitiveContains("permission"))
        XCTAssertTrue(fallback.message.localizedCaseInsensitiveContains("not supported"))
    }

    func testRuntimeFallbackKeepsFailureDetail() throws {
        let fallback = try XCTUnwrap(ScannerAvailability.runtimeError("Camera interrupted").fallback)
        XCTAssertTrue(fallback.message.contains("Camera interrupted"))
    }

    func testResultGateStopsAndDeliversOnlyFirstSuccess() {
        var results: [ScannerResult] = []
        var stopCount = 0
        let gate = ScannerResultGate { results.append($0) }

        gate.deliver(.scan(payload: "first", isQR: true)) { stopCount += 1 }
        gate.deliver(.scan(payload: "second", isQR: false)) { stopCount += 1 }
        gate.deliver(.failure(message: "late failure")) { stopCount += 1 }

        XCTAssertEqual(results, [.scan(payload: "first", isQR: true)])
        XCTAssertEqual(stopCount, 1)
    }

    func testResultGateStopsAndDeliversOnlyFirstFailure() {
        var results: [ScannerResult] = []
        var stopCount = 0
        let gate = ScannerResultGate { results.append($0) }

        gate.deliver(.failure(message: "Start failed")) { stopCount += 1 }
        gate.deliver(.failure(message: "Delegate failed")) { stopCount += 1 }
        gate.deliver(.scan(payload: "late", isQR: true)) { stopCount += 1 }

        XCTAssertEqual(results, [.failure(message: "Start failed")])
        XCTAssertEqual(stopCount, 1)
    }

    func testCoordinatorPropagatesConcreteUnavailableDelegateCallback() {
        var failureMessages: [String] = []
        let coordinator = ScannerView.Coordinator(
            onScan: { _, _ in XCTFail("Unavailable callback must not scan") },
            onFailure: { failureMessages.append($0) })
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode()])
        let delegate: any DataScannerViewControllerDelegate = coordinator

        delegate.dataScanner(scanner, becameUnavailableWithError: .cameraRestricted)

        XCTAssertEqual(failureMessages.count, 1)
    }
}
