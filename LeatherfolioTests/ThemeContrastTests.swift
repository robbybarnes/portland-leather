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

    // MARK: Light mode — Cognac Gallery (text on Cream #F4F2ED / Parchment #FFFFFF)

    func testLightModeTextPairsMeetAA() {
        XCTAssertGreaterThanOrEqual(contrast(0x221C18, 0xF4F2ED), 4.5, "Espresso on Cream")
        XCTAssertGreaterThanOrEqual(contrast(0x786A5C, 0xF4F2ED), 4.5, "Nutmeg on Cream")
        XCTAssertGreaterThanOrEqual(contrast(0x9A4A27, 0xF4F2ED), 4.5, "Cognac on Cream")
        XCTAssertGreaterThanOrEqual(contrast(0x2E7D4F, 0xF4F2ED), 4.5, "Gain on Cream")
        XCTAssertGreaterThanOrEqual(contrast(0xB3372F, 0xF4F2ED), 4.5, "Loss on Cream")
        XCTAssertGreaterThanOrEqual(contrast(0x221C18, 0xFFFFFF), 4.5, "Espresso on Parchment")
        XCTAssertGreaterThanOrEqual(contrast(0x786A5C, 0xFFFFFF), 4.5, "Nutmeg on Parchment")
    }

    // MARK: Dark mode — Cognac Gallery (text on Cream-dark #131110 / Parchment-dark #1F1B18)

    func testDarkModeTextPairsMeetAA() {
        XCTAssertGreaterThanOrEqual(contrast(0xF1EBE3, 0x131110), 4.5, "Espresso on Cream")
        XCTAssertGreaterThanOrEqual(contrast(0xB4A594, 0x131110), 4.5, "Nutmeg on Cream")
        XCTAssertGreaterThanOrEqual(contrast(0xCE7E48, 0x131110), 4.5, "Cognac on Cream")
        XCTAssertGreaterThanOrEqual(contrast(0x5FBF8A, 0x131110), 4.5, "Gain on Cream")
        XCTAssertGreaterThanOrEqual(contrast(0xE07A6E, 0x131110), 4.5, "Loss on Cream")
        XCTAssertGreaterThanOrEqual(contrast(0xF1EBE3, 0x1F1B18), 4.5, "Espresso on Parchment")
        XCTAssertGreaterThanOrEqual(contrast(0xB4A594, 0x1F1B18), 4.5, "Nutmeg on Parchment")
    }

    // MARK: Asset catalog

    func testAssetCatalogColorsResolve() {
        for name in ["Cream", "Parchment", "Espresso", "Nutmeg", "Cognac", "Gain", "Loss"] {
            XCTAssertNotNil(UIColor(named: name), "Missing colorset: \(name)")
        }
    }
}
