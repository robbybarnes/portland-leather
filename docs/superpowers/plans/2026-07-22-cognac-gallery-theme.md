# Cognac Gallery Theme + House-Dog Easter Egg — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the app's "Warm Editorial" palette with a neutral "Cognac Gallery" palette (light + dark) that lets colorful product photos carry the color, and hide the house-dog illustration behind a long-press easter egg on the Stats headline.

**Architecture:** The theme is already well-factored: `Theme` (in `Support/Theme.swift`) exposes semantic colors (`background`, `card`, `textPrimary`, `textSecondary`, `accent`, `gain`, `loss`) that resolve from named asset-catalog colorsets, each carrying a light value and a `luminosity: dark` variant. We change only the **values** of five colorsets and keep the asset names and the `Theme` API stable, so no call sites change. WCAG AA is enforced by `ThemeContrastTests`, which duplicates the palette hexes as a second source of truth — those must be kept in lock-step with the colorset JSON. The easter egg is added inline to the already-referenced `StatsView.swift` (no new Swift file, so no `.pbxproj` edits) plus one new image set inside the existing `Assets.xcassets` (asset catalogs compile as a unit, so no `.pbxproj` edit either).

**Tech Stack:** SwiftUI, SwiftData, Xcode asset catalogs, XCTest, `xcodebuild` + iOS Simulator.

## Global Constraints

- **Platform / project:** iOS app. Project `Leatherfolio.xcodeproj`, scheme `Leatherfolio`, test target `LeatherfolioTests`. Simulator: `iPhone 17`.
- **Accessibility floor:** Every text-on-background pair must meet WCAG AA (contrast ≥ 4.5:1) in both light and dark. `LeatherfolioTests/ThemeContrastTests.swift` is the executable guardrail; its hardcoded hexes are a second source of truth and MUST equal the colorset JSON values.
- **API stability:** Do NOT rename the asset colorsets (`Cream`, `Parchment`, `Espresso`, `Nutmeg`, `Cognac`, `Gain`, `Loss`) or the `Theme` members. The names are legacy; only their values change. Read colors by role, not by literal color name.
- **No new standalone Swift files** unless you also edit `Leatherfolio.xcodeproj/project.pbxproj` — the project uses explicit file references (no synchronized folders). This plan adds no Swift files.
- **Toolchain reality:** Only Xcode 27 Beta 4 is installed (`/Applications/Xcode.app` is a symlink to it). SwiftData insert/save **traps at runtime** under this beta, so a full `xcodebuild test` run is unreliable (persistence tests crash the host). Compilation is unaffected; run only non-SwiftData test classes in isolation with `-only-testing:`. When a stable Xcode 26.x becomes available, the full suite can be run.
- **Palette (Cognac Gallery) — exact values:**

  | Role (asset name) | Light | Dark |
  | --- | --- | --- |
  | Ground (`Cream`) | `#F4F2ED` | `#131110` |
  | Card (`Parchment`) | `#FFFFFF` | `#1F1B18` |
  | Ink (`Espresso`) | `#221C18` | `#F1EBE3` |
  | Clay (`Nutmeg`) | `#786A5C` | `#B4A594` |
  | Cognac accent (`Cognac`) | `#9A4A27` | `#CE7E48` |
  | Gain (`Gain`) — unchanged | `#2E7D4F` | `#5FBF8A` |
  | Loss (`Loss`) — unchanged | `#B3372F` | `#E07A6E` |

- **Easter-egg copy:** title "Chief Bag Inspector", dismiss hint "Tap to dismiss", VoiceOver action "Meet the house dog", VoiceOver label "The house dog, Chief Bag Inspector".
- **Source illustration:** `~/Obsidian/Personal/Pasted image 20260721234301.png` (2000×2000 PNG of the Bernedoodle between two PLG bags).

---

## Task 0: Branch

**Files:** none (git only).

- [ ] **Step 1: Create a feature branch off main**

```bash
cd /Users/robbybarnes/GitHub/portland-leather
git checkout main && git pull --ff-only
git checkout -b feature/cognac-gallery
```

- [ ] **Step 2: Confirm clean tree**

Run: `git status --short`
Expected: no output (clean).

---

## Task 1: Swap the palette (colorsets + contrast guardrail + Theme doc)

Deliverable: the five colorsets carry Cognac Gallery values, the contrast test's hexes match them and pass AA, and `Theme.swift`'s doc comment describes the new palette. `Theme`'s API and the asset names are unchanged.

**Files:**
- Modify: `Leatherfolio/Resources/Assets.xcassets/Cream.colorset/Contents.json`
- Modify: `Leatherfolio/Resources/Assets.xcassets/Parchment.colorset/Contents.json`
- Modify: `Leatherfolio/Resources/Assets.xcassets/Espresso.colorset/Contents.json`
- Modify: `Leatherfolio/Resources/Assets.xcassets/Nutmeg.colorset/Contents.json`
- Modify: `Leatherfolio/Resources/Assets.xcassets/Cognac.colorset/Contents.json`
- Modify: `Leatherfolio/Support/Theme.swift` (doc comment only)
- Test: `LeatherfolioTests/ThemeContrastTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: unchanged `Theme` API — `Theme.background/card/textPrimary/textSecondary/accent/gain/loss` (all `Color`). Later tasks and existing call sites depend on these names being unchanged.

- [ ] **Step 1: Prove the target palette meets WCAG AA before touching anything**

Create the scratch verifier (mirrors the exact formula in `ThemeContrastTests`) and run it:

```bash
python3 - <<'PY'
def lum(h):
    n=int(h,16)
    def ch(v):
        c=v/255.0
        return c/12.92 if c<=0.03928 else ((c+0.055)/1.055)**2.4
    return 0.2126*ch((n>>16)&255)+0.7152*ch((n>>8)&255)+0.0722*ch(n&255)
def contrast(a,b):
    l1,l2=lum(a),lum(b); return (max(l1,l2)+0.05)/(min(l1,l2)+0.05)
L={'Ground':'F4F2ED','Card':'FFFFFF','Ink':'221C18','Clay':'786A5C','Cognac':'9A4A27','Gain':'2E7D4F','Loss':'B3372F'}
D={'Ground':'131110','Card':'1F1B18','Ink':'F1EBE3','Clay':'B4A594','Cognac':'CE7E48','Gain':'5FBF8A','Loss':'E07A6E'}
def check(mode,P):
    ok=True
    for txt in ['Ink','Clay','Cognac','Gain','Loss']:
        for grd in ['Ground','Card']:
            if txt in ('Cognac','Gain','Loss') and grd=='Card': continue
            r=contrast(P[txt],P[grd])
            if r<4.5: ok=False; print(f"FAIL {mode} {txt} on {grd}: {r:.2f}")
    return ok
print("PASS" if check('Light',L) and check('Dark',D) else "FAIL")
PY
```

Expected: `PASS` (no `FAIL` lines). Lowest margins are Gain-on-Ground ≈ 4.51 and Clay-on-Ground ≈ 4.68 — both clear 4.5.

- [ ] **Step 2: Update the contrast test hexes to the new palette**

Replace the two `// MARK: Light mode …` / `// MARK: Dark mode …` methods in `LeatherfolioTests/ThemeContrastTests.swift` with:

```swift
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
```

Leave the WCAG-math helpers (`luminance`, `contrast`) and `testAssetCatalogColorsResolve()` unchanged.

- [ ] **Step 3: Rewrite the five colorsets to matching values**

```bash
python3 - <<'PY'
import json, os
base="Leatherfolio/Resources/Assets.xcassets"
palette={
 "Cream":     ("F4F2ED","131110"),
 "Parchment": ("FFFFFF","1F1B18"),
 "Espresso":  ("221C18","F1EBE3"),
 "Nutmeg":    ("786A5C","B4A594"),
 "Cognac":    ("9A4A27","CE7E48"),
}
def comp(h): return {"alpha":"1.000","red":f"0x{h[0:2]}","green":f"0x{h[2:4]}","blue":f"0x{h[4:6]}"}
def colorset(l,d):
    return {"colors":[
        {"idiom":"universal","color":{"color-space":"srgb","components":comp(l)}},
        {"idiom":"universal","appearances":[{"appearance":"luminosity","value":"dark"}],
         "color":{"color-space":"srgb","components":comp(d)}},
    ],"info":{"author":"xcode","version":1}}
for name,(l,d) in palette.items():
    p=os.path.join(base,f"{name}.colorset","Contents.json")
    with open(p,"w") as f: json.dump(colorset(l,d),f,indent=2); f.write("\n")
    print("wrote",p)
PY
```

Expected: five `wrote …` lines. Do NOT touch `Gain.colorset` or `Loss.colorset` — their values already pass on the new grounds.

- [ ] **Step 4: Validate every colorset JSON parses**

```bash
python3 - <<'PY'
import json,glob
bad=0
for p in glob.glob("Leatherfolio/Resources/Assets.xcassets/**/Contents.json",recursive=True):
    try: json.load(open(p))
    except Exception as e: print("BAD",p,e); bad+=1
print("all valid" if not bad else f"{bad} bad")
PY
```

Expected: `all valid`.

- [ ] **Step 5: Update the `Theme.swift` doc comment (values only; keep the code)**

Replace the header comment and the five `static let` lines' block with:

```swift
/// Cognac Gallery design language: a quiet neutral ground (soft bone in light,
/// near-black gallery in dark) so colorful product photos carry the color, with
/// a single cognac accent and serif display type. Colors resolve from the asset
/// catalog (light/dark variants; WCAG AA verified by ThemeContrastTests).
///
/// Asset names (Cream/Parchment/Espresso/Nutmeg/Cognac) are retained from the
/// earlier Warm Editorial palette to keep the semantic API stable; only their
/// values changed. Read them by role, not by literal color name.
enum Theme {
    static let background = Color("Cream")      // Ground — soft bone / near-black
    static let card = Color("Parchment")        // Card — white / warm charcoal
    static let textPrimary = Color("Espresso")  // Ink
    static let textSecondary = Color("Nutmeg")  // Clay
    static let accent = Color("Cognac")         // Cognac
    static let gain = Color("Gain")
    static let loss = Color("Loss")
```

(The `Spacing` enum, `cardCornerRadius`, `Font.display`, and `CardStyle` below are unchanged.)

- [ ] **Step 6: Build app + tests**

Run:

```bash
xcodebuild build-for-testing -scheme Leatherfolio -project Leatherfolio.xcodeproj \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath /tmp/leatherfolio-dd 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:"
```

Expected: `** TEST BUILD SUCCEEDED **`, no `error:` lines.

- [ ] **Step 7: Run the contrast tests (pure math + asset resolve; no SwiftData)**

Run:

```bash
xcodebuild test-without-building -scheme Leatherfolio -project Leatherfolio.xcodeproj \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath /tmp/leatherfolio-dd \
  -only-testing:LeatherfolioTests/ThemeContrastTests 2>&1 \
  | grep -E "passed|failed|\*\* TEST"
```

Expected: `testAssetCatalogColorsResolve`, `testDarkModeTextPairsMeetAA`, `testLightModeTextPairsMeetAA` all `passed`; `** TEST EXECUTE SUCCEEDED **`.

- [ ] **Step 8: Commit**

```bash
git add Leatherfolio/Resources/Assets.xcassets/{Cream,Parchment,Espresso,Nutmeg,Cognac}.colorset/Contents.json \
        Leatherfolio/Support/Theme.swift LeatherfolioTests/ThemeContrastTests.swift
git commit -m "feat: adopt Cognac Gallery palette (light + dark, AA-verified)"
```

---

## Task 2: Add the house-dog image set

Deliverable: a single-scale `HouseDog` image set inside the existing asset catalog, compiling cleanly. No `.pbxproj` change (the catalog is already a project reference).

**Files:**
- Create: `Leatherfolio/Resources/Assets.xcassets/HouseDog.imageset/house-dog.png`
- Create: `Leatherfolio/Resources/Assets.xcassets/HouseDog.imageset/Contents.json`

**Interfaces:**
- Produces: an asset named `HouseDog`, loadable via SwiftUI `Image("HouseDog")`. Task 3 depends on this exact name.

- [ ] **Step 1: Generate a right-sized PNG (1024px) from the source**

```bash
DEST="Leatherfolio/Resources/Assets.xcassets/HouseDog.imageset"
mkdir -p "$DEST"
sips -Z 1024 -s format png "$HOME/Obsidian/Personal/Pasted image 20260721234301.png" \
  --out "$DEST/house-dog.png" >/dev/null
sips -g pixelWidth -g pixelHeight "$DEST/house-dog.png" | tail -2
```

Expected: `pixelWidth: 1024`, `pixelHeight: 1024`.

- [ ] **Step 2: Write a single-scale `Contents.json`**

```bash
cat > "Leatherfolio/Resources/Assets.xcassets/HouseDog.imageset/Contents.json" <<'JSON'
{
  "images" : [
    {
      "idiom" : "universal",
      "filename" : "house-dog.png"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
JSON
python3 -c "import json;json.load(open('Leatherfolio/Resources/Assets.xcassets/HouseDog.imageset/Contents.json'));print('valid')"
```

Expected: `valid`. Single-scale (no `1x/2x/3x`) avoids empty-slot warnings; the 1024px source is crisp at the ~260pt display size.

- [ ] **Step 3: Build to confirm the catalog compiles the new asset**

Run:

```bash
xcodebuild build-for-testing -scheme Leatherfolio -project Leatherfolio.xcodeproj \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath /tmp/leatherfolio-dd 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:"
```

Expected: `** TEST BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add Leatherfolio/Resources/Assets.xcassets/HouseDog.imageset
git commit -m "feat: add HouseDog easter-egg illustration asset"
```

---

## Task 3: Wire the easter egg into StatsView

Deliverable: long-pressing the Stats headline reveals the dog over a dimmed backdrop as "Chief Bag Inspector", with a soft haptic, Reduce-Motion respected, and VoiceOver support. Rendering stays crash-free.

**Files:**
- Modify: `Leatherfolio/Features/Stats/StatsView.swift`
- Test: `LeatherfolioTests/StatsViewRenderTests.swift` (existing — used as the regression gate; no edits required)

**Interfaces:**
- Consumes: `Image("HouseDog")` from Task 2; `Theme.Spacing` and `Font.display(_:)` from Task 1's unchanged `Theme`.
- Produces: no new public API (all changes are private to `StatsView` and a fileprivate `HouseDogReveal`).

- [ ] **Step 1: Run the existing render tests to establish a green baseline**

Run:

```bash
xcodebuild test-without-building -scheme Leatherfolio -project Leatherfolio.xcodeproj \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath /tmp/leatherfolio-dd \
  -only-testing:LeatherfolioTests/StatsViewRenderTests 2>&1 | grep -E "passed|failed|\*\* TEST"
```

Expected: `testStatsViewRendersWithoutCrashing` and `testStatsViewRendersEmptyCollection` both `passed`. (These render `StatsView` from a pure `CollectionStats` value — no SwiftData — so they are safe under the beta.)

- [ ] **Step 2: Add reveal state and the reveal trigger to `StatsView`**

Replace the `struct StatsView: View { let stats … var body … }` opening and add `revealDog()` so the top of the struct reads:

```swift
struct StatsView: View {
    let stats: CollectionStats
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showDog = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headline
                moneyBlock
                ratingBlock
                categoryChart
                completenessBlock
            }
            .padding()
        }
        .navigationTitle("Stats")
        .background(Theme.background)
        .sensoryFeedback(trigger: showDog) { _, revealed in
            revealed ? .impact(flexibility: .soft) : nil
        }
        .overlay {
            if showDog {
                HouseDogReveal {
                    withAnimation(.easeOut(duration: 0.2)) { showDog = false }
                }
                .transition(reduceMotion
                            ? .opacity
                            : .scale(scale: 0.85).combined(with: .opacity))
            }
        }
    }

    /// Easter egg: the house dog, hidden behind a long-press on the headline.
    private func revealDog() {
        withAnimation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.62)) {
            showDog = true
        }
    }
```

- [ ] **Step 3: Attach the long-press + accessibility to the headline**

Replace the `private var headline` computed property with:

```swift
    private var headline: some View {
        Text(StatsHeadline.text(
            itemCount: stats.itemCount,
            colorCount: stats.distinctColorCount,
            leatherTypeCount: stats.distinctLeatherTypeCount,
            unicornCount: stats.unicornCount
        ))
        .font(.display(.title3))
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.5) { revealDog() }
        .accessibilityAddTraits(.isHeader)
        .accessibilityAction(named: "Meet the house dog") { revealDog() }
    }
```

- [ ] **Step 4: Add the `HouseDogReveal` view at the end of the file**

After the closing `}` of `struct StatsView`, append:

```swift

/// The house dog easter egg: a dimmed backdrop and a spring-in portrait of the
/// Chief Bag Inspector. Dismissed by tapping anywhere or the VoiceOver escape.
private struct HouseDogReveal: View {
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(spacing: Theme.Spacing.m) {
                Image("HouseDog")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: .black.opacity(0.35), radius: 20, y: 10)
                Text("Chief Bag Inspector")
                    .font(.display(.title3))
                    .foregroundStyle(.white)
                Text("Tap to dismiss")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(Theme.Spacing.xl)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityLabel("The house dog, Chief Bag Inspector")
        .accessibilityAction(.escape, onDismiss)
    }
}
```

- [ ] **Step 5: Build**

Run:

```bash
xcodebuild build-for-testing -scheme Leatherfolio -project Leatherfolio.xcodeproj \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath /tmp/leatherfolio-dd 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:"
```

Expected: `** TEST BUILD SUCCEEDED **`, no `error:` lines. (Confirms `.sensoryFeedback(trigger:_:)`, the transition, and `Image("HouseDog")` type-check.)

- [ ] **Step 6: Re-run the render tests (regression gate)**

Run:

```bash
xcodebuild test-without-building -scheme Leatherfolio -project Leatherfolio.xcodeproj \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath /tmp/leatherfolio-dd \
  -only-testing:LeatherfolioTests/StatsViewRenderTests 2>&1 | grep -E "passed|failed|\*\* TEST"
```

Expected: both render tests still `passed` — the overlay/gesture didn't break rendering.

- [ ] **Step 7: Commit**

```bash
git add Leatherfolio/Features/Stats/StatsView.swift
git commit -m "feat: hide house-dog easter egg behind long-press on Stats headline"
```

---

## Task 4: Consolidated verification

Deliverable: recorded evidence that the change is sound as far as the beta toolchain allows, plus an explicit note of what remains unverifiable until a stable Xcode is available.

**Files:** none (verification only; optional docs commit).

- [ ] **Step 1: Clean build of app + tests**

Run:

```bash
xcodebuild clean build-for-testing -scheme Leatherfolio -project Leatherfolio.xcodeproj \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath /tmp/leatherfolio-dd 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:"
```

Expected: `** TEST BUILD SUCCEEDED **`.

- [ ] **Step 2: Run the isolated, SwiftData-free test classes touched by this change**

Run:

```bash
xcodebuild test-without-building -scheme Leatherfolio -project Leatherfolio.xcodeproj \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath /tmp/leatherfolio-dd \
  -only-testing:LeatherfolioTests/ThemeContrastTests \
  -only-testing:LeatherfolioTests/StatsViewRenderTests \
  -only-testing:LeatherfolioTests/StatsHeadlineTests \
  -only-testing:LeatherfolioTests/StatsFormattingTests 2>&1 \
  | grep -E "Executed .* test|failed|\*\* TEST"
```

Expected: `** TEST EXECUTE SUCCEEDED **`, 0 failures across the four classes (3 + 2 + 3 + 1 = 9 tests).

- [ ] **Step 3: Record the toolchain caveat**

The full suite (`xcodebuild test` with no `-only-testing:`) is NOT run here: persistence tests (e.g. `CloudKitRulesTests`, `PhotoLifecycleTests`, `ItemDeletionTests`) perform SwiftData inserts/saves that trap under Xcode 27 Beta 4. Re-run the full suite once a stable Xcode 26.x is installed:

```bash
sudo xcode-select -s /Applications/Xcode-26.app/Contents/Developer   # when available
xcodebuild test -scheme Leatherfolio -project Leatherfolio.xcodeproj \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

- [ ] **Step 4 (optional): Manual smoke on a stable toolchain**

When on stable Xcode: launch the app, open **Stats**, long-press the headline → the dog springs in with a soft haptic and "Chief Bag Inspector"; tap to dismiss. Toggle the simulator between Light and Dark appearance and confirm the whole app follows (near-black ground in dark, soft-bone in light), with the cognac accent legible in both.

---

## Self-Review

**1. Spec coverage.** Design asks were: (a) adopt Cognac Gallery light+dark — Task 1; (b) keep it a single palette swap on the existing architecture — Task 1 keeps asset names + `Theme` API; (c) dog easter egg via long-press on the Stats title — Tasks 2 (asset) + 3 (gesture/reveal); (d) preserve WCAG AA — Task 1 Steps 1/7 + Task 4 Step 2. All covered.

**2. Placeholder scan.** No `TBD`/`TODO`/"handle edge cases"/"similar to Task N". Every code step shows complete code; every run step shows the command and expected output. Clear.

**3. Type consistency.** `Image("HouseDog")` (Task 3) matches the asset name produced in Task 2. `revealDog()`, `showDog`, `reduceMotion`, and `HouseDogReveal(onDismiss:)` are used consistently across Task 3 Steps 2–4. `Theme.Spacing.m/.xl` and `Font.display(.title3)` reference the unchanged members preserved in Task 1 Step 5. Palette hexes in the Task 1 verifier (Step 1), the test (Step 2), and the colorset generator (Step 3) are identical.

**4. Toolchain honesty.** The beta SwiftData-save limitation is stated in Global Constraints and Task 4, with the exact isolated-test workaround and the full-suite command to run once stable Xcode is available.
