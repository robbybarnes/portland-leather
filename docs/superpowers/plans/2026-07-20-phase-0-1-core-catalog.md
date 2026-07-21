# Leatherfolio Phase 0–1: Core Catalog Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the Leatherfolio Xcode project (XcodeGen, Swift 6, iOS 18) and ship the core-catalog MVP: SwiftData models, ImageStore thumbnails, collection grid, add/edit flow, item detail with cascade delete, and `leatherfolio://item/<uuid>` deep-link routing.

**Architecture:** SwiftUI + SwiftData with a CloudKit-shaped schema (sync off), an `@Observable` form model and router, an ImageStore service for thumbnails, XcodeGen-generated project. The spec is authoritative: `docs/superpowers/specs/2026-07-20-plg-catalog-app-design.md`. Shared interfaces and phase ordering: `docs/superpowers/plans/2026-07-20-leatherfolio-master-plan.md` — this plan copies its model/service contracts verbatim and must not rename anything in them.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, PhotosUI, ImageIO, UIKit interop (UIImagePickerController), XCTest, XcodeGen, xcodebuild. Zero third-party dependencies in the app target.

## Global Constraints

(Copied verbatim from `docs/superpowers/plans/2026-07-20-leatherfolio-master-plan.md`. Every task's requirements implicitly include this section.)

- **iOS deployment target:** 18.0. Swift language mode 6.
- **Bundle ID:** `com.robbybarnes.leatherfolio`. **Display name:** My PLG Collection. **URL scheme:** `leatherfolio`. (Module/target/dirs stay `Leatherfolio` — valid Swift identifiers; only the user-facing display name changes.)
- **No third-party dependencies** in the app target. Dev tooling allowed: XcodeGen (via Homebrew), SwiftLint optional.
- **Project generation:** `project.yml` (XcodeGen) is source of truth; `Leatherfolio.xcodeproj` is generated and **gitignored**. Regenerate with `xcodegen generate` after any file add/remove.
- **Build/test loop:** `xcodegen generate && xcodebuild -project Leatherfolio.xcodeproj -scheme Leatherfolio -destination 'platform=iOS Simulator,name=iPhone 16' build` (tests: `test` action, same destination; substitute any available iPhone simulator via `xcrun simctl list devices available`).
- **CloudKit schema rules (every model, every phase):** every property optional or with a default; every relationship optional; no `@Attribute(.unique)`; no `.deny` delete rules. Sync itself stays OFF (`cloudKitDatabase: .none`) until signing exists; do not add the iCloud capability yet.
- **Photos:** never store image bytes in queries/lists. Originals via `@Attribute(.externalStorage)`; grids use `ImageStore` thumbnails only.
- **Money:** `Decimal` everywhere; render with the user's locale currency.
- **Naming/copy:** no "Portland Leather Goods" trademark in app name, bundle ID, or App Store-facing strings; in-app reference data may name product lines (research-permission caveat is in the spec). Scraped data stays in `research/` (repo), curated seed ships as `Leatherfolio/Resources/plg_catalog.json`.
- **Commits:** small, per task, conventional-commit style (`feat:`, `test:`, `chore:`).

**Working directory:** every command in this plan runs from the repo root, `/Users/robbybarnes/GitHub/portland-leather`.

**Simulator note (applies to every build/test command):** the commands below use `name=iPhone 16`. If that simulator is not installed, list what is available with `xcrun simctl list devices available` and substitute any available iPhone (e.g. `name=iPhone 16 Pro`). Use the same substitution consistently for the whole plan.

**Swift 6 concurrency note (applies to every test file):** the project builds in Swift 6 language mode with strict concurrency. All test classes that touch SwiftData contexts, UIKit, or SwiftUI are annotated `@MainActor` — copy that annotation exactly as shown in each test step.

## File map (this plan)

| Path | Responsibility |
|---|---|
| `project.yml` | XcodeGen source of truth: app + unit-test targets, Info.plist properties |
| `.gitignore` | Ignore generated `.xcodeproj`, DerivedData, user state |
| `Leatherfolio/App/LeatherfolioApp.swift` | `@main` entry, model container attachment, deep-link handling (Task 7) |
| `Leatherfolio/App/ContentView.swift` | Root NavigationStack + navigation destinations |
| `Leatherfolio/App/AppModelContainer.swift` | ModelContainer factory (CloudKit off, in-memory option for tests) |
| `Leatherfolio/App/AppRouter.swift` | `@Observable` NavigationPath owner + `leatherfolio://item/<uuid>` parsing |
| `Leatherfolio/Models/Enums.swift` | `ItemCategory`, `LeatherType`, `ItemCondition` |
| `Leatherfolio/Models/Item.swift` | `Item` @Model (verbatim from master plan) |
| `Leatherfolio/Models/Photo.swift` | `Photo` @Model (verbatim from master plan) |
| `Leatherfolio/Models/Tag.swift` | `Tag` @Model (verbatim from master plan) |
| `Leatherfolio/Services/ImageStore.swift` | ImageIO downsampling, disk + NSCache thumbnail layers |
| `Leatherfolio/Features/Collection/CollectionView.swift` | Grid home + empty state + add sheet |
| `Leatherfolio/Features/Collection/ItemCell.swift` | Grid cell (thumbnail, name, spec line, badges) + `UnicornBadge` |
| `Leatherfolio/Features/AddEdit/AddEditItemModel.swift` | `@Observable` form state + testable save logic |
| `Leatherfolio/Features/AddEdit/AddEditItemView.swift` | Add/edit form (photos, pickers, costs, notes) |
| `Leatherfolio/Features/AddEdit/CameraPicker.swift` | UIImagePickerController camera wrapper |
| `Leatherfolio/Features/Shared/RatingControl.swift` | Reusable 0–5 star control |
| `Leatherfolio/Features/Shared/DecimalParsing.swift` | Decimal <-> text helpers, currency rendering |
| `Leatherfolio/Features/ItemDetail/ItemDetailView.swift` | Hero carousel, chips, costs, QR-label card, edit/delete |
| `Leatherfolio/Features/ItemDetail/ItemDetailLoaderView.swift` | UUID → Item resolution for navigation |
| `Leatherfolio/Features/ItemDetail/ItemDeletion.swift` | `Item.deleteWithCleanup` (cascade + thumbnail cleanup) |
| `LeatherfolioTests/…` | One test file per task, named in each task below |

---

### Task 1: Tooling + project skeleton

**Files:**
- Create: `.gitignore`
- Create: `project.yml`
- Create: `Leatherfolio/App/LeatherfolioApp.swift`
- Create: `Leatherfolio/App/ContentView.swift`
- Create: `LeatherfolioTests/SmokeTests.swift`

**Interfaces:**
- Consumes: nothing (first task).
- Produces: a building, testable Xcode project with scheme `Leatherfolio`, app target `Leatherfolio` (bundle ID `com.robbybarnes.leatherfolio`, URL scheme `leatherfolio`, camera + photo-library usage strings), and unit-test target `LeatherfolioTests`. Every later task depends on `xcodegen generate` + this scheme.

- [ ] **Step 1: Verify XcodeGen is installed (install via Homebrew if missing)**

Run:

```bash
xcodegen --version || brew install xcodegen
```

Expected: a version line such as `Version: 2.44.1` (any 2.x is fine). If Homebrew ran the install, re-run `xcodegen --version` and confirm the version line prints.

- [ ] **Step 2: Create `.gitignore`**

Create `.gitignore` at the repo root with exactly this content (if one already exists, append any missing lines):

```gitignore
# macOS
.DS_Store

# Xcode — the project is generated by XcodeGen; never commit it
*.xcodeproj
xcuserdata/
DerivedData/
build/
.swiftpm/
*.xcresult
```

- [ ] **Step 3: Create `project.yml`**

Create `project.yml` at the repo root:

```yaml
name: Leatherfolio
options:
  bundleIdPrefix: com.robbybarnes
  deploymentTarget:
    iOS: "18.0"
  createIntermediateGroups: true
settings:
  base:
    SWIFT_VERSION: "6.0"
targets:
  Leatherfolio:
    type: application
    platform: iOS
    deploymentTarget: "18.0"
    sources:
      - Leatherfolio
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.robbybarnes.leatherfolio
        TARGETED_DEVICE_FAMILY: "1"
        CURRENT_PROJECT_VERSION: 1
        MARKETING_VERSION: "1.0"
    info:
      path: Leatherfolio/Info.plist
      properties:
        CFBundleDisplayName: My PLG Collection
        UILaunchScreen: {}
        UISupportedInterfaceOrientations:
          - UIInterfaceOrientationPortrait
        NSCameraUsageDescription: "Leatherfolio uses the camera to photograph your items and, later, to scan QR and barcode labels."
        NSPhotoLibraryUsageDescription: "Leatherfolio lets you pick photos of your items from your photo library."
        CFBundleURLTypes:
          - CFBundleURLName: com.robbybarnes.leatherfolio
            CFBundleURLSchemes:
              - leatherfolio
  LeatherfolioTests:
    type: bundle.unit-test
    platform: iOS
    deploymentTarget: "18.0"
    sources:
      - LeatherfolioTests
    settings:
      base:
        GENERATE_INFOPLIST_FILE: YES
    dependencies:
      - target: Leatherfolio
schemes:
  Leatherfolio:
    build:
      targets:
        Leatherfolio: all
    run:
      config: Debug
    test:
      config: Debug
      targets:
        - LeatherfolioTests
```

Notes for the implementer:
- `info.properties` is how the URL scheme (`leatherfolio`) and the camera/photo-library usage descriptions land in `Leatherfolio/Info.plist`. XcodeGen writes that plist file for you on `xcodegen generate` — do not hand-create it. Commit the generated `Leatherfolio/Info.plist` (it is small, diffs cleanly, and keeps fresh clones consistent).
- `SWIFT_VERSION: "6.0"` puts both targets in Swift 6 language mode (strict concurrency on).
- `LeatherfolioTests` depends on the app target, so tests are hosted in the app and can `@testable import Leatherfolio`.

- [ ] **Step 4: Create the minimal app entry point**

Create `Leatherfolio/App/LeatherfolioApp.swift`:

```swift
import SwiftUI

@main
struct LeatherfolioApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

- [ ] **Step 5: Create the minimal root view**

Create `Leatherfolio/App/ContentView.swift`:

```swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        Text("Leatherfolio")
            .font(.largeTitle)
            .padding()
    }
}

#Preview {
    ContentView()
}
```

- [ ] **Step 6: Create a skeleton test so the test target has a source file**

XcodeGen fails if a target's `sources` directory is empty. Create `LeatherfolioTests/SmokeTests.swift`:

```swift
import XCTest
@testable import Leatherfolio

final class SmokeTests: XCTestCase {
    /// Proves the test target builds, links against the app target, and runs.
    func testTargetBuildsAndLinks() {
        XCTAssertEqual(1 + 1, 2)
    }
}
```

- [ ] **Step 7: Generate the Xcode project**

Run:

```bash
xcodegen generate
```

Expected output ends with:

```
Created project at /Users/robbybarnes/GitHub/portland-leather/Leatherfolio.xcodeproj
```

- [ ] **Step 8: Build on the simulator**

Run (substitute an available iPhone simulator from `xcrun simctl list devices available` if `iPhone 16` is not installed):

```bash
xcodegen generate && xcodebuild -project Leatherfolio.xcodeproj -scheme Leatherfolio -destination 'platform=iOS Simulator,name=iPhone 16' build
```

Expected: ends with `** BUILD SUCCEEDED **`.

- [ ] **Step 9: Run the skeleton test**

Run:

```bash
xcodegen generate && xcodebuild -project Leatherfolio.xcodeproj -scheme Leatherfolio -destination 'platform=iOS Simulator,name=iPhone 16' test
```

Expected: `Test Suite 'SmokeTests' passed` and `** TEST SUCCEEDED **`.

- [ ] **Step 10: Commit**

```bash
git add .gitignore project.yml Leatherfolio/App/LeatherfolioApp.swift Leatherfolio/App/ContentView.swift Leatherfolio/Info.plist LeatherfolioTests/SmokeTests.swift
git commit -m "chore: scaffold Leatherfolio project via XcodeGen (iOS 18, Swift 6)"
```

---
### Task 2: SwiftData models (CloudKit-shaped, tested)

**Files:**
- Create: `Leatherfolio/Models/Enums.swift`
- Create: `Leatherfolio/Models/Item.swift`
- Create: `Leatherfolio/Models/Photo.swift`
- Create: `Leatherfolio/Models/Tag.swift`
- Create: `Leatherfolio/App/AppModelContainer.swift`
- Modify: `Leatherfolio/App/LeatherfolioApp.swift`
- Test: `LeatherfolioTests/CloudKitRulesTests.swift`

**Interfaces:**
- Consumes: the project skeleton from Task 1.
- Produces (used by every later task): `ItemCategory`, `LeatherType`, `ItemCondition`; `Item` (with `category`/`leatherType`/`condition` typed accessors, `valueDelta: Decimal?`, `primaryPhoto: Photo?`); `Photo` (`imageData: Data?` external storage, `isPrimary: Bool`); `Tag`; `AppModelContainer.shared: ModelContainer` and `AppModelContainer.make(inMemory:) throws -> ModelContainer`.
- **The enum and model code below is copied verbatim from the master plan's Shared Interfaces section. Do not rename, retype, or "improve" any property.**

- [ ] **Step 1: Write the failing test**

Create `LeatherfolioTests/CloudKitRulesTests.swift`:

```swift
import XCTest
import SwiftData
@testable import Leatherfolio

/// Swift 6 concurrency: SwiftData's mainContext is main-actor-bound, so the
/// whole test class runs on @MainActor.
@MainActor
final class CloudKitRulesTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let container = try AppModelContainer.make(inMemory: true)
        return container.mainContext
    }

    /// CloudKit rule: every property optional or defaulted. If a bare Item()
    /// inserts and saves with no arguments, the rule holds for the schema.
    func testItemWithOnlyDefaultsSaves() throws {
        let context = try makeContext()
        let item = Item()
        context.insert(item)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Item>())
        XCTAssertEqual(fetched.count, 1)
        let saved = try XCTUnwrap(fetched.first)
        XCTAssertEqual(saved.name, "")
        XCTAssertEqual(saved.category, .other)
        XCTAssertEqual(saved.rating, 0)
        XCTAssertFalse(saved.isUnicorn)
        XCTAssertFalse(saved.isWishlist)
        XCTAssertFalse(saved.favorite)
        XCTAssertNil(saved.size)
        XCTAssertNil(saved.color)
        XCTAssertNil(saved.leatherType)
        XCTAssertNil(saved.condition)
        XCTAssertNil(saved.myCost)
        XCTAssertNil(saved.retailCost)
        XCTAssertNil(saved.estimatedValue)
        XCTAssertNil(saved.valueDelta)
        XCTAssertNil(saved.upc)
        XCTAssertNil(saved.dateAcquired)
        XCTAssertNil(saved.notes)
        XCTAssertTrue((saved.photos ?? []).isEmpty)
        XCTAssertTrue((saved.tags ?? []).isEmpty)
        XCTAssertNil(saved.primaryPhoto)
    }

    /// Relationships round-trip in both directions: Item -> Photo/Tag and
    /// the inverses Photo.item / Tag.items.
    func testPhotoAndTagRelationshipsRoundTrip() throws {
        let context = try makeContext()
        let item = Item()
        item.name = "Medium Crossbody Tote"
        let photo = Photo()
        photo.isPrimary = true
        photo.item = item
        let tag = Tag(name: "work")
        item.tags = [tag]
        context.insert(item)
        context.insert(photo)
        context.insert(tag)
        try context.save()

        let items = try context.fetch(FetchDescriptor<Item>())
        let saved = try XCTUnwrap(items.first)
        XCTAssertEqual(saved.photos?.count, 1)
        XCTAssertEqual(saved.primaryPhoto?.id, photo.id)
        XCTAssertEqual(saved.tags?.first?.name, "work")
        XCTAssertEqual(photo.item?.id, saved.id)
        XCTAssertEqual(tag.items?.first?.id, saved.id)
    }

    /// Typed accessors map to/from raw string storage, and valueDelta is
    /// computed (never stored).
    func testTypedAccessorsMapRawStorage() throws {
        let item = Item()
        item.category = .tote
        XCTAssertEqual(item.categoryRaw, "Tote")
        item.leatherType = .pebbled
        XCTAssertEqual(item.leatherTypeRaw, "Pebbled")
        item.condition = .excellent
        XCTAssertEqual(item.conditionRaw, "Excellent")
        item.myCost = 100
        item.estimatedValue = 145
        XCTAssertEqual(item.valueDelta, 45)
        item.myCost = nil
        XCTAssertNil(item.valueDelta)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
xcodegen generate && xcodebuild -project Leatherfolio.xcodeproj -scheme Leatherfolio -destination 'platform=iOS Simulator,name=iPhone 16' test
```

Expected: **FAIL** — the test target does not compile, with errors like `cannot find 'AppModelContainer' in scope` and `cannot find type 'Item' in scope`. (A compile failure of the test target is this step's "red".)

- [ ] **Step 3: Create the enums — verbatim from the master plan**

Create `Leatherfolio/Models/Enums.swift`:

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

- [ ] **Step 4: Create the Item model — verbatim from the master plan**

Create `Leatherfolio/Models/Item.swift`:

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
```

- [ ] **Step 5: Create the Photo model — verbatim from the master plan**

Create `Leatherfolio/Models/Photo.swift`:

```swift
import SwiftData
import Foundation

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
```

- [ ] **Step 6: Create the Tag model — verbatim from the master plan**

Create `Leatherfolio/Models/Tag.swift`:

```swift
import SwiftData
import Foundation

@Model
final class Tag {
    var name: String = ""
    var items: [Item]? = []
    init(name: String = "") { self.name = name }
}
```

- [ ] **Step 7: Create the container factory**

Create `Leatherfolio/App/AppModelContainer.swift`:

```swift
import SwiftData

enum AppConfig {
    /// CloudKit sync is OFF until Apple Developer signing exists.
    /// When flipping this on, change `cloudKitDatabase: .none` below to
    /// `.automatic` and add the iCloud capability — that is the whole flip,
    /// because the schema obeys every CloudKit rule already.
    static let cloudKitEnabled = false
}

@MainActor
enum AppModelContainer {
    /// The app's on-disk container. Tests use make(inMemory: true) instead.
    static let shared: ModelContainer = {
        do {
            return try make(inMemory: false)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()

    static func make(inMemory: Bool) throws -> ModelContainer {
        let schema = Schema([Item.self, Photo.self, Tag.self])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .none  // one-line flip to .automatic later (see AppConfig)
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
```

- [ ] **Step 8: Attach the container to the app**

Replace the entire contents of `Leatherfolio/App/LeatherfolioApp.swift` with:

```swift
import SwiftUI

@main
struct LeatherfolioApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(AppModelContainer.shared)
    }
}
```

- [ ] **Step 9: Run the tests to verify they pass**

Run:

```bash
xcodegen generate && xcodebuild -project Leatherfolio.xcodeproj -scheme Leatherfolio -destination 'platform=iOS Simulator,name=iPhone 16' test
```

Expected: `Test Suite 'CloudKitRulesTests' passed` (3 tests) and `** TEST SUCCEEDED **`.

- [ ] **Step 10: Commit**

```bash
git add Leatherfolio/Models/Enums.swift Leatherfolio/Models/Item.swift Leatherfolio/Models/Photo.swift Leatherfolio/Models/Tag.swift Leatherfolio/App/AppModelContainer.swift Leatherfolio/App/LeatherfolioApp.swift LeatherfolioTests/CloudKitRulesTests.swift
git commit -m "feat: add SwiftData models with CloudKit-safe schema and container factory"
```

---
### Task 3: ImageStore (ImageIO downsampling + two-layer thumbnail cache)

**Files:**
- Create: `Leatherfolio/Services/ImageStore.swift`
- Test: `LeatherfolioTests/ImageStoreTests.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks (pure service; `Photo` IDs are just UUIDs to it).
- Produces (master-plan contract — do not rename):
  - `ImageStore.shared`
  - `func thumbnail(for photoID: UUID, imageData: Data?) async -> UIImage?`
  - `func deleteThumbnail(for photoID: UUID)`
  - `func downsampledJPEG(from data: Data, maxDimension: CGFloat) -> Data?`
  - Additive helpers this plan also defines (later tasks and tests use them): `init(directory: URL? = nil)` and `func thumbnailFileURL(for photoID: UUID) -> URL`.
- Task 4's `ItemCell` calls `thumbnail(for:imageData:)`; Task 5's save calls `downsampledJPEG(from:maxDimension:)` with `2_048`; Task 6's delete calls `deleteThumbnail(for:)`.

- [ ] **Step 1: Write the failing tests**

Create `LeatherfolioTests/ImageStoreTests.swift`:

```swift
import XCTest
import UIKit
@testable import Leatherfolio

@MainActor
final class ImageStoreTests: XCTestCase {

    private var tempDirectory: URL!
    private var store: ImageStore!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageStoreTests-\(UUID().uuidString)", isDirectory: true)
        store = ImageStore(directory: tempDirectory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    /// 2000x1000 solid-color JPEG rendered at scale 1 so pixel math is exact.
    private func makeTestJPEGData(width: CGFloat = 2_000, height: CGFloat = 1_000) throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: width, height: height), format: format)
        let image = renderer.image { context in
            UIColor.brown.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        return try XCTUnwrap(image.jpegData(compressionQuality: 0.9))
    }

    func testDownsampledJPEGCapsMaxDimensionAndKeepsAspect() throws {
        let data = try makeTestJPEGData()
        let result = try XCTUnwrap(store.downsampledJPEG(from: data, maxDimension: 400))
        let image = try XCTUnwrap(UIImage(data: result))
        XCTAssertLessThanOrEqual(max(image.size.width, image.size.height), 400)
        XCTAssertEqual(image.size.width / image.size.height, 2.0, accuracy: 0.05,
                       "aspect ratio must be preserved")
    }

    func testThumbnailGeneratesCachesAndPersistsToDisk() async throws {
        let data = try makeTestJPEGData()
        let photoID = UUID()

        let thumbnail = try XCTUnwrap(await store.thumbnail(for: photoID, imageData: data))
        XCTAssertLessThanOrEqual(
            max(thumbnail.size.width * thumbnail.scale,
                thumbnail.size.height * thumbnail.scale), 400)

        let fileURL = store.thumbnailFileURL(for: photoID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path),
                      "thumbnail JPEG must be cached on disk")

        // Second call must serve without any source data (disk/NSCache hit).
        let cached = await store.thumbnail(for: photoID, imageData: nil)
        XCTAssertNotNil(cached)
    }

    func testDeleteThumbnailRemovesFileAndCacheEntry() async throws {
        let data = try makeTestJPEGData()
        let photoID = UUID()
        _ = await store.thumbnail(for: photoID, imageData: data)
        let fileURL = store.thumbnailFileURL(for: photoID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        store.deleteThumbnail(for: photoID)

        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        let afterDelete = await store.thumbnail(for: photoID, imageData: nil)
        XCTAssertNil(afterDelete, "no cache layer may survive deleteThumbnail")
    }

    func testDownsampledJPEGReturnsNilForGarbageData() {
        XCTAssertNil(store.downsampledJPEG(from: Data([0x00, 0x01, 0x02]), maxDimension: 400))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:

```bash
xcodegen generate && xcodebuild -project Leatherfolio.xcodeproj -scheme Leatherfolio -destination 'platform=iOS Simulator,name=iPhone 16' test
```

Expected: **FAIL** — test target does not compile: `cannot find 'ImageStore' in scope`.

- [ ] **Step 3: Implement ImageStore**

Create `Leatherfolio/Services/ImageStore.swift`:

```swift
import UIKit
import ImageIO

/// Thumbnails cached as ~400px JPEGs in Caches/thumbnails/<photo-uuid>.jpg.
/// Originals live in Photo.imageData (externalStorage). Detail views load
/// originals directly; every grid/list goes through thumbnail(for:).
///
/// `@unchecked Sendable`: both stored properties are immutable references to
/// types Apple documents as thread-safe (NSCache; FileManager.default).
final class ImageStore: @unchecked Sendable {
    static let shared = ImageStore()

    static let thumbnailMaxDimension: CGFloat = 400

    private let memoryCache = NSCache<NSString, UIImage>()
    private let directory: URL

    /// Pass a custom directory in tests; defaults to Caches/thumbnails.
    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: self.directory, withIntermediateDirectories: true)
    }

    func thumbnailFileURL(for photoID: UUID) -> URL {
        directory.appendingPathComponent("\(photoID.uuidString).jpg")
    }

    /// Memory cache → disk cache → generate-from-original, in that order.
    /// Returns nil only when no cached thumbnail exists and imageData is nil
    /// or undecodable.
    func thumbnail(for photoID: UUID, imageData: Data?) async -> UIImage? {
        let key = photoID.uuidString as NSString
        if let cached = memoryCache.object(forKey: key) {
            return cached
        }
        let fileURL = thumbnailFileURL(for: photoID)
        if let diskData = try? Data(contentsOf: fileURL),
           let image = UIImage(data: diskData) {
            memoryCache.setObject(image, forKey: key)
            return image
        }
        guard let imageData,
              let jpegData = downsampledJPEG(
                  from: imageData, maxDimension: Self.thumbnailMaxDimension),
              let image = UIImage(data: jpegData) else {
            return nil
        }
        try? jpegData.write(to: fileURL, options: .atomic)
        memoryCache.setObject(image, forKey: key)
        return image
    }

    func deleteThumbnail(for photoID: UUID) {
        memoryCache.removeObject(forKey: photoID.uuidString as NSString)
        try? FileManager.default.removeItem(at: thumbnailFileURL(for: photoID))
    }

    /// ImageIO downsampling: decodes at most maxDimension pixels on the long
    /// edge without ever inflating the full-size bitmap into memory. Used
    /// both for thumbnails (400) and for shrinking imports before storage
    /// (2048, see AddEditItemModel.save).
    func downsampledJPEG(from data: Data, maxDimension: CGFloat) -> Data? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            return nil
        }
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.8)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:

```bash
xcodegen generate && xcodebuild -project Leatherfolio.xcodeproj -scheme Leatherfolio -destination 'platform=iOS Simulator,name=iPhone 16' test
```

Expected: `Test Suite 'ImageStoreTests' passed` (4 tests) and `** TEST SUCCEEDED **` (CloudKitRulesTests and SmokeTests still green).

- [ ] **Step 5: Commit**

```bash
git add Leatherfolio/Services/ImageStore.swift LeatherfolioTests/ImageStoreTests.swift
git commit -m "feat: add ImageStore with ImageIO downsampling and two-layer thumbnail cache"
```

---
### Task 4: Collection grid + empty state

**Files:**
- Create: `Leatherfolio/Features/Collection/CollectionView.swift`
- Create: `Leatherfolio/Features/Collection/ItemCell.swift`
- Modify: `Leatherfolio/App/ContentView.swift`
- Test: `LeatherfolioTests/CollectionViewSmokeTests.swift`

**Interfaces:**
- Consumes: `Item` (Task 2: `name`, `size`, `color`, `category`, `isUnicorn`, `favorite`, `createdAt`, `primaryPhoto`), `ImageStore.shared.thumbnail(for:imageData:)` (Task 3), `AppModelContainer.make(inMemory:)` (Task 2, tests).
- Produces: `CollectionView` (home screen; `@State private var showingAdd` drives an add sheet whose stub content Task 5 replaces), `ItemCell`, `UnicornBadge` (reused by Task 6's detail header). Navigation pushes `UUID` values; ContentView's `navigationDestination(for: UUID.self)` stub is replaced in Task 6.

- [ ] **Step 1: Write the failing tests**

Create `LeatherfolioTests/CollectionViewSmokeTests.swift`:

```swift
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:

```bash
xcodegen generate && xcodebuild -project Leatherfolio.xcodeproj -scheme Leatherfolio -destination 'platform=iOS Simulator,name=iPhone 16' test
```

Expected: **FAIL** — test target does not compile: `cannot find 'CollectionView' in scope`.

- [ ] **Step 3: Implement the grid cell + unicorn badge**

Create `Leatherfolio/Features/Collection/ItemCell.swift`:

```swift
import SwiftUI

struct ItemCell: View {
    let item: Item
    @State private var thumbnail: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                thumbnailView
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                if item.isUnicorn {
                    UnicornBadge()
                        .padding(6)
                }
            }
            HStack(spacing: 4) {
                Text(item.name.isEmpty ? "Untitled" : item.name)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                if item.favorite {
                    Image(systemName: "heart.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .accessibilityLabel("Favorite")
                }
            }
            Text(specLine)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .task(id: item.primaryPhoto?.id) {
            await loadThumbnail()
        }
        .accessibilityElement(children: .combine)
    }

    /// "Medium · Honey" when size/color exist; falls back to the category.
    private var specLine: String {
        let parts = [item.size, item.color]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? item.category.rawValue : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let thumbnail {
            Image(uiImage: thumbnail)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                Rectangle()
                    .fill(Color(.secondarySystemBackground))
                Image(systemName: "bag")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    /// Grid cells only ever touch ImageStore thumbnails — never full-res
    /// Photo.imageData decoding in the scroll path beyond this one pass.
    private func loadThumbnail() async {
        guard let photo = item.primaryPhoto else {
            thumbnail = nil
            return
        }
        thumbnail = await ImageStore.shared.thumbnail(
            for: photo.id, imageData: photo.imageData)
    }
}

/// Star-on-unicorn badge treatment for one-of-one items.
struct UnicornBadge: View {
    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "star.fill")
                .font(.system(size: 9))
                .foregroundStyle(.yellow)
            Text("🦄")
                .font(.system(size: 11))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.thinMaterial, in: Capsule())
        .accessibilityLabel("Unicorn item")
    }
}
```

- [ ] **Step 4: Implement the collection screen**

Create `Leatherfolio/Features/Collection/CollectionView.swift`:

```swift
import SwiftUI
import SwiftData

struct CollectionView: View {
    @Query(sort: \Item.createdAt, order: .reverse) private var items: [Item]
    @State private var showingAdd = false

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 12)]

    var body: some View {
        Group {
            if items.isEmpty {
                emptyState
            } else {
                grid
            }
        }
        .navigationTitle("Leatherfolio")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAdd = true
                } label: {
                    Label("Add Item", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAdd) {
            // Task 5 replaces this stub with AddEditItemView(item: nil).
            Text("Add flow arrives in the next task.")
                .padding()
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(items) { item in
                    NavigationLink(value: item.id) {
                        ItemCell(item: item)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No items yet", systemImage: "bag")
        } description: {
            Text("Your leather collection starts here.")
        } actions: {
            Button("Add your first item") {
                showingAdd = true
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
```

- [ ] **Step 5: Point the root view at the grid, with a stubbed detail destination**

Replace the entire contents of `Leatherfolio/App/ContentView.swift` with:

```swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            CollectionView()
                .navigationDestination(for: UUID.self) { itemID in
                    // Task 6 replaces this stub with
                    // ItemDetailLoaderView(itemID: itemID).
                    Text("Item \(itemID.uuidString)")
                }
        }
    }
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run:

```bash
xcodegen generate && xcodebuild -project Leatherfolio.xcodeproj -scheme Leatherfolio -destination 'platform=iOS Simulator,name=iPhone 16' test
```

Expected: `Test Suite 'CollectionViewSmokeTests' passed` (2 tests) and `** TEST SUCCEEDED **` (all earlier suites still green).

- [ ] **Step 7: Manual simulator check (30 seconds)**

Build and run in the simulator (open `Leatherfolio.xcodeproj` in Xcode and Cmd-R, or install via the build products). Verify: the empty state renders with the "Add your first item" button, and tapping it shows the stub sheet.

- [ ] **Step 8: Commit**

```bash
git add Leatherfolio/Features/Collection/CollectionView.swift Leatherfolio/Features/Collection/ItemCell.swift Leatherfolio/App/ContentView.swift LeatherfolioTests/CollectionViewSmokeTests.swift
git commit -m "feat: add collection grid with empty state and thumbnail cells"
```

---
### Task 5: Add flow (photo-first form with testable save model)

**Files:**
- Create: `Leatherfolio/Features/Shared/DecimalParsing.swift`
- Create: `Leatherfolio/Features/Shared/RatingControl.swift`
- Create: `Leatherfolio/Features/AddEdit/AddEditItemModel.swift`
- Create: `Leatherfolio/Features/AddEdit/AddEditItemView.swift`
- Create: `Leatherfolio/Features/AddEdit/CameraPicker.swift`
- Modify: `Leatherfolio/Features/Collection/CollectionView.swift` (replace add-sheet stub)
- Test: `LeatherfolioTests/AddEditItemModelTests.swift`

**Interfaces:**
- Consumes: `Item`, `Photo` (Task 2), `AppModelContainer.make(inMemory:)` (Task 2, tests), `ImageStore.downsampledJPEG(from:maxDimension:)` and `ImageStore.shared` (Task 3).
- Produces:
  - `AddEditItemView(item: Item?)` — one form for add (`nil`) and edit (non-nil). Task 6's detail view presents `AddEditItemView(item: item)`.
  - `AddEditItemModel` — `@MainActor @Observable`; `init(item: Item?)`; `@discardableResult func save(in context: ModelContext, imageStore: ImageStore = .shared) throws -> Item`; `var canSave: Bool`; photo queue `newPhotoDatas: [Data]`.
  - **Phase 2 injection point:** `AddEditItemModel.sizeOptions: [String]` and `colorOptions: [String]` (CatalogSeed-shaped arrays). Empty (the Phase 1 default) means the form shows free-text fields; Phase 2 fills them to get pickers. Do not rename these two properties.
  - `RatingControl(rating: Binding<Int>)` — reusable 0–5 stars; Task 6's detail view reuses it.
  - `DecimalParsing.decimal(from:)`, `DecimalParsing.text(from:)`, `Decimal.currencyDisplay` — Task 6's costs block reuses `currencyDisplay`.

- [ ] **Step 1: Write the failing tests for the form model**

Create `LeatherfolioTests/AddEditItemModelTests.swift`:

```swift
import XCTest
import SwiftData
import UIKit
@testable import Leatherfolio

@MainActor
final class AddEditItemModelTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        try AppModelContainer.make(inMemory: true).mainContext
    }

    /// 2000x1000 solid-color JPEG at scale 1 (same shape as a picked photo).
    private func makeTestJPEGData() throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: 2_000, height: 1_000), format: format)
        let image = renderer.image { context in
            UIColor.brown.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2_000, height: 1_000))
        }
        return try XCTUnwrap(image.jpegData(compressionQuality: 0.9))
    }

    func testSaveWithNameOnlyProducesValidItem() throws {
        let context = try makeContext()
        let model = AddEditItemModel(item: nil)
        model.name = "  Honey Tote  "

        let item = try model.save(in: context)

        XCTAssertEqual(item.name, "Honey Tote")
        XCTAssertEqual(item.category, .other)
        XCTAssertNil(item.size)
        XCTAssertNil(item.color)
        XCTAssertNil(item.myCost)
        XCTAssertNil(item.dateAcquired)
        XCTAssertNil(item.notes)
        XCTAssertTrue((item.photos ?? []).isEmpty)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Item>()).count, 1)
    }

    func testCanSaveRequiresNonBlankName() throws {
        let model = AddEditItemModel(item: nil)
        XCTAssertFalse(model.canSave)
        model.name = "   "
        XCTAssertFalse(model.canSave)
        model.name = "Wallet"
        XCTAssertTrue(model.canSave)
    }

    func testSaveParsesDecimalCurrencyFields() throws {
        let context = try makeContext()
        let model = AddEditItemModel(item: nil)
        model.name = "Wallet"
        model.myCostText = "125.50"
        model.estimatedValueText = "180"

        let item = try model.save(in: context)

        XCTAssertEqual(item.myCost, Decimal(string: "125.50", locale: .current))
        XCTAssertEqual(item.estimatedValue, 180)
        XCTAssertEqual(item.valueDelta, Decimal(string: "54.50", locale: .current))
        XCTAssertNil(item.retailCost)
    }

    func testSaveAttachesDownsampledPrimaryPhoto() throws {
        let context = try makeContext()
        let model = AddEditItemModel(item: nil)
        model.name = "Belt Bag"
        model.newPhotoDatas = [try makeTestJPEGData()]

        let item = try model.save(in: context)

        XCTAssertEqual(item.photos?.count, 1)
        let photo = try XCTUnwrap(item.primaryPhoto)
        XCTAssertTrue(photo.isPrimary, "first photo becomes primary")
        let data = try XCTUnwrap(photo.imageData, "externalStorage data must be set")
        let image = try XCTUnwrap(UIImage(data: data))
        XCTAssertLessThanOrEqual(max(image.size.width, image.size.height), 2_048,
                                 "originals are stored downsampled to 2048")
    }

    func testUndecodablePhotoIsSkippedButItemStillSaves() throws {
        let context = try makeContext()
        let model = AddEditItemModel(item: nil)
        model.name = "Cardholder"
        model.newPhotoDatas = [Data([0x00, 0x01, 0x02])]

        let item = try model.save(in: context)

        XCTAssertTrue((item.photos ?? []).isEmpty,
                      "bad image data must not block the item save")
        XCTAssertEqual(try context.fetch(FetchDescriptor<Item>()).count, 1)
    }

    func testEditingExistingItemUpdatesInPlace() throws {
        let context = try makeContext()
        let create = AddEditItemModel(item: nil)
        create.name = "Original"
        let item = try create.save(in: context)
        let firstUpdatedAt = item.updatedAt

        let edit = AddEditItemModel(item: item)
        XCTAssertTrue(edit.isEditing)
        XCTAssertEqual(edit.name, "Original")
        edit.name = "Renamed"
        edit.rating = 4
        edit.isUnicorn = true
        let saved = try edit.save(in: context)

        XCTAssertEqual(saved.id, item.id)
        XCTAssertEqual(saved.name, "Renamed")
        XCTAssertEqual(saved.rating, 4)
        XCTAssertTrue(saved.isUnicorn)
        XCTAssertGreaterThanOrEqual(saved.updatedAt, firstUpdatedAt)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Item>()).count, 1,
                       "edit must not create a second item")
    }

    func testSecondPhotoDoesNotStealPrimary() throws {
        let context = try makeContext()
        let create = AddEditItemModel(item: nil)
        create.name = "Tote"
        create.newPhotoDatas = [try makeTestJPEGData()]
        let item = try create.save(in: context)
        let originalPrimaryID = try XCTUnwrap(item.primaryPhoto?.id)

        let edit = AddEditItemModel(item: item)
        edit.newPhotoDatas = [try makeTestJPEGData()]
        _ = try edit.save(in: context)

        XCTAssertEqual(item.photos?.count, 2)
        XCTAssertEqual(item.primaryPhoto?.id, originalPrimaryID)
        XCTAssertEqual(item.photos?.filter(\.isPrimary).count, 1)
    }
}
```

Note (locale): `DecimalParsing` parses with `Locale.current` and the assertions also build their expected values with `Locale.current`, so the test is self-consistent. Simulators default to en_US.

- [ ] **Step 2: Run the tests to verify they fail**

Run:

```bash
xcodegen generate && xcodebuild -project Leatherfolio.xcodeproj -scheme Leatherfolio -destination 'platform=iOS Simulator,name=iPhone 16' test
```

Expected: **FAIL** — test target does not compile: `cannot find 'AddEditItemModel' in scope`.

- [ ] **Step 3: Implement the Decimal helpers**

Create `Leatherfolio/Features/Shared/DecimalParsing.swift`:

```swift
import Foundation

/// Locale-aware Decimal <-> text helpers for the currency fields.
enum DecimalParsing {
    static func decimal(from text: String) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return Decimal(string: trimmed, locale: .current)
    }

    static func text(from decimal: Decimal?) -> String {
        guard let decimal else { return "" }
        return "\(decimal)"
    }
}

extension Decimal {
    /// "$125.50"-style rendering in the user's locale currency
    /// (global constraint: money is Decimal, rendered per locale).
    var currencyDisplay: String {
        formatted(.currency(code: Locale.current.currency?.identifier ?? "USD"))
    }
}
```

- [ ] **Step 4: Implement the reusable star rating control**

Create `Leatherfolio/Features/Shared/RatingControl.swift`:

```swift
import SwiftUI

/// Reusable 0–5 star control. Tapping the currently selected star clears the
/// rating back to 0 (0 = unrated, matching Item.rating's contract).
struct RatingControl: View {
    @Binding var rating: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: star <= rating ? "star.fill" : "star")
                    .foregroundStyle(star <= rating ? .yellow : .secondary)
                    .onTapGesture {
                        rating = (rating == star) ? 0 : star
                    }
                    .accessibilityLabel("\(star) star\(star == 1 ? "" : "s")")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(rating) of 5 stars")
    }
}
```

- [ ] **Step 5: Implement the form model**

Create `Leatherfolio/Features/AddEdit/AddEditItemModel.swift`:

```swift
import Foundation
import Observation
import SwiftData

/// Form state + save logic for both add and edit, extracted from the view so
/// the save path is unit-testable without any UI.
@MainActor
@Observable
final class AddEditItemModel {

    // MARK: Form fields
    var name = ""
    var category: ItemCategory = .other
    var sizeText = ""
    var colorText = ""
    var leatherType: LeatherType?
    var condition: ItemCondition?
    var rating = 0
    var isUnicorn = false
    var favorite = false
    var isWishlist = false
    var myCostText = ""
    var retailCostText = ""
    var estimatedValueText = ""
    var hasDateAcquired = false
    var dateAcquired = Date.now
    var notes = ""

    /// JPEG/HEIC data of photos picked this session, in pick order.
    var newPhotoDatas: [Data] = []

    // MARK: Phase 2 injection point (cascading pickers)
    // Phase 2's CatalogSeed fills these from plg_catalog.json. Empty means
    // "no curated options" and the form falls back to free-text fields —
    // which is the entire Phase 1 behavior. Do not rename.
    var sizeOptions: [String] = []
    var colorOptions: [String] = []

    private(set) var existingItem: Item?
    var isEditing: Bool { existingItem != nil }
    var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    init(item: Item?) {
        existingItem = item
        guard let item else { return }
        name = item.name
        category = item.category
        sizeText = item.size ?? ""
        colorText = item.color ?? ""
        leatherType = item.leatherType
        condition = item.condition
        rating = item.rating
        isUnicorn = item.isUnicorn
        favorite = item.favorite
        isWishlist = item.isWishlist
        myCostText = DecimalParsing.text(from: item.myCost)
        retailCostText = DecimalParsing.text(from: item.retailCost)
        estimatedValueText = DecimalParsing.text(from: item.estimatedValue)
        hasDateAcquired = item.dateAcquired != nil
        dateAcquired = item.dateAcquired ?? .now
        notes = item.notes ?? ""
    }

    /// Writes the form into a new or existing Item, downsampling (2048 max
    /// dimension) and attaching any newly picked photos. The first photo an
    /// item ever gets becomes primary. Photos that fail to decode are
    /// skipped so the item still saves (spec: never lose user input over an
    /// image failure).
    @discardableResult
    func save(in context: ModelContext, imageStore: ImageStore = .shared) throws -> Item {
        let item = existingItem ?? Item()
        if existingItem == nil {
            context.insert(item)
        }
        item.name = name.trimmingCharacters(in: .whitespaces)
        item.category = category
        item.size = normalized(sizeText)
        item.color = normalized(colorText)
        item.leatherType = leatherType
        item.condition = condition
        item.rating = rating
        item.isUnicorn = isUnicorn
        item.favorite = favorite
        item.isWishlist = isWishlist
        item.myCost = DecimalParsing.decimal(from: myCostText)
        item.retailCost = DecimalParsing.decimal(from: retailCostText)
        item.estimatedValue = DecimalParsing.decimal(from: estimatedValueText)
        item.dateAcquired = hasDateAcquired ? dateAcquired : nil
        item.notes = normalized(notes)
        item.updatedAt = .now

        var hasPrimary = (item.photos ?? []).contains(where: \.isPrimary)
        for data in newPhotoDatas {
            guard let jpeg = imageStore.downsampledJPEG(from: data, maxDimension: 2_048) else {
                continue  // undecodable photo: skip it, keep the item
            }
            let photo = Photo()
            photo.imageData = jpeg
            photo.isPrimary = !hasPrimary
            hasPrimary = true
            photo.item = item
            context.insert(photo)
        }
        newPhotoDatas = []
        try context.save()
        return item
    }

    private func normalized(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
```

- [ ] **Step 6: Run the model tests to verify they pass**

Run:

```bash
xcodegen generate && xcodebuild -project Leatherfolio.xcodeproj -scheme Leatherfolio -destination 'platform=iOS Simulator,name=iPhone 16' test
```

Expected: `Test Suite 'AddEditItemModelTests' passed` (7 tests) and `** TEST SUCCEEDED **` (all earlier suites still green).

- [ ] **Step 7: Implement the camera wrapper**

Create `Leatherfolio/Features/AddEdit/CameraPicker.swift`:

```swift
import SwiftUI
import UIKit

/// UIImagePickerController wrapper for camera capture. The simulator has no
/// camera, so this path can only be exercised on hardware — see the manual
/// device-test note at the end of this task. Callers must check
/// UIImagePickerController.isSourceTypeAvailable(.camera) before presenting
/// (AddEditItemView hides the button otherwise).
struct CameraPicker: UIViewControllerRepresentable {
    let onCapture: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate,
                             UINavigationControllerDelegate {
        private let parent: CameraPicker

        init(_ parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage,
               let data = image.jpegData(compressionQuality: 0.9) {
                parent.onCapture(data)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
```

- [ ] **Step 8: Implement the add/edit form view**

Create `Leatherfolio/Features/AddEdit/AddEditItemView.swift`:

```swift
import SwiftUI
import SwiftData
import PhotosUI

/// One form for both add (item == nil) and edit (item != nil).
struct AddEditItemView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var model: AddEditItemModel
    @State private var selectedPickerItems: [PhotosPickerItem] = []
    @State private var showingCamera = false
    @State private var showingSaveError = false

    init(item: Item?) {
        _model = State(initialValue: AddEditItemModel(item: item))
    }

    var body: some View {
        NavigationStack {
            Form {
                photosSection
                basicsSection
                flagsSection
                costsSection
                acquiredSection
                notesSection
            }
            .navigationTitle(model.isEditing ? "Edit Item" : "New Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!model.canSave)
                }
            }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraPicker { data in
                    model.newPhotoDatas.append(data)
                }
                .ignoresSafeArea()
            }
            .alert("Couldn't save item", isPresented: $showingSaveError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Something went wrong writing to the library. Please try again.")
            }
            .onChange(of: selectedPickerItems) {
                Task { await loadPickedPhotos() }
            }
        }
    }

    // MARK: Sections

    private var photosSection: some View {
        Section("Photos") {
            if !model.newPhotoDatas.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(Array(model.newPhotoDatas.enumerated()), id: \.offset) { _, data in
                            if let image = UIImage(data: data) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 72, height: 72)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }
            }
            PhotosPicker(selection: $selectedPickerItems,
                         maxSelectionCount: 5,
                         matching: .images) {
                Label("Choose from Library", systemImage: "photo.on.rectangle")
            }
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button {
                    showingCamera = true
                } label: {
                    Label("Take Photo", systemImage: "camera")
                }
            }
        }
    }

    private var basicsSection: some View {
        Section("Details") {
            TextField("Name", text: $model.name)
            Picker("Category", selection: $model.category) {
                ForEach(ItemCategory.allCases) { category in
                    Text(category.rawValue).tag(category)
                }
            }
            // Phase 2 injection point: when CatalogSeed provides options,
            // these two fields become cascading pickers. Empty options mean
            // free-text — all of Phase 1.
            if model.sizeOptions.isEmpty {
                TextField("Size", text: $model.sizeText)
            } else {
                Picker("Size", selection: $model.sizeText) {
                    Text("None").tag("")
                    ForEach(model.sizeOptions, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
            }
            if model.colorOptions.isEmpty {
                TextField("Color", text: $model.colorText)
            } else {
                Picker("Color", selection: $model.colorText) {
                    Text("None").tag("")
                    ForEach(model.colorOptions, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
            }
            Picker("Leather", selection: $model.leatherType) {
                Text("None").tag(LeatherType?.none)
                ForEach(LeatherType.allCases) { type in
                    Text(type.rawValue).tag(LeatherType?.some(type))
                }
            }
            Picker("Condition", selection: $model.condition) {
                Text("None").tag(ItemCondition?.none)
                ForEach(ItemCondition.allCases) { condition in
                    Text(condition.rawValue).tag(ItemCondition?.some(condition))
                }
            }
        }
    }

    private var flagsSection: some View {
        Section("Rating & Flags") {
            HStack {
                Text("Rating")
                Spacer()
                RatingControl(rating: $model.rating)
            }
            Toggle("Unicorn 🦄", isOn: $model.isUnicorn)
            Toggle("Favorite", isOn: $model.favorite)
            Toggle("Wishlist", isOn: $model.isWishlist)
        }
    }

    private var costsSection: some View {
        Section("Costs & Value") {
            currencyRow("My cost", text: $model.myCostText)
            currencyRow("Retail cost", text: $model.retailCostText)
            currencyRow("Estimated value", text: $model.estimatedValueText)
        }
    }

    private func currencyRow(_ label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", text: text)
                .multilineTextAlignment(.trailing)
                // .decimalPad rather than .numberPad: currency entry needs
                // the decimal-separator key. Parsed into Decimal via
                // DecimalParsing.decimal(from:) at save time.
                .keyboardType(.decimalPad)
                .frame(maxWidth: 120)
        }
    }

    private var acquiredSection: some View {
        Section {
            Toggle("Date acquired", isOn: $model.hasDateAcquired.animation())
            if model.hasDateAcquired {
                DatePicker("Acquired on", selection: $model.dateAcquired,
                           displayedComponents: .date)
            }
        }
    }

    private var notesSection: some View {
        Section("Notes") {
            TextEditor(text: $model.notes)
                .frame(minHeight: 96)
        }
    }

    // MARK: Actions

    private func save() {
        do {
            try model.save(in: modelContext)
            dismiss()
        } catch {
            showingSaveError = true
        }
    }

    private func loadPickedPhotos() async {
        for pickerItem in selectedPickerItems {
            if let data = try? await pickerItem.loadTransferable(type: Data.self) {
                model.newPhotoDatas.append(data)
            }
        }
        selectedPickerItems = []
    }
}
```

- [ ] **Step 9: Replace the add-sheet stub in CollectionView**

In `Leatherfolio/Features/Collection/CollectionView.swift`, replace:

```swift
        .sheet(isPresented: $showingAdd) {
            // Task 5 replaces this stub with AddEditItemView(item: nil).
            Text("Add flow arrives in the next task.")
                .padding()
        }
```

with:

```swift
        .sheet(isPresented: $showingAdd) {
            AddEditItemView(item: nil)
        }
```

- [ ] **Step 10: Build and run the full test suite**

Run:

```bash
xcodegen generate && xcodebuild -project Leatherfolio.xcodeproj -scheme Leatherfolio -destination 'platform=iOS Simulator,name=iPhone 16' test
```

Expected: `** TEST SUCCEEDED **` — all suites green (SmokeTests, CloudKitRulesTests, ImageStoreTests, CollectionViewSmokeTests, AddEditItemModelTests).

- [ ] **Step 11: Manual simulator check (2 minutes)**

Run the app in the simulator: tap "Add your first item", pick a photo from the simulator's built-in library (PhotosPicker works in-sim), fill in a name, save. The item must appear in the grid with its thumbnail. **Camera note:** the "Take Photo" button is hidden in the simulator (no camera hardware); verifying CameraPicker requires a physical device — record that as an open manual milestone, do not block this task on it.

- [ ] **Step 12: Commit**

```bash
git add Leatherfolio/Features/Shared/DecimalParsing.swift Leatherfolio/Features/Shared/RatingControl.swift Leatherfolio/Features/AddEdit/AddEditItemModel.swift Leatherfolio/Features/AddEdit/AddEditItemView.swift Leatherfolio/Features/AddEdit/CameraPicker.swift Leatherfolio/Features/Collection/CollectionView.swift LeatherfolioTests/AddEditItemModelTests.swift
git commit -m "feat: add photo-first add/edit item flow with testable form model"
```

---
### Task 6: Item detail view (carousel, chips, costs, delete)

**Files:**
- Create: `Leatherfolio/Features/ItemDetail/ItemDeletion.swift`
- Create: `Leatherfolio/Features/ItemDetail/ItemDetailView.swift`
- Create: `Leatherfolio/Features/ItemDetail/ItemDetailLoaderView.swift`
- Modify: `Leatherfolio/App/ContentView.swift` (replace detail stub)
- Test: `LeatherfolioTests/ItemDeletionTests.swift`

**Interfaces:**
- Consumes: `Item`/`Photo` (Task 2), `ImageStore.shared.deleteThumbnail(for:)` + `ImageStore(directory:)` + `thumbnailFileURL(for:)` (Task 3), `UnicornBadge` (Task 4), `AddEditItemView(item:)` + `RatingControl(rating:)` + `Decimal.currencyDisplay` (Task 5).
- Produces: `ItemDetailView(item: Item)`, `ItemDetailLoaderView(itemID: UUID)` (the navigation destination Task 7's router pushes to), and `Item.deleteWithCleanup(in:imageStore:)` — the one delete path in the app (cascade-deletes photos, purges thumbnails).
- The **QR label card** in this view is a real shipping intermediate: the card exists now and renders the item UUID as selectable text; Phase 3 swaps its body for the CIFilter-generated QR image (`QRService.qrImage`). The card view itself — not its content — is the stable seam.

- [ ] **Step 1: Write the failing deletion tests**

Create `LeatherfolioTests/ItemDeletionTests.swift`:

```swift
import XCTest
import SwiftData
import UIKit
@testable import Leatherfolio

@MainActor
final class ItemDeletionTests: XCTestCase {

    private func makeTestJPEGData() throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: 800, height: 600), format: format)
        let image = renderer.image { context in
            UIColor.brown.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 800, height: 600))
        }
        return try XCTUnwrap(image.jpegData(compressionQuality: 0.9))
    }

    func testDeleteCascadesPhotosAndRemovesThumbnails() async throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = container.mainContext
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ItemDeletionTests-\(UUID().uuidString)",
                                    isDirectory: true)
        let store = ImageStore(directory: tempDirectory)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        // Item with one photo whose thumbnail is materialized on disk.
        let item = Item()
        item.name = "Coldbrew Crossbody"
        let photo = Photo()
        photo.imageData = try makeTestJPEGData()
        photo.isPrimary = true
        photo.item = item
        context.insert(item)
        context.insert(photo)
        try context.save()
        _ = await store.thumbnail(for: photo.id, imageData: photo.imageData)
        let thumbnailURL = store.thumbnailFileURL(for: photo.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: thumbnailURL.path))

        try item.deleteWithCleanup(in: context, imageStore: store)

        XCTAssertEqual(try context.fetch(FetchDescriptor<Item>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Photo>()).count, 0,
                       "cascade rule must delete photos with the item")
        XCTAssertFalse(FileManager.default.fileExists(atPath: thumbnailURL.path),
                       "delete must also purge the disk thumbnail")
    }

    func testDeleteItemWithoutPhotosJustDeletes() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = container.mainContext
        let item = Item()
        item.name = "No photos"
        context.insert(item)
        try context.save()

        try item.deleteWithCleanup(in: context)

        XCTAssertEqual(try context.fetch(FetchDescriptor<Item>()).count, 0)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:

```bash
xcodegen generate && xcodebuild -project Leatherfolio.xcodeproj -scheme Leatherfolio -destination 'platform=iOS Simulator,name=iPhone 16' test
```

Expected: **FAIL** — test target does not compile: `value of type 'Item' has no member 'deleteWithCleanup'`.

- [ ] **Step 3: Implement the delete-with-cleanup path**

Create `Leatherfolio/Features/ItemDetail/ItemDeletion.swift`:

```swift
import Foundation
import SwiftData

extension Item {
    /// The one delete path in the app: removes the item, its cascade of
    /// Photos (SwiftData .cascade rule on Item.photos), and every cached
    /// thumbnail (memory + Caches/thumbnails/<uuid>.jpg) so thumbnails
    /// never leak after deletion.
    @MainActor
    func deleteWithCleanup(in context: ModelContext,
                           imageStore: ImageStore = .shared) throws {
        for photo in photos ?? [] {
            imageStore.deleteThumbnail(for: photo.id)
        }
        context.delete(self)
        try context.save()
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:

```bash
xcodegen generate && xcodebuild -project Leatherfolio.xcodeproj -scheme Leatherfolio -destination 'platform=iOS Simulator,name=iPhone 16' test
```

Expected: `Test Suite 'ItemDeletionTests' passed` (2 tests) and `** TEST SUCCEEDED **` (all earlier suites still green).

- [ ] **Step 5: Implement the detail view**

Create `Leatherfolio/Features/ItemDetail/ItemDetailView.swift`:

```swift
import SwiftUI
import SwiftData

struct ItemDetailView: View {
    @Bindable var item: Item
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showingEdit = false
    @State private var showingDeleteConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                photoCarousel
                header
                specChips
                ratingRow
                costsBlock
                if let notes = item.notes, !notes.isEmpty {
                    infoCard("Notes") { Text(notes) }
                }
                if let dateAcquired = item.dateAcquired {
                    infoCard("Acquired") {
                        Text(dateAcquired.formatted(date: .long, time: .omitted))
                    }
                }
                if let upc = item.upc, !upc.isEmpty {
                    infoCard("UPC") {
                        Text(upc).font(.body.monospaced())
                    }
                }
                qrLabelCard
            }
            .padding()
        }
        .navigationTitle(item.name.isEmpty ? "Item" : item.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { showingEdit = true }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .sheet(isPresented: $showingEdit) {
            AddEditItemView(item: item)
        }
        .confirmationDialog("Delete this item?",
                            isPresented: $showingDeleteConfirmation,
                            titleVisibility: .visible) {
            Button("Delete Item", role: .destructive) { deleteItem() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its photos are deleted too. This can't be undone.")
        }
    }

    // MARK: Sections

    private var sortedPhotos: [Photo] {
        (item.photos ?? []).sorted { first, second in
            if first.isPrimary != second.isPrimary { return first.isPrimary }
            return first.createdAt < second.createdAt
        }
    }

    /// The detail view is the one place full-res originals (Photo.imageData)
    /// load — grids stay on ImageStore thumbnails.
    @ViewBuilder
    private var photoCarousel: some View {
        if sortedPhotos.isEmpty {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemBackground))
                Image(systemName: "bag")
                    .font(.system(size: 48))
                    .foregroundStyle(.tertiary)
            }
            .frame(height: 280)
        } else {
            TabView {
                ForEach(sortedPhotos) { photo in
                    if let data = photo.imageData, let image = UIImage(data: data) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color(.secondarySystemBackground)
                    }
                }
            }
            .tabViewStyle(.page)
            .frame(height: 320)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(item.name.isEmpty ? "Untitled" : item.name)
                .font(.title.bold())
            if item.isUnicorn { UnicornBadge() }
            Spacer()
            if item.favorite {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
                    .accessibilityLabel("Favorite")
            }
        }
    }

    private var specChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(item.category.rawValue)
                if let size = item.size { chip("Size \(size)") }
                if let color = item.color { chip(color) }
                if let leather = item.leatherType { chip("\(leather.rawValue) leather") }
                if let condition = item.condition { chip(condition.rawValue) }
            }
        }
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(.secondarySystemBackground), in: Capsule())
    }

    private var ratingRow: some View {
        HStack {
            Text("Rating").font(.headline)
            Spacer()
            RatingControl(rating: $item.rating)
                .onChange(of: item.rating) {
                    item.updatedAt = .now
                }
        }
    }

    private var costsBlock: some View {
        infoCard("Costs & Value") {
            VStack(spacing: 8) {
                costRow("My cost", item.myCost)
                costRow("Retail", item.retailCost)
                costRow("Estimated value", item.estimatedValue)
                if let delta = item.valueDelta {
                    Divider()
                    HStack {
                        Text("Value delta").font(.subheadline.bold())
                        Spacer()
                        Text((delta >= 0 ? "+" : "") + delta.currencyDisplay)
                            .font(.subheadline.bold())
                            .foregroundStyle(delta >= 0 ? .green : .red)
                    }
                }
            }
        }
    }

    private func costRow(_ label: String, _ value: Decimal?) -> some View {
        HStack {
            Text(label).font(.subheadline)
            Spacer()
            Text(value?.currencyDisplay ?? "—")
                .font(.subheadline)
                .foregroundStyle(value == nil ? .secondary : .primary)
        }
    }

    /// Shipping intermediate, not a placeholder: this card is the QR-label
    /// section. Phase 3 replaces ONLY its body with the CIFilter-generated
    /// QR image (QRService.qrImage) encoding leatherfolio://item/<uuid>.
    /// Until then it shows the same stable UUID the QR will encode.
    private var qrLabelCard: some View {
        infoCard("QR Label") {
            VStack(alignment: .leading, spacing: 6) {
                Text(item.id.uuidString)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                Text("Printable QR code arrives with scanning support.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func infoCard(_ title: String,
                          @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: Actions

    private func deleteItem() {
        try? item.deleteWithCleanup(in: modelContext)
        dismiss()
    }
}
```

- [ ] **Step 6: Implement the UUID → Item navigation resolver**

Create `Leatherfolio/Features/ItemDetail/ItemDetailLoaderView.swift`:

```swift
import SwiftUI
import SwiftData

/// Resolves a UUID navigation value to the live Item. Grid taps and deep
/// links (Task 7) both push UUIDs, so this is the single destination type.
struct ItemDetailLoaderView: View {
    private let itemID: UUID
    @Query private var items: [Item]

    init(itemID: UUID) {
        self.itemID = itemID
        _items = Query(filter: #Predicate<Item> { $0.id == itemID })
    }

    var body: some View {
        if let item = items.first {
            ItemDetailView(item: item)
        } else {
            ContentUnavailableView("Item not found",
                                   systemImage: "questionmark.circle")
        }
    }
}
```

- [ ] **Step 7: Replace the detail stub in ContentView**

In `Leatherfolio/App/ContentView.swift`, replace:

```swift
                .navigationDestination(for: UUID.self) { itemID in
                    // Task 6 replaces this stub with
                    // ItemDetailLoaderView(itemID: itemID).
                    Text("Item \(itemID.uuidString)")
                }
```

with:

```swift
                .navigationDestination(for: UUID.self) { itemID in
                    ItemDetailLoaderView(itemID: itemID)
                }
```

- [ ] **Step 8: Build and run the full test suite**

Run:

```bash
xcodegen generate && xcodebuild -project Leatherfolio.xcodeproj -scheme Leatherfolio -destination 'platform=iOS Simulator,name=iPhone 16' test
```

Expected: `** TEST SUCCEEDED **` — all suites green.

- [ ] **Step 9: Manual simulator check (2 minutes)**

Run the app: tap an item in the grid → detail shows the photo carousel, spec chips, rating stars (tap to change — persists), costs block, and the QR Label card with the UUID. Tap Edit → the form opens pre-filled; change the name, save, detail updates. Tap the trash toolbar action → confirmation dialog → Delete Item → back on the grid, the item is gone.

- [ ] **Step 10: Commit**

```bash
git add Leatherfolio/Features/ItemDetail/ItemDeletion.swift Leatherfolio/Features/ItemDetail/ItemDetailView.swift Leatherfolio/Features/ItemDetail/ItemDetailLoaderView.swift Leatherfolio/App/ContentView.swift LeatherfolioTests/ItemDeletionTests.swift
git commit -m "feat: add item detail with photo carousel, costs block, and cascade delete"
```

---
### Task 7: AppRouter + deep-link navigation (MVP wrap-up)

**Files:**
- Create: `Leatherfolio/App/AppRouter.swift`
- Modify: `Leatherfolio/App/LeatherfolioApp.swift`
- Modify: `Leatherfolio/App/ContentView.swift`
- Test: `LeatherfolioTests/AppRouterTests.swift`

**Interfaces:**
- Consumes: `ItemDetailLoaderView(itemID:)` (Task 6), `CollectionView` (Task 4), `AppModelContainer.shared` (Task 2).
- Produces (master-plan contract — do not rename): `AppRouter` — `@Observable` class owning `var path: NavigationPath`, with `func open(itemID: UUID)`. Plus `func handle(url: URL)`, which Phase 3's Task consumes when it swaps the inline parse for `QRService.itemID(fromPayload:)`.
- **Phase 3 seam:** `handle(url:)` inline-parses `leatherfolio://item/<uuid>` today. Phase 3 replaces only the parsing line with `QRService.itemID(fromPayload: url.absoluteString)`; the accepted format and rejection behavior must stay identical (the tests below pin that behavior and must keep passing after the swap).

- [ ] **Step 1: Write the failing router tests**

Create `LeatherfolioTests/AppRouterTests.swift`:

```swift
import XCTest
import Foundation
@testable import Leatherfolio

@MainActor
final class AppRouterTests: XCTestCase {

    func testOpenItemIDAppendsToPath() {
        let router = AppRouter()
        XCTAssertEqual(router.path.count, 0)
        router.open(itemID: UUID())
        XCTAssertEqual(router.path.count, 1)
    }

    func testHandleValidDeepLinkOpensItem() throws {
        let router = AppRouter()
        let id = UUID()
        let url = try XCTUnwrap(URL(string: "leatherfolio://item/\(id.uuidString)"))
        router.handle(url: url)
        XCTAssertEqual(router.path.count, 1)
    }

    func testHandleLowercasedUUIDStillParses() throws {
        let router = AppRouter()
        let lowered = UUID().uuidString.lowercased()
        let url = try XCTUnwrap(URL(string: "leatherfolio://item/\(lowered)"))
        router.handle(url: url)
        XCTAssertEqual(router.path.count, 1)
    }

    func testHandleRejectsWrongScheme() throws {
        let router = AppRouter()
        let url = try XCTUnwrap(URL(string: "https://item/\(UUID().uuidString)"))
        router.handle(url: url)
        XCTAssertEqual(router.path.count, 0)
    }

    func testHandleRejectsWrongHost() throws {
        let router = AppRouter()
        let url = try XCTUnwrap(URL(string: "leatherfolio://tag/\(UUID().uuidString)"))
        router.handle(url: url)
        XCTAssertEqual(router.path.count, 0)
    }

    func testHandleRejectsMalformedUUID() throws {
        let router = AppRouter()
        let url = try XCTUnwrap(URL(string: "leatherfolio://item/not-a-uuid"))
        router.handle(url: url)
        XCTAssertEqual(router.path.count, 0)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:

```bash
xcodegen generate && xcodebuild -project Leatherfolio.xcodeproj -scheme Leatherfolio -destination 'platform=iOS Simulator,name=iPhone 16' test
```

Expected: **FAIL** — test target does not compile: `cannot find 'AppRouter' in scope`.

- [ ] **Step 3: Implement AppRouter**

Create `Leatherfolio/App/AppRouter.swift`:

```swift
import SwiftUI
import Observation

/// Owns the app's navigation path. Grid taps push UUIDs directly via
/// NavigationLink(value:); deep links come in through handle(url:).
@MainActor
@Observable
final class AppRouter {
    var path = NavigationPath()

    func open(itemID: UUID) {
        path.append(itemID)
    }

    /// Parses leatherfolio://item/<uuid>.
    /// Phase 3 seam: replace ONLY the guard's parsing with
    /// QRService.itemID(fromPayload: url.absoluteString) once QRService
    /// exists. Accepted format and rejections must stay identical —
    /// AppRouterTests pins that behavior.
    func handle(url: URL) {
        guard url.scheme == "leatherfolio",
              url.host() == "item",
              let itemID = UUID(uuidString: url.lastPathComponent) else {
            return
        }
        open(itemID: itemID)
    }
}
```

(`UUID(uuidString:)` accepts lowercase hex, which is why the lowercase test passes without extra code.)

- [ ] **Step 4: Run the tests to verify they pass**

Run:

```bash
xcodegen generate && xcodebuild -project Leatherfolio.xcodeproj -scheme Leatherfolio -destination 'platform=iOS Simulator,name=iPhone 16' test
```

Expected: `Test Suite 'AppRouterTests' passed` (6 tests) and `** TEST SUCCEEDED **`.

- [ ] **Step 5: Give the router the NavigationStack path**

Replace the entire contents of `Leatherfolio/App/ContentView.swift` with:

```swift
import SwiftUI

struct ContentView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.path) {
            CollectionView()
                .navigationDestination(for: UUID.self) { itemID in
                    ItemDetailLoaderView(itemID: itemID)
                }
        }
    }
}
```

- [ ] **Step 6: Wire the router and .onOpenURL into the app**

Replace the entire contents of `Leatherfolio/App/LeatherfolioApp.swift` with:

```swift
import SwiftUI

@main
struct LeatherfolioApp: App {
    @State private var router = AppRouter()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(router)
                .onOpenURL { url in
                    router.handle(url: url)
                }
        }
        .modelContainer(AppModelContainer.shared)
    }
}
```

- [ ] **Step 7: Run the FULL MVP test suite**

Run:

```bash
xcodegen generate && xcodebuild -project Leatherfolio.xcodeproj -scheme Leatherfolio -destination 'platform=iOS Simulator,name=iPhone 16' test
```

Expected: `** TEST SUCCEEDED **` with all seven suites green: SmokeTests (1), CloudKitRulesTests (3), ImageStoreTests (4), CollectionViewSmokeTests (2), AddEditItemModelTests (7), ItemDeletionTests (2), AppRouterTests (6) — 25 tests total.

- [ ] **Step 8: Manual MVP smoke on the simulator (5 minutes)**

1. Run the app (Xcode Cmd-R, or `xcodebuild ... build` then `xcrun simctl install booted <path-to-Leatherfolio.app> && xcrun simctl launch booted com.robbybarnes.leatherfolio`).
2. Add an item with a library photo → it appears in the grid with a thumbnail.
3. Open its detail → copy the UUID from the QR Label card (text is selectable).
4. Background the app (Home), then in Terminal run:

```bash
xcrun simctl openurl booted "leatherfolio://item/<PASTED-UUID>"
```

Expected: the app foregrounds and navigates straight to that item's detail view. Also verify a bogus link is a no-op: `xcrun simctl openurl booted "leatherfolio://item/nope"` leaves the app wherever it was.

- [ ] **Step 9: Commit**

```bash
git add Leatherfolio/App/AppRouter.swift Leatherfolio/App/LeatherfolioApp.swift Leatherfolio/App/ContentView.swift LeatherfolioTests/AppRouterTests.swift
git commit -m "feat: wire AppRouter deep-link navigation for leatherfolio://item URLs"
```

---

## Phase 0–1 definition of done

- All seven tasks' checkboxes complete, each with its own commit.
- `xcodegen generate && xcodebuild -project Leatherfolio.xcodeproj -scheme Leatherfolio -destination 'platform=iOS Simulator,name=iPhone 16' test` → `** TEST SUCCEEDED **` (25 tests).
- Manual simulator smoke (Task 7 Step 8) passes end to end: add with photo → grid thumbnail → detail → deep link back to detail.
- Open manual milestone carried forward (not a blocker): CameraPicker capture verified on a physical device.
- Every master-plan shared interface consumed by Phase 2–3 exists under its exact name: the three enums, `Item`/`Photo`/`Tag`, `AppModelContainer`, `ImageStore.thumbnail(for:imageData:)` / `deleteThumbnail(for:)` / `downsampledJPEG(from:maxDimension:)`, `AppRouter.open(itemID:)`, `AddEditItemModel.sizeOptions` / `colorOptions` injection point, and the ItemDetailView QR-label card seam.
