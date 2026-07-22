import XCTest
import UIKit
@testable import Leatherfolio

/// Executable proof that the chosen palette meets WCAG AA (4.5:1) for every
/// text-on-background pair, and that every colorset exists in the asset
/// catalog. Hex values here are the palette's source of truth alongside the
/// colorset JSON — keep them in sync.
final class ThemeContrastTests: XCTestCase {
    // MARK: WCAG math

    private func luminance(_ hex: UInt32) -> Double {
        func channel(_ v: UInt32) -> Double {
            let c = Double(v) / 255.0
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel((hex >> 16) & 0xFF)
             + 0.7152 * channel((hex >> 8) & 0xFF)
             + 0.0722 * channel(hex & 0xFF)
    }

    private func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let (l1, l2) = (luminance(a), luminance(b))
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    // MARK: Light mode (text on Cream #F7F2E9 / Parchment #FFFBF4)

    func testLightModeTextPairsMeetAA() {
        XCTAssertGreaterThanOrEqual(contrast(0x3B2A20, 0xF7F2E9), 4.5, "Espresso on Cream")
        XCTAssertGreaterThanOrEqual(contrast(0x6E5138, 0xF7F2E9), 4.5, "Nutmeg on Cream")
        XCTAssertGreaterThanOrEqual(contrast(0x8A4B2A, 0xF7F2E9), 4.5, "Cognac on Cream")
        XCTAssertGreaterThanOrEqual(contrast(0x2E7D4F, 0xF7F2E9), 4.5, "Gain on Cream")
        XCTAssertGreaterThanOrEqual(contrast(0xB3372F, 0xF7F2E9), 4.5, "Loss on Cream")
        XCTAssertGreaterThanOrEqual(contrast(0x3B2A20, 0xFFFBF4), 4.5, "Espresso on Parchment")
        XCTAssertGreaterThanOrEqual(contrast(0x6E5138, 0xFFFBF4), 4.5, "Nutmeg on Parchment")
    }

    // MARK: Dark mode (text on Cream-dark #1E1A16 / Parchment-dark #2A241E)

    func testDarkModeTextPairsMeetAA() {
        XCTAssertGreaterThanOrEqual(contrast(0xF1E9DC, 0x1E1A16), 4.5, "Espresso on Cream")
        XCTAssertGreaterThanOrEqual(contrast(0xC4B29E, 0x1E1A16), 4.5, "Nutmeg on Cream")
        XCTAssertGreaterThanOrEqual(contrast(0xD08A5A, 0x1E1A16), 4.5, "Cognac on Cream")
        XCTAssertGreaterThanOrEqual(contrast(0x5FBF8A, 0x1E1A16), 4.5, "Gain on Cream")
        XCTAssertGreaterThanOrEqual(contrast(0xE07A6E, 0x1E1A16), 4.5, "Loss on Cream")
        XCTAssertGreaterThanOrEqual(contrast(0xF1E9DC, 0x2A241E), 4.5, "Espresso on Parchment")
        XCTAssertGreaterThanOrEqual(contrast(0xC4B29E, 0x2A241E), 4.5, "Nutmeg on Parchment")
    }

    // MARK: Asset catalog

    func testAssetCatalogColorsResolve() {
        for name in ["Cream", "Parchment", "Espresso", "Nutmeg", "Cognac", "Gain", "Loss"] {
            XCTAssertNotNil(UIColor(named: name), "Missing colorset: \(name)")
        }
    }
}
