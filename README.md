# My PLG Collection

A personal-catalog iOS app for tracking the leather bags and accessories you own from
[Portland Leather Goods](https://www.portlandleathergoods.com/) — name, size, color, leather
type, photos, cost/value, plus QR self-labeling and barcode capture to speed up cataloging.
Think "closet inventory / collection tracker" for one leather brand's ecosystem.

> **Unofficial fan project — not affiliated with or endorsed by Portland Leather Goods.**
> This is a personal tool built by a customer. It will **not** be publicly released unless and
> until PLG grants permission to use their product names and imagery. Scraped reference data
> lives in `research/` and is used only for local development. The app name uses the "PLG"
> abbreviation, not the full trademark; the internal Xcode module/target is named `Leatherfolio`
> (Swift identifiers can't contain spaces) while the user-facing display name is "My PLG Collection".

## Status: work in progress

Phase 0-1 (core catalog MVP) is partially built. This repo currently contains the full design
documentation, catalog research, and the first slice of app code.

| Phase / Task | State |
|---|---|
| Design spec, master plan, phase plans | ✅ Complete (`docs/superpowers/`) |
| Catalog research (37 products via Firecrawl) | ✅ Complete (`research/`) |
| Task 1 — XcodeGen project skeleton | ✅ Done, reviewed |
| Task 2 — SwiftData models (Item/Photo/Tag) | ✅ Done, reviewed, tests green |
| Task 3 — ImageStore (thumbnail cache) | ✅ Done, reviewed, tests green |
| Task 4-7 — grid, add/edit, detail, navigation | ⏳ Planned, not yet built |
| Phase 2-3 — catalog seed + scanning | ⏳ Planned |
| Phase 4 — filters, stats, design, a11y | ⏳ Planned |

## Architecture

- **SwiftUI + SwiftData**, local-first. The SwiftData schema is CloudKit-shaped from day one
  (every property optional-or-defaulted, every relationship optional, no unique constraints) so
  iCloud sync can be switched on with a one-line change once app signing is set up. Sync starts
  **off** (`cloudKitDatabase: .none`).
- **Photos** are stored as external files (`@Attribute(.externalStorage)`, mapped to CKAsset under
  sync); grids render downsized ~400px thumbnails via `ImageStore`, never full-res in a scroll list.
- **QR self-labeling** (planned): each item gets an app-generated QR encoding
  `leatherfolio://item/<uuid>`; scanning it opens that item. UPC barcodes are captured but not
  looked up in v1 (PLG products aren't reliably in public UPC databases).
- **Zero third-party dependencies** in the app target — everything is first-party Apple frameworks
  (SwiftData, VisionKit, Core Image, PhotosUI, Swift Charts).
- **XcodeGen** owns the project: `project.yml` is the source of truth and `Leatherfolio.xcodeproj`
  is generated and git-ignored.

## Building

Requirements: macOS with Xcode, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
# one-time tooling
brew install xcodegen

# generate the Xcode project from project.yml (re-run after adding/removing files)
xcodegen generate

# build
xcodebuild -project Leatherfolio.xcodeproj -scheme Leatherfolio \
  -destination 'platform=iOS Simulator,name=iPhone 17' build

# test
xcodebuild -project Leatherfolio.xcodeproj -scheme Leatherfolio \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Notes:
- **Deployment target:** iOS 18.0, Swift 6.
- **Simulator name:** substitute any installed iPhone simulator
  (`xcrun simctl list devices available`). Examples here use `iPhone 17`.
- **Use a stable Xcode (26.x), not the 27 beta.** Xcode 27 Beta 4 traps every SwiftData
  save in the simulator, which blocks the persistence tests. A released Xcode 26.x avoids this and
  is fully compatible with the iOS 18 / Swift 6 target.

## Repository layout

```
docs/superpowers/
  specs/    design spec (the authoritative description of what's being built)
  plans/    master plan + phase-by-phase implementation plans
research/
  plg_products.json       37 scraped PLG products (dev reference only)
  plg_catalog_notes.md    catalog structure, size/color/leather notes
  images/                 sample product images, one per category
Leatherfolio/             the app source (App/, Models/, Services/, Features/, Resources/)
LeatherfolioTests/        unit tests
project.yml               XcodeGen project definition (source of truth)
```

## Roadmap

v1 (single-user): add/edit/delete items with photos, curated cascading pickers seeded from real
catalog data, grid/list collection with filter/sort/search, rich detail view, ratings, "unicorn"
(grail) flags, cost/value stats, QR self-labeling + scan-to-open, UPC capture, wishlist toggle,
warm editorial design, Dynamic Type + VoiceOver. iCloud sync flips on before any release.

Later: CloudKit sharing, export/backup, Apple Watch quick-view.

## License / usage

Private, personal project. Reference data in `research/` is not for redistribution. Do not ship or
publish this app or its bundled brand references without Portland Leather Goods' permission.
