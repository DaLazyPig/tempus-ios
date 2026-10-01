# Tempus Design System

This document is the binding design contract for Tempus. The product is the native iOS
app (`Tempus/`); the design truth is the reference build `tempus_final_prerelease.html`,
whose 124 tokens are declared in the `:root` block of its HTML shell and mirrored
one-to-one in Swift (`Tempus/Theme/*.swift`). If the two disagree, the reference is
right — fix the Swift. Token files are the ONLY place raw values (hex, pt, ms) may live.

To re-read the tokens, unpack the reference (see CLAUDE.md § Commands) and grep the
shell for `--`; every value in §2–§6 below came from there.

**CSS var → Swift mapping**: `--navy-700` → `TColor.navy700` · `--text-primary` →
`TColor.textPrimary` · type roles → `TFont.title1/body/label/readout` (labels via
`.tpLabel()`) · `--space-4` → `TSpace.s4` · `--radius-md` → `TRadius.md` ·
`--shadow-card` → `.tpShadow(.card)` · `--ease-glide`+durations → `Animation.glide(TDur.base)`.

## 1. Concept

Tempus dresses a focus/screen-time product in the language of **air travel**:
studying is flying somewhere real, distraction is a diversion, currency is Miles,
history is a flight log, the UI chrome quotes boarding passes and departure boards.
Every design decision should reinforce calm, competent travel — an airline you trust,
not a slot machine. That is why the palette is night-sky navy + copper, the motion
glides without bouncing, and numerals read like departure-board readouts.

## 2. Color

Base ramps (raw values live in `tokens.css`):

| Ramp | Role | Steps |
|---|---|---|
| Navy | primary brand, night sky, dark screens | `--navy-900…500` (core: `--navy-700` #23395b) |
| Steel | secondary text, chrome | `--steel-700…400` |
| Sky | supporting fills, routes, altitude lines | `--sky-500…100` |
| Cloud | light surfaces | `--cloud-100`, `--cloud-050`, `--white` |
| Copper | THE accent: Miles, primary actions | `--copper-700…100` (core: `--copper-500` #b86f52) |

Status colors follow flight-board semantics — on-time green `--status-ontime`,
delayed amber `--status-delayed`, diverted red `--status-diverted`, each with a
`-soft` tint for chips/rows.

**Rules**
- Copper is scarce. One primary copper action per screen; Miles amounts and links
  may also be copper. If everything is copper, nothing is.
- Screens are either *light* (cloud page, white cards, navy text) or *dark*
  (navy surface, cloud text) — the flight-session screens (preflight, pass, flying)
  are dark; everything else is light. Use the semantic vars (`--surface-*`,
  `--text-*`, `--border-*`), never the ramps directly, so this stays consistent.
- Glass overlays on photos/dark: `--glass-on-dark` + `--blur-glass`.

## 3. Typography

Two families, strict division of labor:

- **Outfit** (`--font-core`) — everything a person reads AND every large numeral.
  Geometric, even-width digits keep readouts steady without a mono.
- **DM Mono** (`--font-data`) — ONLY small uppercase boarding-pass labels and flight
  codes (`--text-label` + `--track-label` 0.16em tracking + uppercase). Never body text.

Composed roles (use these `font:` shorthands, not ad-hoc sizes): `--text-display` 64,
`--text-title-1` 40, `--text-title-2` 30, `--text-title-3` 23, `--text-body-role` 16,
`--text-label` 11 mono, `--text-readout` 56 (flight-data numerals, always
`fontVariantNumeric:'tabular-nums'` when they tick).

Fonts ship as static instances in `Tempus/Fonts/` and are registered in `Info.plist`;
`Tempus/Fonts/FONTS.md` lists every file with its exact PostScript name. Reach them only
through `TFont` — a misnamed font does not throw, it silently becomes Helvetica.

**The membership cards are the exception, and it is deliberate.** Each status tier is set
in its own typeface, and that per-tier type *is* the identity of the tier:

| tier | face | character |
|---|---|---|
| Essential | Big Shoulders Display | condensed grotesque |
| Signature | Cormorant Garamond | old-style serif |
| Premier | Bodoni Moda | didone |
| Prestige | Syne | geometric extended |
| Founders | Italiana | high-contrast display serif |

These are reached only through `TCardFont`, and only on card faces — never in the
interface, which stays Outfit and DM Mono.

## 4. Space, shape, layout

- 4px grid: `--space-1…20` (4→80px). No off-grid values.
- Radii round generously: `--radius-xs` 6 → `--radius-xl` 32; **anything tappable is a
  pill** (`--radius-pill`). Cards are `--radius-md/lg`; the phone frame is 44px.
- Phone canvas: 390×844, `--width-screen-max` 420, `--gutter-screen` 20px,
  minimum tap target `--tap-min` 48px.

## 5. Elevation

Four shadow tiers only: `--shadow-card` (resting card), `--shadow-raised` (lifted,
draggable), `--shadow-overlay` (sheets/modals), `--shadow-accent` (copper CTA glow).
Focus is `--ring-focus` (copper, 3px). Tracks/wells use `--shadow-inset-track`.

## 6. Motion

**Things glide. No springs, no bounce, no overshoot.**

- Easing: `--ease-glide` cubic-bezier(.22,.61,.36,1) for nearly everything;
  `--ease-exit` for things leaving; `--ease-in-out` for symmetric moves.
- Durations: `--dur-instant` 90 (press feedback) · `--dur-fast` 160 (hover, toggles) ·
  `--dur-base` 240 (element enter/exit) · `--dur-slow` 420 (sheets) ·
  `--dur-scene` 700 (full-screen transitions).
- Press = `scale(var(--press-scale))` (.975); hover lift = `--hover-lift` (-1px).
- Router cuts carry **two** numbers, and they differ on purpose: a teardown length that
  holds the outgoing layer, and the animation lengths themselves (`zoom` tears down at
  520 but animates 480 in / 400 out). `TransitionType` keeps both.
- Signature moves: the deck deal, the boarding-pass print and **tear**, the copper
  card→screen **morph**, the Home⇄Settings **circle reveal**, and the gate rising from
  the bottom edge with its top corners unrounding. The first two belong to their
  screens; the last three own their own clock and live in
  `DesignSystem/Transitions.swift` and `Screens/GateScreen.swift`.
- Staggered entrances use the `Rise`/`ORise` wrappers (70ms / 130ms steps) — don't
  hand-roll delays.
- Anything driven by a progress value rather than by animating a property runs off
  `tpRamp`, one real-clock driver, so a hand-driven curve cannot drift from a
  property-animated one.

## 7. Components

Everything lives in `Tempus/DesignSystem/`, is stateless-controlled, and uses tokens only.
The table below is the reference's own component manifest; note that the reference app
actually instantiates only **Button** and **Dial** from it — the rest of the row names are
its design-system source, and the real Settings furniture (`GlassSwitch`, `SetRow`,
`SetGroup`, `ChoiceSheet`) lives in its app file instead. Ours follow what the app does.

| Component | Purpose |
|---|---|
| core/Button | pill button; variants `primary` (copper), `secondary` (navy), `outline`, `ghost`, `onDark`; `icon`/`iconAfter`, `size` sm/md/lg, `fullWidth`, `disabled` |
| core/Card | white rounded surface, `--shadow-card` |
| core/IconButton | 48px round tappable icon |
| core/Tag | small status/label chip (status colors) |
| feedback/StatusBanner | on-time / delayed / diverted banner rows |
| flight/BoardingPass | the pass artifact: route, codes, perforation, barcode |
| flight/Dial | minute-picker dial (the study-length control) |
| flight/FlightLogRow | one flight-log entry row |
| flight/FlightProgress | route progress arc/line with plane |
| flight/MilesBalance | copper Miles readout |
| flight/RedeemRow | app row with Miles cost in the redeem sheet |
| flight/TaskCard | study-task deck card |
| forms/Input | text field |
| forms/RouteOption | selectable route/option row |
| forms/SegmentedControl | segmented switch |
| forms/Switch | toggle |
| navigation/ScreenHeader | title + back chrome |
| navigation/TabBar | bottom tab bar |

The fastest way to see the intended look of anything is to open
`tempus_final_prerelease.html` in a browser and drive it with its own dev panel.
Purpose-built composites (deck cards, the airport wheel, the boarding pass) live with
their screens; promote one into the design system only when a second screen needs it.

**Two kinds of art, and they are not interchangeable.** The membership *card* faces are
drawn natively in `Screens/CardArt.swift`, because they are shapes and gradients. The
Concourse's 274 shop faces, 42 headers and 18 gift faces are **data** — markup in
`Resources/shop.json` rendered by `DesignSystem/Markup/`. That renderer covers exactly
the vocabulary that file uses and must not grow into a general browser engine: adding
stock means adding data, not a `Shape`.

## 8. Voice

Interface copy is airline-operational: short, lowercase-calm, no exclamation marks,
no guilt. "Flight diverted — no miles earned" states a fact; it never scolds. Labels
in DM Mono are uppercase telegraphic ("GATE", "MILES", "DEPARTS"); sentences are
Outfit and human.

## 9. Iconography

Lucide, 1.75px stroke, via `<Icon n="kebab-name" s={size}/>`. Icons inherit
`currentColor`; never bake a color into an icon.
