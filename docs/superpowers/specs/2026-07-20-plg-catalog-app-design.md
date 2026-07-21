# Leatherfolio — Personal Catalog App for Portland Leather Goods Collectors

**Date:** 2026-07-20
**Status:** Design spec, pending Robby's review
**Source brief:** `~/Obsidian/Personal/Portland Leather App/Portland Leather iOS app.md`

A personal-catalog iOS app for Portland Leather Goods (PLG) customers to track the bags and accessories they own — name, size, color, leather type, photos, cost/value — with QR self-labeling and barcode capture to speed up cataloging. "Closet inventory for one leather brand's ecosystem."

**Working title:** *Leatherfolio* (deliberately generic — no PLG trademark in the name). The app is an unofficial fan tool and will not be released until PLG grants permission to use their product names/imagery. All scraped reference data lives in `research/` and is for development only.

---

## Decisions made (where the brief left options open)

The brief invited judgment calls. Here are mine, with reasoning:

1. **Tags are many-to-many** (`Item <->> Tag`). Shared tags across items ("work", "travel", "gift from Mom") are the useful design. SwiftData expresses this as to-many on both sides; CloudKit supports it. Tag names are deduplicated in app logic (no `.unique` allowed under CloudKit).
2. **UPC lookup is cut from v1 entirely; UPC *capture* stays.** The brief itself concludes PLG products likely aren't in public UPC databases and flags this as the biggest unknown, resolvable only with a physical item test. So v1 scans and stores the raw code as a stable identifier, and the lookup path is left as a `ProductLookupService` protocol with a no-op implementation. No paid API dependency, nothing to rip out if the physical test fails.
3. **QR self-labeling is the flagship scan feature**, exactly as the brief recommends: each item gets an app-generated QR encoding `leatherfolio://item/<uuid>`; scanning one jumps to the item, scanning an unknown code starts the add flow with the code pre-attached.
4. **Local-first now, CloudKit-ready always, sync flipped on when signing is available.** The model obeys every CloudKit rule from day one (all properties optional-or-defaulted, all relationships optional, no `.unique`), but the ModelContainer starts with `cloudKitDatabase: .none` behind a single build-config flag. Reason: CloudKit requires a paid team + provisioning; agents building/running in the simulator shouldn't be blocked on that. Flipping to `.automatic` later is a one-line change *because* the schema was CloudKit-shaped from the start. Verifying two-device sync is an explicit milestone once signing exists.
5. **XcodeGen owns the Xcode project.** `project.yml` is checked in; `.xcodeproj` is generated and gitignored. Rationale: agents (and humans) edit YAML reliably; hand-editing pbxproj is the classic agent failure mode. `xcodegen` + `xcodebuild` gives a scriptable build/test loop.
6. **iOS 18.0 minimum, SwiftUI + SwiftData, zero third-party dependencies in the app target.** Everything needed (VisionKit scanning, CIFilter QR generation, PhotosUI, Charts for stats) is first-party.
7. **Catalog seed is built from the Firecrawl research pass** (`research/plg_products.json`) and hand-curated into `plg_catalog.json` bundled with the app: lines → sizes → colors → leather types, powering cascading pickers with free-text escape hatches everywhere.
8. **Wishlist ships in v1 after all** — but as the cheapest possible version: a single `isWishlist` Bool on Item and a segmented scope toggle (Owned / Wishlist) on the collection screen. The brief deferred it, but the model cost is one defaulted field (schema-safe to add now, painful to retrofit post-CloudKit), and the UI cost is one filter. Cutting it from v1 *scope* but not from the *schema* would be the alternative; including the field either way is the non-negotiable part.
9. **Hard-require nothing about iCloud in v1 builds** (follows from #4). When sync ships, the app explains iCloud state rather than blocking: signed out → banner "your collection is on this device only."

Everything else follows the brief as written.

---

## Architecture

**Pattern:** SwiftUI app, MV-ish (views + `@Observable` services; no heavyweight VIPER/TCA). SwiftData models are the source of truth; services wrap side-effecting subsystems.

```
Leatherfolio/
├── App/                 LeatherfolioApp, ModelContainer setup, deep-link router
├── Models/              Item, Photo, Tag (SwiftData); enums (Category, LeatherType, Condition)
├── Services/
│   ├── ImageStore       write originals (external storage), generate/cache ~400px thumbnails
│   ├── QRService        generate per-item QR (CIFilter), parse leatherfolio:// payloads
│   ├── ScanRouter       scanned payload → known item / new-item flow
│   ├── ProductLookupService (protocol; v1 impl = no-op)
│   └── CatalogSeed      load + query bundled plg_catalog.json
├── Features/
│   ├── Collection/      grid/list home, filters, sort, search, Owned/Wishlist scope
│   ├── ItemDetail/      hero carousel, spec chips, rating, costs block, QR label
│   ├── AddEdit/         photo-first add flow, cascading pickers, UPC attach
│   ├── Scanner/         ScannerView (VisionKit DataScannerViewController wrapper)
│   └── Stats/           counts, collection value, spend, deltas, completeness
└── Resources/           plg_catalog.json, assets, app icon
```

**Data flow:** Views query SwiftData directly (`@Query`); mutations go through small intent functions on the models/services. Photos never live in the row — `Photo.imageData` uses `@Attribute(.externalStorage)` (mapped to CKAsset under sync), and grid cells only ever touch `ImageStore` thumbnails.

**Research-driven corrections to the brief** (from the 2026-07-20 Firecrawl pass, `research/plg_catalog_notes.md`): PLG's current leather types are Smooth, Pebbled, Suede, and **Metallic** — no Nubuck/Brushed — so `LeatherType` uses those four plus Other. Categories align to the real catalog: Tote, Crossbody Tote, Crossbody, Belt Bag, Backpack, Wallet, Cardholder, Belt, Accessory, Other. The Crossbody Tote family sells sizes as separate listings (Mini/Medium/Original are distinct products), so the catalog seed groups them into one line with a merged size list.

**Deep links:** `leatherfolio://item/<uuid>` registered as a custom scheme; the scanner and QR labels both speak it.

## Data model

As specified in the brief (Item / Photo / Tag with the full field list: category, size, color, leatherType, isUnicorn, myCost/retailCost/estimatedValue as `Decimal`, rating Int 0–5, upc, condition, favorite, dateAcquired, notes, timestamps), plus `isWishlist: Bool = false` per decision #8. CloudKit rules baked in: every property optional or defaulted, every relationship optional, no unique constraints, no `.deny` deletion rules. Derived values (value delta, collection totals) are computed, never stored.

## Error handling

- **ImageStore** failures (disk full, decode failure) surface as non-blocking alerts; the item saves without the photo rather than losing user input.
- **Scanner**: camera permission denied → inline explainer with Settings link; `DataScannerViewController.isSupported/isAvailable` checked before presenting.
- **Catalog seed** malformed/missing → pickers degrade to free-text; never crash on bundled data.
- **Sync (later)**: account-changed notifications explained to the user (local store replaced), per the brief.

## Testing

- Unit tests (XCTest, run via `xcodebuild test` on simulator): ImageStore round-trip + thumbnail generation, QR payload encode/parse, ScanRouter routing table, CatalogSeed parsing + cascading queries, stats math (Decimal), model defaults satisfying CloudKit rules (reflection test that walks the schema).
- UI smoke test: launch, add item (no photo), see it in grid.
- Manual milestones: physical UPC test on a real PLG tag (decides the lookup path's fate); two-device CloudKit sync once signing exists.

## v1 scope (ship line)

Single-user catalog: add/edit/delete items with photos, curated cascading pickers from the PLG seed, grid/list collection with filter/sort/search, rich detail view, ratings/unicorn/costs/value stats, QR self-labeling + scan-to-open, UPC capture (no lookup), wishlist toggle, warm editorial design language, Dynamic Type + VoiceOver. CloudKit sync flipped on as soon as signing allows, before any App Store submission.

**Explicitly out of v1:** UPC lookup APIs, sharing/social, widgets, export, Watch app, App Clips — all per the brief's "Later / v2+" list.

## Costs & constraints

$99/yr Apple Developer Program is the only recurring cost. No backend, no per-user infra. **Release is gated on PLG's permission** for product names/imagery; until then the app is a local/TestFlight-personal project and scraped data stays in `research/`.
