import XCTest
import SwiftUI
import SwiftData
@testable import Leatherfolio

@MainActor
final class CollectionViewSmokeTests: XCTestCase {

    /// Mirrors CollectionView's @Query(sort: \.createdAt, order: .reverse):
    /// newest items come first.
    func testItemsFetchNewestFirst() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = container.mainContext
        let older = Item()
        older.name = "Older"
        older.createdAt = Date(timeIntervalSinceNow: -3_600)
        let newer = Item()
        newer.name = "Newer"
        context.insert(older)
        context.insert(newer)
        try context.save()

        let descriptor = FetchDescriptor<Item>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        let items = try context.fetch(descriptor)
        XCTAssertEqual(items.map(\.name), ["Newer", "Older"])
    }

    /// UI smoke: the view renders in a hosting controller both empty (empty
    /// state) and populated (grid), without crashing or hanging layout.
    func testCollectionViewRendersEmptyAndPopulated() throws {
        let container = try AppModelContainer.make(inMemory: true)

        let emptyHost = UIHostingController(
            rootView: NavigationStack { CollectionView() }.modelContainer(container))
        emptyHost.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        emptyHost.view.layoutIfNeeded()
        XCTAssertNotNil(emptyHost.view)

        let item = Item()
        item.name = "Honey Tote"
        item.size = "Medium"
        item.color = "Honey"
        item.isUnicorn = true
        item.favorite = true
        container.mainContext.insert(item)
        try container.mainContext.save()

        let gridHost = UIHostingController(
            rootView: NavigationStack { CollectionView() }.modelContainer(container))
        gridHost.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        gridHost.view.layoutIfNeeded()
        XCTAssertNotNil(gridHost.view)
    }
}
