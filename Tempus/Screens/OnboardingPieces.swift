import SwiftUI
import QuartzCore

/// The parts the onboarding sequence is built from: its constants, its clock, its state, the
/// per-frame style it computes, and the handful of bespoke views only it uses.
///
/// Onboarding is the one screen in the app that does not animate by declaring `withAnimation`.
/// Ten screens, nine crossings and one exit are hand-authored as functions of a single progress
/// value `t`, advanced by a display link. Several crossings run different properties on different
/// windows of the same clock (a transform on the scene curve while the opacity runs linearly over
/// the middle half), which a chain of nested animations cannot express.

// MARK: - Constants

/// The ten screens, by name.
///
/// Everything that used to be a page number goes through this: the crossing table, the durations,
/// the dark grounds, and every Next button's target. The screens have been reordered once already
/// — the Screen Time gate moved from after the app list to before it — and a reorder that has to
/// be chased through nine numeric literals is a reorder that silently leaves a crossing playing on
/// the wrong pair. Moving a case here moves the screen, its crossing and its ground together.
enum OBScreen: Int, CaseIterable, Hashable {
    case cover      // the deck of passes, torn to begin
    case earn       // flying earns miles
    case spend      // miles buy screen time
    case gate       // the Screen Time permission gate
    case apps       // what should cost miles
    case cap        // cap what you spend in a day
    case home       // which airport do you fly from
    case account    // the account
    case club       // the Status Club
    case shop       // the Concourse
    case business   // business class

    /// The array index. Layers, contents and `flow.i` are all positional.
    var i: Int { rawValue }

    /// The screen after this one, or `nil` at the end of the sequence.
    var next: OBScreen? { OBScreen(rawValue: rawValue + 1) }

    static let last = OBScreen.business
}

enum OBConst {

    /// Crossing lengths in seconds, keyed by the screen the crossing *leaves*. Going backwards
    /// replays the same choreography with `t` running 1 → 0.
    /// These are the reference's own `OB_DUR` figures, re-keyed onto the screen each crossing
    /// leaves. The reference has eight crossings to our ten, so exactly two lengths here are not
    /// its: `cap` (onto the wheel) and `shop` (the Concourse, onto the upgrade) are the screens
    /// this app adds, and both run at the same 1.25 as the sheet crossings they are siblings to.
    static let durations: [OBScreen: Double] = [
        .cover: 4.0, .earn: 1.6, .spend: 1.25, .gate: 1.25, .apps: 1.2,
        .cap: 1.25, .home: 1.2, .account: 2.4, .club: 1.25, .shop: 1.25,
    ]

    /// The exit, from `business` to the home deck.
    static let exitDuration: Double = 1.5

    /// The column inset every screen's content takes from the top and bottom of its own ground.
    ///
    /// The screens are full-bleed — each paints its ground to the physical edge, and the crossings
    /// are measured in that space — so the hardware is cleared here, by the column. The reference
    /// pads 52/34 against a phone frame that has no island and no home indicator; a real phone's
    /// insets can be larger, and the column takes whichever is greater rather than stacking the
    /// two, which is 96pt this screen does not have to give.
    static var padTop: CGFloat { max(52, TSafeArea.insets.top) }
    static var padBottom: CGFloat { max(34, TSafeArea.insets.bottom) }

    /// The screens that paint a dark ground, so the status bar flips to its light treatment.
    /// `club` is not here: it takes its tone from whichever tier card is showing.
    static let darkScreens: Set<OBScreen> = [.cover, .spend, .cap, .business]

    /// The apps offered on `apps`, in the order they are listed — which is also the order they
    /// are handed back to the model.
    static let apps: [(key: String, label: String)] = [
        ("tt", "TikTok"), ("ig", "Instagram"), ("yt", "YouTube"),
        ("rd", "Reddit"), ("sc", "Snapchat"), ("mu", "Music")
    ]

    /// The daily spend cap's dial, in miles. It reaches 300 in fives, the density Preflight's
    /// minute dial runs at — a dial wants ticks, not four presets.
    static let capMax: Double = 300
    static let capStep: Double = 5


    /// The seven airports the wheel offers — a fixed list, not `Geography`'s table.
    ///
    /// Tokyo is **HND**, where the reference says `NRT`. `NRT` is not one of `Geography`'s 65
    /// airports, so `byCode` would fall through to the first entry and picking Tokyo would
    /// silently set home to Sydney. Every other code here exists in the table.
    static let airports: [(city: String, code: String)] = [
        ("Auckland", "AKL"), ("Singapore", "SIN"), ("São Paulo", "GRU"), ("Sydney", "SYD"),
        ("Tokyo", "HND"), ("Toronto", "YYZ"), ("Paris", "CDG")
    ]

    /// Sydney — where the wheel opens.
    static let defaultWheel: Double = 3

    /// Per-card tear windows, as fractions of the 4000 ms cover crossing. Every window overlaps
    /// its neighbour and each is shorter than the one before, so the deck accelerates and all nine
    /// are gone before the camera arrives.
    static let deckTears: [(start: Double, end: Double)] = [
        (0, 0.21), (0.13, 0.32), (0.245, 0.415), (0.345, 0.495), (0.43, 0.56),
        (0.50, 0.615), (0.56, 0.66), (0.61, 0.70), (0.655, 0.735)
    ]

    /// How far the tear travels, and how far the carousel steps.
    static let tearCommitDistance: CGFloat = 88
    static let tearCommitVelocity: Double = 0.85
    static let wheelRow: CGFloat = 48

    // MARK: The economy onboarding quotes

    /// The demo flight the cover pass and the earn screen both show, and what it actually pays.
    ///
    /// **Derived, never typed.** The reference hardcodes `120 mi` against a 50-minute flight in
    /// three places while its own earn rate is the same 0.25 mi a minute this app uses — so its
    /// first screen promises a new member nine times what its economy pays, and the flight they
    /// then fly banks 13. Quoting a number here rather than computing one reproduces that, and it
    /// is the first thing anybody sees.
    ///
    /// Onboarding cannot reach Settings, so the rates are necessarily their defaults.
    static let demoMinutes = 50
    static var demoEarn: Int { Status.earn(minutes: demoMinutes, rate: 0.25, mult: 1) }

    /// The spend demo: a half-hour unlock, and what a half hour costs.
    ///
    /// The reference's card is internally consistent at *four* miles a minute — "4 MI A MINUTE"
    /// against "−120 mi" for thirty minutes — but its own spend rate, and this app's, is one. So
    /// the card taught a new member a price four times what Redeem would actually charge. Both
    /// halves come off the same constant now, so they cannot drift apart again.
    static let demoUnlockSeconds = 1800
    static let demoSpendRate: Double = 1
    static var demoSpend: Int { Int((Double(demoUnlockSeconds) / 60 * demoSpendRate).rounded()) }
    static var demoSpendRateLine: String {
        let r = demoSpendRate
        let n = r == r.rounded() ? String(Int(r)) : String(format: "%g", r)
        return "\(n) mi a minute"
    }
    static let carouselStep: CGFloat = 272
    static let carouselCommit: CGFloat = 56

    /// The reference's frame. Only the two crossing anchors that are stated as absolute points
    /// (the hatch circle's centre, the Next button's rect) are measured against it.
    static let designSize = CGSize(width: 390, height: 844)

    static func deckTear(_ k: Int, _ q: Double) -> Double {
        guard q >= 0, k >= 0, k < deckTears.count else { return 0 }
        let w = deckTears[k]
        return TEase.clamp((q - w.start) / (w.end - w.start))
    }

    /// The travel curve for a torn half: cubic in-out over a distance far larger than the frame,
    /// so the visible part is all acceleration and the slow tail lands off-screen.
    static func tearCurve(_ u: Double) -> Double {
        u <= 0 ? 0 : (u >= 1 ? 1 : TEase.inOut(u))
    }

    /// The Next button growing into the page, as a colour: it leaves copper and arrives as the
    /// ground it is opening. Naive sRGB-component lerp, no gamma — a colour-managed blend reads
    /// visibly different here. The reference ends this on paper because the screen it opened was
    /// white; the `apps` ⇄ `cap` crossing opens onto navy, and a pill that turned white first
    /// would flash before the reveal.
    static func expandGround(_ t: Double) -> Color {
        Color(.sRGB,
              red: TEase.lerp(184, 35, t) / 255,
              green: TEase.lerp(111, 57, t) / 255,
              blue: TEase.lerp(82, 91, t) / 255)
    }
}

/// What the deck is doing at a given point in the cover crossing.
struct OBDeckState {
    /// A continuous "cards spent" count, 0 → 9.
    var front: Double = 0
    var zoom: Double = 1
    /// The title and footer fade out over the first 600 ms.
    var copy: Double = 1
    /// The buried cards grow in over the first 560 ms.
    var reveal: Double = 0

    /// `q` is the crossing clock while the cover pair is live, and −1 at rest.
    init(_ q: Double) {
        guard q >= 0 else { return }
        front = (0..<OBConst.deckTears.count).reduce(0) { $0 + TEase.inOut(OBConst.deckTear($1, q)) }
        // One continuous push: an eased ramp while the deck is being spent, then a cubic that
        // keeps steepening once there is nothing left to tear.
        zoom = 1 + 0.85 * TEase.inOut(TEase.clamp(q / 0.78)) + 38 * pow(TEase.clamp((q - 0.42) / 0.58), 3.4)
        copy = 1 - TEase.out(TEase.clamp(q / 0.15))
        reveal = TEase.out(TEase.clamp(q / 0.14))
    }
}

// MARK: - The tier palettes

/// The five Status Club palettes, and the tier facts `club` quotes. Each palette is authored in
/// the tone of that tier's default card face, so the whole screen re-tones as the carousel moves.
struct OBTier {
    let name: String
    let mono: String
    /// Qualifying hours in a 90-day period. Founders is by invitation and has no gate.
    let gate: Int
    /// Printed, not computed — "×1.1" must not become "×1.1000000000000001".
    let mult: String
    let bonus: Int
    let invite: Bool
    let face: TCardFont

    let bg, ink, mute, accent, rule, chip, chipInk, idle, btn, btnInk: Color
    let dark: Bool

    static let all: [OBTier] = [
        OBTier(name: "Essential", mono: "ESS", gate: 0, mult: "1", bonus: 0, invite: false,
               face: .essential,
               bg: Color(hex: 0xbcd3ea), ink: Color(hex: 0x152740), mute: Color(hex: 0x4c6684),
               accent: Color(hex: 0x9d5230), rule: Color(hex: 0x152740, opacity: 0.16),
               chip: Color(hex: 0x152740, opacity: 0.10), chipInk: Color(hex: 0x3a5673),
               idle: Color(hex: 0x152740, opacity: 0.20), btn: Color(hex: 0x152740),
               btnInk: Color(hex: 0xf2f5fa), dark: false),
        OBTier(name: "Signature", mono: "SIG", gate: 30, mult: "1.1", bonus: 0, invite: false,
               face: .signature,
               bg: Color(hex: 0x1b3a5c), ink: Color(hex: 0xf2f5fa), mute: Color(hex: 0xa6bcd8),
               accent: Color(hex: 0xe6b08f), rule: Color(hex: 0xf2f5fa, opacity: 0.14),
               chip: Color(hex: 0xf2f5fa, opacity: 0.14), chipInk: Color(hex: 0xcfdcee),
               idle: Color(hex: 0xf2f5fa, opacity: 0.24), btn: Color(hex: 0xb86f52),
               btnInk: Color(hex: 0xffffff), dark: true),
        OBTier(name: "Premier", mono: "PRM", gate: 75, mult: "1.2", bonus: 10, invite: false,
               face: .premier,
               bg: Color(hex: 0xecd3c1), ink: Color(hex: 0x4a2a19), mute: Color(hex: 0x8a5f47),
               accent: Color(hex: 0x9d5230), rule: Color(hex: 0x4a2a19, opacity: 0.18),
               chip: Color(hex: 0x4a2a19, opacity: 0.10), chipInk: Color(hex: 0x7a4229),
               idle: Color(hex: 0x4a2a19, opacity: 0.22), btn: Color(hex: 0x7a4229),
               btnInk: Color(hex: 0xfff6f0), dark: false),
        OBTier(name: "Prestige", mono: "PRS", gate: 120, mult: "1.3", bonus: 20, invite: false,
               face: .prestige,
               bg: Color(hex: 0xc9ced4), ink: Color(hex: 0x141a24), mute: Color(hex: 0x4d5765),
               accent: Color(hex: 0x8a5a34), rule: Color(hex: 0x141a24, opacity: 0.16),
               chip: Color(hex: 0x141a24, opacity: 0.10), chipInk: Color(hex: 0x39424f),
               idle: Color(hex: 0x141a24, opacity: 0.22), btn: Color(hex: 0x141a24),
               btnInk: Color(hex: 0xf0e6d6), dark: false),
        OBTier(name: "Founders", mono: "FDR", gate: 0, mult: "1.4", bonus: 0, invite: true,
               face: .founders,
               bg: Color(hex: 0x63512f), ink: Color(hex: 0xf8f0dd), mute: Color(hex: 0xdccdab),
               accent: Color(hex: 0xf3e3bf), rule: Color(hex: 0xf8f0dd, opacity: 0.2),
               chip: Color(hex: 0xf8f0dd, opacity: 0.16), chipInk: Color(hex: 0xf4e9d2),
               idle: Color(hex: 0xf8f0dd, opacity: 0.3), btn: Color(hex: 0xf3e3bf),
               btnInk: Color(hex: 0x3b2f18), dark: true)
    ]

    /// The three facts printed under the card, and whether each value takes the accent colour.
    var rows: [(label: String, value: String, accent: Bool)] {
        if invite {
            return [("How you reach it", "Invitation only", true),
                    ("Every mile earned", "\u{00d7}" + mult, true),
                    ("Lifetime hours", "10,000 h", false)]
        }
        return [("Hours to reach it", "\(gate) h in 90 days", false),
                ("Every mile earned", "\u{00d7}" + mult, mult != "1"),
                ("Bonus for reaching it", bonus > 0 ? "+\(bonus) mi, once" : "None", bonus > 0)]
    }

    var chipLabel: String {
        if invite { return "By invitation" }
        if mono == "ESS" { return "Yours today" }
        if mono == "SIG" { return "In economy" }
        return "Business Class"
    }
}

// MARK: - The clock

/// One display-link-backed progress driver. `tick` is called with 0…1 every frame for `duration`
/// seconds, then `done` once.
///
/// A `CADisplayLink` rather than a `Timer` because every crossing is authored as a function of a
/// fraction of wall-clock time: a dropped frame must skip ahead, not stretch the sequence.
final class OBClock: NSObject {
    private var link: CADisplayLink?
    private var t0: CFTimeInterval = 0
    private var duration: Double = 1
    private var tick: ((Double) -> Void)?
    private var done: (() -> Void)?

    /// `startAt` is a fraction of the run, so a launch seam can open a crossing already in motion.
    func run(duration: Double, startAt: Double = 0,
             tick: @escaping (Double) -> Void, done: (() -> Void)? = nil) {
        cancel()
        self.duration = max(0.001, duration)
        self.tick = tick
        self.done = done
        t0 = CACurrentMediaTime() - TEase.clamp(startAt) * self.duration
        let l = CADisplayLink(target: self, selector: #selector(step))
        l.add(to: .main, forMode: .common)
        link = l
        step()
    }

    @objc private func step() {
        let q = TEase.clamp((CACurrentMediaTime() - t0) / duration)
        tick?(q)
        if q >= 1 {
            let finish = done
            cancel()
            finish?()
        }
    }

    func cancel() {
        link?.invalidate()
        link = nil
        tick = nil
        done = nil
    }

    deinit { link?.invalidate() }
}

// MARK: - State

/// Everything onboarding owns, in a reference type.
///
/// This is not a style preference. Every mutation here happens from an escaping closure — a drag
/// callback, a display-link tick, a scheduled commit — and a `View` struct captured in such a
/// closure writes to `@State` storage without reliably invalidating the live view: the value reads
/// back changed while `body` is never re-evaluated. That is how a tear gesture ends up moving
/// nothing at all.
@Observable
final class OnboardingFlow {

    /// The settled screen, 0…8.
    var i = 0
    /// The lower screen of the crossing in flight, or −1 at rest.
    var pair = -1
    /// The crossing clock, 0…1. Runs 1 → 0 when going backwards.
    var t: Double = 0
    /// The exit clock, or −1 while idle.
    var exitT: Double = -1

    /// The tear: how far the stub has been pulled, after the rubber band.
    var dy: CGFloat = 0
    var dragging = false
    var torn = false

    /// The airport wheel's continuous position, 0…6.
    var wPos: Double = OBConst.defaultWheel
    var wheelDragging = false

    /// Which apps will be locked. Read back in `OBConst.apps` order. The stand-in: it is what
    /// `apps` offers while Screen Time is not connected, and what `finish` hands back either way
    /// — a real selection is written straight to the model by iOS's own picker.
    var picked: Set<String> = ["tt", "ig", "rd"]

    /// Which crossing variant to play, from `-tempusCross`. `nil` is what ships.
    ///
    /// ponytail: this is a comparison harness, not a feature — when a variant wins, it becomes the
    /// only body of its case and this goes with the loser.
    var cross: String?

    /// Whether Screen Time is connected. `gate` asks for it and writes the answer here; `apps`
    /// reads it to decide whether it can draw the real apps, and can ask again from
    /// its banner if the gate was declined.
    var screenTimeOn = false

    /// The daily spend cap, in miles, chosen on `cap`. 0 is off, which is where it starts —
    /// nobody is capped by default, and Settings offers the same list afterwards.
    var spendCap = 0

    /// The Status Club carousel.
    var ci = 0
    var cdx: CGFloat = 0
    var carouselDragging = false

    /// The screen-2 demo countdown, in seconds. Runs down from 29:58 and loops.
    var clockSeconds = OBConst.demoUnlockSeconds - 2

    /// Measured once, because the camera pushes into the perforation rather than into the middle
    /// of anything: the deck's own zoom and the whole screen's scale both take their origin from
    /// the tear line.
    var tearPct: Double = 46
    var tearScreenPct: Double = 46
    /// The copper apex dot on `earn`'s route, which the `earn` ⇄ `spend` reveal grows out of.
    var apex: CGPoint?
    /// `apps`' Next button, which the `apps` ⇄ `cap` crossing expands into the page.
    var nextButtonRect: CGRect?
    /// The copper marker on `cap`'s dial, which the `cap` ⇄ `home` reveal grows out of.
    var dialApex: CGPoint?

    /// The nine passes, drawn once and held. The shuffle is the only nondeterminism in onboarding.
    let deck: [Carriers.Livery] = Carriers.showcase.shuffled()

    /// Blocks `run`, `finish`, the tear and the carousel while a crossing is in flight.
    var busy = false

    private let sceneClock = OBClock()
    private let wheelClock = OBClock()

    // MARK: Crossings

    /// The one way the sequence moves. `seek` opens the crossing already in motion, for the
    /// launch seam that has to catch a set-piece in a static screenshot.
    func run(_ to: Int, model: AppModel, seek: Double = 0) {
        guard !busy else { return }
        if to > OBScreen.last.i { finish(model: model); return }
        guard let arriving = OBScreen(rawValue: to), to != i else { return }

        let p = min(i, to)
        let forward = to > i
        busy = true
        pair = p
        t = forward ? 0 : 1
        let darkTo = arriving == .club
            ? OBTier.all[ci].dark
            : OBConst.darkScreens.contains(arriving)
        let leaving = OBScreen(rawValue: p)

        // The ground changes at the *start* of a crossing, so the status bar cross-fades under
        // it — every crossing here paints the destination's ground across the top of the screen
        // from its first frame, so by the time iOS has finished its ~300ms numeral cross-fade the
        // ground under it already agrees.
        //
        // **Except `apps -> cap`,** whose ground grows out of the Next button at the *bottom* of
        // the page and does not reach the status bar until t ≈ 0.547 — 660ms into a 1.2s
        // crossing. Flipping at t = 0 there put white numerals on the pale app list for over half
        // the run, which reads as the clock blinking out and coming back. That one waits for its
        // own ground, in both directions, so backing out of the wheel flips at the same point the
        // pill uncovers the bar.
        let flipAt: Double = leaving == .apps ? 0.55 : 0
        let darkFrom = leaving.map { OBConst.darkScreens.contains($0) } ?? darkTo
        if flipAt == 0 { model.obDark = darkTo }

        let dur = leaving.flatMap { OBConst.durations[$0] } ?? 1.2
        sceneClock.run(duration: dur, startAt: seek / dur) { [weak self] q in
            self?.t = forward ? q : 1 - q
            if flipAt > 0 {
                let want = (forward ? q : 1 - q) >= flipAt ? darkTo : darkFrom
                if model.obDark != want { model.obDark = want }
            }
        } done: { [weak self] in
            guard let self else { return }
            i = to
            pair = -1
            t = 0
            dy = 0
            torn = false
            busy = false
            if model.obDark != darkTo { model.obDark = darkTo }
        }
    }

    /// Home is committed here and only here, so backing up to the wheel after seeing screens 6–9
    /// still takes effect.
    func finish(model: AppModel) {
        guard !busy else { return }
        busy = true
        let ap = OBConst.airports[pickedAirportIndex]
        let blocked = OBConst.apps.map(\.key).filter { picked.contains($0) }
        let cap = spendCap
        sceneClock.run(duration: OBConst.exitDuration) { [weak self] q in
            self?.exitT = q
        } done: {
            model.finishOnboarding(blocked: blocked, minutes: 50, home: ap.code, limit: cap)
        }
    }

    var pickedAirportIndex: Int {
        min(max(Int(wPos.rounded()), 0), OBConst.airports.count - 1)
    }

    // MARK: The tear

    private var tearLastY: CGFloat = 0
    private var tearLastTime: Date = .distantPast
    private var tearVelocity: Double = 0
    private var tearDistance: CGFloat = 0

    func tearChanged(_ translation: CGFloat, at time: Date) {
        guard !torn, !busy else { return }
        if !dragging {
            dragging = true
            tearLastY = translation
            tearLastTime = time
            tearVelocity = 0
        }
        // Points per millisecond, downwards positive — the same unit the commit threshold uses.
        let dt = max(1, time.timeIntervalSince(tearLastTime) * 1000)
        tearVelocity = Double(translation - tearLastY) / dt
        tearLastY = translation
        tearLastTime = time

        let raw = max(0, translation)
        tearDistance = raw
        // A hard rubber band past 140 pt, so the stub cannot be dragged to the floor.
        dy = raw <= 140 ? raw : 140 + (raw - 140) * 0.36
    }

    func tearEnded(model: AppModel) {
        guard dragging else { return }
        let committed = tearDistance > OBConst.tearCommitDistance
            || tearVelocity > OBConst.tearCommitVelocity
        tearDistance = 0
        tearVelocity = 0
        if committed {
            dragging = false
            torn = true
            run(1, model: model)
        } else {
            dragging = false
            withAnimation(.glide(0.52)) { dy = 0 }
        }
    }

    // MARK: The wheel

    private var wheelBase: Double = 0
    private var wheelLastY: CGFloat = 0
    private var wheelLastTime: Date = .distantPast
    private var wheelVelocity: Double = 0

    func wheelChanged(_ translation: CGFloat, at time: Date) {
        if !wheelDragging {
            wheelClock.cancel()
            wheelDragging = true
            wheelBase = wPos
            wheelLastY = translation
            wheelLastTime = time
            wheelVelocity = 0
        }
        let ms = time.timeIntervalSince(wheelLastTime) * 1000
        if ms > 10 {
            // Rows per ~16 ms frame, which is what the flick allowance below is expressed in.
            wheelVelocity = Double(wheelLastY - translation) / Double(OBConst.wheelRow) / ms * 16
            wheelLastY = translation
            wheelLastTime = time
        }
        // One row per 48 pt; dragging up walks down the list. Hard clamp, no overscroll.
        wheelSet(wheelBase - Double(translation) / Double(OBConst.wheelRow))
    }

    func wheelEnded() {
        guard wheelDragging else { return }
        wheelDragging = false
        // A flick can carry at most 1.8 rows past where it was released.
        wheelSettle(Int((wPos + TEase.clamp(wheelVelocity * 2.4, -1.8, 1.8)).rounded()))
    }

    private func wheelSet(_ v: Double) {
        let next = TEase.clamp(v, 0, Double(OBConst.airports.count - 1))
        // Only `wheelChanged` (a live drag) calls this — `wheelSettle`'s animation writes `wPos`
        // directly — so a tick fired here never doubles up with the settle.
        if Int(next.rounded()) != Int(wPos.rounded()) { Haptics.dialTick() }
        wPos = next
    }

    /// 380 ms on a cubic out. It never calls back — the pick is read straight off `wPos`.
    func wheelSettle(_ to: Int) {
        let target = Double(min(max(to, 0), OBConst.airports.count - 1))
        let from = wPos
        wheelClock.run(duration: 0.38) { [weak self] q in
            self?.wPos = from + (target - from) * TEase.out(q)
        }
    }

    // MARK: The carousel

    func carouselChanged(_ translation: CGFloat) {
        guard !busy else { return }
        carouselDragging = true
        let step = OBConst.carouselStep
        // Rubber band past one whole step.
        cdx = abs(translation) <= step
            ? translation
            : (translation < 0 ? -1 : 1) * (step + (abs(translation) - step) * 0.3)
    }

    func carouselEnded(model: AppModel) {
        guard carouselDragging else { return }
        let d = cdx
        let step = d < -OBConst.carouselCommit ? 1 : (d > OBConst.carouselCommit ? -1 : 0)
        // The drag flag clears *first*, so the settle animation carries the snap.
        carouselDragging = false
        withAnimation(.glide(0.52)) {
            ci = min(max(ci + step, 0), OBTier.all.count - 1)
            cdx = 0
        }
        if i == OBScreen.club.i { model.obDark = OBTier.all[ci].dark }
    }

    func selectCard(_ k: Int, model: AppModel) {
        withAnimation(.glide(0.52)) { ci = k }
        if i == OBScreen.club.i { model.obDark = OBTier.all[k].dark }
    }

    // MARK: Measurement

    /// The two halves of the tear-line measurement arrive from separate geometry readers in no
    /// guaranteed order, so both are kept and the origins recomputed whenever either lands.
    private var deckRect: CGRect?
    private var deckTearBottom: CGFloat?
    private var screenHeight = OBConst.designSize.height

    func setDeckRect(_ r: CGRect, screenHeight h: CGFloat) {
        deckRect = r
        screenHeight = h
        recomputeTearOrigins()
    }

    func setDeckTearBottom(_ y: CGFloat) {
        deckTearBottom = y
        recomputeTearOrigins()
    }

    private func recomputeTearOrigins() {
        guard let deck = deckRect, let bottom = deckTearBottom,
              deck.height > 0, screenHeight > 0 else { return }
        tearPct = TEase.clamp(Double((bottom - deck.minY) / deck.height) * 100, 10, 90)
        tearScreenPct = TEase.clamp(Double(bottom / screenHeight) * 100, 10, 90)
    }

    var tier: OBTier { OBTier.all[min(max(ci, 0), OBTier.all.count - 1)] }
}

// MARK: - The per-frame style

/// One screen's layer style for this frame. Everything the crossings drive lives here, so the
/// choreography is one table of numbers rather than nine screens each animating themselves.
struct OBLayer {
    var hidden = false
    var opacity: Double = 1
    var scale: CGFloat = 1
    var anchor: UnitPoint = .center
    var offsetY: CGFloat = 0
    /// `translateY(%)` — a fraction of the screen's own height.
    var offsetYFraction: CGFloat = 0
    /// CSS `filter: brightness(k)`. The reference states it as a multiplier and this keeps it one,
    /// because `.brightness` is not that filter: SwiftUI *adds* its argument to every channel, so
    /// `brightness(0.5)` restated as `.brightness(-0.5)` crushes a dark ground to flat black where
    /// CSS only halves it. `.colorMultiply` is the multiply, and it is what these numbers are.
    /// 1 is untouched.
    var dim: Double = 1
    var clip: OBCircleClip?
    var topRadius: CGFloat = 0
    var bottomRadius: CGFloat = 0
    /// Draw `bottomRadius` as a falling sheet's teardrop tip rather than as two bottom corners.
    /// Two crossings round a bottom edge and they mean opposite things: `cap -> home` drips into
    /// place, `home -> account` is a sheet sliding up off the screen.
    var teardrop = false
    var shadowY: CGFloat = 0
    var shadowRadius: CGFloat = 0
    var shadowColor: Color = .clear
    var z: Double = 0
}

struct OBCircleClip {
    var r: CGFloat
    var x: CGFloat
    var y: CGFloat
}

/// The content box inside a screen — the padded column that carries everything a screen says.
/// It moves independently of the layer, so a screen can slide while its copy settles later.
struct OBContent {
    var opacity: Double = 1
    var offsetY: CGFloat = 0
    var scale: CGFloat = 1
    var anchor: UnitPoint = .center
}

/// The flat colour wash, the growing pill and the plane badge: three overlays shared by every
/// crossing that needs one, so no screen has to own another screen's effect.
struct OBOverlays {
    var veilColor: Color = TColor.cloud100
    var veilOpacity: Double = 0
    var veilZ: Double = 38

    var expandOpacity: Double = 0
    /// Insets from the screen's edges; negative means the rect has grown past them.
    var expandLeft: CGFloat = 0
    var expandTop: CGFloat = 0
    var expandBottom: CGFloat = 0
    var expandRadius: CGFloat = 999
    var expandColor: Color = TColor.copper500

    var planeOpacity: Double = 0
    var planeX: CGFloat = 0
    var planeY: CGFloat = 0
}

/// Everything the frame needs, computed once per tick.
struct OBStyles {
    /// Sized from `OBScreen` itself rather than from a literal. Both of these read `10` for a
    /// long time and a screen added to the enum without also editing them here is an index crash
    /// on the first crossing — which is the whole reason the enum is the one table.
    static let n = OBScreen.allCases.count
    var layers = [OBLayer](repeating: OBLayer(), count: OBStyles.n)
    var contents = [OBContent](repeating: OBContent(), count: OBStyles.n)
    var overlays = OBOverlays()
    /// The arc's own copper dot and halo, hidden the moment the reveal detaches the plane badge.
    var apexOn: Double = 1
    var haloOn: Double = 0.14
    /// Drives the tier cards' deal-in during the last 72% of the hatch crossing.
    var clubT: Double = 0
    var deck = OBDeckState(-1)
    /// −1 unless the cover crossing is live.
    var deckQ: Double = -1

    init(flow: OnboardingFlow, size: CGSize) {
        let w = size.width
        let h = size.height
        let t = flow.t
        let pair = flow.pair

        for k in 0..<Self.n {
            layers[k].hidden = !(k == flow.i && pair < 0)
        }

        deckQ = pair == OBScreen.cover.i ? t : -1
        deck = OBDeckState(deckQ)
        clubT = pair == OBScreen.account.i
            ? TEase.clamp((t - 0.28) / 0.72)
            : (flow.i >= OBScreen.club.i ? 1 : 0)

        // A crossing only ever touches its own two screens, so they are bound once, by name, and
        // every case below reaches for `from` and `to` rather than a page number that a reorder
        // would leave pointing at the wrong screen.
        if let leaving = OBScreen(rawValue: pair), let arriving = leaving.next {
            let from = leaving.i
            let to = arriving.i
            let e = TEase.inOut(t)
            let r = TEase.expo(t)
            let g = TEase.soft(t)
            layers[from].hidden = false
            layers[to].hidden = false

            switch leaving {

            // The deck tears itself apart while the camera pushes into the perforation.
            case .cover:
                let f = TEase.inOut(TEase.clamp((t - 0.5) / 0.5))
                layers[from].anchor = UnitPoint(x: 0.5, y: flow.tearScreenPct / 100)
                layers[from].scale = 1 + 0.6 * f
                layers[from].z = 1
                overlays.veilColor = TColor.cloud100
                overlays.veilOpacity = TEase.inOut(TEase.clamp((t - 0.55) / 0.4))
                overlays.veilZ = 38
                layers[to].opacity = TEase.inOut(TEase.clamp((t - 0.78) / 0.1))
                layers[to].z = 39
                contents[to].anchor = UnitPoint(x: 0.5, y: 0.46)
                contents[to].scale = TEase.lerp(0.68, 1, TEase.out(TEase.clamp((t - 0.77) / 0.23)))
                contents[to].opacity = TEase.out(TEase.clamp((t - 0.78) / 0.1))

            // A circle reveal out of the route's apex, with the plane riding its edge.
            case .earn:
                let ax = flow.apex?.x ?? w / 2
                let ay = flow.apex?.y ?? h * 600 / OBConst.designSize.height
                let radius = TEase.inOut(TEase.clamp(t / 0.96)) * 1180
                layers[from].scale = 1 + 0.05 * e
                layers[from].opacity = 1 - 0.28 * e
                layers[from].z = 1
                layers[to].clip = OBCircleClip(r: radius, x: ax, y: ay)
                layers[to].z = 2
                contents[to].offsetY = 28 * (1 - r)
                contents[to].opacity = TEase.clamp(t * 2.2 - 0.55)
                overlays.planeX = ax + radius
                overlays.planeY = ay
                overlays.planeOpacity = 1
                apexOn = 0
                haloOn = t > 0.12 ? 0 : 0.14

            // The gate rises over spend like a permission sheet — the reference's own pair 4,
            // which is the set-piece it gives this screen. The gate moved forward in the sequence
            // here, so the crossing moved with it rather than staying on an ordinal: it still
            // enters from below, still rounds its top 240pt as it comes, and still throws its
            // shadow up onto the screen sinking behind it.
            case .spend:
                layers[from].scale = 1 - 0.07 * g
                layers[from].offsetY = CGFloat(-30 * g)
                layers[from].dim = 1 - 0.28 * g
                layers[from].z = 1
                layers[to].offsetYFraction = CGFloat(1 - g)
                layers[to].topRadius = CGFloat(240 * (1 - g))
                layers[to].shadowY = -30
                layers[to].shadowRadius = 45
                layers[to].shadowColor = .black.opacity(0.5)
                layers[to].z = 2
                contents[to].offsetY = CGFloat(34 * (1 - g))
                contents[to].opacity = TEase.clamp(t * 2 - 0.5)

            // The screen behind pushes past the camera and a white wash takes the frame, which the
            // list then settles out of. This is the reference's own `spend -> apps` crossing
            // (pair 2), kept on the pair the app list still arrives on: the gate sits in front of
            // it here, so the zoom-through runs on gate -> apps rather than spend -> apps.
            case .gate:
                layers[from].anchor = .center
                layers[from].scale = 1 + 1.9 * e
                layers[from].z = 1
                contents[from].opacity = 1 - TEase.clamp((t - 0.18) / 0.34)
                // Pure white, not `cloud100`: the reference washes this one crossing to #ffffff and
                // every other veil in the sequence to the page ground, and the two are not the same
                // colour. The wash peaks a little past halfway and then falls away again, so the
                // list is never handed a flat white frame to fade up from.
                overlays.veilColor = TColor.white
                overlays.veilOpacity = t < 0.62
                    ? TEase.clamp((t - 0.16) / 0.46)
                    : TEase.clamp((1 - t) / 0.38)
                overlays.veilZ = 38
                layers[to].scale = CGFloat(TEase.lerp(1.06, 1, g))
                layers[to].opacity = TEase.clamp((t - 0.48) / 0.3)
                layers[to].z = 2
                contents[to].offsetY = CGFloat(30 * (1 - TEase.clamp((t - 0.45) / 0.55)))
                contents[to].opacity = TEase.clamp((t - 0.5) / 0.34)

            // The list's Next button expands into the cap screen.
            //
            // **Nothing here may go transparent while the pill is still on its way up.** This is
            // the only crossing in the sequence whose covering ground starts at the *bottom* of
            // the page — the pill grows out of the Next button — and it does not swallow the
            // status bar until t ≈ 0.547 of a 1.2s run. The screen being left used to fade on
            // `opacity` (0 by t = 0.50) while the arriving one only began at t = 0.52, so for the
            // whole of 0.35 → 0.55 the band above the pill had nothing opaque in it — 240pt of
            // the router's `cloud100` at the halfway frame — and the page visibly washed pale and
            // was then swept dark from below. Measured, not guessed. Two things follow:
            //
            //  * `from` sinks on `dim`, not `opacity`, which is what every other covering
            //    crossing in this table already does (`spend`, `cap`, `account`, `club`). A
            //    `colorMultiply` darkens without ever letting the ground behind it through.
            //  * `to` comes up *entirely behind the opaque pill* (0.60 → 0.70, covered from
            //    0.547, and the pill does not begin to fade until 0.74). It can afford to,
            //    because `expandGround(1)` is rgb(35, 57, 91) — `navy700`, the cap screen's own
            //    ground, to the byte. The pill is built to land on the destination's colour, so
            //    once the layer beneath it is opaque the fade-out is a dissolve between two
            //    identical navies and there is nothing left to flicker.
            case .apps:
                let rect = flow.nextButtonRect
                    ?? CGRect(x: 30, y: h - 94, width: max(0, w - 60), height: 60)
                let l0 = rect.minX
                let t0 = rect.minY
                let b0 = h - rect.maxY
                // **No shrink on the screen being left.** `.scaleEffect` moves what is drawn and
                // leaves the layout frame behind, so a layer at 0.96 uncovers a rim of whatever is
                // behind the onboarding stack — the router's `cloud100` — on all four edges. That
                // is 14pt across the top at the frame the pill is still climbing, and `dim` has by
                // then taken the page itself to grey 185, so the rim reads as a *bright* band
                // appearing above a darkening screen: measured at 241,244,249 against 185,185,185
                // one frame before the pill arrives. The pill growing over the page is the whole
                // effect here and it does not need a camera move under it.
                //
                // (The same rim is latent in every crossing in this table that shrinks its `from`.
                // The others cover their edges early — a circle clip reaches the corners in the
                // first half — so it has never surfaced there. Worth remembering if one of them
                // is ever reported.)
                layers[from].dim = 1 - 0.45 * g
                layers[from].z = 1
                layers[to].scale = TEase.lerp(1.05, 1, g)
                layers[to].opacity = TEase.clamp((t - 0.60) / 0.10)
                layers[to].z = 2
                contents[to].offsetY = 28 * (1 - TEase.clamp((t - 0.45) / 0.55))
                contents[to].opacity = TEase.clamp((t - 0.72) / 0.28)
                overlays.expandLeft = CGFloat(TEase.lerp(Double(l0), -300, g))
                overlays.expandTop = CGFloat(TEase.lerp(Double(t0), -300, g))
                overlays.expandBottom = CGFloat(TEase.lerp(Double(b0), -300, g))
                overlays.expandRadius = CGFloat(TEase.lerp(999, 0, TEase.out(t)))
                overlays.expandColor = OBConst.expandGround(TEase.clamp((t - 0.12) / 0.5))
                overlays.expandOpacity = t > 0.74 ? TEase.clamp((1 - t) / 0.26) : 1

            // The wheel blooms open through the cap dial's own copper marker. This is the one
            // crossing with no reference source — `cap` is the screen this app adds — so it is
            // built from the reference's own vocabulary rather than invented: the circle clip and
            // its timings are `account -> club`'s hatch, anchored on a measured rect the way
            // `earn -> spend` anchors on the route's apex. The cap sinks into shadow behind it,
            // the same understory every covering crossing in this sequence gives the screen it
            // leaves. Without the measurement the circle falls back to the marker's design
            // position — x centred, y 72/390 of the width below the dial's own top.
            case .cap where flow.cross == "teardrop":
                // The take this crossing was carrying before the circle: the wheel descends from
                // above, tip leading, and spreads flat as it lands. Kept behind `-tempusCross
                // teardrop` only while the two are being compared — the loser goes, along with
                // `OBLayer.teardrop` and `OBTeardrop` if it is this one.
                layers[from].scale = 1 - 0.06 * g
                layers[from].offsetY = CGFloat(-18 * g)
                layers[from].dim = 1 - 0.34 * g
                layers[from].z = 1
                layers[to].offsetYFraction = CGFloat(-(1 - g))
                layers[to].bottomRadius = CGFloat(240 * (1 - g))
                layers[to].teardrop = true
                layers[to].shadowY = 30
                layers[to].shadowRadius = 45
                layers[to].shadowColor = .black.opacity(0.5)
                layers[to].z = 2
                contents[to].offsetY = CGFloat(46 * (1 - g))
                // Held back until the drop has nearly landed: this layer descends from above, so
                // anything already opaque on it rides down *through* the status bar.
                contents[to].opacity = TEase.clamp(t * 2.6 - 1.3)

            case .cap:
                let cx = flow.dialApex?.x ?? w / 2
                let cy = flow.dialApex?.y ?? h * 604 / OBConst.designSize.height
                layers[from].scale = 1 - 0.05 * g
                layers[from].offsetY = CGFloat(-16 * g)
                layers[from].dim = 1 - 0.5 * g
                layers[from].z = 1
                layers[to].clip = OBCircleClip(
                    r: CGFloat(TEase.inOut(TEase.clamp(t / 0.92)) * 1240),
                    x: cx,
                    y: cy
                )
                layers[to].z = 2
                contents[to].opacity = TEase.clamp(t * 2.4 - 0.4)

            // The wheel slides up and off, and the account is simply there behind it. The leaving
            // screen owns the foreground here — the one crossing in the sequence where `from` sits
            // above `to` — and its bottom corners round as it goes, so it reads as a sheet being
            // pulled away rather than a screen fading out. The reference's pair 5.
            case .home:
                layers[from].offsetYFraction = CGFloat(-g)
                layers[from].bottomRadius = CGFloat(240 * g)
                layers[from].shadowY = 30
                layers[from].shadowRadius = 45
                layers[from].shadowColor = .black.opacity(0.5)
                layers[from].z = 2
                layers[to].scale = CGFloat(TEase.lerp(0.96, 1, g))
                layers[to].z = 1
                contents[to].offsetY = CGFloat(46 * (1 - g))
                contents[to].opacity = TEase.clamp(t * 1.8)

            // The club opens like a hatch: the account sinks into shadow while the tier
            // cards are dealt into the dark through a growing circle.
            case .account:
                layers[from].scale = 1 - 0.05 * g
                layers[from].offsetY = CGFloat(-16 * g)
                layers[from].dim = 1 - 0.5 * g
                layers[from].z = 1
                layers[to].clip = OBCircleClip(
                    r: CGFloat(TEase.inOut(TEase.clamp(t / 0.92)) * 1240),
                    x: w / 2,
                    y: h * 300 / OBConst.designSize.height
                )
                layers[to].z = 2
                contents[to].opacity = TEase.clamp(t * 2.4 - 0.4)

            // The shelf lifts in over the club. Deliberately the same gesture the app itself uses
            // to reach the Concourse — Home's bag opens it with a `.lift` — so the screen that
            // explains the shop arrives the way the shop does. Mechanically it is `spend -> gate`'s
            // sheet: a 240pt top radius rounding off as it rises, a shadow thrown up onto the
            // screen sinking behind it, and a pale ground climbing over a dark one, which is the
            // pairing that crossing was written for.
            case .club:
                layers[from].scale = 1 - 0.07 * g
                layers[from].offsetY = CGFloat(-30 * g)
                layers[from].dim = 1 - 0.28 * g
                layers[from].z = 1
                layers[to].offsetYFraction = CGFloat(1 - g)
                layers[to].topRadius = CGFloat(240 * (1 - g))
                layers[to].shadowY = -30
                layers[to].shadowRadius = 45
                layers[to].shadowColor = .black.opacity(0.5)
                layers[to].z = 2
                contents[to].offsetY = CGFloat(34 * (1 - g))
                contents[to].opacity = TEase.clamp(t * 2 - 0.5)

            // The upgrade is issued like a ticket. The travel runs on the exponential while the
            // radius and the content run on the scene curve, so it arrives early and settles late.
            //
            // **This set-piece belongs to the upgrade's arrival, not to an ordinal.** It was keyed
            // on `club` while the club was the screen before `business`; the Concourse went in
            // between on 21 Sep 2026 and the case moved with the destination rather than staying
            // where it was and playing on the wrong pair. That is the rule this enum exists for.
            case .shop:
                layers[from].scale = 1 - 0.06 * g
                layers[from].offsetY = CGFloat(-18 * g)
                layers[from].dim = 1 - 0.34 * g
                layers[from].z = 1
                layers[to].offsetYFraction = CGFloat(1 - TEase.expo(t))
                layers[to].topRadius = CGFloat(44 * (1 - g))
                layers[to].shadowY = -30
                layers[to].shadowRadius = 45
                layers[to].shadowColor = Color(hex: 0x101d31, opacity: 0.45)
                layers[to].z = 2
                contents[to].offsetY = CGFloat(30 * (1 - g))
                contents[to].opacity = TEase.clamp(t * 2 - 0.4)

            // The last screen has nothing after it — `leaving.next` already ruled this out.
            case .business:
                break
            }
        }

        // The exit. `pair` is −1 throughout, so every screen but `business` stays hidden.
        if flow.exitT >= 0 {
            let x = flow.exitT
            let g = TEase.soft(x)
            let biz = OBScreen.business.i
            layers[biz].hidden = false
            layers[biz].offsetYFraction = CGFloat(-0.44 * g)
            layers[biz].scale = 1 - 0.07 * g
            layers[biz].opacity = 1 - TEase.clamp((x - 0.5) / 0.5)
            layers[biz].z = 2
            contents[biz].opacity = 1 - TEase.clamp((x - 0.2) / 0.5)
            overlays.veilColor = TColor.cloud100
            overlays.veilOpacity = TEase.clamp((x - 0.3) / 0.5)
            overlays.veilZ = 41
        }
    }
}

// MARK: - Applying a layer

extension View {
    /// Draws one onboarding screen with this frame's layer style. Order matters: the circle clip
    /// is in the screen's own untransformed space, so it has to be masked before it is scaled.
    func obLayer(_ s: OBLayer, size: CGSize) -> some View {
        self
            .frame(width: size.width, height: size.height)
            .modifier(OBLayerShape(layer: s))
            .scaleEffect(s.scale, anchor: s.anchor)
            .offset(y: s.offsetY + s.offsetYFraction * size.height)
            .modifier(OBFade(opacity: s.hidden ? 0 : s.opacity))
            .allowsHitTesting(!s.hidden && s.opacity > 0.01)
            .accessibilityHidden(s.hidden)
            .zIndex(s.z)
    }

    /// The padded column inside a screen.
    func obContent(_ s: OBContent) -> some View {
        self
            .scaleEffect(s.scale, anchor: s.anchor)
            .offset(y: s.offsetY)
            .opacity(s.opacity)
    }

    /// Reads a frame in the onboarding's coordinate space, once. Layout here is static, and
    /// measuring repeatedly would feed a transformed rect back into the transform driving it.
    func obMeasure(_ apply: @escaping (CGRect) -> Void) -> some View {
        background(
            GeometryReader { g in
                Color.clear.onAppear { apply(g.frame(in: .named(OBSpace.name))) }
            }
        )
    }
}

enum OBSpace {
    static let name = "onboarding"
}

/// The corner rounding, the sheet shadow and the reveal's circle mask — each applied only when the
/// frame actually asks for it. Nine screens are mounted at all times, and an unconditional
/// `clipShape` + `mask` would cost nine offscreen passes a frame to draw nothing.
struct OBLayerShape: ViewModifier {
    let layer: OBLayer

    func body(content: Content) -> some View {
        rounded(content)
            .modifier(OBDim(dim: layer.dim))
            .modifier(OBCircleMask(clip: layer.clip))
    }

    @ViewBuilder
    private func rounded(_ content: Content) -> some View {
        // `.circular`, against the project's usual `.continuous` — the one place the two are not
        // interchangeable. CSS `border-radius` draws circular arcs, and at the 240pt these
        // crossings ask for on a 393pt-wide sheet a squircle's shoulders run visibly further along
        // the top edge than the reference's do. At the 14–24pt radii everywhere else in the app the
        // two curves are within a pixel of each other, which is why the convention costs nothing
        // there and does cost something here.
        //
        // `bottomRadius` is drawn one of two ways: as a teardrop tip when `teardrop` is
        // set, otherwise as two plain bottom corners — the shape the reference gives a sheet on
        // its way up and off the screen. A layer asking for both a top and a bottom radius would
        // get a square top; no crossing asks.
        // `.shadow` is a filter that pushes down to every leaf (see `TShadow`, Theme/Shadows.swift)
        // — without `.compositingGroup()` first, this would cast the sheet's own drop shadow under
        // every button, label and icon on the whole screen individually rather than once under the
        // flattened sheet, which is what read as stray shadowing smeared across the onboarding chrome.
        if layer.bottomRadius > 0, layer.teardrop {
            content
                .clipShape(OBTeardrop(depth: layer.bottomRadius))
                .compositingGroup()
                .shadow(color: layer.shadowColor, radius: layer.shadowRadius, x: 0, y: layer.shadowY)
        } else if layer.bottomRadius > 0 {
            content
                .clipShape(UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: layer.bottomRadius,
                    bottomTrailingRadius: layer.bottomRadius,
                    topTrailingRadius: 0,
                    style: .circular
                ))
                .compositingGroup()
                .shadow(color: layer.shadowColor, radius: layer.shadowRadius, x: 0, y: layer.shadowY)
        } else if layer.topRadius > 0 {
            content
                .clipShape(UnevenRoundedRectangle(
                    topLeadingRadius: layer.topRadius,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: layer.topRadius,
                    style: .circular
                ))
                .compositingGroup()
                .shadow(color: layer.shadowColor, radius: layer.shadowRadius, x: 0, y: layer.shadowY)
        } else {
            content
        }
    }
}

/// The gate's underside as it lifts: the bottom edge is drawn down into a single point, so the
/// screen leaves the frame as a drip rather than a slab. `depth` is how far the tip hangs below
/// the shoulders — 0 is a flat bottom, and each side is a quarter-ellipse meeting at the tip.
struct OBTeardrop: Shape {
    var depth: CGFloat

    func path(in rect: CGRect) -> Path {
        let shoulder = rect.maxY - min(depth, rect.height)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: shoulder))
        p.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.maxY),
                       control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: shoulder),
                       control: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// Fading a whole screen out over the one behind it. CSS `opacity` on a screen div establishes a
/// stacking context and composites the subtree **once**; SwiftUI's pushes down to every leaf and
/// fades each separately, so a screen's own ground stops hiding what it is painted on top of and
/// the layer underneath bleeds up through it mid-crossing. `compositingGroup` is that stacking
/// context. It costs an offscreen pass, so it is taken only while a layer is actually part-way
/// transparent — at most the two layers of a crossing, and never at rest.
struct OBFade: ViewModifier {
    let opacity: Double

    @ViewBuilder
    func body(content: Content) -> some View {
        if opacity > 0.001, opacity < 0.999 {
            content.compositingGroup().opacity(opacity)
        } else {
            content.opacity(opacity)
        }
    }
}

/// CSS `filter: brightness(k)`, which is a multiply. Applied only when a frame asks for one —
/// ten screens are mounted at all times and an unconditional filter would cost ten passes a frame
/// to change nothing.
struct OBDim: ViewModifier {
    let dim: Double

    @ViewBuilder
    func body(content: Content) -> some View {
        if dim < 1 {
            content.colorMultiply(Color(white: dim))
        } else {
            content
        }
    }
}

struct OBCircleMask: ViewModifier {
    let clip: OBCircleClip?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let c = clip {
            content.mask {
                Circle().frame(width: c.r * 2, height: c.r * 2).position(x: c.x, y: c.y)
            }
        } else {
            content
        }
    }
}

// MARK: - Shared chrome

/// The back chevron. `club` tints it from the tier palette, which is why the colours are
/// parameters rather than a `dark` flag alone.
struct OBBackButton: View {
    var dark: Bool
    var tint: OBTier?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            OBChevron()
                .stroke(tint?.ink ?? (dark ? TColor.cloud100 : TColor.textPrimary),
                        style: StrokeStyle(lineWidth: 2, lineCap: .butt, lineJoin: .miter))
                .frame(width: 14, height: 7)
                .frame(width: 44, height: 44)
                .background(
                    Circle().fill(tint?.chip
                        ?? (dark ? TColor.glassOnDark : Color(hex: 0xeef2f8)))
                )
        }
        .buttonStyle(.plain)
        .animation(.glide(0.52), value: tint?.ink)
        .accessibilityLabel("Back")
    }
}

/// The caret the onboarding back button wears, drawn in its own box.
///
/// It used to be two sides of a square rotated 45°, which produced the right *glyph* and the wrong
/// *position*: rotating a corner about the box centre leaves the ink spanning only the upper half
/// of it, so the caret sat about 3.5pt high inside its 44pt circle, and a stray `.offset(x: 2)` —
/// an optical nudge for the left-pointing chevron the doc comment wrongly claimed this was — put
/// it 2pt right of centre as well. Drawn directly into a 14 × 7 box it fills its own frame, so the
/// circle centres it with no correction at all, and the arm tips stop being sheared on the
/// diagonal by the butt caps.
struct OBChevron: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return p
    }
}

/// Every screen's eyebrow. Note the tracking is 0.18em, wider than the 0.16em every other
/// boarding-pass label in the app uses. Deliberate or not, it is what the reference ships.
struct OBEyebrow: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(TFont.data(.medium, 11))
            .tracking(0.18 * 11)
            .foregroundStyle(color)
            .animation(.glide(0.52), value: color)
    }
}

/// The copper Next button screens 1–6 and 9 all end on.
struct OBPrimaryButton: View {
    let label: String
    var background: Color = TColor.copper500
    var foreground: Color = TColor.white
    var height: CGFloat = 60
    var fontSize: CGFloat = 17
    var shadowAlpha: Double = 1
    var shadowColor: Color?
    var action: () -> Void

    @Environment(\.tpDarkGround) private var onDark

    /// The reference paints this shadow in the button's own colour — `boxShadow: '0 12px 28px
    /// -16px ' + th.btn` — so it follows a themed button instead of staying copper on a screen
    /// whose button is not.
    ///
    /// That only works on a light ground. On the dark screens the button's own colour is
    /// *lighter* than the page, so painting the shadow in it lit a copper halo around every Next
    /// button instead of dropping one. On dark the tint goes to ink, like every other shadow.
    private var shadowTint: Color {
        if let shadowColor { return shadowColor }
        return onDark ? Color(hex: 0x070d17, opacity: 0.5 * shadowAlpha)
                      : background.opacity(shadowAlpha)
    }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(TFont.core(.semibold, fontSize))
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                // The fill is painted on the *button* below, not in here — so without this the
                // label `.plain` hit-tests is a bare `Text`, and only the glyphs of the word are
                // live. Every Next button in onboarding is this view: tapping the pill anywhere
                // but directly on its letters did nothing, which is why they needed tapping twice.
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        // The fill sits **outside** the button's label, not inside it. `.plain` dims what it is
        // given while the press is held, and a capsule inside the label is part of that — so the
        // pill went translucent under the finger and the blurred halo behind it came up through
        // the middle, a bright soft-edged patch in the centre of what should be one flat copper.
        // Outside, only the text dims, which is the affordance that was wanted in the first place.
        .background(Capsule().fill(background))
        // `0 12px 28px -16px`. The spread is the whole character of this shadow and SwiftUI has
        // none: cast from the full capsule it blooms outward on every side, a copper halo the
        // reference cannot draw, because there the shape is inset 16pt and so sits almost
        // entirely behind the opaque button — only the rim below it shows. Inset the shape and
        // the halo goes with it, which is why this is a `.background` and not a `.shadow`.
        .background {
            Capsule()
                .fill(shadowTint)
                .padding(16)
                .shadow(color: shadowTint, radius: 14, x: 0, y: 12)
        }
        // Same reason `OBFade` carries one: callers fade this button when there is nothing to buy,
        // and an ungrouped `.opacity` fades the halo and the pill separately, so the halo shows
        // through its own button. Grouped, the two fade as one picture. See CLAUDE.md.
        .compositingGroup()
        .animation(.glide(0.52), value: background)
    }
}

/// A quieter button on a dark ground: the gate's "Not now", `business`'s
/// "Stay in economy".
struct OBGhostButton: View {
    let label: String
    var height: CGFloat = 48
    var fontSize: CGFloat = 15
    var fill: Color = Color(hex: 0xf2f5fa, opacity: 0.1)
    var foreground: Color = TColor.textOnDarkMuted
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(TFont.core(.medium, fontSize))
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(Capsule().fill(fill))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - The cover pass

/// One document, issued by whichever livery the deck drew. Same shape, same fields, same
/// placement every time — only the header band changes.
///
/// The route is hard-coded `Sydney / SYD → Anywhere / ANY`: nothing has been picked yet at this
/// point in the sequence, so there is nothing honest to put there.
struct OBCoverPass: View {
    let livery: Carriers.Livery

    var body: some View {
        VStack(spacing: 0) {
            CarrierBandView(livery: livery, crop: true)
                .frame(height: 113)
                .clipped()

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(Carriers.name)
                        .font(TFont.core(.semibold, 16))
                        .tracking(-0.01 * 16)
                        .foregroundStyle(TColor.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(Carriers.iata)
                        .font(TFont.data(.medium, 10))
                        .tracking(0.16 * 10)
                        .foregroundStyle(TColor.textMuted)
                }

                HStack(alignment: .bottom, spacing: 0) {
                    endpoint("Sydney", "SYD", alignment: .leading)
                    Spacer(minLength: 0)
                    // **An arrow, like every other boarding pass in this app.** This was
                    // `OBPlaneGlyph`, an eight-point polygon meant to read as a paper plane; at
                    // the 20pt it is drawn at, the two wing points collapse into each other and it
                    // comes out as an angular hook that reads as a stray mark rather than as an
                    // aircraft — which is exactly how it was reported. Nothing else needed it:
                    // `BoardingPass` and `PassArchiveCard` both set a plain "\u{2192}" in
                    // `sky400` between the two codes, so the one pass that opens the app was also
                    // the only one drawing something else there. Same glyph, same tint, sized
                    // between their 20 and 15.
                    Text(verbatim: "\u{2192}")
                        .font(TFont.core(.regular, 18))
                        .foregroundStyle(TColor.sky400)
                        .padding(.bottom, 8)
                    Spacer(minLength: 0)
                    endpoint("Anywhere", "ANY", alignment: .trailing)
                }
                .padding(.top, 22)

                OBRule()
                    .padding(.top, 20)
                Text("PASSENGER")
                    .font(TFont.data(.medium, 9))
                    .tracking(0.14 * 9)
                    .foregroundStyle(TColor.textMuted)
                    .padding(.top, 16)
                Text("You")
                    .font(TFont.core(.semibold, 19))
                    .tracking(-0.02 * 19)
                    .foregroundStyle(TColor.textPrimary)
                    .padding(.top, 8)

                OBRule()
                    .padding(.top, 16)
                HStack(alignment: .top, spacing: 0) {
                    field("FIRST FLIGHT", "\(OBConst.demoMinutes) min", TColor.textPrimary, .leading)
                    Spacer(minLength: 0)
                    field("EARNS", "\(OBConst.demoEarn) mi", TColor.textAccent, .trailing)
                }
                .padding(.top, 16)
                .padding(.bottom, 20)
            }
            .padding(.horizontal, 22)
            .padding(.top, 20)
        }
        .background(TColor.white)
    }

    private func endpoint(_ city: String, _ code: String, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 0) {
            Text(city)
                .font(TFont.core(.regular, 11))
                .foregroundStyle(TColor.textMuted)
            Text(code)
                .font(TFont.core(.bold, 38))
                .tracking(-0.045 * 38)
                .foregroundStyle(TColor.textPrimary)
                .padding(.top, 7)
        }
    }

    private func field(_ label: String, _ value: String, _ tint: Color,
                       _ alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 0) {
            Text(label)
                .font(TFont.data(.medium, 9))
                .tracking(0.14 * 9)
                .foregroundStyle(TColor.textMuted)
            Text(value)
                .font(TFont.core(.semibold, 15))
                .foregroundStyle(tint)
                .padding(.top, 8)
        }
    }
}

/// The hairline that separates a pass's blocks.
struct OBRule: View {
    var body: some View {
        Rectangle().fill(Color(hex: 0xeef2f8)).frame(height: 1)
    }
}
/// The copper badge that rides the reveal's edge on the 1 ⇄ 2 crossing, so the new screen looks
/// dragged open by the plane that was sitting on the route.
struct OBPlaneBadge: View {
    var body: some View {
        Circle()
            .fill(TColor.copper500)
            .frame(width: 26, height: 26)
            .overlay(OBBadgePlane().fill(TColor.white).frame(width: 26, height: 26))
            // `0 12px 30px -6px`: 15 of blur less 3 of spread. Grouped first so the shadow falls
            // once under the flattened badge, not separately under the circle and the glyph it
            // overlays.
            .compositingGroup()
            .shadow(color: Color(hex: 0xb86f52, opacity: 0.62), radius: 15, x: 0, y: 12)
    }
}

struct OBBadgePlane: Shape {
    func path(in rect: CGRect) -> Path {
        let k = rect.width / 26
        var p = Path()
        p.move(to: CGPoint(x: 9 * k, y: 8 * k))
        p.addLine(to: CGPoint(x: 20 * k, y: 13 * k))
        p.addLine(to: CGPoint(x: 9 * k, y: 18 * k))
        p.addLine(to: CGPoint(x: 11.6 * k, y: 13 * k))
        p.closeSubpath()
        return p
    }
}

// MARK: - `earn`'s route

/// The route diagram: a dotted great circle with its first half flown in copper, a time ruler
/// under it, and the copper apex the next crossing grows out of.
///
/// Authored on 390 × 330 and scaled to the width it is given. `SYD → SIN` and "25 min in" are
/// hard-coded — this is an illustration, not the reader's own route.
struct OBRouteArc: View {
    let apexOn: Double
    let haloOn: Double
    /// Reports where the copper apex ended up, so the reveal can start from it.
    let onApex: (CGPoint) -> Void

    private static let copper = TColor.copper500

    var body: some View {
        GeometryReader { geo in
            let k = geo.size.width / 390
            ZStack(alignment: .topLeading) {
                Color.clear
                canvas
                    .frame(width: 390, height: 330)
                    .scaleEffect(k, anchor: .topLeading)
                    .frame(width: geo.size.width, height: 330 * k, alignment: .topLeading)
            }
            .obMeasure { r in onApex(CGPoint(x: r.minX + 195 * k, y: r.minY + 90 * k)) }
        }
        .frame(height: 330)
        .clipped()
    }

    private var canvas: some View {
        ZStack(alignment: .topLeading) {
            // The whole route, dotted.
            OBArcPath(full: true)
                .stroke(Color(hex: 0xd5dfec),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [2, 7]))
            // The area under the flown half.
            OBArcArea()
                .fill(LinearGradient(
                    colors: [Self.copper.opacity(0.16), Self.copper.opacity(0)],
                    startPoint: .top, endPoint: .bottom))
            // The flown half.
            OBArcPath(full: false)
                .stroke(LinearGradient(
                    colors: [Self.copper.opacity(0.25), Self.copper],
                    startPoint: .bottomLeading, endPoint: .topTrailing),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round))

            OBArcTicks()
                .stroke(Color(hex: 0xc3d1e4),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round))
            OBArcNow()
                .stroke(Self.copper, style: StrokeStyle(lineWidth: 3, lineCap: .round))

            Circle().fill(TColor.textPrimary).frame(width: 11, height: 11)
                .position(x: 34, y: 244)
            Circle().fill(Color(hex: 0xc3d1e4)).frame(width: 10, height: 10)
                .position(x: 356, y: 244)
            Circle().fill(Self.copper).frame(width: 42, height: 42)
                .opacity(haloOn)
                .position(x: 195, y: 90)
            Circle().fill(Self.copper).frame(width: 26, height: 26)
                .opacity(apexOn)
                .position(x: 195, y: 90)
            OBBadgePlane().fill(TColor.white).frame(width: 26, height: 26)
                .opacity(apexOn)
                .position(x: 195, y: 90)

            label("SYD", x: 34, baseline: 268)
            label("SIN", x: 356, baseline: 268)
            Text("25 min in")
                .font(TFont.core(.semibold, 15))
                .foregroundStyle(TColor.textPrimary)
                .position(x: 195, y: 54 - 5)
        }
        .frame(width: 390, height: 330)
    }

    private func label(_ s: String, x: CGFloat, baseline: CGFloat) -> some View {
        Text(s)
            .font(TFont.data(.regular, 11))
            .tracking(1.5)
            .foregroundStyle(TColor.textMuted)
            .position(x: x, y: baseline - 4)
    }
}

struct OBArcPath: Shape {
    /// The dotted line runs the whole way; the copper stroke stops at the apex.
    let full: Bool

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 34, y: 244))
        p.addCurve(to: CGPoint(x: 195, y: 90),
                   control1: CGPoint(x: 120, y: 244), control2: CGPoint(x: 128, y: 90))
        if full {
            p.addCurve(to: CGPoint(x: 356, y: 244),
                       control1: CGPoint(x: 262, y: 90), control2: CGPoint(x: 270, y: 244))
        }
        return p
    }
}

struct OBArcArea: Shape {
    func path(in rect: CGRect) -> Path {
        var p = OBArcPath(full: false).path(in: rect)
        p.addLine(to: CGPoint(x: 195, y: 244))
        p.closeSubpath()
        return p
    }
}

/// The time ruler under the route. Uneven lengths, exactly as authored.
struct OBArcTicks: Shape {
    private static let ticks: [(CGFloat, CGFloat)] = [
        (34, 294), (74, 296), (114, 294), (154, 298),
        (235, 298), (275, 294), (315, 296), (355, 294)
    ]

    func path(in rect: CGRect) -> Path {
        var p = Path()
        for (x, bottom) in Self.ticks {
            p.move(to: CGPoint(x: x, y: 286))
            p.addLine(to: CGPoint(x: x, y: bottom))
        }
        return p
    }
}

struct OBArcNow: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 195, y: 282))
        p.addLine(to: CGPoint(x: 195, y: 304))
        return p
    }
}

// MARK: - The airport wheel

/// The onboarding's airport picker. An iOS-style wheel: it tracks the finger with no transition at
/// all, then glide-settles over 380 ms when let go.
///
/// It deliberately has **no tap-to-select** — the reference's onboarding wheel takes the drag and
/// the scroll only, and the selection is read straight off the position rather than called back.
struct OBWheel: View {
    @Bindable var flow: OnboardingFlow

    private static let rowHeight = OBConst.wheelRow

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(TColor.surfaceSunken)
                .frame(height: Self.rowHeight)

            ForEach(Array(OBConst.airports.enumerated()), id: \.element.code) { k, ap in
                let live = Double(k) - flow.wPos
                let a = abs(live)
                if a <= 3.4 {
                    row(ap, live: live, a: a)
                }
            }

            VStack(spacing: 0) {
                LinearGradient(colors: [TColor.cloud100, TColor.cloud100.opacity(0)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 72)
                Spacer(minLength: 0)
                LinearGradient(colors: [TColor.cloud100.opacity(0), TColor.cloud100],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 72)
            }
            .allowsHitTesting(false)
        }
        .frame(height: 270)
        .clipped()
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in flow.wheelChanged(v.translation.height, at: v.time) }
                .onEnded { _ in flow.wheelEnded() }
        )
        .accessibilityElement()
        .accessibilityLabel("Home airport")
        .accessibilityValue(OBConst.airports[flow.pickedAirportIndex].city)
        .accessibilityAdjustableAction { direction in
            flow.wheelSettle(flow.pickedAirportIndex + (direction == .increment ? 1 : -1))
        }
    }

    private func row(_ ap: (city: String, code: String), live: Double, a: Double) -> some View {
        let selected = a < 0.5
        return HStack {
            Text(ap.city)
                .font(TFont.core(selected ? .semibold : .regular, selected ? 22 : 21))
                .tracking(-0.02 * (selected ? 22 : 21))
                .foregroundStyle(selected ? TColor.textPrimary : TColor.textSecondary)
            Spacer(minLength: 0)
            Text(ap.code)
                .font(TFont.data(.medium, 13))
                .tracking(0.1 * 13)
                .foregroundStyle(selected ? TColor.textAccent : TColor.textMuted)
        }
        .padding(.horizontal, 22)
        .frame(height: Self.rowHeight)
        .opacity(max(0.14, 1 - a * 0.28))
        // `perspective` approximates the reference's CSS `perspective: 820px` on the container.
        .rotation3DEffect(.degrees(-live * 17), axis: (x: 1, y: 0, z: 0), perspective: 0.4)
        .scaleEffect(1 - min(0.3, a * 0.07))
        .offset(y: CGFloat(live) * Self.rowHeight)
    }
}

// MARK: - The tier card
