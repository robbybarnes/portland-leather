import XCTest
import SwiftUI
import SwiftData
@testable import Leatherfolio

/// Lightweight rendering smoke test: the math is covered by Phase 2's
/// CollectionStats tests; this just proves StatsView renders real stats
/// without crashing (bad ForEach IDs, force unwraps, Chart misuse).
@MainActor
final class StatsViewRenderTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        container = try AppModelContainer.make(inMemory: true)
        context = container.mainContext
    }

    override func tearDown() {
        context = nil
        container = nil
    }

    func testStatsViewRendersWithoutCrashing() throws {
        let tote = Item()
        tote.name = "Willow Tote"
        tote.category = .tote
        tote.color = "Honey"
        tote.leatherType = .smooth
        tote.myCost = Decimal(180)
        tote.estimatedValue = Decimal(220)
        tote.rating = 4
        context.insert(tote)

        let wallet = Item()
        wallet.name = "Luxe Wallet"
        wallet.category = .wallet
        wallet.isUnicorn = true
        context.insert(wallet)

        let stats = CollectionStats(items: [tote, wallet], catalog: .shared)
        let renderer = ImageRenderer(
            content: StatsView(stats: stats).frame(width: 390, height: 1400)
        )
        XCTAssertNotNil(renderer.uiImage, "StatsView failed to render")
    }

    func testStatsViewRendersEmptyCollection() throws {
        let stats = CollectionStats(items: [], catalog: .shared)
        let renderer = ImageRenderer(
            content: StatsView(stats: stats).frame(width: 390, height: 800)
        )
        XCTAssertNotNil(renderer.uiImage)
    }
}
