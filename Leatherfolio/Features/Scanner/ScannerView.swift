import SwiftUI
import VisionKit

/// SwiftUI wrapper around VisionKit DataScannerViewController.
/// Calls onScan exactly once per recognized code, then stops scanning.
/// Present via ScannerSheet, which guards ScannerSupport.currentAvailability.
struct ScannerView: UIViewControllerRepresentable {
    let onScan: (_ payload: String, _ isQR: Bool) -> Void
    let onFailure: (_ message: String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode()],   // all symbologies: QR + retail
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        do {
            try scanner.startScanning()
        } catch {
            let coordinator = context.coordinator
            ScannerStartupFailureDelivery.schedule {
                coordinator.fail(error, scanner: scanner)
            }
        }
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(
        _ uiViewController: DataScannerViewController,
        coordinator: Coordinator
    ) {
        uiViewController.stopScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan, onFailure: onFailure)
    }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let resultGate: ScannerResultGate

        init(
            onScan: @escaping (String, Bool) -> Void,
            onFailure: @escaping (String) -> Void
        ) {
            resultGate = ScannerResultGate { result in
                switch result {
                case .scan(let payload, let isQR):
                    onScan(payload, isQR)
                case .failure(let message):
                    onFailure(message)
                }
            }
        }

        func dataScanner(_ dataScanner: DataScannerViewController,
                         didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            for case let .barcode(barcode) in addedItems {
                guard let payload = barcode.payloadStringValue, !payload.isEmpty else { continue }
                resultGate.deliver(
                    .scan(
                        payload: payload,
                        isQR: ScannerSupport.isQR(barcode.observation.symbology))) {
                            dataScanner.stopScanning()
                        }
                return
            }
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable
        ) {
            fail(error, scanner: dataScanner)
        }

        func fail(_ error: Error, scanner: DataScannerViewController) {
            resultGate.deliver(.failure(message: error.localizedDescription)) {
                scanner.stopScanning()
            }
        }
    }
}
