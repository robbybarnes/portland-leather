import SwiftUI
import VisionKit

/// SwiftUI wrapper around VisionKit DataScannerViewController.
/// Calls onScan exactly once per recognized code, then stops scanning.
/// Present via ScannerSheet, which guards ScannerSupport.isReady first.
struct ScannerView: UIViewControllerRepresentable {
    let onScan: (_ payload: String, _ isQR: Bool) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode()],   // all symbologies: QR + retail
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        try? scanner.startScanning()             // throws only when unavailable; sheet guard prevents that
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onScan: (String, Bool) -> Void
        private var hasFired = false

        init(onScan: @escaping (String, Bool) -> Void) {
            self.onScan = onScan
        }

        func dataScanner(_ dataScanner: DataScannerViewController,
                         didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            guard !hasFired else { return }
            for case let .barcode(barcode) in addedItems {
                guard let payload = barcode.payloadStringValue, !payload.isEmpty else { continue }
                hasFired = true
                dataScanner.stopScanning()
                onScan(payload, ScannerSupport.isQR(barcode.observation.symbology))
                return
            }
        }
    }
}
