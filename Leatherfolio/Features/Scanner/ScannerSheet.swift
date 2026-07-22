import SwiftUI

/// Presents the scanner when the device can scan; otherwise an explainer with
/// a Settings link (camera permission) or a plain unsupported message.
struct ScannerSheet: View {
    let onScan: (_ payload: String, _ isQR: Bool) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if ScannerSupport.isReady {
                    ScannerView(onScan: onScan)
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
        ContentUnavailableView {
            Label("Camera Unavailable", systemImage: "camera.fill")
        } description: {
            Text("Scanning needs a device with a camera and permission to use it. Check camera access for Leatherfolio in Settings.")
        } actions: {
            if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                Link("Open Settings", destination: settingsURL)
            }
        }
    }
}
