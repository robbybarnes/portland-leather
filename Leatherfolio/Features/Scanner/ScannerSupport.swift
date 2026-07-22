import Vision
import VisionKit

/// Pure, unit-testable helpers around VisionKit scanning.
enum ScannerSupport {
    /// True when the device can scan right now (hardware support AND camera
    /// permission not denied). False in the simulator and when access is denied.
    @MainActor static var isReady: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    /// Symbology → "is this a QR-family code?" mapping. QR-family codes are the
    /// only ones that can carry the leatherfolio:// self-label payload; every
    /// other symbology is treated as a retail barcode (UPC capture path).
    static func isQR(_ symbology: VNBarcodeSymbology) -> Bool {
        symbology == .qr || symbology == .microQR
    }
}
