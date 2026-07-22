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

    /// Parses leatherfolio://item/<uuid>.
    /// Phase 3 seam: replace ONLY the guard's parsing with
    /// QRService.itemID(fromPayload: url.absoluteString) once QRService
    /// exists. Accepted format and rejections must stay identical —
    /// AppRouterTests pins that behavior.
    func handle(url: URL) {
        guard url.scheme == "leatherfolio",
              url.host() == "item",
              let itemID = UUID(uuidString: url.lastPathComponent) else {
            return
        }
        open(itemID: itemID)
    }
}
