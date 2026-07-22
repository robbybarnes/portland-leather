import SwiftData
import SwiftUI
import XCTest
@testable import Leatherfolio

@MainActor
final class AppRootLifecycleTests: XCTestCase {
    func testRootReconstructionLazilyCreatesOneRetainedStoreOwner() throws {
        let expectedContainer = try AppModelContainer.make(inMemory: true)
        var factoryCalls = 0
        let factory: AppLaunchModel.ContainerFactory = {
            factoryCalls += 1
            return expectedContainer
        }

        let initialRoot = AppRootView(containerFactory: factory)
        let reconstructedRoot = AppRootView(containerFactory: factory)

        XCTAssertEqual(
            factoryCalls,
            0,
            "Constructing replaceable SwiftUI view values must not open the store")

        let host = UIHostingController(rootView: initialRoot)
        let frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let window = UIWindow(frame: frame)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = frame
        host.view.layoutIfNeeded()
        XCTAssertEqual(factoryCalls, 1)

        host.rootView = reconstructedRoot
        host.view.layoutIfNeeded()

        XCTAssertEqual(
            factoryCalls,
            1,
            "Reconstructing the same root identity must retain its store owner")

        window.isHidden = true
    }
}
