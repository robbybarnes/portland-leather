import XCTest
@testable import Leatherfolio

@MainActor
final class AddEditItemModelLookupTests: XCTestCase {

    private struct StubLookup: ProductLookupService {
        let info: ProductInfo?
        func lookup(upc: String) async -> ProductInfo? { info }
    }

    private actor SuspendedLookup: ProductLookupService {
        private var requestedUPC: String?
        private var resultContinuation: CheckedContinuation<ProductInfo?, Never>?
        private var requestWaiters: [CheckedContinuation<String, Never>] = []

        func lookup(upc: String) async -> ProductInfo? {
            requestedUPC = upc
            requestWaiters.forEach { $0.resume(returning: upc) }
            requestWaiters.removeAll()
            return await withCheckedContinuation { resultContinuation = $0 }
        }

        func waitForRequest() async -> String {
            if let requestedUPC { return requestedUPC }
            return await withCheckedContinuation { requestWaiters.append($0) }
        }

        func resume(with info: ProductInfo?) {
            resultContinuation?.resume(returning: info)
            resultContinuation = nil
        }
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

    func testLookupIgnoresResultWhenUPCChangesWhileSuspended() async {
        let lookup = SuspendedLookup()
        let model = AddEditItemModel(item: nil)
        model.lookup = lookup
        model.upc = "012345678905"

        let task = Task { await model.lookupUPCIfNeeded() }
        let requestedUPC = await lookup.waitForRequest()
        XCTAssertEqual(requestedUPC, "012345678905")
        model.upc = "999999999999"
        await lookup.resume(with: ProductInfo(name: "Stale Tote", description: "Stale result"))
        await task.value

        XCTAssertEqual(model.name, "")
        XCTAssertEqual(model.notes, "")
        XCTAssertEqual(model.upc, "999999999999")
    }

    func testCancelledLookupDoesNotApplyResult() async {
        let lookup = SuspendedLookup()
        let model = AddEditItemModel(item: nil)
        model.lookup = lookup
        model.upc = "012345678905"

        let task = Task { await model.lookupUPCIfNeeded() }
        _ = await lookup.waitForRequest()
        task.cancel()
        await lookup.resume(with: ProductInfo(name: "Late Tote", description: "Late result"))
        await task.value

        XCTAssertEqual(model.name, "")
        XCTAssertEqual(model.notes, "")
    }
}
