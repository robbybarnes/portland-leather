import Foundation

enum ScanRoute: Equatable {
    case existingItem(UUID)                      // QR matched an item in the store
    case newItem(code: String, isQR: Bool)       // unknown QR or any barcode → add flow, code attached
}

enum ScanRouter {
    static func route(payload: String, isQR: Bool, existingItemIDs: Set<UUID>) -> ScanRoute {
        if isQR,
           let id = QRService.itemID(fromPayload: payload),
           existingItemIDs.contains(id) {
            return .existingItem(id)
        }
        return .newItem(code: payload, isQR: isQR)
    }
}
