import XCTest
import SwiftData
@testable import Leatherfolio

@MainActor
final class AddEditItemModelCatalogTests: XCTestCase {

    private func fixtureCatalog() -> CatalogSeed {
        let json = """
        [
          {"name": "Test Tote", "category": "Tote", "sizes": ["Small", "Large"],
           "colors": ["Honey", "Black"], "leatherTypes": ["Smooth", "Pebbled"]},
          {"name": "Test Wallet", "category": "Wallet", "sizes": [],
           "colors": ["Plum"], "leatherTypes": ["Smooth"]}
        ]
        """
        return CatalogSeed(data: Data(json.utf8))
    }

    private func makeModel() -> AddEditItemModel {
        let model = AddEditItemModel(item: nil)
        model.catalog = fixtureCatalog()
        return model
    }

    func testLineOptionsFilterByCategory() {
        let model = makeModel()
        model.category = .tote
        XCTAssertEqual(model.lineOptions.map(\.name), ["Test Tote"])
        model.category = .wallet
        XCTAssertEqual(model.lineOptions.map(\.name), ["Test Wallet"])
        model.category = .backpack
        XCTAssertTrue(model.lineOptions.isEmpty)
    }

    func testSelectingLineUpdatesOptionArraysAndPrefillsName() {
        let model = makeModel()
        model.category = .tote
        model.selectLine(model.catalog.line(named: "Test Tote"))
        XCTAssertEqual(model.selectedLineName, "Test Tote")
        XCTAssertEqual(model.name, "Test Tote", "empty name is prefilled from the line")
        XCTAssertEqual(model.sizeOptions, ["Small", "Large"])
        XCTAssertEqual(model.colorOptions, ["Honey", "Black"])
        XCTAssertEqual(model.leatherTypeOptions, [.smooth, .pebbled])
    }

    func testSelectingLineDoesNotClobberUserTypedName() {
        let model = makeModel()
        model.category = .tote
        model.name = "My honeymoon bag"
        model.selectLine(model.catalog.line(named: "Test Tote"))
        XCTAssertEqual(model.name, "My honeymoon bag")
    }

    func testSelectingLineClearsIncompatibleChoices() {
        let model = makeModel()
        model.category = .tote
        model.size = "Jumbo"
        model.color = "Honey"
        model.leatherType = .suede
        model.selectLine(model.catalog.line(named: "Test Tote"))
        XCTAssertEqual(model.size, "", "size not offered by the line is cleared")
        XCTAssertEqual(model.color, "Honey", "compatible color survives")
        XCTAssertNil(model.leatherType, "leather type not offered by the line is cleared")
    }

    func testCategoryChangeDeselectsMismatchedLine() {
        let model = makeModel()
        model.category = .tote
        model.selectLine(model.catalog.line(named: "Test Tote"))
        model.category = .wallet
        model.categoryDidChange()
        XCTAssertNil(model.selectedLineName)
        XCTAssertTrue(model.sizeOptions.isEmpty, "no line selected → free-text pickers")
    }

    func testNoLineSelectedYieldsEmptyOptions() {
        let model = makeModel()
        model.category = .tote
        XCTAssertTrue(model.sizeOptions.isEmpty)
        XCTAssertTrue(model.colorOptions.isEmpty)
        XCTAssertTrue(model.leatherTypeOptions.isEmpty)
    }

    func testFreeTextPathStillSaves() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = container.mainContext
        let model = makeModel()
        model.category = .other
        model.name = "One-off Sample Bag"
        model.color = "Custom Teal"      // not in any catalog line
        model.size = "Bespoke"
        try model.save(in: context)
        let items = try context.fetch(FetchDescriptor<Item>())
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.name, "One-off Sample Bag")
        XCTAssertEqual(items.first?.color, "Custom Teal")
        XCTAssertEqual(items.first?.size, "Bespoke")
    }
}
