import SwiftUI
import VisionKit

typealias ScannerStartAction = @MainActor (DataScannerViewController) throws -> Void

/// SwiftUI wrapper around VisionKit DataScannerViewController.
/// Calls onScan exactly once per recognized code, then stops scanning.
/// Present via ScannerSheet, which guards ScannerSupport.currentAvailability.
struct ScannerView: UIViewControllerRepresentable {
    let onScan: (_ payload: String, _ isQR: Bool) -> Void
    let onFailure: (_ message: String) -> Void
    let startAction: ScannerStartAction

    init(
        onScan: @escaping (_ payload: String, _ isQR: Bool) -> Void,
        onFailure: @escaping (_ message: String) -> Void,
        startAction: @escaping ScannerStartAction = { try $0.startScanning() }
    ) {
        self.onScan = onScan
        self.onFailure = onFailure
        self.startAction = startAction
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode()],   // all symbologies: QR + retail
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        _ = start(scanner, coordinator: context.coordinator)
        return scanner
    }

    /// Returns a task only on failure, allowing tests to await the deferred
    /// callback while production keeps VisionKit's concrete start operation.
    @MainActor
    @discardableResult
    func start(
        _ scanner: DataScannerViewController,
        coordinator: Coordinator
    ) -> Task<Void, Never>? {
        do {
            try startAction(scanner)
            return nil
        } catch {
            return ScannerStartupFailureDelivery.schedule {
                coordinator.fail(error, scanner: scanner)
            }
        }
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
