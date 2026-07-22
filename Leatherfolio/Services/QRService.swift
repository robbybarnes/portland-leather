import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// Payload format: "leatherfolio://item/<uuid-string>"
enum QRService {
    private static let scheme = "leatherfolio"
    private static let host = "item"

    static func payload(for itemID: UUID) -> String {
        "\(scheme)://\(host)/\(itemID.uuidString)"
    }

    static func itemID(fromPayload payload: String) -> UUID? {
        guard let url = URL(string: payload),
              url.scheme?.lowercased() == scheme,
              url.host()?.lowercased() == host,
              url.pathComponents.count == 2   // ["/", "<uuid>"]
        else { return nil }
        return UUID(uuidString: url.pathComponents[1])
    }

    /// Crisp QR: CIFilter output is tiny (1pt per module), so scale it up with
    /// a transform BEFORE rasterizing — never resize the bitmap afterwards.
    static func qrImage(for itemID: UUID, scale: CGFloat) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload(for: itemID).utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
