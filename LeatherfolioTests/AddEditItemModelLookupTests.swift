import XCTest
@testable import Leatherfolio

@MainActor
final class AddEditItemModelLookupTests: XCTestCase {

    private struct StubLookup: ProductLookupService {
        let info: ProductInfo?
        func lookup(upc: String) async -> ProductInfo? { info }
    }

    func testStubLookupPrefillsNameAndNotes() async {
        let model = AddEditItemModel(item: nil)
        model.lookup = StubLookup(info: ProductInfo(name: "Leather Tote Bag",
                                                    description: "Classic full-grain tote"))
        model.applyScanPrefill(code: "012345678905", isQR: false)
        await model.lookupUPCIfNeeded()
        XCTAssertEqual(model.name, "Leather Tote Bag")
        XCTAssertEqual(model.notes, "Classic full-grain tote")
    }

    func testLookupNeverOverwritesUserInput() async {
        let model = AddEditItemModel(item: nil)
        model.lookup = StubLookup(info: ProductInfo(name: "Leather Tote Bag",
                                                    description: "Classic full-grain tote"))
        model.name = "Mom's bag"
        model.notes = "Gift"
        model.applyScanPrefill(code: "012345678905", isQR: false)
        await model.lookupUPCIfNeeded()
        XCTAssertEqual(model.name, "Mom's bag")
        XCTAssertEqual(model.notes, "Gift")
    }

    func testPartialInfoPrefillsOnlyNonNilFields() async {
        let model = AddEditItemModel(item: nil)
        model.lookup = StubLookup(info: ProductInfo(name: "Leather Tote Bag", description: nil))
        model.applyScanPrefill(code: "012345678905", isQR: false)
        await model.lookupUPCIfNeeded()
        XCTAssertEqual(model.name, "Leather Tote Bag")
        XCTAssertEqual(model.notes, "")
    }

    func testNoOpLookupChangesNothing() async {
        let model = AddEditItemModel(item: nil)   // default lookup is NoOpProductLookup
        model.applyScanPrefill(code: "012345678905", isQR: false)
        await model.lookupUPCIfNeeded()
        XCTAssertEqual(model.name, "")
        XCTAssertEqual(model.notes, "")
        XCTAssertEqual(model.upc, "012345678905", "captured UPC is kept either way")
    }

    func testNoLookupWithoutUPC() async {
        let model = AddEditItemModel(item: nil)
        model.lookup = StubLookup(info: ProductInfo(name: "Ghost", description: "Should not appear"))
        await model.lookupUPCIfNeeded()   // upc is empty
        XCTAssertEqual(model.name, "")
        XCTAssertEqual(model.notes, "")
    }
}
