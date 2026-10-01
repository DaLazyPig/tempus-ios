# Tempus

Tempus is a **native iOS app** (SwiftUI, App Store-bound) built around one loop: **you
study to earn Miles, and you spend Miles to unlock the apps that Tempus blocks**
(Instagram, TikTok, …). The whole interface speaks an air-travel metaphor: a study
session is a *flight* to a real destination (longer study = further from home), starting
a session issues a *boarding pass* you tear to depart, quitting early is a *diversion*
(you earn nothing), and your history is a *flight log*. Economy: **earn 0.25 Miles per
studied minute, spend 1 Mile per unlocked minute** (both configurable, `AppModel.rate/spend`)
— so one mile is one minute of screen time, and four studied minutes buy one back.

**The map moves with you.** `Geography` holds 65 real airports and measures great-circle
distance from wherever home currently is: study minutes buy block minutes (`scale = 6`),
those become kilometres at a 875 km/h cruise plus 30 minutes of overhead, and the closest
real airport is the destination. **Landing there makes it your new home**, so every future
route is measured from the city you last flew to.

**Every flight is operated by aeroTempus, and keeps its pass.** There is one carrier and
**six house liveries** (`at1`–`at6`), each built from a stadium-ring mark: a stroked rounded
rectangle plus one even-odd path that punches a four-point star through it. Which livery a
flight flies is drawn from its own flight code by an FNV-1a-shaped hash (see the warning under
Commands — it is deliberately not real FNV-1a), so a pass keeps its livery for good and the
archive re-derives the same one on every read. The livery and the pass header are
*frozen into the flight record at landing* — the pass archive is a stack of documents, not a
live query.

**Hours in the air buy status, miles buy screen time, and the two never mix.** `Status`
runs fixed 90-day periods anchored on the day you joined: what you fly in one period sets
the tier you *carry* into the next, so a tier is earned once and then has to be earned
again. Five tiers (Essential / Signature / Premier / Prestige / **Founders**) raise the earn
multiplier; economy tops out at Signature and always earns ×1.0. Founders is by invitation —
10,000 lifetime hours and the paid plan — and cannot be reached through the hours gate.
Diverted flights pay miles and qualify for nothing.

**Business class is per-flight, and it locks the cabin.** Armed at preflight through a
consent gate, the only way out is the emergency exit: a ten-second hold, a second gate, and a
bill of no miles, −15 mi and −2 qualifying hours. Economy's exit is a 900 ms hold that
diverts directly. **And the cabin is strict: one lapse ends the flight.** Leaving the app once, or
moving the phone once, diverts immediately — no chances, no strike counter, no settle window, and
`divert()` forces the payout to zero for a business flight whatever "Leaving early" is set to,
because partial credit on a rule the member opted into at preflight would make the strict cabin
the cheaper way to fly. Economy keeps its two chances and its settle overlay.

**Spending is a tab.** *Fly* and *Club* are the two docked in the floating nav; the Redeem
dial always spans 5–300 minutes at whatever the spend rate is, and the only rule is that you
can afford it. An unlock in progress is a banner rather than a wall — the dial stays live so
time can be added, or moved to another app after being told what that costs. A shield can also
send you there (`tempus://withdraw` from its notification), but that only names the app — it
does not change the price. See SETUP.md for turning real blocking on.

**The Concourse is a shop, and the shop is open.** Miles buy **191 card faces, 60 pass headers
and 18 gift faces**,
which ship as data (`Tempus/Resources/shop.json`) and are drawn by a markup renderer rather
than hand-built views. Faces are authored on a 340 × 214 card box, headers on the 268 × 90
band. Concourse stock is granted outright — no timer, nothing to open — and a free item leaves
no line on the statement, because the statement records movements of miles.

## Repository layout

```
Tempus.xcodeproj        ← THE PRODUCT: open in Xcode, build & run (iPhone, iOS 17+)
Tempus/                 SwiftUI sources (filesystem-synchronized — files added here
│                       appear in Xcode automatically; no pbxproj editing needed)
├─ TempusApp.swift      @main entry, deep links, foreground hook
├─ RootView.swift       Phase router + the two-layer transition engine
├─ Theme/               Design tokens: Colors (TColor), Typography (TFont/TCardFont),
│                       Layout (TSpace/TRadius), Motion (TDur/TEase/Animation.glide),
│                       Shadows (TShadow)
├─ Models/              AppModel (the state machine), Models (tasks/records/orders),
│                       Geography (65 airports, great-circle routing, moving home),
│                       Carriers (aeroTempus, six liveries, barcode, route),
│                       Status (five tiers, 90-day periods, the qualifying-hours ledger),
│                       MockData (the seeded 12-week history), FocusGuard (cabin
│                       discipline — the accelerometer, the chances, the settle),
│                       LaunchSeams, SelfChecks
├─ Shared/              SharedStore — the App Group surface the extensions share. Compiled
│                       into all four targets, so keep it dependency-free.
│                       FlightActivityAttributes — shared with the widget target only.
├─ DesignSystem/        Buttons, Surfaces, Controls, Dial, Chrome, HoldControls, Reveal,
│                       Transitions (the morph and the circle reveal),
│                       Markup/ (the Concourse renderer — see below)
├─ Screens/             Onboarding, Home, Sheets, Flight, BoardingPass, Redeem, Paywall,
│                       PaySheet, Status, CardDesign, CardArt, Concourse, ShopItem, Gift,
│                       Linked, Passes, Analytics, Settings, Gate
├─ Resources/shop.json  The Concourse stock: 191 faces, 60 headers, 18 gifts
├─ Fonts/               Outfit + DM Mono, and the five tier typefaces (Big Shoulders
│                       Display, Cormorant Garamond, Bodoni Moda, Syne, Italiana) —
│                       FONTS.md lists every file with its exact PostScript name
├─ AppIcon.icon         The app icon, as an Icon Composer document: the house mark
│                       (CarrierMarkShape) on white. actool emits the iOS 26 layered
│                       light/dark/tinted renders and the flat iOS 17 fallback from it,
│                       so there is no AppIcon.appiconset any more.
└─ Assets.xcassets      AccentColor, LaunchBackground

TempusMonitor/          DeviceActivity monitor — re-raises the shield when an unlock expires.
TempusShield/           The shield UI (ShieldConfiguration).
TempusShieldAction/     Its buttons (ShieldAction) — writes the unlock request.
TempusActivity/         The flight's Live Activity: Dynamic Island + lock-screen banner.
TempusReport/           The flight log's screen-time feed: a DeviceActivityReport extension
                        that measures per-app usage and draws the two cards that show it.
                        All five are real targets, built as dependencies of the app and
                        embedded in it — so `xcodebuild -scheme Tempus` compiles them and a
                        break in one fails the build. Each takes its own folder as a
                        synchronized group and reaches into `Tempus/` for the one or two
                        files it shares; SETUP.md §3 has the table.

source_of_truth.html    THE REFERENCE BUILD — a self-extracting bundle of the React
                        app (open it in a browser). This is the source of truth for every
                        screen, number, string and timing. Unpack it with the snippet below.
prototype/              The original web prototype, superseded. Historical only.
reference/original/     Extracted sources of the first artifact. Historical only.
DESIGN.md               THE BINDING DESIGN CONTRACT — read before any UI work.
AGENTS.md               The hand-off for Codex (and any agent without this file's context):
                        how to build, drive the simulator, tap, record and read frames.
SETUP.md                Turning on real blocking: entitlement, targets, App Group.
report.md               How this project was built.
```

## Commands

```bash
open Tempus.xcodeproj                                   # develop in Xcode
xcodebuild -project Tempus.xcodeproj -scheme Tempus \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build   # CI-style check

# The four extensions build with the app, so the line above covers them too. To build one on
# its own (a faster loop when only an extension changed) — `-sdk iphonesimulator` is required,
# because `-target` without a scheme defaults to the device SDK and then wants a provisioning
# profile for that extension's bundle id:
xcodebuild -project Tempus.xcodeproj -target TempusMonitor -sdk iphonesimulator build

# Unpack source_of_truth.html (gzip+base64 manifest) to read the reference sources.
# The manifest keys are UUIDs, not names — identify the files by size and first line.
python3 -c "
import re,json,base64,gzip,pathlib
h=open('source_of_truth.html',encoding='utf-8').read()
m=json.loads(re.search(r'<script type=\"__bundler/manifest\">(.*?)</script>',h,re.S).group(1))
out=pathlib.Path('/tmp/tempus-ref'); out.mkdir(exist_ok=True)
for k,v in m.items():
    d=base64.b64decode(v['data'])
    if v.get('compressed'): d=gzip.decompress(d)
    (out/k).write_bytes(d)
print(out)"   # app.jsx is the 365 KB file; also shop (1.6 MB), carrier, geo, data, design-system
```

**Read the reference by executing it, not only by reading it.** `carrier.js` is written in
layers and its last two override everything above them — reading the file top-down tells you
there are 200 carriers and 72 band patterns, and running it tells you there is one carrier and
six liveries. `node` is available; shim `global.window = global` and require the file.

No test suite. The check is a clean build, the debug self-checks, and walking the flows in
the simulator (onboarding → deck → preflight → tear the pass → fly → land → redeem →
concourse → status → passes → log → settings).

**Self-checks run on every debug launch** (`runSelfChecks()` from `TempusApp`). They assert the
logic that is easy to get subtly wrong and impossible to eyeball: the great-circle routing
(including the one property the whole metaphor rests on — a longer flight never lands nearer),
the livery hash, the barcode's LCG, the 90-day period carry-over (a tier that is not re-flown
is lost, not kept), the redeem arithmetic, the seeded history's PRNG, Status Club's header band
(every tier, every variant and all 191 shop faces have to carry white ink), and the focus guard's
strike/settle machine (driven with synthetic samples, so it is the same on a phone and in the
simulator). **The expected values
were produced by executing the reference JavaScript under node**, so they are a real cross-check
rather than a restatement of this port's own behaviour. A failing assert traps the app on
launch — if it dies immediately in DEBUG, read the assert message before anything else.

**Two of the reference's hashes are arithmetically "wrong", and both must be kept wrong.**
`Carriers.livery(seed:)` looks like FNV-1a and `Carriers.barcode(seed:)` looks like a textbook
LCG, but each multiplies in JavaScript's float64: the products reach ~7.2 × 10¹⁶ and
~2.4 × 10¹⁸, past the 2⁵³ mark where doubles can no longer hold consecutive integers, so the low
bits round away before `>>> 0` / `& 0x7fffffff` truncates. (`livery`'s `^` is also `ToInt32`, so
`h` goes negative mid-loop.) Both are therefore ported as `Double` arithmetic, not `&*` wrapping.
Rewriting either into its correct textbook form changes the answer for **every** seed but the
empty string — which would repaint the livery and reprint the barcode of every pass ever issued,
the one thing the archive promises never happens. `carriersSelfCheck` pins ten livery seeds and a
full 26-bar stamp against node output; if it trips, the hash was "fixed", not broken.
`MockData`'s mulberry32 is the opposite case — the reference uses `Math.imul` there, so exact
32-bit wrapping is correct and `Double` would be wrong.

**Launch seams** for driving screens without synthetic taps (the simulator takes none):

```bash
xcrun simctl launch booted com.crescerestudios.tempus -tempusPhase concourse
xcrun simctl launch booted com.crescerestudios.tempus -tempusPhase redeem -tempusMiles 400
xcrun simctl launch booted com.crescerestudios.tempus -tempusStep 4                 # onboarding 0–10
xcrun simctl launch booted com.crescerestudios.tempus -tempusStep 0 -tempusAdvance  # + mid-crossing
xcrun simctl launch booted com.crescerestudios.tempus -tempusPhase status -tempusTier 2   # 0–4
xcrun simctl launch booted com.crescerestudios.tempus -tempusPhase passes -tempusPasses 14
xcrun simctl launch booted com.crescerestudios.tempus -tempusPhase home -tempusPasses 12 -tempusGoal 8
xcrun simctl launch booted com.crescerestudios.tempus -tempusPhase pass -tempusHeader H01
                                           # owns that header and stamps it onto the pass being
                                           # issued — `board()` otherwise picks one at random, so
                                           # this is the only way to check a bought band's width
xcrun simctl launch booted com.crescerestudios.tempus -tempusShopItem H01   # a header's item screen
xcrun simctl launch booted com.crescerestudios.tempus -tempusShopItem 1.02  # a face's
xcrun simctl launch booted com.crescerestudios.tempus -tempusPhase tierup           # the celebration
xcrun simctl launch booted com.crescerestudios.tempus -tempusPhase exited           # the exit bill
xcrun simctl launch booted com.crescerestudios.tempus -tempusPhase flying -tempusMinutes 1 -tempusBiz
xcrun simctl launch booted com.crescerestudios.tempus -tempusPhase home -tempusSheet
xcrun simctl launch booted com.crescerestudios.tempus -tempusPhase home -tempusMorph  # the card morph
xcrun simctl launch booted com.crescerestudios.tempus -tempusPhase home -tempusMorphClose  # …and its close
xcrun simctl launch booted com.crescerestudios.tempus -tempusPhase home -tempusMorphDrag 120
                                           # shoves the top card 120pt sideways and *then* opens the
                                           # morph from the card's own measured rect — the only seam
                                           # that exercises the measurement (`-tempusMorph` passes a
                                           # literal). A clean rect grows from the card's resting
                                           # frame; a leaking one grows from where the card was shoved.
xcrun simctl launch booted com.crescerestudios.tempus -tempusPhase linked -tempusLinked -tempusLinkBack
                                           # the Linked → Club return, unattended
xcrun simctl launch booted com.crescerestudios.tempus -tempusAtRisk -tempusPhase status
xcrun simctl launch booted com.crescerestudios.tempus -tempusPhase settings -tempusDev  # developer mode
xcrun simctl launch booted com.crescerestudios.tempus -tempusPhase carddesign -tempusPlus \
  -tempusCardClose 2                       # saves face 2 and plays the studio's exit, unattended
xcrun simctl launch booted com.crescerestudios.tempus -tempusPhase status -tempusCardOpen
                                           # Customise, once Status Club has settled — the only way
                                           # to see the studio's entrance *uncover* the club, since
                                           # launching into `carddesign` has nothing behind it
xcrun simctl launch booted com.crescerestudios.tempus -tempusPhase status -tempusFace 1.01 \
                                           # owns shop face 1.01 outright and wears it: the grey band
xcrun simctl launch booted com.crescerestudios.tempus -tempusPhase redeem -tempusMiles 400 \
  -tempusLimit 60 -tempusSpent 60          # a refusal the balance is not the reason for
xcrun simctl launch booted com.crescerestudios.tempus -tempusStep 2 -tempusAdvance \
  -tempusCross white                       # a crossing variant, for comparing two takes
xcrun simctl launch booted com.crescerestudios.tempus -tempusPhase status -tempusPaywallClose \
                                           # opens the paywall once settled and closes it 1.5 s later
xcrun simctl launch booted com.crescerestudios.tempus -tempusPhase status -tempusPerm \
                                           # Club ▸ Redeem's `perm` dome, and back, unattended
xcrun simctl launch booted com.crescerestudios.tempus -tempusPhase settings -tempusCircle \
                                           # Settings' close: the circle reveal from the X's *measured*
                                           # rect, so a leaking measurement shows on the recording
```

`-tempusMinutes N` sets the flight length, so a landing — and everything it writes: the
miles, the hours ledger, a tier-up, the pass — is walkable in a minute rather than fifty.
**`-tempusTier` writes the *hours ledger*, never the tier itself**, so the screens are always
testing a state the app can actually reach. Keep that rule when adding seams.

**Onboarding is keyed by screen, never by page number.** `OBScreen` (cover, earn, spend, gate,
apps, cap, home, account, club, shop, business) is the one table: the crossings switch on it, durations
and dark grounds are keyed by it, every Next button targets `OBScreen.x.i`, and the views are
`OBGateScreen`/`OBCapScreen`/… rather than `OBScreen3`/`OBScreen5`. Each crossing case binds
`from`/`to` from the pair it is given, so a case physically cannot reach another screen's layer.
`OBStyles`'s layer and content arrays size themselves from `OBScreen.allCases.count` rather than
from a literal, because a screen added to the enum without also editing a `count: 10` is an index
crash on the first crossing. The sequence has been reordered once — the Screen Time gate moved from after the app list to
before it — and a reorder chased through numeric literals is how a crossing ends up playing on the
wrong pair. **Reorder by moving a case in `OBScreen`**, which moves the screen, its crossing and
its ground together. `-tempusCross <name>` selects a crossing variant while two takes are being
compared; a variant that loses is deleted, not kept behind the flag.

**Screens that mutate their own state from callbacks need a reference type.** Onboarding's
state is an `@Observable` object (`OnboardingFlow`), not `@State`, because every mutation
happens from an escaping closure — a drag callback, a scheduled commit — and those capture a
*copy* of the `View` struct. Writes through such a copy reach `@State`'s storage but do not
reliably invalidate the live view: reading the value back shows the new one while `body` is
never re-evaluated. That is how a tear gesture came to move nothing at all.

## Architecture notes (read before editing)

- **`AppModel` is the single source of truth** — an `@Observable` class injected via
  `.environment(...)`. A `Phase` enum, one `go(_:_:dir:)` that is the only thing allowed to
  change it, and a flight lifecycle driven by a **wall-clock deadline** (never accumulated
  ticks — it must not drift when backgrounded).
- **Every screen is a no-argument `View` that reads the model from the environment.** The one
  exception is `CardDesignScreen(exiting:)`, which the router renders twice. If a screen needs
  a value, it is on the model — do not add init parameters.
- **`save()` coalesces; `saveNow()` does not.** `save()` is called from nearly every `didSet` in
  `AppModel`, and `Stored` carries 200 flights, the ledger, the statement and the owned catalogue —
  `JSONEncoder` walks all of it on the main thread and `syncSharedStore()` follows with a second
  encode. A dial drag used to pay that many times a second, and `goDirect` pays it on the exact
  frame a set-piece begins. Tens of milliseconds of encoding inside a 220 ms cross-fade is dropped
  frames, and a cross-fade that drops its opening frames does not read as slow — it reads as a
  **flicker**. So `save()` now queues one encode per runloop turn. `saveNow()` is the synchronous
  one, for backgrounding and for anything that reads the store straight back (the self-checks do).
- **Persistence** is one JSON blob in `UserDefaults` under `tempus.app.v2`.
  Add fields to `AppModel.Stored` — everything optional so old blobs keep decoding. Unlike the
  reference, **a flight in the air is persisted** (`endsAt`, `minutes`, `destination`, the
  livery, the header, `biz`), because a phone can be killed mid-flight and the deadline is
  wall-clock.
- **`opacity` groups in CSS and does not in SwiftUI.** A CSS `opacity` on a parent establishes a
  stacking context: the subtree is composited once and *then* faded. SwiftUI's `.opacity` pushes
  down to every leaf and fades each one separately — so a surface with anything stacked inside it
  (a page fill under a header band, a screen's ground under its content) stops hiding what it is
  painted over, and the layer underneath bleeds up through the middle of the fade. It is not a
  timing bug and no amount of re-ordering state fixes it; it peaks at half-faded and disappears at
  both ends, which is exactly what makes it read as a flicker. **Anything porting a CSS `opacity`
  transition needs `.compositingGroup()` before the `.opacity`** — `CardDesignScreen`'s exit and
  `OBFade` in the onboarding stack both carry one. The group costs an offscreen pass, so where many
  layers are mounted at once take it only while that layer is actually part-way transparent.
  `.shadow` has the same shape of problem and the same answer (see `OBLayerShape`).
- **A bottom-pinned pill rides the keyboard, and only one thing may lift it.** `AddSheet`'s subject
  field is the construction (Status Club's Founders invite was the other, until the "Gift a
  Prestige card" privilege was cut on 18 Sep 2026): a `ZStack(alignment: .bottom)`
  over a scrim, with the pill padded up by `KeyboardTracker`. SwiftUI *also* applies a keyboard
  inset of its own to those stacks — not the full keyboard, just enough that the two mechanisms
  together parked the pill a couple of hundred points above the keyboard, in the middle of the
  screen. The stack therefore carries `.ignoresSafeArea(.keyboard, edges: .bottom)`, which makes the
  manual lift the only one. And the lift is `keyboard.lift`, **not** `keyboard.height`: `height` is
  the overlap with the screen, while the stack is laid out inside the safe area and so already sits
  `TSafeArea.insets.bottom` up — padding by the full height lands the pill exactly that inset too
  high, reserving room for a home indicator the keyboard is covering. `KeyboardTracker` also
  animates on the keyboard's **own** curve (raw 7 → `.linear`), because `easeInOut`'s slow start
  falls behind precisely where the keyboard moves fastest and the pill visibly trails it.
- **A bottom-pinned pill never waits for the keyboard.** `AddSheet` used to hide its pill until
  `KeyboardTracker` reported a frame and then fade it across the keyboard's rise — so on a phone,
  where the keyboard takes its time to arrive, the sequence read as keyboard first, pill second.
  The reference pins the pill at a fixed `bottom:262` and plays `tp-pillin` (420 ms, 60 ms after
  mount) while the drawn keyboard rises to meet it. The port now does the same: the scrim and the
  pill play their own entrances from mount, and only the *lift* is the keyboard's, seeded from the
  last lift a keyboard produced (persisted) so the pill is drawn where the keyboard is about to put
  it before the keyboard says so. **`KeyboardTracker.lift` is stored, not derived**: deriving it in
  `body` read `TSafeArea.insets`, and the moment a pill mounted already lifted that read logged
  `AttributeGraph: cycle detected` and killed the router.
- **The first keyboard of a process is paid for at launch.** UIKit loads its keyboard bundle
  lazily on the main thread, stalling every SwiftUI animation for several hundred milliseconds
  (~700 ms in the simulator, and visible on a phone too). In `AddSheet` that read as scrim first,
  pill and keyboard second — the focus request landed after the scrim had begun to fade in.
  `ScreenWarm` now calls `KeyboardWarm.run()` in idle time after warming the sheet's types, paying
  the load by becoming and resigning first responder in one turn without showing a keyboard.
  The reference timings in `AddSheet` were never the problem and stay exactly as they were.
- **`ScreenWarm` needs every environment object the app injects.** It builds each screen through
  `ImageRenderer`, and an `@Environment` object a warmed screen asks for and does not get is a
  **trap**, not a blank render. `Backend` was added to `SettingsScreen` without being added to
  `ScreenWarm.render`, and the result was a launch crash — 2.4 s after any launch that settles on a
  screen other than onboarding, which is late enough that it reads as the app closing itself rather
  than as a crash on open. Adding an `@Environment` object to any screen means adding it to
  `RootView`'s own declarations and to both `render` and `warmAddSheet`.
- **Do not read `TSafeArea.insets` from inside a `GeometryReader` that positions something.**
  `TSpace.topInset` is the right correction for a screen laid out inside the safe area, and the
  Concourse and the linked-account page both take it — but `ShopItemScreen` positions its hero with
  `GeometryReader` + `.position` off the same number, and reading the key window there made that
  geometry unstable enough that the screen's entrance never ran at all: the card sat frozen at its
  shelf-tile rect and the panel never arrived. That screen keeps a literal (`chromeTop`) and says
  why.
- **And never read it in a `body` at all — `AttributeGraph: cycle detected` is how the router
  dies.** `TSafeArea.insets` is a live `keyWindow.safeAreaInsets` call. Reading it *inside a
  `Shape`'s `path(in:)`* is fine: that runs at draw time, outside body's dependency tracking.
  Reading it in a `body`, to pass the value in as a view value, makes the window's own layout an
  **input** to the body of the view that window is laying out — and SwiftUI answers by logging
  `AttributeGraph: cycle detected` once, on the first render, and wedging that part of the graph
  for the life of the process. The symptom is not a warped clip. It is a **dead app**:
  `RootView`'s `ForEach(layers, id: \.phase)` never builds a row for a new phase again, so Fly,
  Club and every header button change `phase` — the tab highlight even moves — while the old
  screen stays on screen for good. `StageClip` therefore takes a `bleeds: Bool` and does the
  window read in `path(in:)`; it took the insets as a parameter for exactly one build (17), and
  that build shipped with no working navigation. **If pages stop responding, read the console for
  that one line before touching anything else** — the cycle is logged at launch, long before the
  first tap that appears to fail.
- **CSS constructs that do not survive the port, and what to write instead.** The shadow-spread
  fold above is one of these; it was found the expensive way, so the rest are written down here
  rather than rediscovered. In every case the CSS reads as if it would work and the SwiftUI
  equivalent quietly does something else:
  - **`opacity` on a parent** composites the subtree once in CSS and fades every leaf separately in
    SwiftUI → `.compositingGroup()` before `.opacity`.
  - **`box-shadow`'s negative spread** insets the caster before blurring; SwiftUI has no spread →
    `TShadow.ShadowLayer.css(...)`, never a narrowed blur.
  - **`overflow: hidden` vs `.clipShape`** — a CSS clip moves with its element's transform; a
    SwiftUI clip applied after `.offset`/`.scaleEffect` does not, because those leave the layout
    frame behind → clip first, transform after.
  - **`transform-origin` in pixels** (`175px 49px`) has no SwiftUI equivalent → a fractional
    `UnitPoint` against the element's own size; the anchor is always 0–1.
  - **One CSS rule can give two properties different durations and delays** (opacity 420 ms,
    transform 520 ms). A single `.animation(_:value:)` couples every animatable modifier chained
    before it to one curve → split the chain with an intermediate `.animation()` per property.
  - **A CSS `transition-delay` sequences two stages; `.animation(_:value:).delay()` is not a
    reliable way to do the same.** The card studio's exit faded its contents and then its own
    sheet, expressed as `.animation(.glide(0.22).delay(0.3), value: on)` with both stages reading
    one `on`. The delayed animation never ran: the sheet held full opacity for the whole window and
    then disappeared in two frames when the layer was unmounted — a cut wearing the source code of
    a fade, which is why it survived several passes of *reading* the file. Sequence a second stage
    from its **own** state flag, flipped inside an explicit `withAnimation(.glide(d).delay(t))` —
    a delayed *transaction* runs on the animation clock; a delayed `.animation(_:value:)` modifier
    reading the same flag as the first stage does not. `CardDesignScreen`'s `groundOut` is that
    pattern (it was `Task.sleep`-sequenced for a while, which ran late under the encode). **And check an animation by recording it**
    (`simctl io recordVideo` + `ffmpeg -vf fps=30`, then read the pixels): a cut and a fade are one
    line apart in the source and unmistakable on the timeline.
  - **A view sized far larger than the container it is positioned in is not placed where you put
    it, and a path drawn far outside its own bounds is not drawn at all.** Onboarding's `apps -> cap`
    crossing grows the Next button into the page by lerping three edge insets to −300, so the rect it
    wants ends up half again the height of the screen. As a `.frame(w,h).position(x,y)` inside the
    stage's `ZStack` it drew *reflected about the middle of the screen* — a pill the numbers put at
    y 666…875, sitting on the button, painted at 0…208. Rewritten as a `Shape` it drew correctly
    until the box outgrew the bounds, and then vanished for ten frames and came back as a frozen
    190 pt band. Both were measured on frames, and either one is the "flicker" on that crossing.
    `OBExpandPill` is the answer: a shape, so nothing can be resized, and its path trimmed to the
    rect with one boolean op, which removes only geometry that was off-screen anyway.
  - **A multi-stop gradient with an opaque run before the fade** (`color 62%, transparent`) needs
    `LinearGradient(stops:)` with explicit `location:`s; the `colors:` convenience spaces stops
    evenly and starts fading immediately.
  - **A background's `ignoresSafeArea()` is granted at rest and withheld mid-transition.** The
    phase layers are laid out inside the safe area and `StageClip` bleeds their *clip* to the
    screen edge, but a ground declared as `.background(color.ignoresSafeArea())` stopped at the
    layout rect for exactly as long as the stack held a second layer — so `perm`'s dome, a 201pt
    semicircle, arrived with its top 62pt unpainted: a slab with shoulders, cut flat at the
    status-bar line, on every Club ▸ Redeem. `PhaseLayer` paints its ground through the same
    bled `StageClip` shape instead; a shape reads the insets at draw time and paints wherever its
    path goes. Measured on frames, not read: the profile of the corner fit a 201pt circle whose
    apex sat 62pt above the painted edge, which is how the missing paint was told apart from a
    wrong radius.
  - **An animated `.mask`'s target size is not free.** A resting mask can be generously oversized;
    an animated one cannot, because `.animation` interpolates the geometry linearly through the
    curve. Sizing the target far past the real content (the pass header's print was 1000 against
    ~190 pt of body) spends most of the duration moving an invisible edge through empty space, and
    the reveal reads as a pop rather than a growth.
- **A short window is a scaled stage, and every iPad is a short window.** This app is iPhone-only,
  and iPadOS runs it in a **375 × 667** compatibility window — the iPhone SE's size, which the
  layouts were never drawn for. App Review rejected build 43 under Guideline 4 on an iPad Air 11"
  (M3): onboarding's Next buttons, the Business Class legal links and the flight's dial ran off the
  bottom. `StageRoot` (RootView) lays the app out on a canvas `TStage.designHeight` (844) tall and
  scales it to the window, so a short window shows the same screen, smaller. **The hosted app gets
  no safe area at all** — a nested `UIHostingController` with `safeAreaRegions = []`, scaled by a
  UIKit transform. The iPad window really has 20/25pt insets; build 46 hid them behind a
  `GeometryReader` and they leaked back mid-transition, so every Fly → Club on iPad drew Status Club
  a status bar low for ~60 ms and snapped it up. Measured, bisected, and gone with the insets. **On a phone at least
  844 tall it is not applied at all** — the 17 Pro and 16 Plus run the exact code they always did.
  Inside the canvas UIKit speaks window points and SwiftUI stage points, so **never read
  `UIScreen.main.bounds` or `.global` directly any more**: `TStage.bounds`, `TStage.space` and
  `TSafeArea.insets` (already divided) are identity on a tall phone and correct on a short one; a
  UIKit frame goes through `TStage.points`. The canvas ignores the keyboard's safe area, so a field
  low on a short screen gets no automatic lift — `KeyboardTracker` is the one lift that is drawn.
  **Verify on the iPad simulator**, not only the phones: an iPad Air 11-inch (M3) simulator shows
  exactly what the reviewer sees, and launch seams drive it with no taps (crop the centred
  375 × 667 window out of the 1640 × 2360 screenshot).
- **Measure a rect for a set-piece *outside* the transforms that move it.** `.offset`,
  `.scaleEffect` and `.rotationEffect` leave the layout frame alone but do carry a descendant
  `GeometryReader`'s `.global` frame with them. `HomeScreen`'s `.measureRect` sat inside the deck
  card's own pose for a long time, so the drag baked into the rect the morph was handed and the
  copper rect grew from off to one side — visible after any swipe, because a tap landing inside
  the 300 ms settle read a mid-animation pose. The measure now goes **last** in `cardView`'s
  chain, outside pose and entrance both. Measured with `-tempusMorphDrag 120`: card at rest 24pt
  from the left edge, dragged 148, morph's first frame 26.
- **The card studio travels to the club's measured card, never to a literal.** `CardDesignScreen`'s
  deck used to start and end 89pt above its own centre — the reference's number, tuned inside a
  390 × 844 drawing. Measured on frames (22 Sep 2026): the club's card top sits at 130 on a 17 Pro
  *and* on a 16 Plus, while the literal put the studio's card at 126 and 117 respectively, so the
  exit's cross-fade overlaid two cards 4–13pt apart and the club's snapped into place as the copy
  was dropped — the "subtle flicker" on every return from Customise, worse the bigger the phone.
  Status Club now measures its card into `AppModel.statusCardBox` (outside the riser's offset) and
  `start` aims at it; the 89 survives only as the fallback for a launch that arrives with nothing
  measured. `-tempusPhase status -tempusCardOpen -tempusCardClose 2` records the open *and* the
  close in one run; trace the card's top edge through the frames and it must land on the club's.
- **A layer's ground always bleeds; only its *clip* cares whether it should.** `StageClip`'s
  `bleeds` exists for corner geometry that has to land on the real screen edge — bleed a `perm`
  dome twice and its tip goes off the top. A flat fill has no such geometry, so over-painting past
  the window is free and under-painting is a pale band across the status bar. `PhaseLayer` used to
  pass `bleeds: !phase.fullBleed` to the ground too, which is right only while the layer's own
  `ignoresSafeArea` is actually in force — and it is withheld for one pass whenever the outer
  stack gains or loses a full-bleed sibling. **Closing the paywall over Status Club flashed white
  across the top for exactly two frames at 30fps** because of it, and the Back/Customise row
  dropped 62pt on those same frames. The ground now always bleeds.
- **Design tokens only.** No raw hex, no magic spacing. DESIGN.md governs.
- **Motion**: `Animation.glide` (cubic-bezier .22,.61,.36,1) for everything. No springs,
  no bounce. Press feedback scales to `TPress.scale` over `TDur.fast`.
- **A clip goes under the transforms, never over them.** `.offset` and `.scaleEffect` move what is
  drawn and leave the layout frame where it was, so a `.clipShape` applied *after* them clips
  against the view's resting rect — a stationary window the moving content slides through. That is
  why `perm` read as a slab and `drip` as a squashed slab for so long: the 240pt rounded tip was
  being drawn at the top of the screen, over nothing, while the sheet itself rose with a hard
  square edge. `PhaseLayer` clips first and transforms after, and `StageClip` takes its bleed as a
  parameter so a full-bleed phase (whose layout rect is already the screen) is not bled twice.
- **A full-screen `.opacity` needs a `.compositingGroup()` under it.** `zoom`, `sink` and `lift`
  cross-fade whole screens, and SwiftUI fades every leaf separately instead of compositing the
  subtree once — so a page fill under a header band bleeds up through the middle of the fade. It
  peaks at half-faded and is gone at both ends, which is what reads as a flicker rather than a cut.
  `PhaseLayer` carries the group; so do `CardDesignScreen`'s exit and `OBFade`.
- **Transitions come in three layers.** (1) The router's cuts — `TransitionType`, which carries
  both a teardown length and separate in/out animation lengths, because in the reference they
  differ. (2) `Rise`/`ORise` — the staggered entrance every screen plays on arrival.
  (3) `DesignSystem/Transitions.swift` — the two set-pieces the router cannot express, because
  they own their own clock and swap the phase underneath themselves: the copper card ⇄
  preflight **morph** and the Home ⇄ Settings **circle reveal**.
- **A screen's first build is expensive, so it is paid for before it is asked for.**
  Swift instantiates the runtime metadata for a screen's whole nested generic view type the first
  time that screen is built — 108 ms for Preflight, ~300 ms for Home, against 10–17 ms for every
  visit after. That bill is why a first visit used to show bare ground and then land its content
  all at once, and the reference has no equivalent because JavaScript has no metadata to
  instantiate. `ScreenWarm` (RootView) builds each screen once through `ImageRenderer` in idle
  time after launch — no hosting, so no `onAppear` and no `.task`: it warms types, it does not run
  screens. **A new screen belongs in its `order` list**, and anything that owns the frame budget
  belongs in `settled`.
- **Screen-time work is live, and `Blocking` is the only thing that makes it so.** Blocking is
  a `FamilyActivitySelection` plus at most one unlock running to a wall-clock deadline; there
  are no schedules and no hardcore mode. `Blocking` is compiled into **both** the app and
  `TempusMonitor`, and both decide from `SharedStore.shouldShield` — a pure function pinned row
  by row by `blockingSelfCheck`, because the two processes answer it hours apart and a
  disagreement is a member staring at a shield the app thinks is down. The app writes the shield
  whenever state changes (a `ManagedSettingsStore` write outlives the process); the one wake-up
  it schedules is an interval that *starts* at an unlock's deadline, since intervals have a
  fifteen-minute minimum and the dial sells from five.
  **Never let the UI imply blocking is live when it is not** — Settings' "Screen time is not
  connected" banner is that promise, and it is what gates the picker. Keep it honest.
- **The Status Club header is Back and Customise, and nothing else.** It carried a share
  sheet and a Concourse shortcut for a while, on the strength of a divergence-table row
  claiming the reference had a Share button with no handler. It does not have one: the
  reference's `StatusScreen` renders exactly two controls in that header, and its `onShop`
  prop is destructured and never used. The row is gone and so are both buttons. The
  Concourse still has its door — the bag in the Home header. Do not re-add either here
  without checking the reference's component body, not its rendered DOM: these are
  icon-only SVGs with no text and no `aria-label`, so searching the DOM for "share"
  returns nothing whether or not the control exists.
- **A CSS spread folds into the alpha, never into the blur.** Every shadow the reference authors
  carries a negative spread — `0 18px 34px -20px rgba(16,29,49,.5)`. Spread *insets the caster*
  before it is blurred, so most of the shadow ends up hidden behind the opaque box and only a soft
  rim escapes. SwiftUI has no spread: `.shadow` always casts from the full silhouette. This port
  used to compensate by shrinking the blur (`radius = (blur − |spread|)/2`, alpha untouched), which
  keeps the shadow the full width of the card and merely sharpens it — every surface in the app
  wore a hard band about three times too dark, and every primary button wore a copper halo. That
  one conversion error was the whole of the "unnatural shadows" report. The correct fold is
  `σ = blur/2` and `alpha' = 2 · alpha · Φ(spread/σ)`, which is what `TShadow.ShadowLayer.css`
  does; `shadowSelfCheck` pins it. **Author every new shadow through that helper**, and if a call
  site has to hand-roll one (a themed button casting in its own paint), use `cssAlpha` rather than
  eyeballing a number. The one place that does the *inset* properly instead is `OBPrimaryButton`,
  which can, because it knows its own shape.
- **A shadow falls on a ground, and has to know which one.** Every tint in `TShadow` is derived
  from navy ink and reads correctly on the light surfaces it was authored against. On a dark
  ground those same tints are *lighter* than what they fall on, so they stop being shadows and
  become halos — copper at 60% over `navy700` is the glow that ringed every Next button in
  onboarding. `tpShadow` therefore reads `\.tpDarkGround` from the environment and swaps to ink at
  a lower opacity; `OBPrimaryButton` reads the same value for its own inset halo. **A new dark
  screen sets `.tpDarkGround()` at its root**, and onboarding reads the flag out of
  `OBConst.darkScreens` rather than listing the dark screens a second time. The test is the ground
  the shadow lands on, not the element's own colour: the Analytics "At this rate" card is dark
  itself but sits on a pale page, so it stays on the light tokens.
- **The flight log is real on both halves, and the screen-time half is drawn out of process.**
  Hours, completion, the streak, Subjects and When you fly all aggregate `AppModel.flights`
  through `MockData.Real`. They used to read the seeded twelve weeks, which meant a paid screen
  told the reader that Thursday evenings were their strongest stretch on the authority of a PRNG.
  Per-app screen time and the "At this rate" projection come from `TempusReport`, a
  `DeviceActivityReport` extension: iOS gives the usage to that process and **the numbers never
  reach the app** — the two cards embed a report view at a fixed height and the extension draws
  the rows and the figure, which is why the projection arithmetic lives in `TempusReport.swift`
  rather than in the app, and why the app cannot offer a "leave this app out" toggle (a report
  view takes no touches). The simulator draws no report, so both cards are blank there.
  `MockData`'s own miles are minted by `Status.earn` at the base rate: a seeded mile and an earned
  mile have to be the same unit.
- **Status is derived, never stored.** `AppModel.status` recomputes `Status.of` on every read,
  so a rolling window can take a tier away as well as give one. Write to the ledger
  (`hourLog`), never to a tier. `Status.earn` is the one place miles are computed for a length
  of flight, so no surface can quote a number different from the one banked.
- **A pass is a document.** `logFlight` is the single writer, so a landing and a divert produce
  the same record, and it freezes the livery and the header into it. Nothing may recompute a
  past flight's livery.
- **Deleting the account deletes the data, on both sides, and `AppModel.wipeInstall` is the one
  local writer.** Settings' Delete account unlinks a shared bank (a failure there stops everything),
  calls `delete_my_account()` — a definer function in `supabase/schema.sql` that removes the backup,
  the invites and the auth user, and can only ever delete its caller — and then wipes the phone
  through the same body developer mode's "Erase this install" runs. It used to DELETE the backup row
  directly, and with no delete policy RLS matched nothing, PostgREST said 204, and the app announced a
  deletion that had not happened. **Under RLS a forbidden write is a silent no-op, not an error** —
  never infer success from a 2xx on a table without reading the policy that permits the verb.
  **Apple's grant is revoked too:** `Backend.deleteAccount` first posts `revoke` to the `apple-token`
  Edge Function (`supabase/functions/apple-token`), which holds the Apple key and the refresh token
  that `storeAppleCode` banked at sign-in; both calls are best effort, so a deletion is never refused
  for Apple being down and a sign-in never shows a revocation error. SETUP.md has the deploy steps.
- **The shared bank's invariants live in SQL, and the client only claims.** After an outside audit
  on 18 Sep 2026: `unlink_pair` writes both halves of the pot to `link_payouts` and returns 0 —
  each member collects their own through `claim_payouts()` (`AppModel.collectPayouts`, run after an
  unlink and on every refresh), so a partner's half no longer vanishes with the row and a lost
  reply is not a lost share. `accept_link_invite` takes advisory locks on both member ids before
  the one-bank-each check, so two invites accepted in the same instant cannot both succeed. And
  `earn_to_pair` takes an `op` UUID the client mints at landing and keeps in `PotCredit`: the
  ledger holds it unique, a replay answers with the balance and credits nothing, and a member can
  credit at most 3,000 mi a day. **Gifts are delivered** (schema part five, 18 Sep 2026): a
  `gifts` row addressed by email like `link_invites`, accepted by the recipient through
  `accept_gift()` (a replay returns 0 and credits nothing). Schema part six supersedes the client-only debit: personal offline changes are persisted in
  `MilesJournal`; `send_gift` reconciles and debits atomically, and `receive_gift` keeps a
  recoverable receipt. A timeout keeps the sender's reservation until a definitive settlement.
  See `supabase/OFFLINE_MILES.md` for the trust limits and deployment requirements. The Gifts chip shows when the account can carry one
  (`Backend.isConfigured && backend.isLinked`) and for every tier — there is no Founders-only
  gift any more.
- **The legal pages ship in the bundle.** `Resources/Legal/Terms.md` and `Privacy.md`, drawn by
  `LegalSheet` from Settings ▸ Legal; the hosted copies at `Billing.termsURL`/`privacyURL` are the
  same text and both must resolve before submission (SETUP.md). Every target carries a
  `PrivacyInfo.xcprivacy`; the app's collected-data list is the source of truth for the App Privacy
  answers in App Store Connect and must move with the policy.
- **`plus` has exactly two grantors and one writer.** A RevenueCat entitlement and the developer
  switch can each raise Business Class, and neither may revoke the other's grant — a store
  downgrade must not take away what the developer switch is holding open, and switching developer
  mode off must not take away a real purchase. `setPlus(_:source:)` is therefore the only writer;
  `plus` is `private(set)`. `accountSelfCheck` pins all four combinations.
- **The store and the account are configured in Info.plist, not in code.** `RevenueCatAPIKey` and
  `GIDClientID` ship as `YOUR_…` placeholders, and both `Billing.isConfigured` and
  `Identity.googleConfigured` treat a placeholder as absent — so an unconfigured build disables the
  buy button and says "the store is not connected" rather than offering one that cannot work.
  SETUP.md has what to paste where.
- **The focus guard's thresholds are calibration, not constants.** Whether a shake trips it
  depends on the phone, its case and the desk — the defaults came from a model of a resting
  iPhone, not from any real one. `FocusGuard.stillJolt`/`moveJolt` are therefore persisted and
  writable, and the developer panel reads the live accelerometer (`startTuning()`, which runs the
  same counters with `strike` unreachable) so they can be set against the real thing. The
  simulator has no accelerometer and the panel says so rather than offering numbers to tune
  against a phone that is always still. **A phone that locks itself while lying still has not been
  left**: iOS delivers no lock event distinguishable from an app switch, so `leftApp()` asks the
  accelerometer instead and only strikes when the phone was being held at the moment it
  backgrounded.
- **A linked partner has a name, and their personal balance is not yours to display.**
  `link_pairs` carries two user ids and nothing else, so a device that never saw the invite showed
  "Linked member" for the life of the link; `Backend.partnerName()` reads the name back off the
  accepted `link_invites` row, which survives acceptance and is readable by both ends.
  `AppModel.unnamedPartner` is the one string that means "still unknown", and `refreshSharedBank`
  upgrades a link wearing it. The *figures* were worse: Status Club and Linked both printed
  "<them> EARNED `link.miles`", which a server-backed pair leaves at 0 for good, under a
  "SHARED BANK" that was actually `pool` — your own balance included, which your partner cannot
  spend — so it showed the pot, what you hold, and what the two let *you* spend — and since linking merges the banks (below) the personal figures went too: **one figure, the shared bank**, on Linked and on Status Club (22 Sep 2026).
- **Linking merges the banks, at once** (22 Sep 2026). It used to merge nothing — each kept their
  balance and the pot filled from the next landing on, which left two members comparing 3,000 mi
  against 81 under a shared bank of 0 and concluding the link was broken. Each phone now deposits
  its own personal balance into the pot the first time it sees the pair live:
  `AppModel.mergePersonalMiles`, called from `acceptLinkRequest` (the accepter) and from
  `refreshSharedBank` (the sender, who learns the invite was accepted nowhere else). `pool` does
  not move — the same miles are held by the pair instead of the member — and `mergedPairs` is what
  stops a second call. The door is `deposit_to_pair` (schema **part nine**, deploy it), *not*
  `earn_to_pair`: a landing's credit is capped at 2,000 a call and 3,000 a rolling day, and a
  balance is neither. **Nothing is zeroed until the server answers**, so an undeliverable deposit
  leaves the miles where they are and `potStale` set; the member's own `link_ledger` line is the
  idempotency key, so the retry answers with the same pot rather than depositing twice.
  **The deposit is paid out of the reconciled wallet** (25 Sep 2026 audit): the first version took
  `amount` on the client's word, so any account could link with an alt and mint 1,000,000 mi into a
  spendable pot, then relink and repeat. `deposit_to_pair` now takes the journal like `send_gift`,
  refuses more than `miles_wallets.balance` and debits it in the same transaction; the client flushes
  the journal first and applies the debit with `changeConfirmedMiles`, never through `miles`.
- **The shared pot is a cache, and it is refreshed where it is read.** `AppModel.pot` only moves
  on a pull of `currentPair()`, and for a long time the four things that pulled were launch,
  foregrounding, Linked and Status Club — **none of them Home**, which is the screen that actually
  draws the figure (`MilesTicker(value: model.pool)`). So a member whose partner had just landed
  sat on Home looking at a stale total until they happened to background the app. The server was
  never wrong: `earn_to_pair` and `spend_from_pair` are atomic and idempotent and both members can
  read the pair row. Home and Redeem now each fire one `refreshSharedBank` on arrival — Redeem
  especially, because spending against a stale pot makes `unlockAllowance` refuse time the member
  actually has, which is the worst failure this feature has. Two phones still only agree as often
  as one of them opens a screen; a Realtime subscription on `link_pairs` is the upgrade path and is
  deliberately not built (a websocket and a reconnect policy for a number that is already honest
  about being unconfirmed — `potStale`).
- **One miles stream per account, and a phone that does not hold it repairs itself.**
  `reconcile_miles` allows exactly one `miles_wallets` row per account — what stops a cloned
  install importing its balance a second time — and refuses every other stream with "Restore the
  latest account backup before transferring miles." A `MilesJournal` mints a fresh wallet id on any
  install with nothing saved (a reinstall, an erased install, a second device), so that phone was
  locked out of every gift for good, holding an instruction it could not carry out: signing in
  *after* onboarding pushes this phone's state over the cloud backup, so the journal the message
  names is already gone by the time the refusal arrives. `AppModel.repairMilesWallet` asks
  `my_wallet()` (schema **part eight**, deploy it) which stream is real and adopts it — once, then
  the refusal stands. **Nothing visible moves**: `miles` is this phone's own figure and is never
  touched; what is dropped is an outbox for a stream the server has never seen. The three refusals
  are matched on their text (`BackendError.isWalletMismatch`), because PostgREST collapses every
  `check_violation` to one status, and what the member is shown is a sentence of ours, not the
  server's — the server's names an action this app does not offer.
- **Accepting a gift is a round trip, and a round trip has to be able to say no.** A gift the
  server delivered is claimed through `receive_gift`, and every way that can fail — no backend, not
  signed in, a wallet the server will not reconcile, the network down — used to leave the Requests
  row exactly as it was with nothing said, which is indistinguishable from a dead button. The claim
  is durable either way (it is queued in `pendingGiftReceipts`, persisted, and retried on the next
  foreground); what was missing was the sentence. `acceptGift` now writes `giftFailed` and Status
  Club prints it under the card. **A gift seeded locally (`-tempusRequest`) has no `remoteID` and
  still credits synchronously**, which is why `giftSelfCheck` passes whether or not a server exists.
- **A refresh of the shared pot delivers what this phone owes it first.** `refreshSharedBank` fetched
  the server's figure, wrote it over `pot` and cleared `potStale` — while a landing whose
  `earn_to_pair` could not be reached was still sitting in `pendingPotCredits`. So the member's own
  miles vanished from `pool` on the next screen that asked, and the app called the number confirmed.
  Home, Redeem, Linked and Status Club all arrive through that function and only launch and
  foregrounding flushed the queue, so the miles came back whenever the app was next backgrounded and
  not before. It now flushes first and leaves `potStale` set while anything is still owed.
- **`payOrder` is the only place miles leave the balance.** `pool = miles + link.miles` is what
  every surface *displays* — linked members hold one bank. What every affordability check *uses*
  is `unlockAllowance`: the pool, capped by whatever a daily spend limit has left of it. The two
  differ only when a limit is set, and reading `pool` where a check belongs is how a surface ends
  up offering time `payOrder` would refuse. The limit covers screen time only; Concourse stock is
  not capped, and earning never is.
- **Landing moves home, so capture the destination at touchdown.** `AppModel.land()` reads the
  origin and the destination *before* reassigning `homeAirport`; recomputing afterwards would
  name the city you are now sitting in.
- **The extensions cannot see any of this.** They run in their own processes and share only
  `SharedStore` (App Group) — plus, for the monitor, `Blocking`, so the two processes that
  raise the shield run the identical code to decide. Adding another shared file means adding
  it to that target's membership exception on the `Tempus` group, never copying it. The Live
  Activity is the exception to the App Group entirely: it gets a typed payload
  (`FlightActivityAttributes`) carrying a wall-clock `endsAt`, so it counts down on its own.
- **A Live Activity clock takes no `pauseTime`.** `Text(timerInterval:)` is the one thing the
  system animates on its own after the app is gone, and passing `pauseTime` turns it into a static
  string the island repaints only when it re-renders the activity — about every nine seconds on a
  phone, so the countdown sat still and jumped. `pauseTime: endsAt` was there to stop the count
  at zero; the closed range already does that. Measured in the simulator by fronting Safari over a
  flight and recording the island: frozen with it, ticking without. `TempusActivityWidget`'s
  `Countdown` says so above the call.
- **The OS surfaces are real, not drawn.** The reference simulates an iOS home screen, Dynamic
  Island, lock screen and blocked-app interstitial inside its phone frame. Here those are
  ActivityKit and the ManagedSettings shield, and there is no fake home screen, because iOS is
  the home screen. The custom in-app QWERTY keyboard is likewise the real keyboard.
- **The Concourse art is parsed, not hand-drawn.** `DesignSystem/Markup/` renders the shop's
  markup from the data it is authored in. It is deliberately a bounded subset of HTML/CSS/SVG —
  exactly the vocabulary `shop.json` uses — and **must not grow into a general browser engine**.
  Adding stock means adding data, not a `Shape`. The membership *card* faces are the opposite:
  those are drawn natively in `CardArt.swift`, because they are shapes and gradients, not data.
- **Fonts**: Outfit (300–800) and DM Mono for the interface; five tier typefaces for the
  membership cards, accessed only through `TCardFont`. A missing or misnamed font does not
  throw — it silently becomes Helvetica — so `fontSelfCheck` names them at launch.

## Where we deliberately do NOT match source_of_truth.html

The reference is the source of truth and the app tracks it closely. These are the places it
does not, each because the reference contradicts itself or would ship something broken.
If you audit fidelity and find them, they are answers, not findings.

| what | reference | here | why |
|---|---|---|---|
| Tokyo, in the onboarding wheel | `NRT` | `HND` | `NRT` is not one of Geography's 65 airports, so picking it falls through and silently sets home to Sydney. |
| The airport picked in onboarding | written to `window.HOME`, then overwritten by the next render from the unchanged `homeAp` state | persisted as the home airport | the reference mirrors `homeAp → window.HOME` during render, so the onboarding's choice is discarded a frame later and every new member starts in Sydney whatever they picked. Reproducing that would ship a control that does nothing. |
| The pass's perforation holes | two opaque `desk`-coloured discs painted over the card, on top of its own `box-shadow` | real transparency, punched with `destinationOut` so the shadow follows the notch | the reference's technique leaves a pale disc where each hole erases a bite out of the card's shadow — reproducing its CSS in a browser shows the same artifact, so this is the reference being wrong rather than us being unfaithful. A hole needs no colour. Cards elsewhere sit on other grounds, and a hole matched to one of them stops being a hole on the next. |
| The Concourse search field | drawn, with nothing wired to it or its filter button | filters the shelf by name, with a clear button and an empty state | a dead control is not shippable. A field you can tap and type into that then ignores you is worse than no field. The filter button had no defined behaviour to port, so it became the clear button a search field always needs. (This row described the intent before it described the code: the field shipped inert for a while, with the filter button still drawn beside it. It filters now.) |
| The shield's buttons | "Redeem miles", which jumps into Redeem, and "Not now" | one button, "Not now", which closes; the subtitle says how far short you are, or that Tempus is where the miles are spent | a `ShieldAction` extension can only close the shield — it cannot open its host app — so a button that says it redeems is a button that does nothing. It shipped for a while with a notification standing in for the jump (tap it to open Redeem) and was removed on device on 18 Sep 2026. The reference's redeem also always works; ours can refuse, and a shield must not promise time the app is about to decline. |
| What an unlock unlocks | the named app | every app in the selection | the reference's blocking is drawn, so an app is a string it can name. A real shield is raised on opaque `ApplicationToken`s, which iOS gives no stable identity, so there is nothing to unlock one-by-one *by*. The price never depended on which app you picked, and still does not. |
| Which apps get blocked | six hardcoded names, in Settings and on onboarding screen 3 | whatever iOS's `FamilyActivityPicker` returns, on both | the same rule as the Concourse search field: a list that cannot reach the OS is a control that does nothing. The six names survive as the stand-in used while Screen Time is unauthorized, under a banner saying blocking is not connected — and the banner's Connect button asks again, for anyone who declined the gate one screen earlier. |
| Storage on launch | wipes `localStorage` every load | persists normally | the reference says "Testing build: every reload starts from scratch". That is a demo harness, not a design decision; launch seams replace it. |
| A flight in the air | not persisted | persisted | a browser reload losing a flight is acceptable; a phone being killed mid-flight is not. |
| Screen 2's unlock demo | a white status card with a soft green "Open" chip and a dot pulsing in it forever | a pass stub: copper header band, the state stamped in it, the spend bar sitting on the perforation | the chip is how a dashboard says "live". Nothing else in Tempus says it that way, and a screen seen once is the worst place for a forever animation. The stub ties the demo to the boarding pass two screens earlier. |
| The pay sheet's side button | a hand-drawn double-press of the physical side button | an on-screen confirm | **iOS delivers no side-button event to any third-party app.** The double-press is a system gesture owned by Apple Pay: it is routed to the system's own payment sheet and nothing else, and there is no API — public or entitled — to observe it, imitate it, or be told it happened. So the reference's drawing is a picture of a control this app cannot have. It is also the *wrong* control to want: that gesture means "authorise a payment", and these are in-app miles, not money. The pay sheet keeps the reference's ceremony and its 980/1120 ms, and confirms on screen, behind a real `LAContext` check. Raised again on 14 Sep 2026 and on 16 Sep 2026 after device testing — it is not a porting gap, and there is nothing to reopen. **The drawn stand-in is also gone.** For a while this shipped a glassy 20 × 104 sliver pinned to the trailing edge at the reference's `top:172`, confirmed by a double-tap. It was removed on 16 Sep 2026: a control drawn on the bezel *claims* to be the hardware and then is not, and the 172 was a CSS literal measured inside a 390 × 844 drawing, so it did not even line up with the button it imitated. An ordinary confirm button says what it is. Do not re-add the sliver as a fidelity gap — `tp-sidein`/`tp-sideout` have nothing left to animate. |
| Picking the phone up, or leaving the app, mid-flight | nothing — a web page has no accelerometer and no lifecycle to leave | costs one of two chances; the third lapse diverts | `FocusGuard`. The reference cannot see either act, so it has no answer to port. Economy only — business class locks the cabin instead, and the only way out of that is the emergency exit. |
| Haptics | none anywhere | on the hold control and the settle overlay | the reference is a web page. A ten-second hold with no feedback is wrong on a phone. All buzzing goes through one `Haptics` enum. |
| The grace period | `GRACE_MS` declared, `grace` always null, a comment describing a feature with no code under it | not built | the feature was cut before it was written. |
| Buying Business Class | `onStart = () => setPlus(true)` — the button grants the plan for nothing | a RevenueCat purchase; the entitlement grants the plan, not the button | a web demo has no store. A shipping app cannot give away its paid tier. `Billing` owns it. **Onboarding's last screen sells it itself** — it does not hand off to the paywall, which would put the same offer, the same three included rows and the same price on screen twice in a row. With nothing to sell it says so and the button goes quiet, which is what the sheet would have said anyway; `Billing.unavailable` is that one sentence, and both surfaces read it. |
| The paywall's price | hardcoded "$39 / yr / 7 days free" | read from the live offering, with the reference's figures as the fallback until the store answers | a price the store does not agree with is a refund request. With no API key the button is disabled and says so. |
| The pay sheet's identity check | a 980 ms timer that turns the ring green and moves the ledger regardless | a real `LAContext` evaluation; miles move only on success | the reference has no biometry to call. Its 980 ms and 1120 ms survive as a *floor* on the ceremony, not its substance. |
| The three sign-in buttons | all three are `run(7)` — three ways of saying "next" | Apple through `AuthenticationServices`, Google through OAuth 2.0 + PKCE in `ASWebAuthenticationSession`, email through a validated address | same rule as the Concourse search field: a button that does nothing is not shippable. |
| "so your miles, log and passes survive a new phone" | said on onboarding screen 6 (7 here) | "to put your own name on the card and every pass" | there is no Tempus backend. `Identity.syncAvailable` is the one constant gating that copy, so it changes back the day there is one. |
| A daily spend limit | none — the reference's balance is the only ceiling | a cap in miles per day, on **its own onboarding screen (5)** and in Settings | a member who wants a ceiling wants it before the first unlock. Miles, not minutes, because the ledger moves miles and the cost per minute is itself a setting. Off by default, so nothing changes for anyone who does not ask. It is set on the same dial Redeem spends miles with, on a dark ground, and the scale runs 140 mi *below* Off so the marker is never parked at the end of its travel drawing one arm of the arc. That makes onboarding **eleven** screens where the reference has nine — the cap is one of the two this app adds; the Concourse (9) is the other. |
| What Business Class buys on the Concourse | n/a — the reference's shop is not gated at all | the shelf is open to everyone; roughly **three quarters of the stock** is Business Class, by a price ceiling per kind (`ShopCatalog.businessOnly`) | gating the shop whole meant a member who had flown for their miles had nothing to spend them on, and the one screen in the app that is a shop read as an advertisement. The split is by price because price is how quality was authored in this catalogue, and it is a *ceiling* rather than a rank so it lands on a whole price band — half a band open and half locked reads as arbitrary when two tiles plainly cost the same. `shopSelfCheck` pins the share between 66% and 80%, so a re-price that quietly makes the shelf 95% locked trips on the next debug launch. All Concourse prices were cut 20% on 21 Sep 2026 at the same time. |
| Changing the membership card's face | n/a | free at every tier | `CardDesignScreen.locked` was `!plus && index > 0` — every tier issued one face and charged for the rest of its own **built-in** run, so the card the membership is *about* could not be changed without the plan. The built-in faces ship in the binary and a member who flew to a tier has earned the right to wear it. A shop face that reaches that deck is one they already bought, which settles the question before the studio opens. |
| How the subscription is sold | one price, `$39 / yr`, take it or leave it | **two plans** — $39.99/yr and $7.99/mo — on one shared `PlanPicker`, annual default-selected | a single-price paywall loses everyone who would try a month first. **Each card leads with what it bills** ($39.99 per year, $7.99 per month) and the annual card's $3.33-a-month equivalent is a small line under its name; the free trial is stated only in the small line above the button, which says **Upgrade**. It was the other way round — $3.33 as the headline and "Start 1 week free" on the button — until App Review rejected build 43 under 3.1.2(c): the billed amount must be the most conspicuous price, and a calculated price or a trial subordinate to it in position and size. The same rule took "7 days free" off the Settings, Status Club and Linked entry points, which were hardcoded and untrue for anyone not eligible. The saving is a `copper100` stamp cut into the annual card's corner — **not** `copper500`, because copper is already the primary button's paint on both surfaces that draw this and a badge in the call-to-action's colour makes the eye unable to separate the discount from the thing to press. The picker draws only when both packages are live, or when nothing is purchasable at all (where the button is already disabled and says why); over a *live* offering selling one package it stays a single price, because tapping Monthly would otherwise fall back to the annual package and charge a year for a month. |
| Where the Screen Time gate sits | the permission screen sits between the app list and the account screen | the gate (3) comes immediately before the app picker (4), and the account is last of the five (7) | the picker cannot open without Screen Time, so asking after the list is drawn means the list is a stand-in for a question already put. The gate goes first and the picker inherits its answer. **Each set-piece stays with its screen, not with its ordinal**, so the reorder moved the choreography too rather than leaving it playing on the pair that inherited the slot: the gate still **rises from the bottom** as a 240pt-radius sheet over spend (the reference's pair 4, which is the crossing it gives the gate), the app list still arrives through the zoom-through white wash (pair 2), the list's Next button still expands into the dark cap screen (pair 3), and `home` still slides up and off to leave the account standing behind it (pair 5). Only `cap` → `home` has no reference source, because `cap` is the screen this app adds: the wheel blooms open through the cap dial's own copper marker, on the club hatch's circle (pair 6) anchored to that marker's measured point the way pair 1 anchors on the route's apex. |
| The Screen Time gate's buttons | **Allow**, and a **Not now** that skips the request | one button, **Continue**, which always goes on to iOS's own prompt | App Review rejected build 43 under 5.1.1(iv): a screen in front of a permission may explain it, but its button may not read as the consent itself ("Allow") and it may not offer a way around the system request ("Not now"). The member declines on iOS's sheet if they decline, which still leaves every flow working with blocking mocked. The copy says what the permission is for. |
| Changing the blocked apps | n/a — the reference's list is free to edit | the first pick is free; every change after it costs `AppModel.selectionChangeCost` (60 mi), confirmed by a 1.2 s hold (`HoldConfirmSheet`, with `HoldState`'s haptics) *before* the picker opens, and paid through `payOrderShared` only if the picker returns a different set | asked for (25 Sep 2026): a list you can empty for nothing is a lock with the key taped to it. Settings' picker edits a draft, and `changeSelection(to:)` is the one writer outside onboarding, so a refused payment leaves the old apps shielded. |
| Redeem's app list | a plain hairline list of six names, the selector on the trailing edge | a grouped card in the activity picker's shape: connected, it is the **real selection** drawn by `Label(token)` — iOS's own icons and names — and states what the unlock opens rather than offering a choice; unconnected, it is the six-name strip with the selector on the leading edge and a monogram tile | the picker is the shape a member already knows for "which apps", and this screen answers the same question. But a shield is one shield over the whole selection — there is no unlocking one app of it — so a chooser over real apps would be a control that does nothing, and the tokens are opaque: `Label(token)` is the only thing that can draw an app this app cannot read. |
| Developer mode | none | a hidden panel behind seven taps on the Settings title, **DEBUG builds only** | no reference equivalent. Sandbox builds (TestFlight) had it behind a passcode from 20 Sep 2026; it was removed on 1 Oct 2026, because App Review installs through the same sandbox as a tester and the panel hands out Business Class for free (Guideline 2.3.1). On TestFlight and the App Store the seven taps are silently eaten and the Developer row never renders. The launch seams are `Dev.seams`, DEBUG-only for the same reason. |