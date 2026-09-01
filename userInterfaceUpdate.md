# papaSteps — User Interface and Experience Update

**Status:** Proposed design and implementation plan
**Document version:** 1.0
**Date:** 11 August 2026
**Applies to:** papaSteps, iOS 26 or later (`IPHONEOS_DEPLOYMENT_TARGET = 26.0`), Swift 6, SwiftUI
**Relationship to `specification.md`:** This document refines §7 (User experience) only. It does not change any sensor, fusion, persistence, HealthKit, or state-machine contract. Where the two documents disagree on wording of a screen, this document wins; where they disagree on behavior, `specification.md` wins.

---

## 1. Purpose

All functional phases (0–6) are complete. The app measures well and explains itself honestly, but it looks like an unstyled reference implementation: system default blue, `.quaternary` boxes, raw enum values shown to the user, and no visual hierarchy separating "the number I need mid-walk" from "the caveat I read afterwards."

This plan turns papaSteps into a product with an identity — **bright green on black** — while adopting iOS 26 design language (Liquid Glass, modern tab and toolbar treatments), improving legibility at a glance, and removing developer language from the interface.

### 1.1 Scope

In scope: colors, typography, layout, iconography, motion, haptics, copy, component structure, accessibility of presentation.

Out of scope, and explicitly protected: the walk state machine, metric fusion, quality gating, permission flow order, persistence, Health integration, Live Activity payloads, and every existing accessibility identifier. **No screen may start showing a value it does not measure, and no honest "unavailable" state may be beautified into a zero.** That rule from `specification.md` §1 survives this redesign intact.

### 1.2 Success criteria

1. A user glancing at the live screen while walking can read speed, direction, and steps in under one second at arm's length.
2. Every user-facing string is plain English in sentence case — no `whenInUse`, no `notDetermined`, no `Requested`.
3. Light and dark mode are both deliberate designs, not one design with inverted defaults.
4. Text and essential icons meet WCAG AA (4.5:1 body, 3:1 large text and meaningful graphics) in both modes.
5. The layout survives the largest accessibility Dynamic Type size without clipping any primary metric or control.
6. `make ci` stays green throughout, with UI-test changes made deliberately and in the same commit as the copy change that caused them.

---

## 2. Audit of the current interface

Evidence is from the four supplied screenshots and the current source.

### 2.1 Identity and color

| Issue | Where | Effect |
|---|---|---|
| Accent is the stock-adjacent blue `#1B71B1` | `Support/Assets.xcassets/AccentColor.colorset` | Nothing about the app is memorable or ownable. |
| Single accent for every semantic role | app-wide | Recording, success, warning, and navigation all read the same. |
| `.quaternary` used as the universal card fill | `WalkMetricCard`, `ProgressView` (5 sections), `HistoryView` detail, `WalkView` readiness | Cards visually dissolve into the background in dark mode; in light mode they read as disabled. |
| No dark-mode-specific design | app-wide | Dark mode is "whatever the system does," visible in the screenshots as flat gray-on-black. |
| No stroke, elevation, or grouping language | app-wide | Six identical gray boxes on Progress, no sense of what matters most. |

### 2.2 Hierarchy and layout

- **Walk start screen:** the hero icon, the headline, the readiness panel, and the Start button all compete at similar weight, and the single most important control on the app sits mid-screen at default button size.
- **Live walk screen:** an eight-card uniform grid means speed, steps, and direction have the same visual weight as altitude and elapsed time, contradicting the glanceable hierarchy `specification.md` §7.3 asks for. The Pause/Done controls scroll away with the content.
- **Progress:** six stacked `.quaternary` panels with no chart styling, no delta indicators, and no visual difference between "this week," "your best ever," and "a rule explanation."
- **History:** a plain list of three inline labels; the route — the most attractive artifact the app produces — never appears until you tap in.
- **Sensor diagnostics:** the only screen with real color coding (green checks), and it is the best-looking screen in the app. That treatment should propagate outward, not stay hidden behind a `#if DEBUG` toolbar button.

### 2.3 Copy problems, including camelCase leaks

These are shown to users today:

| Displayed string | Source | Replacement |
|---|---|---|
| `authorized` | `WalkView.swift:159` | Allowed |
| `whenInUse` | `WalkView.swift:164` | Allowed while using the app |
| `always` | `WalkView.swift:164` | Always allowed |
| `notDetermined` → partly patched to "Not requested" by a string replace at `WalkView.swift:189` | `WalkView.swift:159,164,169` | Not requested yet |
| `denied` / `restricted` | `WalkView.swift:159,164` | Turned off / Not available on this iPhone |
| `full` / `reduced` / `unknown` | `WalkView.swift:169` | Precise / Approximate only / Checking |
| `Requested` | `HealthStore.accessState.displayName`, seen in the screenshot | Connected |
| `Good` / `Degraded` / `Unavailable` from `RouteQuality.rawValue.capitalized` | `HistoryView.swift:113,257` | Good route / Partial route / No route |
| `detail.altitudeQuality.rawValue.capitalized` | `HistoryView.swift:224` | Barometer / Estimated from GPS / Not recorded |
| `CapabilityAvailability.rawValue` spoken by VoiceOver, e.g. `permissionRequired` | `CapabilityStatusRow.swift:56` | Needs permission |
| `ISO week 33 · Rules v2` | `ProgressView.swift:66` | Week of 10 August |
| `100% down · 18.8 km` | `ProgressView.swift:265` | 18.8 km behind your best week |
| `Not Available` (title case mid-sentence) | `HealthInsightSection.swift:83,96` | Not available |
| `0 eligible walks` shown under a `0 km` total | `ProgressView.swift:214` | Replace the whole card with a single explanatory empty state |

Title-case button and heading labels (`No Walks Yet`, `Route Unavailable`, `Progress Unavailable`, `Finish Walk`) should move to sentence case except where iOS convention keeps title case (button labels stay title case per HIG; headings and descriptions move to sentence case).

### 2.4 iOS 26 opportunities not yet taken

The project targets iOS 26 and therefore already gets Liquid Glass on the tab bar, navigation bars, and sheets for free — visible in the screenshots as the floating tab bar. Nothing else uses the material deliberately:

- No `GlassEffectContainer` anywhere; no `.glassEffect()`; no `.buttonStyle(.glass)` / `.glassProminent`.
- No `.scrollEdgeEffectStyle(_:for:)`, so long scrolls collide with the floating tab bar (visible in the Progress screenshot, where "This week" and the metric cards are cut by the header and the tab bar overlaps the comparison rows).
- No `ToolbarSpacer`, so the three Walk-tab toolbar buttons render as one undifferentiated cluster.
- Toolbar buttons are icon-only with no `labelStyle`, so their meaning is guesswork (gear, card, stethoscope).
- No `Namespace` morphing between idle → active → completed walk states, which is the single most satisfying animation opportunity in the app.

---

## 3. Design direction

**Concept: instrument panel, not dashboard.** papaSteps is used outdoors, in motion, often one-handed, sometimes by people who are not chasing a training plan. The interface should feel like a well-made instrument: a black field, one vivid green signal color that means "live and healthy," generous numerals, and everything else in quiet grays until it needs attention.

Five principles:

1. **One number rules each screen.** Live walk: speed. Summary: distance. Progress: this week's distance. Everything else is support.
2. **Green means live.** The accent is reserved for active recording, achieved goals, good data, and the primary action. It is never decoration. When a metric is stale or unavailable, the green drains out — that is the app's honesty rendered as color.
3. **Black is a material, not an absence.** Dark mode uses true black surfaces with a single hairline stroke and a raised card fill, matching the OLED look of the current screenshots but with real edges.
4. **Icons carry meaning, never replace labels.** Every metric keeps its SF Symbol *and* its word. Symbols use consistent weight and optical size, and the symbol vocabulary is fixed in one place.
5. **Motion confirms, never entertains.** Numbers roll, the recording ring pulses, glass morphs between states. All of it respects Reduce Motion.

---

## 4. Design tokens

All tokens live in a new `papaSteps/DesignSystem/` group. Colors ship as asset catalog color sets (so they resolve per appearance and per contrast setting) and are surfaced through a `Color` extension for type-safe use.

### 4.1 Color

Contrast ratios below are computed WCAG values against the surface they are specified for.

**Brand**

| Token | Light | Dark | Use | Contrast |
|---|---|---|---|---|
| `brandGreen` | `#00C853` | `#00E05A` | Primary button fill, recording ring, chart bars, goal fill | Black label on `#00E05A` = 11.8:1; black on `#00C853` = 9.4:1 |
| `brandGreenInk` | `#0A7D3C` | `#3BE477` | Green *text* and small green icons | 5.2:1 on white; 12.6:1 on black |
| `brandInk` | `#000000` | `#FFFFFF` | Label on a `brandGreen` fill, primary text | 19.6:1 / 19.1:1 |

The signature pairing — **bright green fill with a black label** — is used identically in both appearances, which is what makes the app recognizable in a screenshot. Green as *text* always uses `brandGreenInk`, never `brandGreen`, because `#00C853` on white is only ~2.2:1 and would fail.

**Surfaces**

| Token | Light | Dark | Use |
|---|---|---|---|
| `surfaceBase` | `#FFFFFF` | `#000000` | Screen background |
| `surfaceRaised` | `#F6F7F8` | `#121316` | Metric cards, list rows |
| `surfaceSunken` | `#EEF0F2` | `#0A0B0C` | Chart plot areas, inset wells |
| `strokeHairline` | `#00000014` | `#FFFFFF1F` | 1px card border |

**Text**

| Token | Light | Dark | Contrast |
|---|---|---|---|
| `textPrimary` | `#0B0B0C` | `#FFFFFF` | ≥ 19:1 |
| `textSecondary` | `#6B7078` | `#8A8F98` | 5.0:1 / 6.1:1 |
| `textTertiary` | `#8A8F98` | `#6B7078` | Decorative only — never sole carrier of meaning |

**Semantic**

| Token | Light | Dark | Meaning |
|---|---|---|---|
| `signalGood` | `brandGreenInk` | `brandGreen` | Good data, goal met, allowed |
| `signalCaution` | `#B45309` | `#FF9F0A` | Stale, degraded, approximate location (5.0:1 / 10.2:1) |
| `signalAlert` | `#C4271C` | `#FF453A` | Denied, failed, destructive (5.8:1 / 6.2:1) |
| `signalHealth` | `#C2185B` | `#FF6482` | Apple Health attribution only |
| `signalNeutral` | `textSecondary` | `textSecondary` | Not requested, optional, off |

Each color set also gets a **High Contrast** variant in the asset catalog (Xcode's "High Contrast" appearance), darkening `brandGreenInk` to `#06612F` in light and brightening `textSecondary` in dark.

**Rule:** `Color.accentColor` is replaced everywhere by an explicit semantic token. The asset catalog `AccentColor` is updated to `brandGreen` so system-tinted controls follow, but view code should name its intent.

### 4.2 Typography

Use the system font throughout — no custom faces. The change is in *role assignment*, not typeface.

| Role | Style | Notes |
|---|---|---|
| Hero metric (live speed, saved distance) | `.system(size: 64, weight: .semibold, design: .rounded)` + `.monospacedDigit()`, scaled with `@ScaledMetric` | Rounded reads better on numerals at a glance |
| Card metric value | `.title2.weight(.semibold).monospacedDigit()` | as today, plus rounded design |
| Card metric title | `.footnote.weight(.medium)` uppercase-free | Paired with symbol |
| Section header | `.title3.weight(.semibold)` | Sentence case |
| Body / explanation | `.subheadline` | `textSecondary` |
| Caveat / provenance | `.caption` | `textSecondary`, or `signalCaution` when stale |

Every numeric display uses `.monospacedDigit()` so values do not jitter while walking. `.contentTransition(.numericText())` is applied to live-updating numbers.

### 4.3 Spacing, shape, and elevation

- Spacing scale: `4, 8, 12, 16, 20, 24, 32`. Screen margin `20`. Card padding `16`. Grid gutter `12`.
- Corner radii: card `20` (`.rect(cornerRadius:style: .continuous)`), hero panel `28`, chip/pill `.capsule`, map `20`.
- Elevation: no drop shadows in dark mode; use `surfaceRaised` + `strokeHairline`. In light mode, one soft shadow (`y: 1, blur: 3, black at 6%`) on cards only.
- Minimum hit target 44×44pt; primary walk controls 56pt tall.

### 4.4 Iconography

A single `WalkSymbol` enum centralizes SF Symbols so the same concept never uses two glyphs (today "elevation gain" is `arrow.up.right`, which reads as "trending," not "climbing").

| Concept | Symbol | Change |
|---|---|---|
| Distance | `point.topleft.down.to.point.bottomright.curvepath` | replaces `ruler` |
| Steps | `shoeprints.fill` | keep |
| Moving time | `timer` | keep |
| Elapsed time | `clock` | keep |
| Speed / pace | `speedometer` | keep |
| Altitude | `mountain.2.fill` | filled for weight |
| Elevation gain | `arrow.up.forward.square.fill` or `chart.line.uptrend.xyaxis` | pick one, apply everywhere |
| Direction | `location.north.fill` | keep, hero-sized |
| Route quality | `dot.radiowaves.up.forward` | new |
| Health | `heart.fill` with `signalHealth` | keep |
| Streak | `flame.fill` | keep |
| Badge | `medal.fill` | keep |

All symbols get `.symbolRenderingMode(.hierarchical)` by default, `.palette` where two-tone communicates state, and `.symbolEffect(.pulse)` on the recording indicator only.

### 4.5 Motion and haptics

| Event | Motion | Haptic |
|---|---|---|
| Start walk | Glass morph from Start button into the live header, `.spring(response: 0.45, dampingFraction: 0.8)` | `.success` |
| Pause / resume | Control bar crossfade, ring stops/starts pulsing | `.impact(.medium)` |
| Finish confirmed | Summary rises with numbers counting up once | `.success` |
| Goal reached / badge earned | Green sweep across the card | `.success` |
| Stale metric | Color drain over 0.3s, no movement | none |

Everything above is wrapped so that `@Environment(\.accessibilityReduceMotion)` collapses it to a cross-dissolve, and haptics are added as a settings toggle (default on) rather than assumed.

---

## 5. Component inventory

New or reworked components, all in `papaSteps/DesignSystem/` unless noted.

| Component | Replaces | Purpose |
|---|---|---|
| `Theme.swift` | — | Color/spacing/radius/typography tokens |
| `WalkSymbol.swift` | scattered string literals | Symbol vocabulary |
| `DisplayNames.swift` | `.rawValue` in views | Every enum → plain-English label + semantic color |
| `MetricTile` | `WalkMetricCard` | Card with symbol, label, value, provenance line, state color; `prominent` and `compact` sizes |
| `HeroMetric` | ad-hoc `VStack` in `LiveWalkContent` | The one big number, with unit, sub-caption, and stale state |
| `StatusChip` | readiness `LabeledContent` rows | Capsule with icon + plain label + state color |
| `SectionCard` | repeated `.padding().background(.quaternary…)` | Consistent card container with optional header and footnote |
| `DeltaBadge` | `comparisonText` string | ▲/▼ + percentage + reference, colored by direction |
| `GlassControlBar` | `controls` HStack in `LiveWalkContent` | Pinned bottom bar, `GlassEffectContainer` + `.glassEffect()` |
| `RecordingRing` | none | Pulsing green ring around the live hero showing recording/paused |
| `RouteThumbnail` | none | Small static map snapshot for History rows |
| `EmptyStateView` | four different `ContentUnavailableView` calls | Consistent illustration + copy + action |

`WalkMetricFormatting` stays exactly where it is and keeps its API — it is unit-tested by `WalkDisplayFormattingTests` and is not a design concern.

---

## 6. Phases

Each phase is independently shippable, ends with a green `make ci`, and does not depend on a later phase. Recommended model per phase is given with a reason; "with `/code-review`" means run the review command before merging.

---

### Phase U0 — Design system foundation and copy pass ✅ Shipped 11 August 2026

**Model: Claude Opus 5.** This phase sets the vocabulary every other phase consumes, and the copy mapping requires judgment about what a non-technical walker will understand. Getting it wrong is expensive to unwind.

**What shipped, and where it differs from the plan above**

- **Colors are declared in code, not in the asset catalog.** `DesignSystem/Theme.swift` defines each token once as a dynamic `UIColor` covering light, dark, and high-contrast appearances. This was chosen over twelve `Contents.json` files because it makes the palette unit testable: `ThemeContrastTests` resolves every token against real trait collections and asserts WCAG ratios, which delivers part of the U5 promise now rather than at the end. `AccentColor` remains in the catalog for system-tinted controls.
- **`AccentColor` is `brandGreenInk` in light mode, `brandGreen` in dark** — not `brandGreen` in both. The tab bar tints its selected item from the accent, and the fill green as *text* on a white tab bar is 2.2:1. The fill green is still the fill everywhere it is a fill.
- **Two tokens were added** that §4.1 did not anticipate:
  - `onBrandGreen` — always black, for labels sitting on a `brandGreen` fill. The first version used `brandInk` here, which inverts to white in dark mode and lands at about 1.6:1 on the green. `ThemeContrastTests` caught it.
  - `signalAlertFill` — held at the darker red in both appearances so a white label on a destructive button stays above 4.5:1.
  - `signalAward` — gold for medals, since `signalCaution` amber would have meant "something is wrong."
- **`PrimaryWalkButtonStyle` / `SecondaryWalkButtonStyle` were added in U0 rather than U1.** Changing the accent to green made every `.borderedProminent` button render a white label on green, so the button styles had to land with the color change, not after it.
- `HealthAccessState.displayName` moved out of the domain layer into `DisplayNames.swift`, so there is exactly one source of user-facing labels.

**Build**

1. ~~Create asset color sets for all tokens in §4.1~~ → `DesignSystem/Theme.swift` (see above); `AccentColor` updated.
2. `DesignSystem/Theme.swift` — `Color` extension, `Spacing`, `Radius`, `Typography` helpers, `@ScaledMetric` hero size.
3. `DesignSystem/WalkSymbol.swift` — symbol vocabulary from §4.4.
4. `DesignSystem/DisplayNames.swift` — `displayName` and `semanticColor` for `PermissionAuthorizationState`, `LocationAuthorizationState`, `LocationAccuracyState`, `CapabilityAvailability`, `RouteQuality`, `MetricQuality`, `AltitudeSource`, `DistanceSource`, `StepSource`, `HealthEnrichmentStatus`, `HealthAccessState`, using §2.3.
5. Delete the `replacingOccurrences(of: "notDetermined", …)` hack at `WalkView.swift:189` and every `.rawValue.capitalized` in a view.
6. Add `papaStepsTests/DisplayNameTests.swift`: assert every case of every listed enum returns a non-empty label containing no uppercase-mid-word pattern (a regex catching camelCase) and no raw case name.

**Do not** change layout in this phase. Screens should look identical apart from color and wording.

**Acceptance**

- [x] `grep -rn "rawValue" papaSteps/Features papaSteps/DesignSystem` returns only persistence/preferences uses.
- [x] `DisplayNameTests` passes over all UI-exposed enums (camelCase detection, with an allowlist for product names like "iPhone").
- [x] `ThemeContrastTests` passes: every text token ≥ 4.5:1 on both surfaces in both appearances, and high-contrast variants never regress.
- [x] Light and dark screenshots of the Walk tab show the green identity with no layout change.
- [x] `make ci` green. No UI-test string assertion needed changing — every string those tests check was already in its final form.

**Known flake, not caused by this phase:** `testManualHealthWorkoutImportAppearsOnceInHistory` failed once on a freshly booted simulator and then passed three consecutive isolated runs plus a full suite run. Separately, `xcodebuild` UI-test launches fail with `FBSOpenApplicationErrorDomain Code=6 "Busy"` when a simulator has been left in a used state; shutting simulators down before the run clears it.

---

### Phase U1 — Walk tab: start screen and live walk ✅ Shipped 11 August 2026

**Model: Claude Opus 5, with `/code-review`.** The highest-value, highest-risk screen: it reads a live state machine, has eight metric bindings, three limitation banners, and every existing walk UI test drives it. Layout changes here must not disturb `accessibilityIdentifier`s or state transitions.

**What shipped, and where it differs from the plan below**

- **Hero metric is speed** (honoring the pace preference), per the §9 proposal. Open decision 1 is therefore resolved as proposed, not by explicit choice — say so if moving time should take the hero slot.
- **The ring is a full circle, not an arc.** The first version trimmed the stroke to 85%, which read as progress through something. State is carried by color and by the breathing animation instead.
- **The direction value sits under the dial**, not overlaid on the ring, and reads "No heading yet" rather than an em dash when there is no course.
- **A "While you walk" card fills the first-run screen**, listing what the app records. Not in the plan; added because the empty start screen was a dead half-screen before any walk exists. It is replaced by the "Last walk" card as soon as there is history.
- **The map's empty state was rewritten and shrunk** — it was a title-case `ContentUnavailableView` occupying hero height to say "nothing yet."
- **The finish marker is ink, not red.** Red means "something is wrong" everywhere else in the palette.
- **Count-up numbers on the completed screen were not built.** Deferred to U6, where the shared green-sweep animation lands; `MetricTile` takes pre-formatted strings, and threading a numeric animation through it is a component change that belongs with that work. The completed screen animates in with a spring instead.
- **Start → live morph** uses `matchedGeometryEffect` on the primary action, so the green Start capsule becomes the green Pause capsule. Liquid Glass is used for the control bar (`GlassEffectContainer` + `glassEffect`), and no `#available` gate is needed anywhere because the deployment target is already iOS 26.

**One regression worth remembering** (added to §7.2): `.accessibilityIdentifier` applied *after* `.safeAreaInset` propagates into the inset content and overrides the identifiers on the buttons inside it. That silently renamed `walk.pause` and `walk.done` to `walk.live`, and the walk lifecycle UI test caught it. The identifier now goes on the `ScrollView` before the inset.

**Build — start screen**

- Hero block: app mark, one sentence of purpose, then a full-width **Start Walk** button as a 56pt `brandGreen` capsule with black label — the unmistakable focal point, positioned in thumb reach rather than mid-scroll.
- Readiness becomes a horizontal row of `StatusChip`s (Motion, Location, Precise, Health) with plain labels and semantic colors; tapping a non-green chip explains what is limited and offers the relevant action. The verbose panel collapses into this.
- "Last walk" recap card (distance, date, one tap into detail) when history exists — turning a dead screen into a reason to open the app.
- `.scrollEdgeEffectStyle(.soft, for: .top)` and bottom safe-area padding so nothing hides under the floating tab bar.

**Build — live walk**

- Restructure to the `specification.md` §7.3 hierarchy explicitly:
  1. `HeroMetric` — speed (or pace), with the direction arrow and cardinal label beside it inside a `RecordingRing`.
  2. Secondary row of three `MetricTile`s — steps, moving time, distance.
  3. Collapsible "More" section — elapsed, altitude, elevation gain, direction detail. Collapsed by default; state persisted.
  4. Route map, taller, with rounded corners and the follow toggle as a glass button.
  5. `GlassControlBar` pinned to the bottom safe area: Pause/Resume (prominent glass, green when resuming) and Done. **Controls never scroll away.**
- Limitation banners become one `SectionCard` with `signalCaution` styling and a single action, instead of three near-identical inline blocks.
- Stale metrics drain to `textSecondary` + `signalCaution` caption; the VoiceOver value keeps saying the state in words.
- `@Namespace` morph from the Start button into the live header.

**Build — finish and completed**

- Finish sheet: keep all three actions and their identifiers; restyle as a `.medium` detent glass sheet with a clearer hierarchy and sentence-case description.
- Completed screen: celebration header (green check, "Walk saved"), route map as the hero, then `MetricTile` grid, then Health section, then provenance. Numbers count up once on appear (Reduce Motion: no count).

**Acceptance**

- [x] All `walk.*` accessibility identifiers unchanged; every UI test passes untouched.
- [x] "Walk saved" string preserved exactly.
- [x] Pause/Done pinned in a bottom safe-area inset, so they never scroll away.
- [x] Live, finish, and completed screens photographed and reviewed in dark; start screen in both appearances.
- [ ] Reduce Motion, Reduce Transparency, and accessibility Dynamic Type sizes — **not yet verified on device.** The code paths exist (`accessibilityReduceMotion` gates the ring and state transitions; grids collapse at accessibility sizes) but nothing has been run with those settings on. This is the abbreviated U5 pass in §10 and should happen before U2.

---

### Phase U2 — History tab, with the accessibility pass folded in ✅ Shipped 12 August 2026

**Model: Claude Sonnet 5.** Presentational work over a stable store with a clear component spec from U0/U1; no new state machinery.

**What shipped beyond the plan**

- **Route thumbnails are drawn, not snapshotted.** `RouteThumbnail` renders a vector path from coordinates downsampled to 60 points, with longitude corrected for latitude so a walk keeps its true shape. A list of two hundred walks would otherwise fetch two hundred map images. This needed a new repository method (`fetchRoutePreview(id:maximumPoints:)`) and a per-row lazy cache in `WalkHistoryStore`.
- **`AppTabRouter`** now owns tab selection, so History's empty state can offer a Start Walk button that actually moves you to the Walk tab.
- **The metric row is one line of text, not three icon-and-value pairs.** With a thumbnail and a chevron on the row there is no room: the icons truncated distances to "0.8…". Icons return at accessibility text sizes, where the row stacks vertically and has the width for them.
- Month grouping uses each walk's **stored** time zone, so a trip does not shuffle rows between months.

**The accessibility pass (bundled from U5)**

`AccessibilityAuditTests` runs Apple's own `performAccessibilityAudit` against the Walk start, live walk, History, and walk detail screens, at default and at the largest accessibility text size, plus explicit assertions on the labels and values papaSteps promises. It found four things, three of which were real:

1. **Hierarchical symbol rendering** dropped small icons paired with labels below 3:1. Those now render monochrome in the label's own colour.
2. **Fixed-size symbol fonts** (`.font(.system(size: 56))`) ignore Dynamic Type. They are `@ScaledMetric` now.
3. **A chip clipped at the screen edge** — the readiness row scrolled horizontally, so the last chip was sliced. Chips now wrap onto a second line via a custom `WrappingChips` layout. Nothing about readiness should be hidden behind a scroll.
4. **Clipped text at large sizes**: the direction label and the map placeholder could not wrap inside their fixed heights.

Contrast tokens were also widened: secondary text sat at 4.65:1 on a light card — a pass with no margin — and is now 5.6:1 light and 7.1:1 dark.

**Two audit findings are excluded, both after experiment rather than assumption**, documented in full at `ignores(_:in:)`:

- **Contrast under the floating tab bar.** Every remaining contrast report landed on an element either unidentifiable or overlapping the bottom bar — at the largest text size, the flagged label sat at y 807–866 of an 874pt window, beneath a tab bar occupying roughly 795–849. Content dims as it scrolls under that glass. Contrast issues above that band stay enforced.
- **Dynamic Type on numeric displays.** Isolated by changing one modifier at a time: `.monospacedDigit()` resolves the font to a concrete instance that stops advertising the Dynamic Type trait, and the audit reads the trait rather than measuring. papaSteps uses monospaced digits so live numbers do not jitter. `testNumericDisplaysGrowWithTheUsersTextSize` measures the hero and a metric tile at two content-size categories and proves they still scale.

**Still not verified:** Reduce Motion and Reduce Transparency. `simctl` cannot toggle either, so they need a manual pass in Settings on a device or simulator. The code paths exist and are gated on `accessibilityReduceMotion`; nothing has exercised them.

**Build**

- Rows become cards: date and time as the title, a `RouteThumbnail` on the leading edge when a route exists, three metric labels with symbols, and a route-quality chip using the plain-English names.
- Group by month with pinned section headers; show a per-month total.
- Health-sourced walks get the `signalHealth` badge treatment (keep the literal "Health" label — a UI test asserts it).
- Walk detail: route map hero edge-to-edge under the navigation bar with `.backgroundExtensionEffect()`, then metric grid, then Health, then a "Recording details" `SectionCard` with plain-English route quality, altitude source, and GPS point counts.
- Empty state via `EmptyStateView` with a green Start Walk action that switches to the Walk tab.

**Acceptance**

- [x] `history.walk.<uuid>` and `history.walk.detail` identifiers unchanged; `walk.route.map` still present in detail.
- [x] `Health` static text still present for imported walks.
- [x] Thumbnails load per row via `.task` and cache for the session; routes are downsampled in the repository, so a row never loads a full track.
- [x] Apple's accessibility audit passes on Walk start, live walk, History, and walk detail, at default and largest accessibility text sizes.
- [ ] Reduce Motion and Reduce Transparency — still unverified, see above.

---

### Phase U3 — Progress tab ✅ Shipped 12 August 2026

**Model: Claude Sonnet 5 for layout; escalate the chart work to Opus 5 if Swift Charts styling fights the accessibility descriptors.** Mostly composition, but the comparison copy needs care (today it says "100% down · 18.8 km", which reads as a failure message).

**What shipped, and where it differs from the plan above**

- **"This week" is Hero (distance) + a `WalkMetricGrid` of three `MetricTile`s** (moving time, steps, elevation), not four equal-weight tiles. `MetricTile.Size` only ships `.standard` and `.compact` — U0 never added the `.prominent` case §5 anticipated — and principle 1 in §3 names weekly distance as the one number this screen is about, so it takes the hero slot the way distance already does on the Completed and walk-detail screens. `WalkMetricCard` is now fully retired from Progress (History retired it in U2); it remains only in `HealthInsightSection.swift`, which is U4 scope.
- **`DeltaBadge` phrases every comparison as a percentage** ("▲ 12% ahead of your 4-week average", "Even with your best week"), rather than the absolute-difference wording the §2.3 example used for best-week specifically. A percentage reads correctly for all four metrics (steps and elevation gain have no natural "X km" phrasing); a per-kind special case would have made the component metric-aware for no real benefit. Direction is colored `signalGood` (ahead), `signalCaution` (behind), or neutral (even / not enough history) — never conveyed by color alone, the arrow and words carry it too.
- **Goals render as a fill ring with a checkmark on completion**, built as a local `GoalRingRow` (not a shared component — §5 only asked for "ring progress," not a named type). The two existing goals (distance, steps) are unchanged; no new goal metrics were added.
- **Achievements is now a fixed 3-column grid of every `ProgressBadge` case**, earned or not. Locked badges stay visible at reduced opacity with their unlock condition as the caption, replacing the old "Complete an eligible walk to begin earning achievements." empty-state line entirely — there is no longer an empty state for this section, since all three badges are always shown.
- **Fixed a real bug in the chart's week selection while restyling it.** `chartWeeks` was `Array(snapshot.weeklyAggregates.reversed().prefix(8))` — since `weeklyAggregates` is sorted newest-first, reversing then taking a prefix returned the *oldest* eight weeks of a user's history, not the most recent eight. The chart now takes the most recent weeks (up to 52), renders them oldest-to-newest, and is horizontally scrollable (`chartScrollableAxes` + `chartXVisibleDomain(length: 8)`) with the scroll position initialized so the current week is on screen by default instead of flashing the oldest data first.
- **The y-axis now plots the user's distance-unit preference** (km or mi, converted per bar) instead of raw meters under a "km"-implying heading, and the axis labels carry the unit. Bars are corner-rounded, sit on a `surfaceSunken` plot background, and the current week renders at full `brandGreen` opacity against 45% for every other week — all per §6's build note, verified in both appearances with seeded multi-week fixture data.

**Build**

- Header: current week with a plain date range ("Week of 10 August"), streak as a flame chip, and the rules version moved out of the headline into the footer of the eligibility explainer.
- Four `MetricTile`s in `prominent` size for distance, moving time, steps, elevation.
- Weekly distance chart restyled: `brandGreen` bars with rounded corners, current week highlighted and past weeks at 45% opacity, `surfaceSunken` plot area, y-axis in the user's distance unit rather than raw meters (the current chart's "15,000" axis is meters shown under a "km" heading — fix), `.chartScrollableAxes(.horizontal)` for longer histories.
- Comparisons become `DeltaBadge` rows: "▼ 18.8 km behind your best week" in `signalCaution`, "▲ 12% ahead of your 4-week average" in `signalGood`, "Not enough history yet" in `signalNeutral`.
- Goals: ring progress instead of linear bars, green fill, completed state with a check.
- Achievements: medal grid, locked badges shown dimmed with their unlock condition — visible goals motivate more than an empty list.
- Zero-eligible-walk state replaces the whole dashboard rather than showing four `0` cards next to a populated chart (visible inconsistency in the current screenshot).

**Acceptance**

- [x] `progress.dashboard` and `progress.weeklyDistance.chart` identifiers unchanged; "No Eligible Walks Yet" string preserved (unchanged this phase — no UI test needed updating).
- [x] Chart axis units match the user's distance-unit preference and update when it changes (reads live from `WalkDisplayPreferences` via the existing `configuration` plumbing).
- [x] Chart has an accessible representation for every bar (existing `accessibilityLabel`/`accessibilityValue` preserved, unchanged).

**Verified:** `make ci` green (build, release-build, unit tests, UI tests). Visually reviewed in both appearances with seeded four-week fixture data covering a completed goal ring, an in-progress case, an earned and a locked badge, and all three comparison directions (ahead/behind/even) — screenshots not committed, QA-only.

**Not yet verified:** Dynamic Type at accessibility sizes and VoiceOver phrasing for the new ring and badge grid — deferred to U5 alongside the rest of the cross-cutting audit, consistent with the sequencing in §10.

---

### Phase U4 — Settings, permissions, diagnostics, and Live Activity ✅ Shipped 12 August 2026

**Model: Claude Sonnet 5 for the forms; Claude Haiku 4.5 for the mechanical symbol/token substitutions once the pattern is set.**

**What shipped, and where it differs from the plan above**

- **No `ToolbarSpacer`.** The three toolbar items collapsed to exactly one ("Settings"), so there is nothing left to visually separate it from. `WalkSettingsView` is a plain `Form` with "Walk Recording" and "Apple Health" rows, plus a `#if DEBUG` "Sensor Diagnostics" section with a footer explaining it is debug-only — matching the sub-screens' own `Form` idiom rather than inventing a card-based menu.
- **`Theme.swift` and `WalkSymbol.swift` moved from `papaSteps/DesignSystem/` to `Shared/DesignSystem/`.** Neither file was reachable from the `papaStepsLiveActivity` extension target before this phase — the Live Activity's colors and icons were plain system values entirely outside the design system. Moving just the two token files (not the SwiftUI view components, which the widget doesn't need) makes them visible to both targets via Xcode's synchronized-group membership, with zero import changes required anywhere in the app, since Swift visibility is target-based rather than path-based.
- **`WalkPermissionSheet`'s primary action moved out of the `List`** into a `.safeAreaInset(edge: .bottom)` bar so `.buttonStyle(.primaryWalk)` renders as the same full-width green capsule used for Start Walk, rather than an odd capsule squeezed into a Form row. Each capability row also gained a one-line "Without it: …" caption, satisfying the "what still works without it" build note without restructuring the List into free-form cards — a lower-risk change to a delicate, well-tested permission flow.
- **Found and fixed a leftover from U0's icon/color audit while touching `HealthWorkoutImportView.swift`**, a screen none of U0–U3 had reason to open: a literal `"ruler"` icon (the exact one §4.4 replaced everywhere else with `WalkSymbol.distance`), plus `.green`/`.accentColor`/`.secondary` instead of `signalGood`/`brandGreenInk`/`textSecondary`. Also moved "No Walking Workouts" to sentence case, matching §2.3 (not test-asserted, so free to change).
- **Live Activity retint reused the existing semantic mapping** established for `RecordingRingState` and `signalCaution`/`signalAlertFill` rather than inventing new rules: active → `brandGreen`, paused/finish-candidate → `signalCaution`, completed → `signalGood`, interrupted → `signalAlert`, finish button → `signalAlertFill` (chosen specifically because its doc comment guarantees a readable white label, unlike a plain `signalAlert` tint). The two buttons now tinted `brandGreen` (Resume, Keep Walking) got an explicit `.foregroundStyle(Color.onBrandGreen)` — `Theme.swift`'s own comment documents that white-on-`brandGreen` is ~1.6:1 and unreadable, and `.borderedProminent`'s default label color doesn't auto-correct for a light tint, so this would have silently reproduced a contrast bug the team had already found and fixed elsewhere. `activityBackgroundTint` also moved from a near-invisible `.black.opacity(0.08)` to `Color.surfaceBase.opacity(0.2)`, a modest, adaptive nod to "black is a material" without fighting the system's required Lock Screen translucency.
- **Destructive delete-all button** in `PrivacyDataManagementView` kept `role: .destructive` (for VoiceOver/haptic semantics) and added `.foregroundStyle(Color.signalAlert)` alongside it, rather than replacing the role — the confirmation-dialog buttons were left on system styling since `foregroundStyle` has no effect on action-sheet-style destructive buttons.

**Acceptance**

- [x] `walk.health.settings`, `walk.diagnostics`, `walk.recording.settings`, `health.connect`, `health.import.*` identifiers all still resolvable. The toolbar consolidation moved `walk.health.settings`, `walk.recording.settings`, and `walk.diagnostics` one level deeper (behind a new `walk.settings` entry point) and the three affected UI tests were updated in this commit to navigate through it first.
- [x] Live Activity still renders within its size budget — verified by successful build and embedding of `papaStepsLiveActivity.appex` with no layout-affecting changes (only colors, icons, and label casing changed; no frames, paddings, or view structure). A live on-device/simulator Lock Screen and Dynamic Island visual check was not completed this phase — the simulator's manual input became unresponsive during QA (a tooling issue, not a build issue); this is worth a follow-up pass, ideally folded into U5 since it needs a real device or a working simulator session either way.

**Verified:** `make ci` green (build — including the widget extension target — release-build, unit tests, all 15 UI tests). `grep -rho 'accessibilityIdentifier("[^"]*")' papaSteps` shows the identifier set only grew (added `walk.settings`). Settings screen visually confirmed on-device (dark mode) showing the consolidated menu with correct tokens; deeper screens (Apple Health, Sensor Diagnostics, permission sheet, Live Activity) verified via passing automated UI tests and code review, not fresh screenshots, once the simulator stopped responding to manual taps.

---

### Phase U5 — Accessibility, contrast, and motion verification

**Model: Claude Opus 5.** Cross-cutting audit that must reason about intent, not pattern-match; also the phase most likely to find real regressions from U1–U4.

**Build**

- Verify every token pair in §4.1 against its actual usage with a computed-contrast test fixture, not by eye.
- Dynamic Type sweep at `.accessibility5` on all screens; grids collapse to one column (`WalkMetricGrid` already does this — extend the rule to the new hero and control bar).
- VoiceOver pass: every metric announces name, value, unit, and availability state in words; the control bar announces its actions; the chart is navigable.
- Reduce Motion and Reduce Transparency passes; confirm glass surfaces fall back to opaque `surfaceRaised` and remain legible.
- Add snapshot-style UI tests (or documented manual checks in `docs/`) for light/dark at default and largest text size.
- Sunlight legibility check on a real device at maximum brightness — the practical test for an outdoor app.

**Acceptance**

- [ ] Spec scenarios P5-01 and P5-02 re-run and recorded in `docs/`.
- [ ] No text below 4.5:1, no meaningful icon below 3:1, in either appearance.
- [ ] Nothing in the app conveys state by color alone (each colored state has an icon or a word).

---

### Phase U6 — Identity polish

**Model: Claude Sonnet 5 for implementation; the icon artwork itself is a design decision for you, not the model.**

**Build**

- App icon in the green/black identity, with the iOS 26 layered/tinted variants (light, dark, clear).
- Launch screen matching `surfaceBase`.
- One consistent green sweep animation shared by goal completion, badge unlock, and walk saved.
- Optional walk-summary share card (route + hero stats on the black/green identity) — genuinely new surface, so schedule it only after U0–U5 land.

---

## 7. Guardrails — things that must not break

### 7.1 Strings asserted by `papaStepsUITests`

Changing any of these without updating the test in the same commit breaks CI:

`Walk`, `History`, `Progress` (navigation bar titles and tab labels) · `Prepare Your Walk` · `Apple Health` · `Import Walks` · `Walk saved` · `No Eligible Walks Yet` · `Unfinished walk found` · `Health` · `Access has been requested.…` (prefix match) · `Imported 1 walking workout into papaSteps.` · `Connect Apple Health from the Walk screen settings to add optional post-walk insights.`

Several of these are exactly the title-case strings §2.3 wants in sentence case. That is fine — change the string and the assertion together, in one commit, never one without the other.

### 7.2 Accessibility identifiers

Every `accessibilityIdentifier` in the codebase is API for the UI tests. Restyling must preserve them; if a view is replaced, the identifier moves to the replacement. A blanket check before each phase merge:

```bash
grep -rho 'accessibilityIdentifier("[^"]*")' papaSteps | sort -u
```

Compare the output before and after; the set must only grow.

**Modifier-order trap, found in U1.** `.accessibilityIdentifier` applied to a scroll view *after* `.safeAreaInset` propagates into the inset and overrides identifiers set on the buttons inside it — the identifiers survive a `grep` but not the running app. Apply container identifiers before `safeAreaInset`, and treat "the identifier still exists in source" as insufficient evidence: the UI test run is the check that counts.

### 7.3 Behavior that presentation must not touch

- Metric availability states must keep rendering as availability states — a stale value never renders as fresh, and `—` never becomes `0`.
- Provenance lines ("GPS route", "Pedometer estimate", "Apple Health") stay visible on every metric that has them.
- Destructive-action copy in `specification.md` §7.4 is a product contract; restyle it, do not soften it.
- Permission requests stay in-context at Start Walk; no phase may add a first-launch permission wall.

### 7.4 Verification per phase

```bash
make ci
```

Then run the app in both appearances and at the largest accessibility text size:

```bash
xcodebuild -project papaSteps.xcodeproj -scheme papaSteps -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' build
```

---

## 8. Model selection summary

| Phase | Recommended model | Why |
|---|---|---|
| U0 — Design system + copy | **Opus 5** | Sets vocabulary for everything after; copy judgment for non-technical readers |
| U1 — Walk tab | **Opus 5** + `/code-review` | Live state machine, most tests, highest risk |
| U2 — History | **Sonnet 5** | Presentational work against a stable store |
| U3 — Progress | **Sonnet 5**, escalate charts to **Opus 5** | Composition; comparison copy and chart units need care |
| U4 — Settings/permissions/Live Activity | **Sonnet 5**, mechanical passes on **Haiku 4.5** | Form-shaped work with a settled pattern |
| U5 — Accessibility audit | **Opus 5** | Cross-cutting reasoning; catches regressions from U1–U4 |
| U6 — Identity polish | **Sonnet 5** | Implementation of decided artwork/animation |

General guidance: use Opus 5 whenever a phase *defines* a pattern, Sonnet 5 whenever a phase *applies* one, and Haiku 4.5 for mechanical substitution once the pattern is proven in review. Run `/code-review` on U1 and U5 at minimum.

---

## 9. Open design decisions

These need your call and are cheap to change before U1, expensive after:

1. **Hero metric on the live screen** — speed/pace, or moving time? Speed is proposed; a casual walker may care more about time.
2. **Green intensity in light mode** — `#00C853` (proposed, calmer on white) or the full `#00E05A` in both appearances (louder, more consistent identity).
3. **Progress tab default view** — this week (proposed) or a rolling 7-day window, which never shows a near-empty Monday.
4. **Collapsible "More" metrics on the live screen** — collapsed by default (proposed) or remembered per user from last walk.
5. **Haptics** — default on with a settings toggle (proposed), or opt-in.
6. **Share card in U6** — worth building, or out of scope for this release?

---

## 10. Suggested sequencing

U0 → U1 → U5 (partial: verify U1 accessibility) → U2 → U3 → U4 → U5 (full audit) → U6.

Running an abbreviated accessibility check right after U1 catches token or hierarchy mistakes while only one screen has adopted them, rather than after four screens have copied the same error.
