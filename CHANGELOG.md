# Changelog

All notable changes to **My PLG Collection** (internal target `Leatherfolio`) will be documented in this file.

## [Unreleased] — personal development builds

Nothing in this changelog has been publicly released. The entries below describe implemented
preview work, not a completed 1.0 product.

### Added
- **Core Catalog MVP (Phase 0–1):**
  - SwiftData `@Model` schema for `Item`, `Photo`, `Tag` with CloudKit-safe defaults.
  - `ImageStore` downsampling and two-layer memory/disk thumbnail cache (~400px).
  - Collection grid with empty state and primary photo thumbnails.
  - Photo-first add/edit item form with camera capture and photo library picker.
  - Rich item detail view with photo carousel, spec chips, cost/value breakdown, and cascade deletion.
  - `AppRouter` with `leatherfolio://item/<uuid>` deep link navigation support.

- **Catalog Seed & Scanning (Phase 2–3):**
  - Bundled `plg_catalog.json` seed containing 23 curated Portland Leather Goods product lines.
  - `CatalogSeed` query service and cascading pickers in Add/Edit (Category → Line → Size/Color/Leather Type) with custom "Other…" escape hatch.
  - `CollectionStats` engine for computing collection totals, category breakdown, and line completeness.
  - `QRService` for payload encoding/decoding and Core Image vector-scaled QR code rendering.
  - `ScanRouter` for routing scanned QR/barcodes to existing item views or new item prefill flows.
  - `ScannerView` and `ScannerSheet` wrapping VisionKit `DataScannerViewController` with fallback UI for unsupported environments.
  - Printable/exportable QR label sheet with `ShareLink` support.
  - `ProductLookupService` seam with v1 `NoOpProductLookup` implementation for UPC barcode capture.

- **Polish & Design (Phase 4):**
  - `ItemFilter` pure filter, sort, and search engine supporting Owned/Wishlist scope, multi-attribute filtering, full-text token search, and removable chips.
  - Grid vs. list layout toggle (`CollectionLayout`) persisted across app launches.
  - `StatsView` displaying collection headline totals, money breakdown, average ratings, items-by-category bar chart, and line completeness progress bars.
  - Warm editorial `Theme` palette with 7 WCAG AA-compliant light/dark colorsets (`Cream`, `Parchment`, `Espresso`, `Nutmeg`, `Cognac`, `Gain`, `Loss`) and serif display typography.
  - Custom 1024x1024 PNG app icon.
  - Full VoiceOver accessibility pass with `AccessibilityText` label composition, adjustable star rating control, and Dynamic Type single-column grid collapsing.
