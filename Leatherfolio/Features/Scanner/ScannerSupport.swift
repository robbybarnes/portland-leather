import Vision
import VisionKit
import AVFoundation

struct ScannerFallback: Equatable {
    let title: String
    let message: String
    let showsSettings: Bool
}

enum ScannerAvailability: Equatable {
    case ready
    case permissionDeniedOrRestricted
    case unsupportedHardware
    case temporarilyUnavailable
    case runtimeError(String)

    var fallback: ScannerFallback? {
        switch self {
        case .ready:
            nil
        case .permissionDeniedOrRestricted:
            ScannerFallback(
                title: "Camera Access Needed",
                message: "Allow Leatherfolio to use the camera in Settings to scan QR and barcode labels.",
                showsSettings: true)
        case .unsupportedHardware:
            ScannerFallback(
                title: "Scanning Not Supported",
                message: "QR and barcode scanning is not supported on this device.",
                showsSettings: false)
        case .temporarilyUnavailable:
            ScannerFallback(
                title: "Camera Temporarily Unavailable",
                message: "The camera is currently unavailable. Close other camera apps and try again.",
                showsSettings: false)
        case .runtimeError(let detail):
            ScannerFallback(
                title: "Scanning Stopped",
                message: "Scanning stopped because of a camera error: \(detail)",
                showsSettings: false)
        }
    }
}

enum ScannerResult: Equatable {
    case scan(payload: String, isQR: Bool)
    case failure(message: String)
}

/// One terminal result owns the scanner: it stops capture before delivering
/// either a code or an error, and ignores all later callbacks.
@MainActor
final class ScannerResultGate {
    private let onResult: (ScannerResult) -> Void
    private var hasDelivered = false

    init(onResult: @escaping (ScannerResult) -> Void) {
        self.onResult = onResult
    }

    func deliver(_ result: ScannerResult, stopScanning: () -> Void) {
        guard !hasDelivered else { return }
        hasDelivered = true
        stopScanning()
        onResult(result)
    }
}

/// Defers a startup error beyond representable construction so its callback
/// can safely update SwiftUI state on a later MainActor turn.
@MainActor
enum ScannerStartupFailureDelivery {
    @discardableResult
    static func schedule(
        _ delivery: @escaping @MainActor () -> Void
    ) -> Task<Void, Never> {
        Task { @MainActor in
            await Task.yield()
            delivery()
        }
    }
}

/// Pure, unit-testable helpers around VisionKit scanning.
enum ScannerSupport {
    @MainActor static var currentAvailability: ScannerAvailability {
        availability(
            isSupported: DataScannerViewController.isSupported,
            isAvailable: DataScannerViewController.isAvailable,
            authorizationStatus: AVCaptureDevice.authorizationStatus(for: .video))
    }

    static func availability(
        isSupported: Bool,
        isAvailable: Bool,
        authorizationStatus: AVAuthorizationStatus
    ) -> ScannerAvailability {
        guard isSupported else { return .unsupportedHardware }
        if authorizationStatus == .denied || authorizationStatus == .restricted {
            return .permissionDeniedOrRestricted
        }
        guard isAvailable else { return .temporarilyUnavailable }
        return .ready
    }

    /// Symbology → "is this a QR-family code?" mapping. QR-family codes are the
    /// only ones that can carry the leatherfolio:// self-label payload; every
    /// other symbology is treated as a retail barcode (UPC capture path).
    static func isQR(_ symbology: VNBarcodeSymbology) -> Bool {
        symbology == .qr || symbology == .microQR
    }
}
