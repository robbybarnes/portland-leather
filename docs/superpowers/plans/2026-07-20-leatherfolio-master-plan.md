# Leatherfolio Master Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement the phase plans task-by-task. This master document is the coordination layer: global constraints, shared interfaces, and phase ordering. The executable, bite-sized tasks live in the phase plan files listed below. Steps there use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build Leatherfolio, a local-first SwiftUI/SwiftData iOS app for cataloging a personal Portland Leather Goods collection, with QR self-labeling, curated pickers seeded from real catalog research, and a CloudKit-ready schema.

**Architecture:** SwiftUI + SwiftData (CloudKit-shaped schema, sync off until signing exists), services for images/QR/scan-routing/catalog-seed, XcodeGen-generated project. See `docs/superpowers/specs/2026-07-20-plg-catalog-app-design.md` — the spec is authoritative; this plan implements it.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, VisionKit (DataScannerViewController), Core Image (QR generation), PhotosUI, Swift Charts, XCTest, XcodeGen, xcodebuild. Zero third-party dependencies in the app target.

## Phase plans (execution order)

1. `2026-07-20-phase-0-1-core-catalog.md` — project skeleton, models, ImageStore, add/edit/delete, grid + detail. Ship-able MVP.
2. `2026-07-20-phase-2-3-seed-and-scanning.md` — bundled `plg_catalog.json` + cascading pickers + completeness stats; ScannerView, QR labels, scan routing, UPC capture.
3. `2026-07-20-phase-4-polish.md` — filter/sort/search, wishlist scope, stats screen, design language, accessibility, app icon.

Each phase plan produces working, testable software on its own. Complete and commit a phase before starting the next.

## Global Constraints

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

## Shared interfaces (contract — all phase plans copy these verbatim)

Anything a later phase consumes is defined here exactly. Phase plans must not rename these.

### Enums (`Leatherfolio/Models/Enums.swift`)

```swift
enum ItemCategory: String, Codable, CaseIterable, Identifiable {
    case tote = "Tote"
    case crossbodyTote = "Crossbody Tote"
    case crossbody = "Crossbody"
    case beltBag = "Belt Bag"
    case backpack = "Backpack"
    case wallet = "Wallet"
    case cardholder = "Cardholder"
    case belt = "Belt"
    case accessory = "Accessory"
    case other = "Other"
    var id: String { rawValue }
}

enum LeatherType: String, Codable, CaseIterable, Identifiable {
    case smooth = "Smooth"
    case pebbled = "Pebbled"
    case suede = "Suede"
    case metallic = "Metallic"
    case other = "Other"
    var id: String { rawValue }
}

enum ItemCondition: String, Codable, CaseIterable, Identifiable {
    case new = "New"
    case excellent = "Excellent"
    case good = "Good"
    case worn = "Worn"
    var id: String { rawValue }
}
```

### Models (`Leatherfolio/Models/Item.swift`, `Photo.swift`, `Tag.swift`)

```swift
import SwiftData
import Foundation

@Model
final class Item {
    var id: UUID = UUID()
    var name: String = ""
    var categoryRaw: String = ItemCategory.other.rawValue
    var size: String?
    var color: String?
    var leatherTypeRaw: String?
    var isUnicorn: Bool = false
    var isWishlist: Bool = false
    var favorite: Bool = false
    var myCost: Decimal?
    var retailCost: Decimal?
    var estimatedValue: Decimal?
    var rating: Int = 0            // 0 = unrated, 1–5 stars
    var upc: String?
    var conditionRaw: String?
    var dateAcquired: Date?
    var notes: String?
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    @Relationship(deleteRule: .cascade, inverse: \Photo.item)
    var photos: [Photo]? = []
    @Relationship(inverse: \Tag.items)
    var tags: [Tag]? = []

    init() {}

    // Typed accessors over raw storage (SwiftData can't filter enums-in-Codable)
    var category: ItemCategory {
        get { ItemCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }
    var leatherType: LeatherType? {
        get { leatherTypeRaw.flatMap(LeatherType.init(rawValue:)) }
        set { leatherTypeRaw = newValue?.rawValue }
    }
    var condition: ItemCondition? {
        get { conditionRaw.flatMap(ItemCondition.init(rawValue:)) }
        set { conditionRaw = newValue?.rawValue }
    }
    var valueDelta: Decimal? {   // computed, never stored
        guard let estimatedValue, let myCost else { return nil }
        return estimatedValue - myCost
    }
    var primaryPhoto: Photo? {
        (photos ?? []).first(where: \.isPrimary) ?? photos?.first
    }
}

@Model
final class Photo {
    var id: UUID = UUID()
    @Attribute(.externalStorage) var imageData: Data?
    var caption: String?
    var isPrimary: Bool = false
    var createdAt: Date = Date.now
    var item: Item?
    init() {}
}

@Model
final class Tag {
    var name: String = ""
    var items: [Item]? = []
    init(name: String = "") { self.name = name }
}
```

Container setup (`Leatherfolio/App/AppModelContainer.swift`): `ModelConfiguration(cloudKitDatabase: .none)` today; a single `AppConfig.cloudKitEnabled` flag documents the one-line flip to `.automatic` later.

### Services

```swift
// Leatherfolio/Services/ImageStore.swift
/// Thumbnails cached as ~400px JPEGs in Caches/thumbnails/<photo-uuid>.jpg.
/// Originals live in Photo.imageData (externalStorage). Detail views load
/// originals directly; every grid/list goes through thumbnail(for:).
final class ImageStore: Sendable {
    static let shared = ImageStore()
    func thumbnail(for photoID: UUID, imageData: Data?) async -> UIImage?
    func deleteThumbnail(for photoID: UUID)
    func downsampledJPEG(from data: Data, maxDimension: CGFloat) -> Data?  // used on import
}

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

### Deep links

`LeatherfolioApp` handles `.onOpenURL`; `leatherfolio://item/<uuid>` navigates to that item's detail view via a `NavigationPath` owned by an `@Observable AppRouter` (`Leatherfolio/App/AppRouter.swift`, `func open(itemID: UUID)`).

### Reference data inputs

- `research/plg_products.json` — 37 scraped products (name, description, sizes, colors, leather_type, price range, image URL, category).
- `research/plg_catalog_notes.md` — master size list (Mini/Small/Medium/Large/Original/Oversized/Extra Large/Jumbo; belt sizing S–XL and 32–44; Classic/Deluxe), staple colors (Honey, Cognac, Nutmeg, Coldbrew, Black, Chestnut, Sienna, Bone, …), structure caveats (Crossbody Tote sizes are separate listings → merge into one line in the seed).

## Definition of done (whole project)

Every phase plan's tasks checked off and committed; `xcodebuild test` green; manual smoke on simulator: add item with photo → appears in grid → detail shows QR label → scanning that QR (second device/camera or in-sim test hook) routes back to the item; accessibility pass (Dynamic Type XL, VoiceOver labels on grid cells); CloudKit flip + two-device sync verified once signing exists (tracked as a post-plan milestone, not a v1 blocker).
