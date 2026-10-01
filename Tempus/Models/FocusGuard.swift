// Cabin discipline. Once a flight is in the air, leaving the app or picking the phone up costs
// you a chance; run out and the flight diverts, which pays nothing. Every interruption buzzes,
// then asks for the phone back on the table and counts five seconds down before the flight
// carries on. The clock never stops for any of it. That is economy's rule.
//
// **Business class gets none of it.** One lapse — leaving the app, or moving the phone, of any
// kind — ends the flight on the spot and forfeits every mile of it. No chances, no settle
// window, no second look. `flightBegan(canDivert: false)` is how `AppModel` says a flight is
// business class, and it works by forcing `chances` to 0: the very first lapse then takes
// `strike()`'s ordinary "ran out of chances" branch, the same one economy's *third* strike
// takes, and ends the flight through the same `onDiverted()` call. There is no separate
// "locked cabin" machinery left to keep in step with it — one path proves both rules.
//
// **Addition, not a port**, like the haptics it uses: the reference is a web page with no
// accelerometer and no notion of a phone being picked up at all.
//
// The accelerometer is the only sensor involved: |‖a‖ − 1g| is ~0 on a table and spikes the
// moment a hand lifts the phone. Where there is no accelerometer — the simulator, and so every
// flow walked without a device — a timer feeds the same machine a permanently still phone, so
// there is one input path rather than two and interruptions still settle.
import Foundation
import Observation
import CoreMotion

/// Why a flight was interrupted. The raw value is the line the overlay shows, so it stays a
/// statement of what happened — never a scolding.
enum Interruption: String {
    case left = "You left the app"
    case lifted = "You picked your phone up"
}

@Observable
final class FocusGuard {
    /// What went wrong, or nil when the flight is simply flying. Non-nil puts the settle overlay
    /// on screen.
    private(set) var interruption: Interruption?
    /// Seconds left before the flight resumes. Nil while the phone is still moving — the count
    /// only runs once it is lying still.
    private(set) var countdown: Int?
    /// Chances spent this flight. Diverts once it passes `chances`.
    private(set) var strikes = 0
    private(set) var chances = 2
    /// Whether this flight gets any chances at all before a lapse ends it.
    ///
    /// True for economy: two chances, each with its five-second settle. False for business
    /// class, and — since the rule changed — false no longer means "never diverts". It used to:
    /// the guard watched, asked for the phone back, and only the emergency exit could end the
    /// flight, on the theory that diverting was the cheap way out business class was meant to
    /// remove. The member asked for the opposite — one lapse of any kind should forfeit the
    /// whole flight, immediately — so `flightBegan` now reads this the other way: `canDivert ==
    /// false` forces `chances` to 0, which makes the very first lapse run out of chances on the
    /// spot. The stored name still matches the parameter `AppModel` calls it with
    /// (`focusGuard.flightBegan(canDivert: !biz)`); only what `false` does to the flight changed.
    private(set) var canDivert = true

    /// True exactly for business class — the boolean itself did not change, only what it costs
    /// to trip it. Kept for the two screens that ask "is this cabin locked": what they see is
    /// still correct (this is still the harsher of the two regimes), even though "locked" now
    /// undersells it — the cabin does not just resist leaving, it ends the flight the moment you
    /// try.
    var locksCabin: Bool { !canDivert }
    /// True between `flightBegan` and `flightEnded`. Also what makes a second `flightBegan`
    /// a no-op, so extending a flight — which restarts the clock — never hands back a spent chance.
    private(set) var running = false

    /// The last sample and the largest seen since sensing started, both in g away from rest. Only
    /// the developer panel reads them; they exist so a threshold can be set against what this
    /// phone on this desk actually reports rather than against the model the defaults came from.
    private(set) var lastJolt: Double = 0
    private(set) var peakJolt: Double = 0
    /// Sensing with no flight attached: samples feed the readout and the still/move counters, and
    /// `strike` is never reached. What makes "does a shake trip it" answerable without departing.
    private(set) var tuning = false
    /// Whether the readout is coming from a real accelerometer. False in the simulator, where the
    /// pretender feeds a permanently still phone and no threshold can be judged at all.
    var sensorAvailable: Bool { motion.isAccelerometerAvailable }
    /// What the machine would do with the counters as they stand — the panel's live verdict.
    var armedNow: Bool { armed }
    var stillRun: Int { stillSamples }
    var movingRun: Int { movingSamples }

    var chancesLeft: Int { max(0, chances - strikes) }

    /// Wired to `AppModel.divert()`. Fires when the last chance is gone.
    var onDiverted: () -> Void = {}

    /// Fires on every strike that does *not* end the flight, so the spent chance reaches the disk
    /// before the process can. Without it, swiping the app out of the switcher handed economy its
    /// two chances back: the strike is counted on the way out, but `strikes` lived only in memory,
    /// and the relaunch restored the flight and called `flightBegan` fresh. Leaving the app has to
    /// cost the same whether you come back through the switcher or from a cold launch.
    var onStrike: () -> Void = {}

    // Sampled at 20Hz; the thresholds are in g away from rest (|‖a‖ − 1g|).
    //
    // **Revised after device testing.** The original pair (0.035 / 0.16) was calibrated against
    // a model of a resting iPhone, not against a real pickup: 0.16g held for the full
    // `moveSamples` window turned out to demand something close to a shake — an ordinary lift or
    // a tilt off the desk peaks well past 0.16g for a sample or two but does not *sustain* it,
    // so the run of consecutive samples kept resetting before it ever reached the threshold
    // count, and only a deliberately vigorous motion held long enough to register. The first
    // pass lowered `moveJolt` to 0.05g and the window to four samples, but a second device pass
    // on 18 Sep 2026 still needed too vigorous a pickup. It now drops to 0.035g — still roughly
    // 3× the ~0.01g resting noise floor, but a gentle lift holds it — for three consecutive
    // samples (0.15s at 20Hz), so the gesture registers before its acceleration tails off.
    //
    // `stillJolt` stays at the first pass's 0.015g: the 0.015–0.035g dead band still keeps the
    // thresholds more than 2× apart, so lowering the pickup gate does not change what arms it.
    // 0.015g is still well clear of desk vibration transmitted from something like nearby
    // typing — that vibration is a small fraction of a g by the time it reaches the phone
    // through the table — so a phone that is genuinely sitting still keeps reading as still (or
    // at worst falls into the dead band, which costs nothing either way) rather than drifting
    // into `moveJolt`'s count.
    //
    // **Tunable, and they have to be.** The numbers above came from a model of a phone on a desk,
    // not from a phone on *your* desk: a case, a soft surface, a wobbly table and a heavier phone
    // all move the noise floor, and a threshold that is wrong in either direction is either a
    // guard that never fires or one that diverts a flight because a bus went past. The developer
    // panel reads the live jolt and writes these two, so they can be set against the real thing
    // rather than guessed. Defaults are restored by `resetThresholds()`.
    //
    // **Third device pass, 20 Sep 2026: back up to 0.05g.** At 0.035g the guard tripped on
    // movement *of the desk* — a nudge to the table, a laptop set down beside the phone — which
    // is not the gesture it exists to catch. 0.05g with the three-sample window is the middle of
    // the two earlier passes: a lift still holds it, a bumped table does not.
    static let stillJoltDefault = 0.015    // a phone on a table reads well under this
    static let moveJoltDefault = 0.05      // a gentle lift or tilt reads over, and holds it

    private static let stillKey = "tempus.guard.stillJolt"
    private static let moveKey = "tempus.guard.moveJolt"

    static var stillJolt: Double {
        get { UserDefaults.standard.object(forKey: stillKey) as? Double ?? stillJoltDefault }
        set { UserDefaults.standard.set(newValue, forKey: stillKey) }
    }
    static var moveJolt: Double {
        get { UserDefaults.standard.object(forKey: moveKey) as? Double ?? moveJoltDefault }
        set { UserDefaults.standard.set(newValue, forKey: moveKey) }
    }

    static func resetThresholds() {
        UserDefaults.standard.removeObject(forKey: stillKey)
        UserDefaults.standard.removeObject(forKey: moveKey)
    }
    // Sampled at 20Hz, so these are half-second and 0.15-second windows respectively.
    static let settleSamples = 10  // 0.5s of stillness before anything counts
    // Dropped again, from 4 to 3, in the second device pass on 18 Sep 2026: a gentle lift holds
    // the new 0.035g gate for 0.15s at 20Hz without needing the extra shove. Three consecutive
    // samples still reject a single stray spike; the dead band keeps resting noise out.
    static let moveSamples = 3     // 0.15s of movement is a pickup, not a tap
    // Now the same window as moveSamples: moving again stops the wait promptly, without costing
    // another chance for the same lapse.
    static let cancelSamples = 3

    private let motion = CMMotionManager()
    private var pretender: Timer?          // stands in for a missing accelerometer
    private var ticker: Timer?
    private var stillSamples = 0
    private var movingSamples = 0
    /// The phone has been put down at least once, so a pickup means something. Departing leaves it
    /// in your hand — striking then would divert the flight before it started.
    private var armed = false

    // MARK: - Flight lifecycle

    /// `spent` is the chances already taken by this same flight, for a flight resumed after the
    /// app was killed — a fresh flight passes 0 and a relaunched one passes what it had spent.
    func flightBegan(chances: Int = 2, canDivert: Bool = true, spent: Int = 0) {
        guard !running else { return }
        stopTuning()
        running = true
        // Business class is zero tolerance: force the chance count to 0 so `strike()`'s existing
        // "ran out of chances" branch — the one that ends the flight with no settle overlay —
        // fires on the very first lapse instead of the third. See the file header.
        self.chances = canDivert ? chances : 0
        self.canDivert = canDivert
        strikes = max(0, spent)
        interruption = nil
        armed = false
        stillSamples = 0
        movingSamples = 0
        cancelCountdown()
        startSensing()
    }

    private func startSensing() {
        guard !motion.isAccelerometerActive, pretender == nil else { return }
        lastJolt = 0
        peakJolt = 0
        if motion.isAccelerometerAvailable {
            motion.accelerometerUpdateInterval = 0.05
            motion.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
                guard let self, let a = data?.acceleration else { return }
                self.sample(jolt: abs((a.x * a.x + a.y * a.y + a.z * a.z).squareRoot() - 1))
            }
        } else {
            // No sensor: a phone that is always still. Pickups cannot happen, app-exits still do,
            // and an interruption settles as soon as it appears.
            pretender = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                self?.sample(jolt: 0)
            }
        }
    }

    // MARK: - Tuning

    /// Run the sensor with no flight attached, so the developer panel can show what this phone
    /// reports and whether the counters trip — without a flight to divert while finding out.
    func startTuning() {
        guard !running, !tuning else { return }
        tuning = true
        armed = false
        stillSamples = 0
        movingSamples = 0
        startSensing()
    }

    func stopTuning() {
        guard tuning else { return }
        tuning = false
        stopSensing()
        lastJolt = 0
        peakJolt = 0
    }

    func flightEnded() {
        running = false
        stopSensing()
        cancelCountdown()
        interruption = nil
    }

    /// The device was shaken. Unambiguous by construction, so unlike a pickup it does not wait for
    /// the guard to have armed — a phone that was never put down can still be shaken on purpose,
    /// and somebody testing the guard should not have to learn about an arming window first.
    ///
    /// It goes through `strike`, so it costs a chance in economy, asks for the phone back in a
    /// locked cabin, and cannot do either once an interruption is already on screen.
    func shaken() {
        guard running else { return }
        armed = true
        strike(.lifted)
    }

    /// Put a lapse on screen without one having happened, for the settle-overlay launch seam and
    /// the developer panel. Goes through the real `strike`, so what it shows is the real thing.
    func simulateLapse(_ why: Interruption = .lifted) {
        guard running else { return }
        armed = true
        strike(why)
    }

    /// Leaving the app runs exactly the same lapse `shaken()` does — a strike, however the phone
    /// happened to be sitting the instant it backgrounded.
    ///
    /// **Used to spare a phone lying dead still** (auto-lock, or any backgrounding the
    /// accelerometer caught at a resting instant), on the theory that iOS hands out no event that
    /// says "the screen locked" — auto-lock, the side button and a deliberate app-switch all
    /// arrive as the same background transition — so a still phone was assumed to be one nobody
    /// touched. That assumption was also the loophole: a deliberate app-switch made with the phone
    /// left flat on the desk is caught at the same still instant and cost nothing either way.
    /// Device testing on 18 Sep 2026 called that unacceptable — leaving the app must cost the same
    /// as picking the phone up, full stop — so the leniency is gone and every background transition
    /// strikes now, indistinguishable from a deliberate exit or not.
    ///
    /// **The accepted cost:** a phone that locks itself while lying still on the desk mid-flight now
    /// spends a chance too (a fatal one, in a locked cabin) for a screen timing out on its own. A
    /// member who wants to avoid that keeps the screen awake or extends Auto-Lock for the flight's
    /// length — a setting they control, unlike the accelerometer's guess at what backgrounded the
    /// app.
    func leftApp() {
        guard running else { return }
        strike(.left)
    }

    private func stopSensing() {
        if motion.isAccelerometerActive { motion.stopAccelerometerUpdates() }
        pretender?.invalidate()
        pretender = nil
    }

    // MARK: - The state machine

    /// One accelerometer sample, as distance from rest in g. Split out from the motion callback so
    /// the self-check can drive it with a synthetic sequence.
    ///
    /// Guarded on `running`: CoreMotion can hand the main queue one more sample after
    /// `stopAccelerometerUpdates()` has already been called (the stop takes effect for *future*
    /// updates, not one already queued), and that straggler must not resurrect a guard for a
    /// flight that has already landed, diverted, or was never started at all — which is also the
    /// whole of what keeps a business-class flight (never given a `flightBegan()`) immune.
    func sample(jolt: Double) {
        guard running || tuning else { return }
        lastJolt = jolt
        peakJolt = Swift.max(peakJolt, jolt)
        stillSamples = jolt < Self.stillJolt ? stillSamples + 1 : 0
        movingSamples = jolt > Self.moveJolt ? movingSamples + 1 : 0

        // Tuning drives the same counters so the panel's arm/trip readout is the real machine,
        // and stops one line short of the only thing that costs anything.
        if tuning {
            if armed {
                if movingSamples >= Self.moveSamples { armed = false; movingSamples = 0; Haptics.warned() }
            } else if stillSamples >= Self.settleSamples {
                armed = true
            }
            return
        }

        if interruption != nil {
            // Moving again during the count means the phone is back in a hand: stop counting and
            // wait for it to be put down. It does not cost a second chance.
            if movingSamples >= Self.cancelSamples {
                cancelCountdown()
            } else if countdown == nil, stillSamples >= Self.settleSamples {
                beginCountdown()
            }
            return
        }
        guard armed else {
            if stillSamples >= Self.settleSamples { armed = true }
            return
        }
        if movingSamples >= Self.moveSamples { strike(.lifted) }
    }

    /// Spend a chance. Already showing an interruption means this one is part of the same lapse —
    /// one strike per interruption, however long it goes on. `running` is checked again here, not
    /// just at the call sites, so this is the one place a straggling signal can never divert a
    /// flight twice — whichever of `leftApp()` or a queued `sample()` gets there second finds the
    /// gate already shut.
    private func strike(_ why: Interruption) {
        guard running, interruption == nil else { return }
        stillSamples = 0
        movingSamples = 0
        // Business class needs no branch here: `flightBegan` already forced `chances` to 0 for
        // it, so this is the same "ran out of chances" check economy uses — it just always fires
        // on business class's first strike instead of its third.
        strikes += 1
        guard strikes <= chances else {
            Haptics.failed()
            running = false
            stopSensing()
            cancelCountdown()
            onDiverted()
            return
        }
        Haptics.warned()
        interruption = why
        onStrike()
    }

    // MARK: - The five second settle

    private func beginCountdown() {
        countdown = 5
        Haptics.tick(1)
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, let n = self.countdown else { return }
            if n <= 1 {
                self.resume()
            } else {
                self.countdown = n - 1
                Haptics.tick(1)
            }
        }
    }

    private func cancelCountdown() {
        ticker?.invalidate()
        ticker = nil
        countdown = nil
    }

    private func resume() {
        cancelCountdown()
        interruption = nil
        armed = true
        stillSamples = 0
        movingSamples = 0
        Haptics.resumed()
    }

    #if DEBUG
    /// Test-only: completes the settle instantly instead of waiting on the real one-second ticker,
    /// so the self-check can chain several lapses without idling five real seconds per one.
    func forceSettle() { resume() }
    #endif
}

// MARK: - Self-check

#if DEBUG
/// The sample→state machine is the part with an adversary: arming late enough that departing
/// doesn't strike, a pickup that isn't a screen tap, and a count that only runs while the phone is
/// actually still. Deterministic on device and simulator alike — every sample here is synthetic,
/// and the timers only fire after this has returned.

/// Business class: zero tolerance. One lapse of any kind ends the flight immediately, with no
/// settle overlay ever shown, and pays nothing — the same `onDiverted()` call economy's third
/// strike makes, just reached on the first.
func businessClassSelfCheck() {
    Haptics.muted = true
    defer { Haptics.muted = false }

    let tunedStill = FocusGuard.stillJolt, tunedMove = FocusGuard.moveJolt
    FocusGuard.stillJolt = FocusGuard.stillJoltDefault
    FocusGuard.moveJolt = FocusGuard.moveJoltDefault
    defer {
        FocusGuard.stillJolt = tunedStill
        FocusGuard.moveJolt = tunedMove
    }

    // A pickup ends it on the spot.
    do {
        var diverted = false
        let g = FocusGuard()
        g.onDiverted = { diverted = true }
        g.flightBegan(canDivert: false)
        defer { g.flightEnded() }

        assert(g.locksCabin, "a cabin that cannot divert should read as locked")
        assert(g.chances == 0, "business class should be given no chances at all")

        for _ in 0..<FocusGuard.settleSamples { g.sample(jolt: 0) }   // arm it
        for _ in 0..<FocusGuard.moveSamples { g.sample(jolt: 0.5) }   // pick it up
        assert(diverted, "a pickup in business class did not end the flight")
        assert(!g.running, "a diverted business flight is still marked running")
        assert(g.interruption == nil,
               "business class showed a settle overlay it should never reach")
        assert(g.strikes == 1, "business class should record exactly the one, fatal strike")
    }

    // Leaving the app ends it too, even while the phone is lying dead still — the same as economy
    // now that `leftApp()` no longer forgives a still phone either. See the comment on
    // `leftApp()`: every background transition strikes, business or economy, because the member
    // asked for "leaving the app even once".
    do {
        var diverted = false
        let g = FocusGuard()
        g.onDiverted = { diverted = true }
        g.flightBegan(canDivert: false)
        defer { g.flightEnded() }

        for _ in 0..<FocusGuard.settleSamples { g.sample(jolt: 0) }   // resting, dead still
        g.leftApp()
        assert(diverted, "leaving the app while resting still did not end a business flight")
    }

    // A shake goes through `strike()` too, and does not wait to be armed — same as economy.
    do {
        var diverted = false
        let g = FocusGuard()
        g.onDiverted = { diverted = true }
        g.flightBegan(canDivert: false)
        defer { g.flightEnded() }

        g.shaken()
        assert(diverted, "a shake did not end a business flight")
    }
}

func focusGuardSelfCheck() {
    let still = 0.0, moving = 0.5
    Haptics.muted = true
    defer { Haptics.muted = false }

    // The assertions below are written against the *default* thresholds — 0.03 sits in the dead
    // band only while still is 0.015 and moving is 0.035. Those two are tunable now, so a member
    // who moved them would otherwise trap the app on its next debug launch for no reason at all.
    // The check runs on the defaults and hands the tuned values straight back.
    let tunedStill = FocusGuard.stillJolt, tunedMove = FocusGuard.moveJolt
    FocusGuard.stillJolt = FocusGuard.stillJoltDefault
    FocusGuard.moveJolt = FocusGuard.moveJoltDefault
    defer {
        FocusGuard.stillJolt = tunedStill
        FocusGuard.moveJolt = tunedMove
    }

    let g = FocusGuard()
    g.flightBegan()
    defer { g.flightEnded() }

    // Departing leaves the phone in your hand: movement before it has ever been still is the tear
    // gesture and the walk to a desk, not a lapse.
    for _ in 0..<20 { g.sample(jolt: moving) }
    assert(g.strikes == 0, "moved before the phone was ever put down and it struck")

    // Put it down. A phone left alone on a desk — sensor noise, a passing truck, a closing door —
    // must never strike, however long it sits there.
    for _ in 0..<100 { g.sample(jolt: still) }
    assert(g.strikes == 0, "a still phone on a desk struck on its own")

    // A jostle that never actually crosses into "moving" (0.03g sits in the dead band between the
    // 0.015 still and 0.035 moving thresholds) must not strike either, no matter how long it goes on.
    for _ in 0..<50 { g.sample(jolt: 0.03) }
    assert(g.strikes == 0, "a reading in the dead band between still and moving struck")

    // A brief nudge — bumping the desk, not a pickup — never sustains the consecutive samples a
    // pickup needs, so it must not strike either.
    //
    // Every count below is driven off `FocusGuard`'s own windows rather than restating them. They
    // were literals once, and raising the sample rate from 10Hz to 20Hz then trapped the app on
    // launch: the check asked for three samples where a pickup had come to mean six.
    for _ in 0..<10 { g.sample(jolt: moving); g.sample(jolt: still) }
    assert(g.strikes == 0, "a nudge that never held long enough struck")

    // Now the real pickup: a full run of consecutive samples over the moving threshold.
    for _ in 0..<FocusGuard.moveSamples { g.sample(jolt: moving) }
    assert(g.strikes == 1 && g.interruption == .lifted, "a pickup did not cost a chance")
    assert(g.countdown == nil, "counted down while the phone was still moving")
    assert(g.chancesLeft == 1, "a spent chance was not taken off the count")

    // Keeping it in your hand costs nothing more — one strike per lapse, and leaving the app during
    // that same lapse is still that one lapse. Nor does re-arming for an extended flight.
    for _ in 0..<20 { g.sample(jolt: moving) }
    g.leftApp()
    g.flightBegan()
    assert(g.strikes == 1, "one lapse spent more than one chance")

    // Put it down: five seconds, from a standstill.
    for _ in 0..<FocusGuard.settleSamples { g.sample(jolt: still) }
    assert(g.countdown == 5, "a still phone did not start the count")
    // Pick it back up mid-count and the count goes, but the chance does not.
    for _ in 0..<FocusGuard.cancelSamples { g.sample(jolt: moving) }
    assert(g.countdown == nil && g.strikes == 1, "moving mid-count did not stop the count")

    // Put it down again and let the settle actually complete this time (forced, since the
    // self-check cannot idle on the real five-second ticker). It must clear the overlay and
    // re-arm — but it must not hand back the chance already spent.
    for _ in 0..<FocusGuard.settleSamples { g.sample(jolt: still) }
    assert(g.countdown == 5, "a still phone did not restart the count")
    g.forceSettle()
    assert(g.interruption == nil && g.countdown == nil, "the settle left the overlay up")
    assert(g.strikes == 1 && g.chancesLeft == 1, "the settle refunded a spent chance")

    // Three separate lapses on one flight divert on exactly the third — never the first, never
    // the second, and never a fourth that can't happen because the flight is already gone.
    let three = FocusGuard()
    var thirdCount = 0
    three.onDiverted = { thirdCount += 1 }
    three.flightBegan()                              // two chances, the default
    defer { three.flightEnded() }
    three.leftApp()
    assert(three.strikes == 1 && thirdCount == 0, "the first of three lapses diverted early")
    three.forceSettle()
    three.leftApp()
    assert(three.strikes == 2 && thirdCount == 0, "the second of three lapses diverted early")
    three.forceSettle()
    three.leftApp()
    assert(three.strikes == 3 && thirdCount == 1 && !three.running,
           "the third lapse did not divert")

    // Running out is what diverts, and only running out. One fresh flight per setting, because
    // clearing an interruption takes the five seconds it says it does.
    for chances in 0...2 {
        let h = FocusGuard()
        var diverted = false
        h.onDiverted = { diverted = true }
        h.flightBegan(chances: chances)
        h.leftApp()
        assert(diverted == (chances == 0),
               "with \(chances) chances the first lapse \(diverted ? "diverted" : "did not divert")")
        assert(h.chancesLeft == max(0, chances - 1), "chances left did not follow the strike")
        h.flightEnded()
    }

    // Leaving the app strikes even while the phone is lying dead still — the leniency that used to
    // spare a resting phone (the auto-lock case) is gone. See the comment on `leftApp()`.
    do {
        let stillLeave = FocusGuard()
        stillLeave.flightBegan()
        defer { stillLeave.flightEnded() }
        for _ in 0..<FocusGuard.settleSamples { stillLeave.sample(jolt: still) }   // resting, dead still
        stillLeave.leftApp()
        assert(stillLeave.strikes == 1, "leaving the app while resting still did not strike")
    }

    // A guard that is never started at all — as happens when the developer panel's "ignore the
    // focus guard" switch is on, which skips `flightBegan` for every cabin, not just business —
    // must be inert to every signal there is. (Business class *does* call `flightBegan`, with
    // `canDivert: false`; see `businessClassSelfCheck`.)
    let biz = FocusGuard()
    var bizDiverted = false
    biz.onDiverted = { bizDiverted = true }
    for _ in 0..<10 { biz.sample(jolt: still) }
    for _ in 0..<10 { biz.sample(jolt: moving) }
    biz.leftApp()
    assert(biz.strikes == 0 && biz.interruption == nil && !bizDiverted,
           "a guard that was never started struck anyway")

    // An ordinary landing calls flightEnded() itself. A sample that arrives afterward — the same
    // straggling-callback risk landing has as a divert — must find nothing running to strike.
    let landed = FocusGuard()
    landed.flightBegan()
    for _ in 0..<10 { landed.sample(jolt: still) }
    landed.flightEnded()
    for _ in 0..<10 { landed.sample(jolt: moving) }
    assert(landed.strikes == 0 && landed.interruption == nil, "a sample after landing struck")

    // Running out diverts exactly once. A straggler that lands right after — CoreMotion can hand
    // the main queue one more sample after stopAccelerometerUpdates() is called, since the stop
    // only takes effect for updates not already queued — must not divert an already-diverted
    // flight a second time.
    let out = FocusGuard()
    var divertCount = 0
    out.onDiverted = { divertCount += 1 }
    out.flightBegan(chances: 0)
    for _ in 0..<FocusGuard.settleSamples { out.sample(jolt: still) }
    for _ in 0..<FocusGuard.moveSamples { out.sample(jolt: moving) }
    assert(divertCount == 1 && !out.running, "running out on a pickup did not divert")
    for _ in 0..<20 { out.sample(jolt: moving) }
    out.leftApp()
    assert(divertCount == 1, "a diverted flight was diverted again by a straggling signal")

    // A shake is unambiguous, so it does not wait to be armed — a phone that was never put down
    // can still be shaken on purpose, and somebody testing the guard must not first have to
    // discover that an arming window exists.
    let shake = FocusGuard()
    shake.flightBegan()
    shake.shaken()
    assert(shake.strikes == 1 && shake.interruption == .lifted,
           "a shake before the phone was ever put down did not count")

    // It still cannot spend two chances for one lapse.
    shake.shaken()
    assert(shake.strikes == 1, "a second shake during the same lapse spent another chance")
    shake.flightEnded()

    // And it does nothing at all when no flight is in the air.
    let idle = FocusGuard()
    idle.shaken()
    assert(idle.strikes == 0 && idle.interruption == nil, "a shake struck with no flight running")
}
#endif
