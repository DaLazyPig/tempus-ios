# Tempus build report

**Date:** 2026-08-09 · **Deliverable:** a native iOS app (SwiftUI, Xcode, App Store-bound)
converted from a single bundled artifact HTML, preserving the design system and product
behavior — plus CLAUDE.md and DESIGN.md as durable context for future agents.

## The journey (three artifacts, one design)

1. **The original file** was a published-artifact bundle: a loader plus 16 compressed
   resources. Unpacking revealed a complete React prototype — 1,840 lines of JSX, an
   18-component design system, design tokens, self-hosted fonts (Outfit variable +
   DM Mono), a deterministic mock data layer, and every screen of the product.
2. **A structured web port** (`prototype/`) was built first: Vite + React 18, the app
   split into 11 modules, the design system de-transpiled to clean JSX, fonts/tokens/
   keyframes extracted. Fidelity was proven three ways: a mechanical line diff (byte-
   identical outside five allowed transforms), an adversarial 3-agent semantic review
   of the design system (zero findings), and a scripted headless-Chrome walk of every
   flow (zero JS errors, visually indistinguishable from the original). This is now the
   permanent **reference implementation** — the runnable design spec.
3. **The native app** (`Tempus.xcodeproj` + `Tempus/`) is the product: Swift 5 /
   SwiftUI, iOS 17+, iPhone, portrait, light-mode, zero third-party dependencies.

## What the native app contains

- **Screens:** onboarding (4 steps: pitch, home-airport wheel, first-flight dial, app
  picker) → home (task deck with swipe/deal-in, miles header, floating Fly·Redeem·+
  nav) → preflight (minute dial, route, +N mi) → boarding pass (drag-to-tear stub) →
  in-flight (wall-clock countdown, route arc, divert) → landed/diverted (count-up
  miles) → redeem (cost dial, app picker, unlock state) → settings (all groups +
  choice sheets + Tempus Plus paywall) → flight log (Plus-gated; Swift Charts).
- **Design system in Swift:** `Theme/` mirrors `tokens.css` one-to-one (`TColor`,
  `TFont`, `TSpace`, `TRadius`, `Animation.glide`, `.tpShadow`); `DesignSystem/` holds
  TButton (5 variants), dial, deck card, boarding pass, pills, nav, toggles.
  Fonts ship as static instances of the Outfit variable font (cut with fontTools,
  clean PostScript names) + DM Mono, registered in Info.plist.
- **State:** one `@Observable AppModel` — a direct translation of the prototype's
  state machine, including the wall-clock flight deadline (cannot drift when
  backgrounded) and single-blob UserDefaults persistence (`tempus.app.v1`).
- **Data:** the mock screen-time layer ported PRNG-exact (mulberry32, seed 20260807) —
  the simulator's Flight log shows the *same numbers* as the web prototype (33 hours,
  13h 30m Organic chemistry…), which doubles as a correctness proof. It sits behind a
  `ScreenTimeService` protocol so the real integration swaps in without touching UI.
- **Xcode project:** hand-written `project.pbxproj` (objectVersion 77) using
  filesystem-synchronized groups — new files under `Tempus/` appear in Xcode
  automatically, no project-file surgery. App icon generated from the artifact's own
  plane mark. A DEBUG-only launch-argument seam (`-tempusPhase flying`, `-tempusPlus`)
  jumps to any screen for testing.

## How it was orchestrated

Fable stayed orchestrator; workers were **Sonnet agents** throughout (per your
instruction): 17 agents for the web extraction/port/verification, then **9 agents for
the Swift port** against a fixed-signature contract (every shared component's exact
Swift signature was pre-declared, so parallel agents could compile against each other's
unwritten files). Result: the full 18-file SwiftUI app **compiled on the first build**.

## Verification

- `xcodebuild` clean build (only expected warnings), installed and launched on the
  iPhone 17 Pro simulator.
- Every phase screenshot-verified via the launch-argument seam: onboarding, home,
  preflight, pass, flying (live countdown running), landed, diverted, redeem,
  settings, flight log — layouts, tokens, copy, and data all match the reference.

## Honest deviations (all deliberate)

- The prototype's **fake iOS home screen, Dynamic Island and lock-screen simulations
  were not ported** — on a real phone those are OS surfaces, not app screens. The real
  equivalents are: **FamilyControls + DeviceActivity + ManagedSettings** for actual app
  blocking (needs Apple's family-controls entitlement + user consent) and **ActivityKit**
  for the in-flight Live Activity. The `ScreenTimeService` protocol and CLAUDE.md map
  the integration path; the prototype remains runnable as the design spec for both.
- The custom in-app QWERTY keyboard became the real iOS keyboard (native TextField).
- Screen transitions use SwiftUI-idiomatic equivalents of the web's morph/circle/push
  vocabulary (same glide curve and durations).
- Paywall is UI-only (no StoreKit yet); "Start 7 days free" flips the Plus flag.

## Next steps toward the App Store

1. Add your Apple Developer team in Signing & Capabilities (project currently builds
   unsigned for simulator).
2. StoreKit 2 for the Tempus Plus subscription ($39/yr placeholder).
3. Request the Family Controls entitlement; implement `ScreenTimeService` on
   DeviceActivity; shield UI via ManagedSettings.
4. ActivityKit Live Activity for in-flight sessions (widget-extension target).
5. Real study-session history (SwiftData) feeding the existing analytics queries.

---

# The rewrite against `tempus_final_prerelease.html` (Sep 2026)

The prerelease bundle replaced `tempus_v10.html` as the reference build. Rather than patch
the existing Swift toward it, the app was **deleted and rewritten** — all 39 files and 12,671
lines removed with `git rm`, keeping only `Assets.xcassets` and `Fonts/`. What replaced it is
52 files and ~18,300 lines.

## How the reference was read

The bundle is a gzip+base64 manifest of six sources (`app.jsx` at 5,756 lines, `shop.js` at
1.7 MB, plus `carrier.js`, `geo.js`, `data.js`, `design-system.js`). It was unpacked and then
**executed under node**, not only read — which turned out to matter more than expected:

- `carrier.js` reads top-down as 200 carriers and 72 band patterns. Its last two layers
  override everything above them, and running it returns **one carrier and six liveries**.
  `Carriers.swift` is ~120 lines instead of ~750 because of that one `node -e`.
- Two hashes are not the algorithms they resemble. See below.

## Verification

The loop was: `build.sh` → fix → repeat until `BUILD SUCCEEDED`, then install, then
`walk.sh` — which relaunches the app 32 times, once per launch seam, and screenshots each
screen. The simulator accepts no synthetic taps, so the seams *are* the walk.

- **Build**: clean, zero source warnings. All four extension targets type-check separately
  (they are outside the app scheme, so the app build says nothing about them).
- **Self-checks**: `runSelfChecks()` traps on failure in DEBUG, so all 32 seam launches are
  also 32 self-check runs against different seeded state.
- **Expected values came from the reference executed under node**, so the asserts are a
  cross-check, not a restatement of the port's own behaviour.

That last point paid for itself. The livery assert trapped on launch with
`livery(AT7) should be at1, got at2`, and the fixture was right:

> The reference computes `h = (h * 16777619) >>> 0` in JavaScript, where `h` is a float64.
> The product reaches ~7.2 × 10¹⁶ — past 2⁵³, where doubles stop being able to hold
> consecutive integers — so the low bits are rounded away *before* `>>> 0` truncates. Its
> `^` is `ToInt32` as well, so `h` goes negative mid-loop. It is not FNV-1a; it is
> FNV-1a-shaped.

Exact 32-bit wrapping arithmetic — the textbook-correct port — gives a different answer for
every seed but the empty string. The same trap sits in `barcode`, whose LCG multiply reaches
~2.4 × 10¹⁸. Both are now ported as `Double` arithmetic and verified seed-for-seed and
bar-for-bar against node. A sweep of the remaining reference arithmetic found no third site;
`MockData`'s mulberry32 uses `Math.imul`, so exact wrapping is correct there and `Double`
would be wrong.

This is the class of bug the self-checks exist for: silent, invisible in every screenshot,
and it would have repainted the livery and reprinted the barcode of every pass ever issued —
the one thing the pass archive promises never happens.

## Deliberate divergences

Ten, each because the reference contradicts itself or would ship something broken. They are
tabulated in CLAUDE.md under *Where we deliberately do NOT match*. The two worth repeating:
the reference **discards the airport picked in onboarding** (it writes `window.HOME`, then the
next render overwrites it from unchanged state, so every member starts in Sydney whatever they
picked), and its Concourse search field is drawn but wired to nothing.

## Known gaps, carried forward

- The reference's onboarding cover pass quotes **120 mi for a 50-minute flight** — an economy
  of 2.4 mi/min earned against the app's real 0.25. Reproduced verbatim; it needs a design
  decision, not a code fix.
- **FocusGuard, blocking schedules and hardcore mode do not exist in this reference**, so they
  are not in the port. They existed in the previous Swift app.
- `TempusMonitor` blankets `.all()` because `SharedStore` carries no `FamilyActivitySelection`
  tokens. SETUP.md covers what turning real blocking on requires.
