import SwiftUI

/// Presents the scanner when the device can scan; otherwise an explainer with
/// a Settings link (camera permission) or a plain unsupported message.
struct ScannerSheet: View {
    let onScan: (_ payload: String, _ isQR: Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var state = ScannerSheetState()

    private var availability: ScannerAvailability {
        state.availability(base: ScannerSupport.currentAvailability)
    }

    var body: some View {
        NavigationStack {
            Group {
                if availability == .ready {
                    ScannerView(
                        onScan: onScan,
                        onFailure: state.receiveFailure)
                        .ignoresSafeArea()
                } else {
                    unavailableView
                }
            }
            .navigationTitle("Scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var unavailableView: some View {
        let fallback = availability.fallback ?? ScannerFallback(
            title: "Camera Unavailable",
            message: "Scanning is unavailable.",
            showsSettings: false)
        return ContentUnavailableView {
            Label(fallback.title, systemImage: "camera.fill")
        } description: {
            Text(fallback.message)
        } actions: {
            if fallback.showsSettings,
               let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                Link("Open Settings", destination: settingsURL)
            }
        }
    }
}
