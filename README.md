# My PLG Collection

An early-development iOS preview for cataloging a personal collection of leather bags and
accessories: names, sizes, colors, leather types, photos, cost/value, ratings, QR self-labeling,
and barcode capture.

> **Unofficial fan project — not affiliated with or endorsed by Portland Leather Goods.**
> This is a personal tool built by a customer. It will not be publicly released unless and until
> PLG grants permission to use its product names and imagery. Scraped reference data lives in
> `research/` for local development only.

## Status

This repository is an **early development preview**, not a released or feature-complete product.
Core local workflows are implemented and covered by automated tests, but manual accessibility,
physical-camera, CloudKit, signing, and permission gates remain. See the verification checklist
below for the exact boundary.

## Architecture

- **SwiftUI + SwiftData**, local-first. The schema is shaped for a possible future CloudKit
  migration, but sync is explicitly **off** (`cloudKitDatabase: .none`).
- **Photos** use SwiftData external storage for originals and `ImageStore` for downsized thumbnail
  caching; grids do not intentionally decode full-resolution photos.
- **QR self-labeling** gives each item a `leatherfolio://item/<uuid>` label; scanning a known label
  opens that item. UPC barcodes are captured, with network lookup intentionally unimplemented.
- **Zero third-party app dependencies**. The app uses Apple frameworks including SwiftUI,
  SwiftData, VisionKit, Core Image, PhotosUI, and Swift Charts.
- **XcodeGen** owns the project. `project.yml` is the source of truth and the generated
  `Leatherfolio.xcodeproj` is ignored.

## Build and test

Requirements: macOS with Xcode, an iOS simulator, and
[XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
xcodegen generate

xcodebuild -project Leatherfolio.xcodeproj -scheme Leatherfolio \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath .derived-data/build build

xcodebuild -project Leatherfolio.xcodeproj -scheme Leatherfolio \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath .derived-data/test test
```

Substitute any available simulator from `xcrun simctl list devices available`. The deployment
target is iOS 18 and the language mode is Swift 6.

### Regenerate the app icon

The committed icon is generated with Swift plus AppKit/CoreGraphics only:

```bash
swift Scripts/generate_app_icon.swift
```

The script deterministically writes the asset-catalog input at
`Leatherfolio/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png`. Verify it with:

```bash
file Leatherfolio/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
sips -g pixelWidth -g pixelHeight -g hasAlpha -g space \
  Leatherfolio/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
```

Expected metadata: 1024×1024, RGB, with no alpha channel.

## Verification and release checklist

Automated checks prove compilation and covered behavior; they do not prove simulator rendering,
VoiceOver output, physical camera behavior, CloudKit sync, signing, or release permission.

### Automated evidence

- [x] Fresh full XCTest suite passed from review commit `f2a877f`: 172 tests, 0 failures,
  0 skips (2026-07-22, iPhone 17 Pro simulator running iOS 26.4).
- [x] Fresh simulator build succeeded from the generated project (2026-07-22, iPhone 17 Pro
  simulator running iOS 26.4).
- [x] App icon generator reproduced a byte-identical 1024×1024 opaque RGB PNG on the current
  development machine (2026-07-22).

### Simulator checks — pending

- [ ] Complete add/edit/delete, QR routing, scanner fallback, filtering, stats, and relaunch smoke.
- [ ] Inspect light and dark appearances for clipping or contrast regressions.
- [ ] At the largest accessibility Dynamic Type size, confirm the grid collapses to one column and
  names, specs, controls, sheets, and detail content remain readable without clipping.
- [ ] With VoiceOver/Accessibility Inspector, confirm cell composition, carousel photo captions,
  item-specific QR labels, and the adjustable rating action.

### Physical device checks — pending

- [ ] Verify camera permission grant/denial/recovery on supported hardware.
- [ ] Scan a printed Leatherfolio QR label and representative UPC barcodes.
- [ ] Capture and import representative photos, then verify memory behavior with multiple items.

### CloudKit and signing — pending

- [ ] Enroll/configure Apple Developer signing and choose the production CloudKit container.
- [ ] Add the iCloud capability and CloudKit container to `project.yml`; keep sync off until then.
- [ ] Verify add/edit/delete propagation in both directions on two signed-in devices.
- [ ] Verify signed-out and iCloud-account-change behavior and user-facing copy.

### Release permission — pending

- [ ] Obtain written PLG permission for any public distribution of product names, seed data, or
  imagery. Until then, do not publish to the App Store or public TestFlight.

## Repository layout

```text
docs/superpowers/    design spec and implementation plans
research/            private development reference data and sample imagery
Leatherfolio/        app source and bundled resources
LeatherfolioTests/   automated tests
Scripts/             reproducible local asset tooling
project.yml          XcodeGen source of truth
```

## License and usage

Private, personal project. Reference data in `research/` is not for redistribution. Do not ship or
publish the app or bundled brand references without Portland Leather Goods' permission.
