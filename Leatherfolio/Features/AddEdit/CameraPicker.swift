import SwiftUI
import UIKit

/// UIImagePickerController wrapper for camera capture. The simulator has no
/// camera, so this path can only be exercised on hardware — see the manual
/// device-test note at the end of this task. Callers must check
/// UIImagePickerController.isSourceTypeAvailable(.camera) before presenting
/// (AddEditItemView hides the button otherwise).
struct CameraPicker: UIViewControllerRepresentable {
    enum CaptureError: Error { case encodingFailed }

    let onCapture: (Result<Data, Error>) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate,
                             UINavigationControllerDelegate {
        private let parent: CameraPicker

        init(_ parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage,
               let data = image.jpegData(compressionQuality: 0.9) {
                parent.onCapture(.success(data))
            } else {
                parent.onCapture(.failure(CaptureError.encodingFailed))
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
