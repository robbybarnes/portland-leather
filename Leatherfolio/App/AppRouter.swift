import SwiftUI
import Observation

/// Owns the app's navigation path. Grid taps push UUIDs directly via
/// NavigationLink(value:); deep links come in through handle(url:).
@MainActor
@Observable
final class AppRouter {
    var path = NavigationPath()

    func open(itemID: UUID) {
        path.append(itemID)
    }

    func handle(url: URL) {
        guard let itemID = QRService.itemID(fromPayload: url.absoluteString) else { return }
        open(itemID: itemID)
    }
}
