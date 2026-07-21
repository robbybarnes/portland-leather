# Leatherfolio Phase 2–3: Catalog Seed & Scanning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the curated PLG catalog seed with cascading pickers and a tested completeness-stats engine (Phase 2), then QR self-labeling, VisionKit scanning, scan routing, and UPC capture with the v2 lookup seam (Phase 3).

**Architecture:** A bundled `plg_catalog.json` powers a `CatalogSeed` service that feeds cascading pickers in `AddEditItemModel` and a pure `CollectionStats` value type. Scanning wraps VisionKit's `DataScannerViewController` in `ScannerView`; `QRService` (Core Image) generates/parses `leatherfolio://item/<uuid>` payloads; `ScanRouter` maps scans to existing-item navigation or the add flow. `ProductLookupService` is a protocol with a no-op v1 implementation, injected into the add/edit model.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, VisionKit (DataScannerViewController), Core Image (CIFilter.qrCodeGenerator), Vision (VNBarcodeSymbology), XCTest, XcodeGen, xcodebuild. Zero third-party dependencies in the app target.

## Global Constraints

(Copied verbatim from `docs/superpowers/plans/2026-07-20-leatherfolio-master-plan.md`. Every task's requirements implicitly include this section.)

- **iOS deployment target:** 18.0. Swift language mode 6.
- **Bundle ID:** `com.robbybarnes.leatherfolio`. **Display name:** Leatherfolio. **URL scheme:** `leatherfolio`.
- **No third-party dependencies** in the app target. Dev tooling allowed: XcodeGen (via Homebrew), SwiftLint optional.
- **Project generation:** `project.yml` (XcodeGen) is source of truth; `Leatherfolio.xcodeproj` is generated and **gitignored**. Regenerate with `xcodegen generate` after any file add/remove.
- **Build/test loop:** `xcodegen generate && xcodebuild -project Leatherfolio.xcodeproj -scheme Leatherfolio -destination 'platform=iOS Simulator,name=iPhone 16' build` (tests: `test` action, same destination; substitute any available iPhone simulator via `xcrun simctl list devices available`).
- **CloudKit schema rules (every model, every phase):** every property optional or with a default; every relationship optional; no `@Attribute(.unique)`; no `.deny` delete rules. Sync itself stays OFF (`cloudKitDatabase: .none`) until signing exists; do not add the iCloud capability yet.
- **Photos:** never store image bytes in queries/lists. Originals via `@Attribute(.externalStorage)`; grids use `ImageStore` thumbnails only.
- **Money:** `Decimal` everywhere; render with the user's locale currency.
- **Naming/copy:** no "Portland Leather Goods" trademark in app name, bundle ID, or App Store-facing strings; in-app reference data may name product lines (research-permission caveat is in the spec). Scraped data stays in `research/` (repo), curated seed ships as `Leatherfolio/Resources/plg_catalog.json`.
- **Commits:** small, per task, conventional-commit style (`feat:`, `test:`, `chore:`).

## Baseline from Phase 0–1 (what this plan consumes)

Phase 0–1 is complete and committed. This plan assumes exactly the master-plan interfaces plus these Phase 0–1 deliverables:

- The project builds and tests via `xcodegen generate && xcodebuild ... test`. Targets: app `Leatherfolio`, unit tests `LeatherfolioTests` (hosted in the app, so `Bundle.main` inside tests is the app bundle).
- `Leatherfolio/Models/Enums.swift` defines `ItemCategory`, `LeatherType`, `ItemCondition` exactly as in the master plan.
- `Leatherfolio/Models/Item.swift`, `Photo.swift`, `Tag.swift` exactly as in the master plan (`Item.id: UUID`, `name: String`, `category: ItemCategory` accessor, `size: String?`, `color: String?`, `leatherType: LeatherType?`, `myCost/retailCost/estimatedValue: Decimal?`, `rating: Int` 0–5, `upc: String?`, `notes: String?`, `isUnicorn/isWishlist/favorite: Bool`, `valueDelta: Decimal?`).
- `Leatherfolio/Features/AddEdit/AddEditItemModel.swift` — `@Observable @MainActor final class AddEditItemModel` with form fields `name: String`, `category: ItemCategory`, `size: String`, `color: String`, `leatherType: LeatherType?`, `upc: String`, `notes: String` (non-optional strings, `""` = unset; `save(in:)` writes them back to `Item`, mapping `""` → `nil`). It has a documented injection point that reads picker options from CatalogSeed-shaped `[String]` arrays where an empty array means "free-text field". If Phase 0–1 named a field differently (e.g. `itemName` instead of `name`), keep Phase 0–1's name and adapt the code in Tasks 3, 8, and 9 mechanically — do not rename Phase 0–1 code.
- `Leatherfolio/Features/ItemDetail/ItemDetailView.swift` has a "QR label" card that currently renders `item.id.uuidString` as text (replaced in Task 8).
- `Leatherfolio/App/AppRouter.swift` — `@Observable final class AppRouter` with `func open(itemID: UUID)`; `LeatherfolioApp` has `.onOpenURL` that inline-parses `leatherfolio://item/<uuid>` (replaced with `QRService` in Task 8).
- `Leatherfolio/Features/Collection/CollectionView.swift` is the home screen with a `@Query` of items and a toolbar (scan button added in Task 8).

## Shared interfaces this plan produces (copied verbatim from the master plan — do not rename)

```swift
// Leatherfolio/Services/QRService.swift
/// Payload format: "leatherfolio://item/<uuid-string>"
enum QRService {
    static func payload(for itemID: UUID) -> String
    static func itemID(fromPayload payload: String) -> UUID?
    static func qrImage(for itemID: UUID, scale: CGFloat) -> UIImage?
}

// Leatherfolio/Services/ScanRouter.swift
enum ScanRoute: Equatable {
    case existingItem(UUID)                      // QR matched an item in the store
    case newItem(code: String, isQR: Bool)       // unknown QR or any barcode → add flow, code attached
}
enum ScanRouter {
    static func route(payload: String, isQR: Bool, existingItemIDs: Set<UUID>) -> ScanRoute
}

// Leatherfolio/Features/Scanner/ScannerView.swift
/// SwiftUI wrapper around VisionKit DataScannerViewController.
/// Calls onScan exactly once per recognized code, then stops scanning.
struct ScannerView: UIViewControllerRepresentable {
    let onScan: (_ payload: String, _ isQR: Bool) -> Void
}

// Leatherfolio/Services/CatalogSeed.swift  (backed by Resources/plg_catalog.json)
struct CatalogLine: Decodable, Identifiable, Equatable {
    let name: String            // e.g. "Crossbody Tote"
    let category: String        // ItemCategory rawValue
    let sizes: [String]
    let colors: [String]
    let leatherTypes: [String]  // LeatherType rawValues
    var id: String { name }
}
final class CatalogSeed: Sendable {
    static let shared = CatalogSeed()          // loads bundled JSON; never crashes (falls back to [])
    var lines: [CatalogLine] { get }
    func lines(in category: ItemCategory) -> [CatalogLine]
    func line(named name: String) -> CatalogLine?
    var allColors: [String] { get }            // deduped, sorted, across lines
}

// Leatherfolio/Services/ProductLookupService.swift
struct ProductInfo: Equatable { let name: String?; let description: String? }
protocol ProductLookupService: Sendable {
    func lookup(upc: String) async -> ProductInfo?
}
struct NoOpProductLookup: ProductLookupService {   // v1 implementation
    func lookup(upc: String) async -> ProductInfo? { nil }
}
```

## File structure (created/modified by this plan)

| File | Responsibility |
|---|---|
| `Leatherfolio/Resources/plg_catalog.json` | Curated catalog seed (Task 1) |
| `project.yml` | Ensure Resources ship in the app bundle; camera usage string (Tasks 1, 7) |
| `Leatherfolio/Services/CatalogSeed.swift` | Load + query the seed (Task 2) |
| `Leatherfolio/Features/AddEdit/AddEditItemModel.swift` | Cascading picker state, scan prefill, UPC lookup seam (Tasks 3, 8, 9) |
| `Leatherfolio/Features/AddEdit/AddEditItemView.swift` | Picker UI with "Other…" escape hatch (Task 3) |
| `Leatherfolio/Features/AddEdit/OptionPicker.swift` | Reusable picker row + free-text escape hatch (Task 3) |
| `Leatherfolio/Services/CollectionStats.swift` | Pure stats engine (Task 4) |
| `Leatherfolio/Services/QRService.swift` | QR payload + image generation (Task 5) |
| `Leatherfolio/Services/ScanRouter.swift` | Scan → route decision (Task 6) |
| `Leatherfolio/Features/Scanner/ScannerSupport.swift` | Pure symbology/availability helpers (Task 7) |
| `Leatherfolio/Features/Scanner/ScannerView.swift` | VisionKit wrapper (Task 7) |
| `Leatherfolio/Features/Scanner/ScannerSheet.swift` | Availability guard + fallback UI (Task 7) |
| `Leatherfolio/Features/Collection/CollectionView.swift` | Scan toolbar button + routing (Task 8) |
| `Leatherfolio/Features/ItemDetail/ItemDetailView.swift` + `QRLabelSheet.swift` | Real QR label card + export (Task 8) |
| `Leatherfolio/App/LeatherfolioApp.swift` | `.onOpenURL` via QRService (Task 8) |
| `Leatherfolio/Services/ProductLookupService.swift` | Lookup protocol + NoOp (Task 9) |
| `LeatherfolioTests/…` | One test file per task, named in each task |

---
## Phase 2 — Catalog seed, cascading pickers, stats engine

### Task 1: Curate `Leatherfolio/Resources/plg_catalog.json`

**Files:**
- Create: `Leatherfolio/Resources/plg_catalog.json`
- Modify: `project.yml` (resources build phase)

**Interfaces:**
- Consumes: `research/plg_products.json` and `research/plg_catalog_notes.md` (reference only — those files stay in `research/`, they are NOT bundled).
- Produces: the bundled seed file that Task 2's `CatalogSeed` decodes. Top-level JSON shape is a **bare array of line objects**, each with keys `name`, `category`, `sizes`, `colors`, `leatherTypes` (matching `CatalogLine`'s `Decodable` synthesis exactly).

Curation rules applied (already baked into the JSON below — do not re-derive):
- 23 iconic lines chosen from the 37 scraped products; every category the spec requires is represented (Tote, Crossbody Tote, Crossbody, Belt Bag, Backpack, Wallet, Cardholder, Belt, Accessory).
- The Crossbody Tote family (scraped as three separate listings: Mini / Medium / original "Crossbody Tote") is merged into ONE line named `"Crossbody Tote"` with `sizes: ["Mini", "Medium", "Original"]` and colors drawn from the union of the three listings' color lists.
- Scraped category `"Belt Bag / Sling"` maps to ItemCategory rawValue `"Belt Bag"`.
- `leatherTypes` contain ONLY master-plan `LeatherType` rawValues: `"Smooth / Pebbled (varies by colorway)"` → `["Smooth", "Pebbled"]`, `"Smooth / Suede (varies by colorway)"` → `["Smooth", "Suede"]`, `"Smooth / Pebbled / Metallic (varies by colorway)"` → `["Smooth", "Pebbled", "Metallic"]`, `"Smooth / Metallic (varies by colorway)"` → `["Smooth", "Metallic"]`, `"Smooth"` → `["Smooth"]`.
- Ultra-long scraped color lists (some lines had 40–54 colors) are trimmed to ≤ 20 per line, always keeping the staple colors that appear on that line (Honey, Cognac, Nutmeg, Coldbrew, Black, Chestnut, Sienna, Bone, Cobalt, Plum, Sea Glass, Chili Red, Grizzly, Merlot, Orchid, Koi) plus that line's distinctive colorways. Every color value below appears verbatim in that line's scraped data.
- Products with `sizes: null` in the scrape get `sizes: []` (empty = the size picker degrades to free-text).

- [ ] **Step 1: Create the seed file with this exact content**

Create `Leatherfolio/Resources/plg_catalog.json` (create the `Resources` directory if Phase 0–1 did not):

```json
[
  {
    "name": "Leather Tote Bag",
    "category": "Tote",
    "sizes": ["Small", "Medium", "Large", "Oversized"],
    "colors": ["Honey", "Nutmeg", "Meadow", "Cognac", "Black", "Pebbled Black", "Pebbled Bone", "Coldbrew", "Chestnut", "Evergreen", "Westward Blue", "Cobalt", "Stone", "Chili Red", "Merlot", "Mango", "Sea Glass", "Grizzly"],
    "leatherTypes": ["Smooth", "Pebbled"]
  },
  {
    "name": "August Tote",
    "category": "Tote",
    "sizes": ["Medium", "Large"],
    "colors": ["Nutmeg", "Sienna", "Night Owl", "Cobalt", "Plum", "Bacalar", "Black", "Sea Glass", "Coldbrew", "Meadow", "Stone", "Forest Green", "Mango", "Chocolate Brown", "Cosmo", "Koi"],
    "leatherTypes": ["Smooth"]
  },
  {
    "name": "Montana Tote",
    "category": "Tote",
    "sizes": ["Medium", "Large"],
    "colors": ["Honey", "Nutmeg", "Cognac", "Pebbled Black", "Coldbrew", "Asheville", "Phoenix", "Sunshine", "Evergreen", "Sienna", "Cowboy Blue", "Westward Blue", "Mango", "Forest Green", "Stone", "Empire"],
    "leatherTypes": ["Smooth", "Pebbled"]
  },
  {
    "name": "Devan Bucket Tote",
    "category": "Tote",
    "sizes": ["Small", "Large", "Oversized"],
    "colors": ["Black", "Bone", "Grizzly", "Sienna", "Plum", "Bacalar", "Boreal", "Nutmeg", "Sunshine", "Cobalt", "Coldbrew", "Chestnut", "Chili Red", "Orchid", "Koi", "Pink Suede", "Lagoon", "Empire"],
    "leatherTypes": ["Smooth", "Suede"]
  },
  {
    "name": "Crossbody Tote",
    "category": "Crossbody Tote",
    "sizes": ["Mini", "Medium", "Original"],
    "colors": ["Honey", "Cognac", "Nutmeg", "Coldbrew", "Black", "Pebbled Black", "Pebbled Bone", "Bone", "Chestnut", "Sienna", "Cobalt", "Plum", "Meadow", "Chili Red", "Orchid", "Merlot", "Grizzly", "Koi", "Aquarius", "Metallic Greench"],
    "leatherTypes": ["Smooth", "Pebbled", "Metallic"]
  },
  {
    "name": "Lola Crossbody Tote",
    "category": "Crossbody Tote",
    "sizes": [],
    "colors": ["Chocolate Brown", "Grizzly", "Black", "Pebbled Black", "Cognac", "Honey", "Stone", "Nutmeg", "Coldbrew", "Chestnut", "Sea Glass", "Westward Blue", "Phoenix", "Cowboy Blue", "Merlot", "Night Owl"],
    "leatherTypes": ["Smooth", "Pebbled"]
  },
  {
    "name": "Circle Crossbody",
    "category": "Crossbody",
    "sizes": ["Small", "Large"],
    "colors": ["Honey", "Meadow", "Cognac", "Nutmeg", "Coldbrew", "Pebbled Black", "Black", "Bone", "Cobalt", "Boreal", "Chestnut", "Chili Red", "Deep Water", "Aquarius", "Ruby", "Empire"],
    "leatherTypes": ["Smooth", "Pebbled"]
  },
  {
    "name": "Monaco Crossbody",
    "category": "Crossbody",
    "sizes": ["Small", "Large"],
    "colors": ["Madrone", "Orchid", "Chocolate Brown", "Black", "Sienna", "Nutmeg", "Larkspur", "Cobalt", "Chili Red", "Bone", "Moose", "Evergreen", "Boreal", "Wild Rose", "Blue Joy", "Stone", "Wasabi", "Seafoam"],
    "leatherTypes": ["Smooth"]
  },
  {
    "name": "Raindrop Crossbody Bag",
    "category": "Crossbody",
    "sizes": ["Small", "Large"],
    "colors": ["Orchid", "Sienna", "Grizzly", "Lagoon", "Bacalar", "Sunshine", "Evergreen", "Cobalt", "Sea Glass", "Nutmeg", "Honey", "Plum", "Bone", "Pebbled Black", "Coldbrew", "Chestnut", "Ruby", "Night Owl"],
    "leatherTypes": ["Smooth", "Pebbled"]
  },
  {
    "name": "Bucket Bag",
    "category": "Crossbody",
    "sizes": ["Small", "Large"],
    "colors": ["Sienna", "Coldbrew", "Asheville", "Cobalt", "Pebbled Black", "Plum", "Boreal", "Nutmeg", "Shadow Lime", "Bacalar", "Skyway", "Orchid", "Pinkaboo", "Butter Bliss"],
    "leatherTypes": ["Smooth", "Pebbled"]
  },
  {
    "name": "Sally Sling Bag",
    "category": "Belt Bag",
    "sizes": [],
    "colors": ["Cognac", "Coldbrew", "Black", "Sea Glass", "Chili Red", "Molino Blue", "Plum", "Pebbled Bone", "Asheville", "Cactus", "Wild Rose", "Oatmilk"],
    "leatherTypes": ["Smooth", "Pebbled"]
  },
  {
    "name": "Koala Sling Bag",
    "category": "Belt Bag",
    "sizes": ["Small", "Medium", "Large"],
    "colors": ["Meadow", "Nutmeg", "Coldbrew", "Honey", "Pebbled Black", "Sienna", "Bacalar", "Cobalt", "Sunshine", "Chili Red", "Orchid", "Pebbled Bone", "Bone", "Sea Glass", "Metallic Greench", "Cowboy Blue"],
    "leatherTypes": ["Smooth", "Pebbled", "Metallic"]
  },
  {
    "name": "Tote Backpack",
    "category": "Backpack",
    "sizes": ["Small", "Large"],
    "colors": ["Nutmeg", "Sienna", "Honey", "Meadow", "Cognac", "Pebbled Black", "Sea Glass", "Night Owl", "Orchid", "Cobalt", "Lagoon", "Plum", "Black", "Coldbrew", "Chili Red", "Koi"],
    "leatherTypes": ["Smooth", "Pebbled"]
  },
  {
    "name": "Laptop Backpack",
    "category": "Backpack",
    "sizes": [],
    "colors": ["Honey", "Pebbled Black", "Nutmeg", "Molino Blue", "Chili Red", "Night Owl", "Black", "Cognac", "Bacalar", "Forest Green", "Coldbrew", "Orchid", "Cobalt", "Cosmo"],
    "leatherTypes": ["Smooth", "Pebbled"]
  },
  {
    "name": "Women's Bifold Wallet",
    "category": "Wallet",
    "sizes": [],
    "colors": ["Nutmeg", "Coldbrew", "Honey", "Meadow", "Black", "Plum", "Bacalar", "Grizzly", "Koi", "Pebbled Black", "Cognac", "Chestnut", "Boreal", "Deep Water", "Metallic Greench", "Merlot", "Ruby", "English Tan"],
    "leatherTypes": ["Smooth", "Pebbled", "Metallic"]
  },
  {
    "name": "Mini Bifold Wallet",
    "category": "Wallet",
    "sizes": [],
    "colors": ["Meadow", "Honey", "Nutmeg", "Black", "Plum", "Bacalar", "Grizzly", "Metallic Greench", "Koi", "Cognac", "Coldbrew", "Chestnut", "Boreal", "Pebbled Black", "Ruby", "Merlot"],
    "leatherTypes": ["Smooth", "Pebbled", "Metallic"]
  },
  {
    "name": "Small Zip Wallet",
    "category": "Wallet",
    "sizes": [],
    "colors": ["Madrone", "Cognac", "Nutmeg", "Chocolate Brown", "Cobalt", "Pebbled Black", "Sunflower", "Plum", "Chestnut", "Sea Glass", "Orchid", "Coldbrew", "Chili Red", "Honey", "Black", "Grizzly"],
    "leatherTypes": ["Smooth", "Pebbled"]
  },
  {
    "name": "Highlander Card Holder",
    "category": "Cardholder",
    "sizes": ["Classic", "Deluxe"],
    "colors": ["Saddlestone", "Trailstone", "Black Rock", "Red Rock"],
    "leatherTypes": ["Smooth"]
  },
  {
    "name": "Napoli Card Holder",
    "category": "Cardholder",
    "sizes": [],
    "colors": ["Naturale", "Nero", "Marrone", "Toscano"],
    "leatherTypes": ["Smooth"]
  },
  {
    "name": "Women's Legacy Leather Belt",
    "category": "Belt",
    "sizes": ["S", "M", "L", "XL"],
    "colors": ["Amber", "Pecan", "Umber", "Black"],
    "leatherTypes": ["Smooth"]
  },
  {
    "name": "Men's Artisan Leather Belt",
    "category": "Belt",
    "sizes": ["32", "34", "36", "38", "40", "42", "44"],
    "colors": ["Java", "Amber", "Jet Black", "Pecan"],
    "leatherTypes": ["Smooth"]
  },
  {
    "name": "Leather Tassel",
    "category": "Accessory",
    "sizes": ["Classic", "Jumbo"],
    "colors": ["Bacalar", "Orchid", "Cognac", "Honey", "Grizzly", "Pebbled Black", "Cobalt", "Bone", "Chili Red", "Coldbrew", "Black", "Nutmeg", "Chestnut", "Merlot", "Stardust", "Sunflower"],
    "leatherTypes": ["Smooth", "Pebbled"]
  },
  {
    "name": "Makeup Bag",
    "category": "Accessory",
    "sizes": ["Large", "Extra Large"],
    "colors": ["Cognac", "Nutmeg", "Honey", "Black", "Bone", "Sunshine", "Stone", "Cobalt", "Bacalar", "Metallic Greench", "Ruby", "Meadow", "Deep Water", "Pine"],
    "leatherTypes": ["Smooth", "Metallic"]
  }
]
```

- [ ] **Step 2: Validate the JSON parses**

Run: `python3 -m json.tool Leatherfolio/Resources/plg_catalog.json > /dev/null && echo OK`
Expected: `OK`

- [ ] **Step 3: Ensure the file ships in the app bundle via project.yml**

XcodeGen adds `.json` files under a plain `sources:` folder to the resources build phase by default, but make it explicit so a future `sources` refactor can't silently drop the seed. In `project.yml`, change the `Leatherfolio` target's `sources` entry to:

```yaml
targets:
  Leatherfolio:
    # ... existing keys (type, platform, deploymentTarget, settings, info) unchanged ...
    sources:
      - path: Leatherfolio
        excludes:
          - "Resources/**"
      - path: Leatherfolio/Resources
        buildPhase: resources
```

Keep every other key in the target exactly as Phase 0–1 left it.

- [ ] **Step 4: Regenerate and verify the resource lands in the built app**

Run:
```bash
xcodegen generate && xcodebuild -project Leatherfolio.xcodeproj -scheme Leatherfolio -destination 'platform=iOS Simulator,name=iPhone 16' build
find ~/Library/Developer/Xcode/DerivedData -path "*Leatherfolio.app/plg_catalog.json" -newer project.yml
```
(Substitute an available simulator from `xcrun simctl list devices available` if iPhone 16 is missing.)
Expected: build succeeds; `find` prints one path ending in `Leatherfolio.app/plg_catalog.json`.

- [ ] **Step 5: Commit**

```bash
git add Leatherfolio/Resources/plg_catalog.json project.yml
git commit -m "feat: add curated PLG catalog seed (23 lines) bundled as app resource"
```

---
### Task 2: CatalogSeed service

**Files:**
- Create: `Leatherfolio/Services/CatalogSeed.swift`
- Test: `LeatherfolioTests/CatalogSeedTests.swift`

**Interfaces:**
- Consumes: `Leatherfolio/Resources/plg_catalog.json` (Task 1), `ItemCategory` (Phase 0–1).
- Produces: `CatalogLine` and `CatalogSeed` exactly as in the master-plan contract (`shared`, `lines`, `lines(in:)`, `line(named:)`, `allColors`), plus a test-only seam `init(data: Data)`. Tasks 3 and 4 consume these.

- [ ] **Step 1: Write the failing tests**

Create `LeatherfolioTests/CatalogSeedTests.swift`:

```swift
import XCTest
@testable import Leatherfolio

final class CatalogSeedTests: XCTestCase {

    func testSharedDecodesBundledJSON() {
        // Tests are hosted in the app, so Bundle.main resolves the app bundle.
        XCTAssertFalse(CatalogSeed.shared.lines.isEmpty, "bundled plg_catalog.json should decode to non-empty lines")
        XCTAssertGreaterThanOrEqual(CatalogSeed.shared.lines.count, 15)
    }

    func testEveryLineUsesValidCategoryAndLeatherTypeRawValues() {
        for line in CatalogSeed.shared.lines {
            XCTAssertNotNil(ItemCategory(rawValue: line.category),
                            "\(line.name) has invalid category \(line.category)")
            for lt in line.leatherTypes {
                XCTAssertNotNil(LeatherType(rawValue: lt),
                                "\(line.name) has invalid leather type \(lt)")
            }
        }
    }

    func testLinesInToteCategoryNonEmpty() {
        let totes = CatalogSeed.shared.lines(in: .tote)
        XCTAssertFalse(totes.isEmpty)
        XCTAssertTrue(totes.allSatisfy { $0.category == ItemCategory.tote.rawValue })
    }

    func testLineNamedExactMatch() {
        let line = CatalogSeed.shared.line(named: "Crossbody Tote")
        XCTAssertNotNil(line)
        XCTAssertEqual(line?.sizes, ["Mini", "Medium", "Original"])
        XCTAssertNil(CatalogSeed.shared.line(named: "crossbody tote"), "match is exact, not case-insensitive")
        XCTAssertNil(CatalogSeed.shared.line(named: "Nonexistent Bag"))
    }

    func testAllColorsDedupedAndSorted() {
        let colors = CatalogSeed.shared.allColors
        XCTAssertFalse(colors.isEmpty)
        XCTAssertEqual(colors, Array(Set(colors)).sorted(), "allColors must be deduped and sorted")
        XCTAssertTrue(colors.contains("Honey"))
        XCTAssertEqual(colors.filter { $0 == "Nutmeg" }.count, 1, "staple colors appear once despite being on many lines")
    }

    func testMalformedDataFallsBackToEmpty() {
        let malformed = CatalogSeed(data: Data("{ not json".utf8))
        XCTAssertTrue(malformed.lines.isEmpty)
        XCTAssertTrue(malformed.allColors.isEmpty)
        XCTAssertNil(malformed.line(named: "Leather Tote Bag"))
        XCTAssertTrue(malformed.lines(in: .tote).isEmpty)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
xcodegen generate && xcodebuild -project Leatherfolio.xcodeproj -scheme Leatherfolio -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:LeatherfolioTests/CatalogSeedTests
```
(Substitute an available simulator if needed.)
Expected: BUILD FAILS with "cannot find 'CatalogSeed' in scope" (compile error counts as the red step here).

- [ ] **Step 3: Implement CatalogSeed**

Create `Leatherfolio/Services/CatalogSeed.swift`:

```swift
import Foundation

/// One curated product line from the bundled seed (Resources/plg_catalog.json).
struct CatalogLine: Decodable, Identifiable, Equatable {
    let name: String            // e.g. "Crossbody Tote"
    let category: String        // ItemCategory rawValue
    let sizes: [String]
    let colors: [String]
    let leatherTypes: [String]  // LeatherType rawValues
    var id: String { name }
}

/// Loads and queries the bundled catalog seed. Never crashes on missing or
/// malformed data — pickers degrade to free-text when `lines` is empty.
final class CatalogSeed: Sendable {
    static let shared = CatalogSeed()

    let lines: [CatalogLine]

    /// Loads Resources/plg_catalog.json from the app bundle.
    convenience init() {
        let data = Bundle.main.url(forResource: "plg_catalog", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) }
        self.init(data: data ?? Data())
    }

    /// Test seam: decode from raw data; malformed input falls back to [].
    init(data: Data) {
        self.lines = (try? JSONDecoder().decode([CatalogLine].self, from: data)) ?? []
    }

    func lines(in category: ItemCategory) -> [CatalogLine] {
        lines.filter { $0.category == category.rawValue }
    }

    func line(named name: String) -> CatalogLine? {
        lines.first { $0.name == name }
    }

    /// Deduped, sorted union of every line's colors.
    var allColors: [String] {
        Array(Set(lines.flatMap(\.colors))).sorted()
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
xcodegen generate && xcodebuild -project Leatherfolio.xcodeproj -scheme Leatherfolio -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:LeatherfolioTests/CatalogSeedTests
```
Expected: TEST SUCCEEDED, 6 tests pass. If `testSharedDecodesBundledJSON` fails with empty lines, Task 1 Step 3's resources stanza is wrong — fix `project.yml`, not the code.

- [ ] **Step 5: Commit**

```bash
git add Leatherfolio/Services/CatalogSeed.swift LeatherfolioTests/CatalogSeedTests.swift
git commit -m "feat: CatalogSeed service loading bundled plg_catalog.json with empty fallback"
```

---
### Task 3: Cascading pickers in Add/Edit

**Files:**
- Modify: `Leatherfolio/Features/AddEdit/AddEditItemModel.swift` (add the catalog-options section shown below)
- Create: `Leatherfolio/Features/AddEdit/OptionPicker.swift`
- Modify: `Leatherfolio/Features/AddEdit/AddEditItemView.swift` (replace the Phase 0–1 size/color/leather picker rows)
- Test: `LeatherfolioTests/AddEditItemModelCatalogTests.swift`

**Interfaces:**
- Consumes: `CatalogSeed` / `CatalogLine` (Task 2); Phase 0–1 `AddEditItemModel` fields `name/category/size/color/leatherType` and `save(in: ModelContext)`.
- Produces: on `AddEditItemModel` — `var catalog: CatalogSeed`, `var selectedLineName: String?`, `var lineOptions: [CatalogLine]`, `var selectedLine: CatalogLine?`, `var sizeOptions: [String]`, `var colorOptions: [String]`, `var leatherTypeOptions: [LeatherType]`, `func selectLine(_ line: CatalogLine?)`, `func categoryDidChange()`, `func syncSelectedLineFromName()`. Tasks 8 and 9 build on this model. Also `struct OptionPicker: View` for reuse.

- [ ] **Step 1: Write the failing model tests**

Create `LeatherfolioTests/AddEditItemModelCatalogTests.swift`:

```swift
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
        let model = AddEditItemModel()
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
        let container = try ModelContainer(
            for: Item.self, Photo.self, Tag.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let model = makeModel()
        model.category = .other
        model.name = "One-off Sample Bag"
        model.color = "Custom Teal"      // not in any catalog line
        model.size = "Bespoke"
        model.save(in: context)
        let items = try context.fetch(FetchDescriptor<Item>())
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.name, "One-off Sample Bag")
        XCTAssertEqual(items.first?.color, "Custom Teal")
        XCTAssertEqual(items.first?.size, "Bespoke")
    }
}
```

(If Phase 0–1's save method is spelled differently — e.g. `save(to:)` — use Phase 0–1's spelling in this test; do not rename Phase 0–1 code.)

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
xcodegen generate && xcodebuild -project Leatherfolio.xcodeproj -scheme Leatherfolio -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:LeatherfolioTests/AddEditItemModelCatalogTests
```
Expected: BUILD FAILS — `AddEditItemModel` has no member `catalog` / `selectLine`.

- [ ] **Step 3: Add the catalog section to AddEditItemModel**

In `Leatherfolio/Features/AddEdit/AddEditItemModel.swift`, add this block inside the class body (below the existing form fields). This REPLACES Phase 0–1's documented picker-options injection point — delete any placeholder option arrays Phase 0–1 left there:

```swift
    // MARK: - Catalog-driven picker options (Phase 2)

    /// Injection seam: tests assign a CatalogSeed(data:) fixture.
    var catalog: CatalogSeed = .shared

    /// Name of the selected catalog line; nil = free-form item.
    var selectedLineName: String?

    var lineOptions: [CatalogLine] { catalog.lines(in: category) }
    var selectedLine: CatalogLine? { selectedLineName.flatMap { catalog.line(named: $0) } }
    var sizeOptions: [String] { selectedLine?.sizes ?? [] }
    var colorOptions: [String] { selectedLine?.colors ?? [] }
    var leatherTypeOptions: [LeatherType] {
        (selectedLine?.leatherTypes ?? []).compactMap(LeatherType.init(rawValue:))
    }

    /// Select (or deselect with nil) a catalog line. Prefills the name when the
    /// user hasn't typed one (or typed exactly another line's name), and clears
    /// any picker choices the new line doesn't offer.
    func selectLine(_ line: CatalogLine?) {
        selectedLineName = line?.name
        guard let line else { return }
        if name.isEmpty || catalog.line(named: name) != nil {
            name = line.name
        }
        if !size.isEmpty, !line.sizes.contains(size) { size = "" }
        if !color.isEmpty, !line.colors.contains(color) { color = "" }
        if let leatherType, !line.leatherTypes.contains(leatherType.rawValue) {
            self.leatherType = nil
        }
    }

    /// Call after `category` changes: a line from another category can't stay selected.
    func categoryDidChange() {
        if let selectedLine, selectedLine.category != category.rawValue {
            selectLine(nil)
        }
    }

    /// Call when loading an existing item for editing: re-links the line whose
    /// name the item carries so the cascading pickers light up.
    func syncSelectedLineFromName() {
        selectedLineName = catalog.line(named: name)?.name
    }
```

Also: at the end of the existing "load from item" path (the initializer or `configure(with item: Item)` method Phase 0–1 wrote), add one call: `syncSelectedLineFromName()`.

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
xcodegen generate && xcodebuild -project Leatherfolio.xcodeproj -scheme Leatherfolio -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:LeatherfolioTests/AddEditItemModelCatalogTests
```
Expected: TEST SUCCEEDED, 8 tests pass.

- [ ] **Step 5: Create the reusable OptionPicker view**

Create `Leatherfolio/Features/AddEdit/OptionPicker.swift`:

```swift
import SwiftUI

/// A picker row backed by catalog options with an "Other…" escape hatch.
/// - Empty `options` → renders a plain free-text field (seed missing/degraded).
/// - Non-empty → wheel/menu picker with None + options + "Other…"; choosing
///   "Other…" reveals a free-text field bound to the same selection.
struct OptionPicker: View {
    let title: String
    let options: [String]
    @Binding var selection: String   // "" = unset
    @State private var useFreeText = false

    private static let otherTag = "__other__"

    var body: some View {
        if options.isEmpty {
            TextField(title, text: $selection)
                .accessibilityLabel(title)
        } else {
            Picker(title, selection: pickerBinding) {
                Text("None").tag("")
                ForEach(options, id: \.self) { Text($0).tag($0) }
                Text("Other…").tag(Self.otherTag)
            }
            if showsFreeText {
                TextField("Custom \(title.lowercased())", text: $selection)
                    .accessibilityLabel("Custom \(title)")
            }
        }
    }

    private var showsFreeText: Bool {
        useFreeText || (!selection.isEmpty && !options.contains(selection))
    }

    private var pickerBinding: Binding<String> {
        Binding(
            get: {
                if useFreeText { return Self.otherTag }
                if selection.isEmpty { return "" }
                return options.contains(selection) ? selection : Self.otherTag
            },
            set: { newValue in
                if newValue == Self.otherTag {
                    useFreeText = true
                    if options.contains(selection) { selection = "" }
                } else {
                    useFreeText = false
                    selection = newValue
                }
            }
        )
    }
}
```

- [ ] **Step 6: Wire the pickers into AddEditItemView**

In `Leatherfolio/Features/AddEdit/AddEditItemView.swift`, replace Phase 0–1's size/color/leather-type rows with this section (keep the category picker and every other row Phase 0–1 built; `model` below is the view's `@Bindable var model: AddEditItemModel` — use `@State`/property spelling as Phase 0–1 declared it):

```swift
        Section("Catalog") {
            Picker("Line", selection: lineSelection) {
                Text("None").tag(String?.none)
                ForEach(model.lineOptions) { line in
                    Text(line.name).tag(String?.some(line.name))
                }
            }
            OptionPicker(title: "Size", options: model.sizeOptions, selection: $model.size)
            OptionPicker(title: "Color", options: model.colorOptions, selection: $model.color)
            leatherTypeRow
        }
        .onChange(of: model.category) { model.categoryDidChange() }
```

And add these two helpers to the same view struct:

```swift
    private var lineSelection: Binding<String?> {
        Binding(
            get: { model.selectedLineName },
            set: { newName in model.selectLine(newName.flatMap { model.catalog.line(named: $0) }) }
        )
    }

    @ViewBuilder private var leatherTypeRow: some View {
        let options = model.leatherTypeOptions
        Picker("Leather", selection: $model.leatherType) {
            Text("None").tag(LeatherType?.none)
            // Line-restricted options plus Other as the escape hatch; no seed
            // line lists "Other", so no duplicate tags arise.
            ForEach(options.isEmpty ? LeatherType.allCases : options + [.other]) { lt in
                Text(lt.rawValue).tag(LeatherType?.some(lt))
            }
        }
    }
```

- [ ] **Step 7: Full build + test sweep**

Run:
```bash
xcodegen generate && xcodebuild -project Leatherfolio.xcodeproj -scheme Leatherfolio -destination 'platform=iOS Simulator,name=iPhone 16' test
```
Expected: TEST SUCCEEDED — all Phase 0–1 tests still green plus the 8 new ones.

- [ ] **Step 8: Manual simulator smoke (2 minutes)**

Launch in the simulator: Add item → category Tote → Line picker shows the seed's tote lines → pick "Leather Tote Bag" → name prefills, Size shows Small/Medium/Large/Oversized, Color shows that line's colors → pick "Other…" on Color → free-text field appears → save with a custom color. Expected: item saves and shows the custom color in detail.

- [ ] **Step 9: Commit**

```bash
git add Leatherfolio/Features/AddEdit/AddEditItemModel.swift Leatherfolio/Features/AddEdit/AddEditItemView.swift Leatherfolio/Features/AddEdit/OptionPicker.swift LeatherfolioTests/AddEditItemModelCatalogTests.swift
git commit -m "feat: cascading catalog pickers with Other… free-text escape hatch"
```

---
### Task 4: Completeness stats engine (CollectionStats)

**Files:**
- Create: `Leatherfolio/Services/CollectionStats.swift`
- Test: `LeatherfolioTests/CollectionStatsTests.swift`

**Interfaces:**
- Consumes: `Item` (Phase 0–1), `CatalogSeed`/`CatalogLine` (Task 2).
- Produces: `struct LineCompleteness`, `struct CategoryCount`, and `struct CollectionStats` with `init(items: [Item], catalog: CatalogSeed)` — the pure engine the Phase 4 stats SCREEN will render. No UI in this task. Callers decide what to pass (Phase 4 passes owned, non-wishlist items); this type computes over exactly the array it's given.

- [ ] **Step 1: Write the failing tests**

Create `LeatherfolioTests/CollectionStatsTests.swift`:

```swift
import XCTest
import SwiftData
@testable import Leatherfolio

@MainActor
final class CollectionStatsTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        container = try ModelContainer(
            for: Item.self, Photo.self, Tag.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        context = ModelContext(container)
    }

    private func fixtureCatalog() -> CatalogSeed {
        let json = """
        [
          {"name": "Test Tote", "category": "Tote", "sizes": ["Small"],
           "colors": ["Honey", "Black", "Cobalt"], "leatherTypes": ["Smooth"]},
          {"name": "Test Wallet", "category": "Wallet", "sizes": [],
           "colors": ["Plum", "Honey"], "leatherTypes": ["Smooth"]}
        ]
        """
        return CatalogSeed(data: Data(json.utf8))
    }

    private func makeItem(name: String = "Test Tote", color: String? = nil,
                          leatherType: LeatherType? = nil, isUnicorn: Bool = false,
                          myCost: Decimal? = nil, estimatedValue: Decimal? = nil,
                          rating: Int = 0) -> Item {
        let item = Item()
        item.name = name
        item.color = color
        item.leatherType = leatherType
        item.isUnicorn = isUnicorn
        item.myCost = myCost
        item.estimatedValue = estimatedValue
        item.rating = rating
        context.insert(item)
        return item
    }

    func testEmptyCollection() {
        let stats = CollectionStats(items: [], catalog: fixtureCatalog())
        XCTAssertEqual(stats.itemCount, 0)
        XCTAssertEqual(stats.distinctColorCount, 0)
        XCTAssertEqual(stats.distinctLeatherTypeCount, 0)
        XCTAssertEqual(stats.unicornCount, 0)
        XCTAssertEqual(stats.totalSpent, 0)
        XCTAssertEqual(stats.totalEstimatedValue, 0)
        XCTAssertEqual(stats.unrealizedDelta, 0)
        XCTAssertNil(stats.averageRating)
        XCTAssertTrue(stats.itemsByCategory.isEmpty)
        XCTAssertTrue(stats.lineCompleteness.isEmpty)
    }

    func testCountsAndDistincts() {
        let a = makeItem(color: "Honey", leatherType: .smooth, isUnicorn: true)
        let b = makeItem(color: "Honey", leatherType: .pebbled)
        let c = makeItem(color: "Black", leatherType: nil)
        let d = makeItem(color: nil)
        let stats = CollectionStats(items: [a, b, c, d], catalog: fixtureCatalog())
        XCTAssertEqual(stats.itemCount, 4)
        XCTAssertEqual(stats.distinctColorCount, 2, "Honey + Black; nil colors don't count")
        XCTAssertEqual(stats.distinctLeatherTypeCount, 2, "Smooth + Pebbled; nil doesn't count")
        XCTAssertEqual(stats.unicornCount, 1)
    }

    func testItemsByCategoryOrderedAndNonEmptyOnly() {
        let a = makeItem(); a.category = .tote
        let b = makeItem(); b.category = .tote
        let c = makeItem(); c.category = .wallet
        let stats = CollectionStats(items: [a, b, c], catalog: fixtureCatalog())
        XCTAssertEqual(stats.itemsByCategory,
                       [CategoryCount(category: .tote, count: 2),
                        CategoryCount(category: .wallet, count: 1)],
                       "Ordered by ItemCategory.allCases; empty categories omitted")
    }

    func testMoneyTotalsUseDecimalExactly() {
        let a = makeItem(myCost: Decimal(string: "129.99")!, estimatedValue: Decimal(string: "150.00")!)
        let b = makeItem(myCost: Decimal(string: "0.01")!, estimatedValue: Decimal(string: "0.03")!)
        let c = makeItem(myCost: nil, estimatedValue: Decimal(string: "40.00")!) // no cost: counts in value, not delta
        let stats = CollectionStats(items: [a, b, c], catalog: fixtureCatalog())
        XCTAssertEqual(stats.totalSpent, Decimal(string: "130.00")!)
        XCTAssertEqual(stats.totalEstimatedValue, Decimal(string: "190.03")!)
        // Delta sums per-item valueDelta only where BOTH sides exist:
        // (150.00 - 129.99) + (0.03 - 0.01) = 20.03
        XCTAssertEqual(stats.unrealizedDelta, Decimal(string: "20.03")!)
    }

    func testAverageRatingCountsRatedItemsOnly() {
        let a = makeItem(rating: 5)
        let b = makeItem(rating: 2)
        let c = makeItem(rating: 0) // unrated — excluded
        let stats = CollectionStats(items: [a, b, c], catalog: fixtureCatalog())
        XCTAssertEqual(stats.averageRating!, 3.5, accuracy: 0.0001)
    }

    func testAverageRatingNilWhenNothingRated() {
        let a = makeItem(rating: 0)
        let stats = CollectionStats(items: [a], catalog: fixtureCatalog())
        XCTAssertNil(stats.averageRating)
    }

    func testLineCompleteness() {
        _ = makeItem(name: "Test Tote", color: "Honey")
        _ = makeItem(name: "Test Tote", color: "Black")
        _ = makeItem(name: "Test Tote", color: "Honey")        // duplicate color counts once
        _ = makeItem(name: "Test Tote", color: "Custom Teal")  // off-catalog color ignored for completeness
        _ = makeItem(name: "Unlisted Bag", color: "Honey")     // not a catalog line → no entry
        let items = try! context.fetch(FetchDescriptor<Item>())
        let stats = CollectionStats(items: items, catalog: fixtureCatalog())
        XCTAssertEqual(stats.lineCompleteness.count, 1)
        let tote = stats.lineCompleteness[0]
        XCTAssertEqual(tote.lineName, "Test Tote")
        XCTAssertEqual(tote.ownedColors.sorted(), ["Black", "Honey"])
        XCTAssertEqual(tote.totalColors, 3)
        XCTAssertEqual(tote.summary, "You own 2 of 3 colors of Test Tote")
    }

    func testLineCompletenessSortedByName() {
        _ = makeItem(name: "Test Wallet", color: "Plum")
        _ = makeItem(name: "Test Tote", color: "Honey")
        let items = try! context.fetch(FetchDescriptor<Item>())
        let stats = CollectionStats(items: items, catalog: fixtureCatalog())
        XCTAssertEqual(stats.lineCompleteness.map(\.lineName), ["Test Tote", "Test Wallet"])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
xcodegen generate && xcodebuild -project Leatherfolio.xcodeproj -scheme Leatherfolio -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:LeatherfolioTests/CollectionStatsTests
```
Expected: BUILD FAILS — cannot find `CollectionStats` in scope.

- [ ] **Step 3: Implement CollectionStats**

Create `Leatherfolio/Services/CollectionStats.swift`:

```swift
import Foundation

/// "You own N of M colors of line X" — one entry per catalog line the user owns.
struct LineCompleteness: Equatable, Identifiable {
    let lineName: String
    let ownedColors: [String]   // distinct owned colors that exist in the line's palette
    let totalColors: Int        // the line's full palette size

    var id: String { lineName }
    var summary: String {
        "You own \(ownedColors.count) of \(totalColors) colors of \(lineName)"
    }
}

/// One bar of Phase 4's items-by-category chart.
struct CategoryCount: Equatable, Identifiable {
    let category: ItemCategory
    let count: Int
    var id: String { category.rawValue }
}

/// Pure stats engine over a snapshot of items. Computed, never stored (spec:
/// derived values are computed). Phase 4's stats screen renders this.
struct CollectionStats: Equatable {
    let itemCount: Int
    let distinctColorCount: Int
    let distinctLeatherTypeCount: Int
    let unicornCount: Int
    let totalSpent: Decimal           // sum of myCost where present
    let totalEstimatedValue: Decimal  // sum of estimatedValue where present
    let unrealizedDelta: Decimal      // sum of per-item valueDelta (both sides present)
    let averageRating: Double?        // over items with rating >= 1; nil if none rated
    let itemsByCategory: [CategoryCount]      // ordered by ItemCategory.allCases; empty categories omitted
    let lineCompleteness: [LineCompleteness]  // sorted by lineName

    init(items: [Item], catalog: CatalogSeed) {
        itemCount = items.count
        distinctColorCount = Set(items.compactMap(\.color)).count
        distinctLeatherTypeCount = Set(items.compactMap(\.leatherType)).count
        unicornCount = items.count(where: \.isUnicorn)
        totalSpent = items.compactMap(\.myCost).reduce(0, +)
        totalEstimatedValue = items.compactMap(\.estimatedValue).reduce(0, +)
        unrealizedDelta = items.compactMap(\.valueDelta).reduce(0, +)

        let ratings = items.map(\.rating).filter { $0 >= 1 }
        averageRating = ratings.isEmpty
            ? nil
            : Double(ratings.reduce(0, +)) / Double(ratings.count)

        let byCategory = Dictionary(grouping: items, by: \.category)
        itemsByCategory = ItemCategory.allCases.compactMap { cat in
            guard let count = byCategory[cat]?.count, count > 0 else { return nil }
            return CategoryCount(category: cat, count: count)
        }

        // Group owned colors by catalog line (matched by exact item name).
        var ownedByLine: [String: Set<String>] = [:]
        for item in items {
            guard let line = catalog.line(named: item.name) else { continue }
            let owned = ownedByLine[line.name] ?? []
            if let color = item.color, line.colors.contains(color) {
                ownedByLine[line.name] = owned.union([color])
            } else {
                ownedByLine[line.name] = owned  // owning the line with an off-palette color still lists the line
            }
        }
        lineCompleteness = ownedByLine.keys.sorted().compactMap { lineName in
            guard let line = catalog.line(named: lineName) else { return nil }
            return LineCompleteness(
                lineName: lineName,
                ownedColors: ownedByLine[lineName, default: []].sorted(),
                totalColors: line.colors.count)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
xcodegen generate && xcodebuild -project Leatherfolio.xcodeproj -scheme Leatherfolio -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:LeatherfolioTests/CollectionStatsTests
```
Expected: TEST SUCCEEDED, 9 tests pass. (If `items.count(where:)` fails to compile on your toolchain, replace with `items.filter(\.isUnicorn).count`.)

- [ ] **Step 5: Commit**

```bash
git add Leatherfolio/Services/CollectionStats.swift LeatherfolioTests/CollectionStatsTests.swift
git commit -m "feat: CollectionStats engine with Decimal totals and per-line completeness"
```

---
## Phase 3 — Scanning: QR labels, scan routing, UPC capture

### Task 5: QRService

**Files:**
- Create: `Leatherfolio/Services/QRService.swift`
- Test: `LeatherfolioTests/QRServiceTests.swift`

**Interfaces:**
- Consumes: nothing app-specific (Foundation, CoreImage, UIKit).
- Produces: `enum QRService` exactly per the master-plan contract — `payload(for:)`, `itemID(fromPayload:)`, `qrImage(for:scale:)`. Task 6 (routing), Task 8 (detail card + `.onOpenURL`) consume it.

- [ ] **Step 1: Write the failing tests**

Create `LeatherfolioTests/QRServiceTests.swift`:

```swift
import XCTest
@testable import Leatherfolio

final class QRServiceTests: XCTestCase {

    func testPayloadRoundTrip() {
        let id = UUID()
        let payload = QRService.payload(for: id)
        XCTAssertEqual(payload, "leatherfolio://item/\(id.uuidString)")
        XCTAssertEqual(QRService.itemID(fromPayload: payload), id)
    }

    func testParseIsCaseInsensitiveOnSchemeAndUUID() {
        let id = UUID(uuidString: "D9E0A2C4-1B7F-4E30-9A5C-2F6B8D1E4A7C")!
        XCTAssertEqual(
            QRService.itemID(fromPayload: "LEATHERFOLIO://item/d9e0a2c4-1b7f-4e30-9a5c-2f6b8d1e4a7c"),
            id)
    }

    func testRejectsGarbage() {
        XCTAssertNil(QRService.itemID(fromPayload: ""))
        XCTAssertNil(QRService.itemID(fromPayload: "not a url at all"))
        XCTAssertNil(QRService.itemID(fromPayload: "012345678905"))  // retail UPC digits
    }

    func testRejectsNonLeatherfolioURLs() {
        XCTAssertNil(QRService.itemID(fromPayload: "https://example.com/item/\(UUID().uuidString)"))
        XCTAssertNil(QRService.itemID(fromPayload: "otherapp://item/\(UUID().uuidString)"))
        XCTAssertNil(QRService.itemID(fromPayload: "leatherfolio://tag/\(UUID().uuidString)"))
    }

    func testRejectsBadUUIDs() {
        XCTAssertNil(QRService.itemID(fromPayload: "leatherfolio://item/not-a-uuid"))
        XCTAssertNil(QRService.itemID(fromPayload: "leatherfolio://item/"))
        XCTAssertNil(QRService.itemID(fromPayload: "leatherfolio://item/\(UUID().uuidString)/extra"))
    }

    func testQRImageGeneratedAtRequestedScale() throws {
        let image = try XCTUnwrap(QRService.qrImage(for: UUID(), scale: 8))
        let cgImage = try XCTUnwrap(image.cgImage)
        // Smallest QR is 21 modules; CIQRCodeGenerator output scaled 8x must be
        // at least 21 * 8 px on a side.
        XCTAssertGreaterThanOrEqual(cgImage.width, 21 * 8)
        XCTAssertEqual(cgImage.width, cgImage.height, "QR is square")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
xcodegen generate && xcodebuild -project Leatherfolio.xcodeproj -scheme Leatherfolio -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:LeatherfolioTests/QRServiceTests
```
Expected: BUILD FAILS — cannot find `QRService` in scope.

- [ ] **Step 3: Implement QRService**

Create `Leatherfolio/Services/QRService.swift`:

```swift
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// Payload format: "leatherfolio://item/<uuid-string>"
enum QRService {
    private static let scheme = "leatherfolio"
    private static let host = "item"

    static func payload(for itemID: UUID) -> String {
        "\(scheme)://\(host)/\(itemID.uuidString)"
    }

    static func itemID(fromPayload payload: String) -> UUID? {
        guard let url = URL(string: payload),
              url.scheme?.lowercased() == scheme,
              url.host()?.lowercased() == host,
              url.pathComponents.count == 2   // ["/", "<uuid>"]
        else { return nil }
        return UUID(uuidString: url.pathComponents[1])
    }

    /// Crisp QR: CIFilter output is tiny (1pt per module), so scale it up with
    /// a transform BEFORE rasterizing — never resize the bitmap afterwards.
    static func qrImage(for itemID: UUID, scale: CGFloat) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload(for: itemID).utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
xcodegen generate && xcodebuild -project Leatherfolio.xcodeproj -scheme Leatherfolio -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:LeatherfolioTests/QRServiceTests
```
Expected: TEST SUCCEEDED, 6 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Leatherfolio/Services/QRService.swift LeatherfolioTests/QRServiceTests.swift
git commit -m "feat: QRService payload codec and CIFilter QR generation"
```

---

### Task 6: ScanRouter

**Files:**
- Create: `Leatherfolio/Services/ScanRouter.swift`
- Test: `LeatherfolioTests/ScanRouterTests.swift`

**Interfaces:**
- Consumes: `QRService.itemID(fromPayload:)` (Task 5).
- Produces: `enum ScanRoute` and `enum ScanRouter` exactly per the master-plan contract. Task 8's scan handler consumes `ScanRouter.route(payload:isQR:existingItemIDs:)`.

- [ ] **Step 1: Write the failing tests**

Create `LeatherfolioTests/ScanRouterTests.swift`:

```swift
import XCTest
@testable import Leatherfolio

final class ScanRouterTests: XCTestCase {

    func testQRWithKnownUUIDRoutesToExistingItem() {
        let known = UUID()
        let payload = QRService.payload(for: known)
        let route = ScanRouter.route(payload: payload, isQR: true, existingItemIDs: [known, UUID()])
        XCTAssertEqual(route, .existingItem(known))
    }

    func testQRWithUnknownUUIDRoutesToNewItemKeepingPayload() {
        let payload = QRService.payload(for: UUID())
        let route = ScanRouter.route(payload: payload, isQR: true, existingItemIDs: [UUID()])
        XCTAssertEqual(route, .newItem(code: payload, isQR: true))
    }

    func testForeignQRRoutesToNewItem() {
        let route = ScanRouter.route(payload: "https://example.com/x", isQR: true, existingItemIDs: [])
        XCTAssertEqual(route, .newItem(code: "https://example.com/x", isQR: true))
    }

    func testRetailBarcodeRoutesToNewItemAsNonQR() {
        let route = ScanRouter.route(payload: "012345678905", isQR: false, existingItemIDs: [UUID()])
        XCTAssertEqual(route, .newItem(code: "012345678905", isQR: false))
    }

    func testNonQRPayloadThatLooksLikeOurURLStillGoesToNewItem() {
        // A linear barcode can't carry our QR contract; isQR gates the lookup.
        let known = UUID()
        let payload = QRService.payload(for: known)
        let route = ScanRouter.route(payload: payload, isQR: false, existingItemIDs: [known])
        XCTAssertEqual(route, .newItem(code: payload, isQR: false))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
xcodegen generate && xcodebuild -project Leatherfolio.xcodeproj -scheme Leatherfolio -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:LeatherfolioTests/ScanRouterTests
```
Expected: BUILD FAILS — cannot find `ScanRouter` in scope.

- [ ] **Step 3: Implement ScanRouter**

Create `Leatherfolio/Services/ScanRouter.swift`:

```swift
import Foundation

enum ScanRoute: Equatable {
    case existingItem(UUID)                      // QR matched an item in the store
    case newItem(code: String, isQR: Bool)       // unknown QR or any barcode → add flow, code attached
}

enum ScanRouter {
    static func route(payload: String, isQR: Bool, existingItemIDs: Set<UUID>) -> ScanRoute {
        if isQR,
           let id = QRService.itemID(fromPayload: payload),
           existingItemIDs.contains(id) {
            return .existingItem(id)
        }
        return .newItem(code: payload, isQR: isQR)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
xcodegen generate && xcodebuild -project Leatherfolio.xcodeproj -scheme Leatherfolio -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:LeatherfolioTests/ScanRouterTests
```
Expected: TEST SUCCEEDED, 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Leatherfolio/Services/ScanRouter.swift LeatherfolioTests/ScanRouterTests.swift
git commit -m "feat: ScanRouter maps scans to existing-item or new-item routes"
```

---
### Task 7: ScannerView (VisionKit wrapper)

**Files:**
- Create: `Leatherfolio/Features/Scanner/ScannerSupport.swift`
- Create: `Leatherfolio/Features/Scanner/ScannerView.swift`
- Create: `Leatherfolio/Features/Scanner/ScannerSheet.swift`
- Modify: `project.yml` (camera usage description)
- Test: `LeatherfolioTests/ScannerSupportTests.swift`

**Interfaces:**
- Consumes: nothing app-specific (VisionKit, Vision, SwiftUI, UIKit).
- Produces: `struct ScannerView: UIViewControllerRepresentable { let onScan: (_ payload: String, _ isQR: Bool) -> Void }` per the master-plan contract; `struct ScannerSheet: View` (`init(onScan:)`, same closure type) that guards availability and shows the fallback; `enum ScannerSupport` with `static var isReady: Bool` and `static func isQR(_ symbology: VNBarcodeSymbology) -> Bool`. Task 8 presents `ScannerSheet`.

Camera capture does not run in the simulator, so `DataScannerViewController` behavior is NOT simulator-testable. The pure symbology→isQR mapping is extracted into `ScannerSupport` precisely so it IS unit-testable; the rest gets a manual device step (and the full end-to-end device checklist lives in Task 8).

- [ ] **Step 1: Write the failing test for the pure helper**

Create `LeatherfolioTests/ScannerSupportTests.swift`:

```swift
import XCTest
import Vision
@testable import Leatherfolio

final class ScannerSupportTests: XCTestCase {

    func testQRSymbologiesMapToIsQRTrue() {
        XCTAssertTrue(ScannerSupport.isQR(.qr))
        XCTAssertTrue(ScannerSupport.isQR(.microQR))
    }

    func testRetailSymbologiesMapToIsQRFalse() {
        XCTAssertFalse(ScannerSupport.isQR(.ean13))
        XCTAssertFalse(ScannerSupport.isQR(.ean8))
        XCTAssertFalse(ScannerSupport.isQR(.upce))
        XCTAssertFalse(ScannerSupport.isQR(.code128))
        XCTAssertFalse(ScannerSupport.isQR(.code39))
        XCTAssertFalse(ScannerSupport.isQR(.itf14))
        XCTAssertFalse(ScannerSupport.isQR(.dataMatrix))
        XCTAssertFalse(ScannerSupport.isQR(.aztec))
        XCTAssertFalse(ScannerSupport.isQR(.pdf417))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
xcodegen generate && xcodebuild -project Leatherfolio.xcodeproj -scheme Leatherfolio -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:LeatherfolioTests/ScannerSupportTests
```
Expected: BUILD FAILS — cannot find `ScannerSupport` in scope.

- [ ] **Step 3: Implement ScannerSupport**

Create `Leatherfolio/Features/Scanner/ScannerSupport.swift`:

```swift
import Vision
import VisionKit

/// Pure, unit-testable helpers around VisionKit scanning.
enum ScannerSupport {
    /// True when the device can scan right now (hardware support AND camera
    /// permission not denied). False in the simulator and when access is denied.
    @MainActor static var isReady: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    /// Symbology → "is this a QR-family code?" mapping. QR-family codes are the
    /// only ones that can carry the leatherfolio:// self-label payload; every
    /// other symbology is treated as a retail barcode (UPC capture path).
    static func isQR(_ symbology: VNBarcodeSymbology) -> Bool {
        symbology == .qr || symbology == .microQR
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
xcodegen generate && xcodebuild -project Leatherfolio.xcodeproj -scheme Leatherfolio -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:LeatherfolioTests/ScannerSupportTests
```
Expected: TEST SUCCEEDED, 2 tests pass.

- [ ] **Step 5: Implement ScannerView**

Create `Leatherfolio/Features/Scanner/ScannerView.swift`:

```swift
import SwiftUI
import VisionKit

/// SwiftUI wrapper around VisionKit DataScannerViewController.
/// Calls onScan exactly once per recognized code, then stops scanning.
/// Present via ScannerSheet, which guards ScannerSupport.isReady first.
struct ScannerView: UIViewControllerRepresentable {
    let onScan: (_ payload: String, _ isQR: Bool) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode()],   // all symbologies: QR + retail
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        try? scanner.startScanning()             // throws only when unavailable; sheet guard prevents that
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onScan: (String, Bool) -> Void
        private var hasFired = false

        init(onScan: @escaping (String, Bool) -> Void) {
            self.onScan = onScan
        }

        func dataScanner(_ dataScanner: DataScannerViewController,
                         didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            guard !hasFired else { return }
            for case let .barcode(barcode) in addedItems {
                guard let payload = barcode.payloadStringValue, !payload.isEmpty else { continue }
                hasFired = true
                dataScanner.stopScanning()
                onScan(payload, ScannerSupport.isQR(barcode.observation.symbology))
                return
            }
        }
    }
}
```

- [ ] **Step 6: Implement ScannerSheet (availability guard + fallback)**

Create `Leatherfolio/Features/Scanner/ScannerSheet.swift`:

```swift
import SwiftUI

/// Presents the scanner when the device can scan; otherwise an explainer with
/// a Settings link (camera permission) or a plain unsupported message.
struct ScannerSheet: View {
    let onScan: (_ payload: String, _ isQR: Bool) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if ScannerSupport.isReady {
                    ScannerView(onScan: onScan)
                        .ignoresSafeArea()
                } else {
                    unavailableView
                }
            }
            .navigationTitle("Scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var unavailableView: some View {
        ContentUnavailableView {
            Label("Camera Unavailable", systemImage: "camera.fill")
        } description: {
            Text("Scanning needs a device with a camera and permission to use it. Check camera access for Leatherfolio in Settings.")
        } actions: {
            if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                Link("Open Settings", destination: settingsURL)
            }
        }
    }
}
```

- [ ] **Step 7: Add the camera usage description to project.yml**

Scanning requires `NSCameraUsageDescription` or the app crashes on first camera access. In `project.yml`, inside the `Leatherfolio` target's existing `info: properties:` block, add:

```yaml
        NSCameraUsageDescription: "Leatherfolio uses the camera to scan item QR labels and product barcodes."
```

(Keep the rest of the `info` block exactly as Phase 0–1 left it — this is one added key.)

- [ ] **Step 8: Full build + test sweep**

Run:
```bash
xcodegen generate && xcodebuild -project Leatherfolio.xcodeproj -scheme Leatherfolio -destination 'platform=iOS Simulator,name=iPhone 16' test
```
Expected: TEST SUCCEEDED — everything compiles (ScannerView compiles for simulator even though it can't capture there); all prior tests remain green.

- [ ] **Step 9: Manual simulator check of the fallback path**

Launch in the simulator and present `ScannerSheet` from a temporary Xcode preview or by wiring a quick button (Task 8 wires it for real). In the simulator `ScannerSupport.isReady` is false, so the expected result is the ContentUnavailableView with the "Open Settings" link — not a crash. (If you prefer to defer this to Task 8's manual step, that is acceptable; the sheet is exercised there too.)

- [ ] **Step 10: Commit**

```bash
git add Leatherfolio/Features/Scanner/ScannerSupport.swift Leatherfolio/Features/Scanner/ScannerView.swift Leatherfolio/Features/Scanner/ScannerSheet.swift LeatherfolioTests/ScannerSupportTests.swift project.yml
git commit -m "feat: VisionKit ScannerView with availability fallback and camera usage string"
```

---
### Task 8: Integrate scanning into the app

**Files:**
- Modify: `Leatherfolio/Features/AddEdit/AddEditItemModel.swift` (add `applyScanPrefill(code:isQR:)`)
- Modify: `Leatherfolio/Features/Collection/CollectionView.swift` (scan toolbar button + routing)
- Modify: `Leatherfolio/Features/ItemDetail/ItemDetailView.swift` (real QR label card)
- Create: `Leatherfolio/Features/ItemDetail/QRLabelSheet.swift`
- Modify: `Leatherfolio/App/LeatherfolioApp.swift` (`.onOpenURL` via QRService)
- Test: `LeatherfolioTests/AddEditItemModelScanTests.swift`

**Interfaces:**
- Consumes: `ScannerSheet` (Task 7), `ScanRouter`/`ScanRoute` (Task 6), `QRService` (Task 5), `AddEditItemModel` (Task 3), `AppRouter.open(itemID:)` (Phase 0–1).
- Produces: `AddEditItemModel.applyScanPrefill(code: String, isQR: Bool)` (Task 9 extends the same flow with lookup); `QRLabelSheet(item:)`.

- [ ] **Step 1: Write the failing prefill tests**

Create `LeatherfolioTests/AddEditItemModelScanTests.swift`:

```swift
import XCTest
@testable import Leatherfolio

@MainActor
final class AddEditItemModelScanTests: XCTestCase {

    func testRetailBarcodePrefillsUPC() {
        let model = AddEditItemModel()
        model.applyScanPrefill(code: "012345678905", isQR: false)
        XCTAssertEqual(model.upc, "012345678905")
        XCTAssertEqual(model.notes, "", "retail codes go to upc, not notes")
    }

    func testUnknownQRAttachesCodeToNotesNotUPC() {
        let model = AddEditItemModel()
        let payload = QRService.payload(for: UUID())
        model.applyScanPrefill(code: payload, isQR: true)
        XCTAssertEqual(model.upc, "", "QR payloads are not UPCs")
        XCTAssertEqual(model.notes, "Scanned code: \(payload)")
    }

    func testQRPrefillAppendsToExistingNotes() {
        let model = AddEditItemModel()
        model.notes = "Bought at the tannery sale"
        model.applyScanPrefill(code: "some-qr-content", isQR: true)
        XCTAssertEqual(model.notes, "Bought at the tannery sale\nScanned code: some-qr-content")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
xcodegen generate && xcodebuild -project Leatherfolio.xcodeproj -scheme Leatherfolio -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:LeatherfolioTests/AddEditItemModelScanTests
```
Expected: BUILD FAILS — `AddEditItemModel` has no member `applyScanPrefill`.

- [ ] **Step 3: Add applyScanPrefill to AddEditItemModel**

In `Leatherfolio/Features/AddEdit/AddEditItemModel.swift`, add below the catalog section from Task 3:

```swift
    // MARK: - Scan capture (Phase 3)

    /// Prefill from a scan: retail barcodes become the UPC (stable identifier,
    /// spec decision #2 — capture, no lookup in v1); unknown QR payloads are
    /// attached to notes so no scanned data is ever dropped.
    func applyScanPrefill(code: String, isQR: Bool) {
        if isQR {
            let line = "Scanned code: \(code)"
            notes = notes.isEmpty ? line : notes + "\n" + line
        } else {
            upc = code
        }
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
xcodegen generate && xcodebuild -project Leatherfolio.xcodeproj -scheme Leatherfolio -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:LeatherfolioTests/AddEditItemModelScanTests
```
Expected: TEST SUCCEEDED, 3 tests pass.

- [ ] **Step 5: Add the scan button + routing to CollectionView**

In `Leatherfolio/Features/Collection/CollectionView.swift`, add these members inside the `CollectionView` struct. `items` is the view's existing `@Query` result; `router` is the `AppRouter` from the environment (Phase 0–1 injects it — match its spelling, e.g. `@Environment(AppRouter.self) private var router`):

```swift
    @State private var showingScanner = false
    @State private var scanPrefill: ScanPrefill?

    struct ScanPrefill: Identifiable {
        let id = UUID()
        let code: String
        let isQR: Bool
    }

    private func handleScan(payload: String, isQR: Bool) {
        showingScanner = false
        let route = ScanRouter.route(
            payload: payload,
            isQR: isQR,
            existingItemIDs: Set(items.map(\.id)))
        switch route {
        case .existingItem(let id):
            router.open(itemID: id)
        case .newItem(let code, let isQR):
            scanPrefill = ScanPrefill(code: code, isQR: isQR)
        }
    }
```

Add to the view's existing `.toolbar { ... }` block (alongside the Phase 0–1 add button):

```swift
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showingScanner = true
                } label: {
                    Label("Scan", systemImage: "qrcode.viewfinder")
                }
                .accessibilityLabel("Scan a QR label or barcode")
            }
```

And attach these two sheets to the view's outermost content (next to any existing `.sheet` modifiers):

```swift
        .sheet(isPresented: $showingScanner) {
            ScannerSheet(onScan: handleScan)
        }
        .sheet(item: $scanPrefill) { prefill in
            AddEditItemView(model: {
                let model = AddEditItemModel()
                model.applyScanPrefill(code: prefill.code, isQR: prefill.isQR)
                return model
            }())
        }
```

(If Phase 0–1's `AddEditItemView` initializer takes no model and builds its own, add a `model:` initializer parameter with a default `AddEditItemModel()` — an additive change — rather than restructuring the view.)

- [ ] **Step 6: Replace the UUID-text QR card in ItemDetailView**

Create `Leatherfolio/Features/ItemDetail/QRLabelSheet.swift`:

```swift
import SwiftUI

/// Full-size QR label for an item, with export via ShareLink (print it, stick
/// it in the dust bag — scanning it later jumps straight to this item).
struct QRLabelSheet: View {
    let item: Item
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if let uiImage = QRService.qrImage(for: item.id, scale: 16) {
                    let image = Image(uiImage: uiImage)
                    image
                        .interpolation(.none)   // keep modules crisp when SwiftUI scales
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 280)
                        .accessibilityLabel("QR label for \(item.name)")
                    Text(item.name)
                        .font(.headline)
                    ShareLink(
                        item: image,
                        preview: SharePreview("Leatherfolio label — \(item.name)", image: image)
                    ) {
                        Label("Export Label", systemImage: "square.and.arrow.up")
                    }
                } else {
                    ContentUnavailableView("Could not generate QR label",
                                           systemImage: "qrcode")
                }
            }
            .padding()
            .navigationTitle("QR Label")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
```

In `Leatherfolio/Features/ItemDetail/ItemDetailView.swift`: delete the Phase 0–1 card body that renders `item.id.uuidString` as text and replace it with this (add `@State private var showingQRLabel = false` to the view struct):

```swift
        // QR label card — tap to enlarge/export
        Button {
            showingQRLabel = true
        } label: {
            HStack(spacing: 16) {
                if let uiImage = QRService.qrImage(for: item.id, scale: 8) {
                    Image(uiImage: uiImage)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 88, height: 88)
                }
                VStack(alignment: .leading) {
                    Text("QR Label")
                        .font(.headline)
                    Text("Tap to enlarge or export")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("QR label. Tap to enlarge or export.")
        .sheet(isPresented: $showingQRLabel) {
            QRLabelSheet(item: item)
        }
```

- [ ] **Step 7: Route deep links through QRService**

In `Leatherfolio/App/LeatherfolioApp.swift`, replace the Phase 0–1 inline URL parse inside `.onOpenURL` with:

```swift
            .onOpenURL { url in
                if let itemID = QRService.itemID(fromPayload: url.absoluteString) {
                    router.open(itemID: itemID)
                }
            }
```

Delete the now-dead inline parsing helper Phase 0–1 wrote (if it was a private function, remove it; the URL contract now lives in exactly one place: `QRService`).

- [ ] **Step 8: Full build + test sweep**

Run:
```bash
xcodegen generate && xcodebuild -project Leatherfolio.xcodeproj -scheme Leatherfolio -destination 'platform=iOS Simulator,name=iPhone 16' test
```
Expected: TEST SUCCEEDED — all tests green.

- [ ] **Step 9: Simulator smoke of the non-camera paths**

In the simulator:
1. Open an item's detail → QR card renders an actual QR image (not UUID text) → tap → QRLabelSheet shows the large label and an Export Label share button.
2. Deep link still works through the new path: with the app installed, run `xcrun simctl openurl booted "leatherfolio://item/<uuid-of-an-existing-item>"` (copy a real UUID by adding a temporary `print(item.id)` or reading it from the QR sheet's share preview). Expected: the app opens that item's detail.
3. Tap the Scan toolbar button → the camera-unavailable fallback appears with the Open Settings link (simulator has no camera scanning).

- [ ] **Step 10: Manual DEVICE test checklist (requires a physical iPhone; free personal signing team is fine)**

Record results as checklist ticks in the commit message or PR notes:
1. Build to the device. Tap Scan → camera permission prompt shows the Task 7 usage string → grant.
2. Display an item's QR label on another screen (or print it) → scan it → expected: scanner dismisses and that item's detail opens (existingItem route).
3. Scan any retail product barcode (any EAN/UPC on hand, e.g. a grocery item — a real PLG hangtag when available; this doubles as the spec's "physical UPC test" milestone) → expected: add flow opens with the UPC field prefilled and notes empty (newItem, isQR false).
4. Scan a foreign QR code (e.g. a Wi-Fi QR) → expected: add flow opens with "Scanned code: …" in notes and UPC empty (newItem, isQR true).
5. Deny camera permission in Settings → tap Scan → expected: fallback view with working Open Settings link.

- [ ] **Step 11: Commit**

```bash
git add Leatherfolio/Features/AddEdit/AddEditItemModel.swift Leatherfolio/Features/Collection/CollectionView.swift Leatherfolio/Features/ItemDetail/ItemDetailView.swift Leatherfolio/Features/ItemDetail/QRLabelSheet.swift Leatherfolio/App/LeatherfolioApp.swift LeatherfolioTests/AddEditItemModelScanTests.swift
git commit -m "feat: scan-to-open and scan-to-add flows; real QR label card with export"
```

---
### Task 9: ProductLookupService protocol + NoOp (v2 seam)

**Files:**
- Create: `Leatherfolio/Services/ProductLookupService.swift`
- Modify: `Leatherfolio/Features/AddEdit/AddEditItemModel.swift` (inject the service, add `lookupUPCIfNeeded()`)
- Modify: `Leatherfolio/Features/AddEdit/AddEditItemView.swift` (fire the lookup)
- Test: `LeatherfolioTests/AddEditItemModelLookupTests.swift`

**Interfaces:**
- Consumes: `AddEditItemModel` (Tasks 3, 8).
- Produces: `ProductInfo`, `ProductLookupService`, `NoOpProductLookup` exactly per the master-plan contract; `AddEditItemModel.lookup: any ProductLookupService` and `func lookupUPCIfNeeded() async`. A future v2 UPC-lookup implementation swaps in via this seam only — no other file changes.

- [ ] **Step 1: Write the failing tests**

Create `LeatherfolioTests/AddEditItemModelLookupTests.swift`:

```swift
import XCTest
@testable import Leatherfolio

@MainActor
final class AddEditItemModelLookupTests: XCTestCase {

    private struct StubLookup: ProductLookupService {
        let info: ProductInfo?
        func lookup(upc: String) async -> ProductInfo? { info }
    }

    func testStubLookupPrefillsNameAndNotes() async {
        let model = AddEditItemModel()
        model.lookup = StubLookup(info: ProductInfo(name: "Leather Tote Bag",
                                                    description: "Classic full-grain tote"))
        model.applyScanPrefill(code: "012345678905", isQR: false)
        await model.lookupUPCIfNeeded()
        XCTAssertEqual(model.name, "Leather Tote Bag")
        XCTAssertEqual(model.notes, "Classic full-grain tote")
    }

    func testLookupNeverOverwritesUserInput() async {
        let model = AddEditItemModel()
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
        let model = AddEditItemModel()
        model.lookup = StubLookup(info: ProductInfo(name: "Leather Tote Bag", description: nil))
        model.applyScanPrefill(code: "012345678905", isQR: false)
        await model.lookupUPCIfNeeded()
        XCTAssertEqual(model.name, "Leather Tote Bag")
        XCTAssertEqual(model.notes, "")
    }

    func testNoOpLookupChangesNothing() async {
        let model = AddEditItemModel()   // default lookup is NoOpProductLookup
        model.applyScanPrefill(code: "012345678905", isQR: false)
        await model.lookupUPCIfNeeded()
        XCTAssertEqual(model.name, "")
        XCTAssertEqual(model.notes, "")
        XCTAssertEqual(model.upc, "012345678905", "captured UPC is kept either way")
    }

    func testNoLookupWithoutUPC() async {
        let model = AddEditItemModel()
        model.lookup = StubLookup(info: ProductInfo(name: "Ghost", description: "Should not appear"))
        await model.lookupUPCIfNeeded()   // upc is empty
        XCTAssertEqual(model.name, "")
        XCTAssertEqual(model.notes, "")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
xcodegen generate && xcodebuild -project Leatherfolio.xcodeproj -scheme Leatherfolio -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:LeatherfolioTests/AddEditItemModelLookupTests
```
Expected: BUILD FAILS — cannot find `ProductLookupService` in scope.

- [ ] **Step 3: Implement the service and the model seam**

Create `Leatherfolio/Services/ProductLookupService.swift`:

```swift
import Foundation

struct ProductInfo: Equatable { let name: String?; let description: String? }

protocol ProductLookupService: Sendable {
    func lookup(upc: String) async -> ProductInfo?
}

/// v1 implementation. The brief concluded PLG products likely aren't in public
/// UPC databases; v1 captures the raw code only. A v2 lookup backend replaces
/// this by assigning AddEditItemModel.lookup — nothing else changes.
struct NoOpProductLookup: ProductLookupService {
    func lookup(upc: String) async -> ProductInfo? { nil }
}
```

In `Leatherfolio/Features/AddEdit/AddEditItemModel.swift`, add below the scan-capture section from Task 8:

```swift
    // MARK: - UPC lookup seam (v2; NoOp in v1)

    /// Injection seam: tests assign a stub; v2 assigns a real lookup backend.
    var lookup: any ProductLookupService = NoOpProductLookup()

    /// If a UPC was captured, ask the lookup service and prefill name/notes —
    /// only fields the user hasn't filled, and only non-nil results. With
    /// NoOpProductLookup this is a no-op, so v1 behavior is unchanged.
    func lookupUPCIfNeeded() async {
        guard !upc.isEmpty else { return }
        guard let info = await lookup.lookup(upc: upc) else { return }
        if let lookedUpName = info.name, name.isEmpty { name = lookedUpName }
        if let lookedUpDescription = info.description, notes.isEmpty { notes = lookedUpDescription }
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
xcodegen generate && xcodebuild -project Leatherfolio.xcodeproj -scheme Leatherfolio -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:LeatherfolioTests/AddEditItemModelLookupTests
```
Expected: TEST SUCCEEDED, 5 tests pass.

- [ ] **Step 5: Fire the lookup from the add flow**

In `Leatherfolio/Features/AddEdit/AddEditItemView.swift`, attach to the view's outermost content (next to the modifiers from Task 3):

```swift
        .task { await model.lookupUPCIfNeeded() }
```

This runs once when the add/edit sheet appears; with the NoOp service it returns immediately, and when a scan prefilled a UPC (Task 8) a future v2 backend will prefill name/notes here.

- [ ] **Step 6: Full build + test sweep**

Run:
```bash
xcodegen generate && xcodebuild -project Leatherfolio.xcodeproj -scheme Leatherfolio -destination 'platform=iOS Simulator,name=iPhone 16' test
```
Expected: TEST SUCCEEDED — full suite green (Phases 0–3).

- [ ] **Step 7: Commit**

```bash
git add Leatherfolio/Services/ProductLookupService.swift Leatherfolio/Features/AddEdit/AddEditItemModel.swift Leatherfolio/Features/AddEdit/AddEditItemView.swift LeatherfolioTests/AddEditItemModelLookupTests.swift
git commit -m "feat: ProductLookupService seam with NoOp v1 implementation wired into add flow"
```

---

## Phase completion checklist

- [ ] All nine tasks committed; `xcodegen generate && xcodebuild ... test` fully green.
- [ ] Simulator smoke: add item via cascading pickers (line → size/color/leather) and via "Other…" free-text; detail shows a real QR image; `simctl openurl` deep link opens the item.
- [ ] Device checklist from Task 8 Step 10 completed and recorded (QR → detail; retail barcode → add flow with UPC; foreign QR → add flow with notes; permission-denied fallback).
- [ ] The spec's "physical UPC test on a real PLG tag" milestone is logged as pending until a physical PLG hangtag is available (Task 8 Step 10.3 covers the mechanics with any retail barcode).
