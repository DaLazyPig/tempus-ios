import Foundation
import Observation
import SwiftUI
import FamilyControls

/// Every screen in this app is one value of `phase`, rendered by one switch in `RootView` and
/// cross-faded by one transition engine. There is no navigation stack and no history.
enum Phase: String, Codable, CaseIterable {
    case ob, home, settings, stats, status, concourse, carddesign, linked, passes
    case redeem, preflight, pass, flying, landed

    /// Phases that paint navy and put the status bar into its light treatment.
    var isDark: Bool { self == .preflight || self == .pass || self == .flying }

    /// Whether the *home indicator* is dark. Deliberately narrower than the status bar's rule:
    /// dark only on the three flight phases and on a dark onboarding step.
    var homeBarDark: Bool { isDark }

    /// Screens whose content is laid out edge to edge, status bar and home indicator included.
    /// The router reads this: see the note in `RootView`'s layer stack for why the ignore cannot
    /// be left to the screen itself. Keep it in step with the screens that end their body with
    /// `.ignoresSafeArea()` — a background that bleeds does not count, only content that does.
    var fullBleed: Bool {
        switch self {
        case .ob, .status, .carddesign: return true
        default: return false
        }
    }
}

/// The router's cuts. Each carries its own teardown length and its own in/out animation lengths,
/// which differ — the teardown timer is deliberately at least as long as the motion.
enum TransitionType: String, Codable {
    case none, zoom, sink, lift, perm, permout
    /// Fully implemented in the reference and never triggered by any call site. Kept because they
    /// cost nothing; nothing routes through them.
    case push, cover, uncover

    /// How long the two-layer teardown holds before the outgoing layer is dropped.
    var teardown: Double {
        switch self {
        case .push: return 0.520
        case .zoom: return 0.520
        case .sink: return 0.380
        case .cover: return 0.560
        case .uncover: return 0.490
        case .lift: return 0.560
        case .perm: return 1.250
        case .permout: return 1.200
        case .none: return 0
        }
    }

    /// The incoming layer's animation length.
    var inDuration: Double {
        switch self {
        case .push: return 0.490
        case .zoom: return 0.480
        case .cover: return 0.540
        case .lift: return 0.560
        case .perm: return 1.250
        default: return 0
        }
    }

    /// The outgoing layer's animation length.
    var outDuration: Double {
        switch self {
        case .push: return 0.490
        case .zoom: return 0.400
        case .sink: return 0.340
        case .uncover: return 0.470
        case .lift: return 0.460
        case .permout: return 1.200
        default: return 0
        }
    }
}

struct Transition: Equatable {
    var type: TransitionType
    /// Only `push` and `lift` read this. +1 rises, −1 falls.
    var dir: Int = 1
    var from: Phase
    var key = UUID()
}

/// How leaving early is paid.
enum DivertPolicy: String, Codable, CaseIterable {
    case none, partial

    var label: String { self == .none ? "All or nothing" : "Partial" }
}

/// A consent gate. Nothing about a locked cabin should be one tap away from either direction.
struct GateState: Equatable {
    enum Kind: String { case board, exit }
    enum Closing: String { case up, down }
    var kind: Kind
    /// `up` = confirmed, the gate leaves through the top; `down` = cancelled, it retracts.
    var closing: Closing?
}

/// The single source of truth.
@Observable
final class AppModel {

    // MARK: - Router and chrome

    private(set) var phase: Phase
    /// Set once, by finishing onboarding. It is a fact about the install, not derived from the
    /// phase — a launch seam that drops straight onto a screen must not count as having onboarded.
    private(set) var onboarded: Bool
    private(set) var trans: Transition?
    private var transTask: Task<Void, Never>?

    /// Onboarding paints its own ground and tells the chrome what it is doing.
    var obDark = false

    /// The copper card ⇄ preflight morph.
    struct Morph: Equatable {
        var rect: CGRect
        var mode: Mode
        var next: Phase?
        enum Mode: String { case open, close }
    }
    var morph: Morph?
    /// Where the last morph started, so closing can shrink back into the same card.
    private var morphRect: CGRect?

    /// The Home ⇄ Settings circle reveal.
    struct CircleReveal: Equatable {
        var x: CGFloat
        var y: CGFloat
        var next: Phase
    }
    var circle: CircleReveal?

    /// Status Club opened straight off a tier-up: the ground it flies in from.
    var statusIntro: Color?
    /// The card studio opened from a landing: the rect, ground and rotation it grows out of.
    struct CardDesignFrom: Equatable {
        var rect: CGRect
        var bg: Color
        var rot: Double
    }
    var cardDesignFrom: CardDesignFrom?
    /// Status Club's hero band, as that screen last measured it. The card studio's entrance grows
    /// its own band out of this one, and a literal cannot know it: the reference's `500` lands on
    /// the bottom of the club's hero in a 390 x 844 drawing and ~40pt short of it on a 17 Pro, so
    /// the studio's first frame painted a pale strip across a band the club had filled. A
    /// `RectBox`, so keeping it current invalidates nothing (see Measure.swift).
    let statusHero = RectBox()
    /// Status Club's membership card, as that screen last measured it — where the studio's deck
    /// starts from and travels back to. It was a literal 89pt above the deck, tuned by eye on one
    /// phone: 4pt off the club's card on a 17 Pro and 13pt off on a 16 Plus, so the exit's
    /// cross-fade overlaid two cards that far apart and the club's snapped into place under it.
    let statusCardBox = RectBox()
    /// The leaving card studio, drawn over Status Club while it shrinks back into the card.
    var cardDesignOut: Int?

    var addSheet = false
    var editTask: TaskItem?
    var airportSheet = false
    /// A task just added — the deck plays its drop for 700 ms.
    var dropID: String?
    /// The deck deals itself in.
    var deal = false

    // MARK: - Flight

    var minutes: Int
    /// Seconds flown. Always derived from the wall clock, never accumulated.
    private(set) var elapsed: Double = 0
    /// The wall-clock deadline. Persisted, so a relaunch resumes the same flight.
    private(set) var endsAt: Date?
    private(set) var diverted = false
    /// Whole minutes flown when a flight was left early.
    private(set) var leftAt = 0
    private(set) var flightNo = "TP 0842"
    private(set) var destination: Destination?
    private(set) var operatedBy: Carriers.Operated?
    /// The pass header this flight flies, stamped at boarding so the tear, the flight and the
    /// archive tile all show the same band.
    private(set) var passHeader: String?
    private(set) var landedAt: Destination?
    /// The airport the last landing departed from — captured before `land()` moves home, so the
    /// arrival screen's route strip can draw the leg that was actually flown.
    private(set) var landedFrom: String?
    /// Business class, armed per flight.
    private(set) var biz = false
    var gate: GateState?
    private var gateTask: Task<Void, Never>?
    /// The last landing was an emergency exit.
    private(set) var penalty = false
    /// The tier just reached, if this landing crossed one.
    var tierUp: Int?
    /// What the last landing actually paid.
    ///
    /// `earned` is derived from the *current* status, and a landing that crosses a tier changes
    /// the status a moment after banking at the old multiplier — so by the time the landing screen
    /// reads `earned`, it is a different number from the one credited. Miles are computed in one
    /// place and quoted from one place; this is that place.
    private(set) var bankedMiles = 0
    /// Debug flight-clock multiplier. Never persisted — a relaunch always returns to real time.
    var speed: Double = 1 { didSet { rescaleForSpeed(from: oldValue) } }

    private var tickTask: Task<Void, Never>?
    private var hasLanded = false

    /// Cabin discipline: the accelerometer, the chances, and the settle countdown. Economy only —
    /// business class locks the cabin instead, so there is no lapse to forgive and no chance to
    /// spend, only the emergency exit.
    let focusGuard = FocusGuard()
    /// Chances this flight has already spent, kept here because `FocusGuard`'s own `strikes` does
    /// not outlive the process and a flight does. Seeded from the save file on a relaunch and
    /// written back on every strike, so swiping Tempus out of the switcher cannot refill them.
    private var spentChances = 0

    /// Set once `init` is finished. The settings observers above fire while the model is still
    /// assembling itself — and a half-built model must never reach the disk.
    private var ready = false

    // MARK: - Economy, ledgers, archives

    private(set) var miles: Int {
        didSet {
            if ready && !applyingConfirmedMiles { milesJournal.append(miles - oldValue) }
        }
    }
    private var milesJournal: MilesJournal
    private var applyingConfirmedMiles = false
    private var pendingGift: PendingGift?
    private var pendingGiftReceipts: [ReceivedGift] = []
    private var giftNetworking = false
    /// What a linked member is called before their name has been read back off the invite —
    /// never a name anyone chose, and the one string `refreshSharedBank` treats as "still unknown".
    static let unnamedPartner = "Linked member"
    var link: LinkAccount? { didSet { save() } }
    /// The real pair backing `link`, once a request has actually been accepted server-side.
    /// `nil` means either nothing has been linked yet or the whole link is still local-only — the
    /// old, pre-Supabase shape, where `link.miles` itself carries whatever a caller put there
    /// (see `linkedMiles`).
    private(set) var linkPairID: String?
    /// The shared pot's last value this device has seen. Persisted so a cold launch shows it
    /// immediately instead of 0 — `potStale` is what says whether it has been confirmed since.
    private(set) var pot: Int = 0
    /// Whether `pot` has been confirmed by a round trip this session. Always true right after
    /// launch, whatever was on disk: a shared number nobody has fetched yet is a guess, and
    /// showing a guess as live is the one dishonesty this feature cannot afford. Never persisted —
    /// every launch starts unconfirmed.
    private(set) var potStale = true
    /// Pairs whose merge has already been made from this phone — see `mergePersonalMiles`.
    /// Persisted, because the deposit is once per member per pair and a relaunch must not ask
    /// again. (The server refuses a second one anyway; this is what stops a call being made.)
    private(set) var mergedPairs: [String] = []
    /// The server id of the invite behind an incoming or outgoing `link` — set by `showInvite`
    /// whenever a real `LinkInvite` is mirrored into `link` for display. `acceptLinkRequest` and
    /// `declineLinkRequest` use it to answer the real invite; with no id behind `link` (the local
    /// demo seams, or a build with no backend) they fall back to the old, purely local behaviour.
    private(set) var linkInviteID: String?
    /// One landing's earn that could not yet be delivered to the shared pot, in the order they
    /// were earned. `land()` appends to this rather than lose the credit; `flushPendingPotCredits`
    /// retries it. Persisted, because a phone can be killed before the retry lands.
    struct PotCredit: Codable, Identifiable {
        var id: TimeInterval
        var pair: String
        var amount: Int
        var label: String
        /// The landing's name on the server, minted once here and kept with the credit so a
        /// retry carries the same one. Optional so a queue saved before it existed still decodes;
        /// `flushPendingPotCredits` mints one for those before sending.
        var op: String?
    }
    private(set) var pendingPotCredits: [PotCredit] = []
    private(set) var spends: [SpendEntry] = []
    private(set) var hourLog: [Status.HourEntry] = []
    /// The last status period whose closing notice was dismissed.
    var periodAck = -1 { didSet { save() } }
    private(set) var flights: [FlightRecord] = []
    private(set) var marks = Marks()
    var rate: Double = 0.25 { didSet { save() } }
    var spend: Double = 1 { didSet { save() } }
    var policy: DivertPolicy = .none { didSet { save() } }
    private(set) var unlocked: Unlock?
    private var expiryTask: Task<Void, Never>?
    /// A coalesced `save()` is already queued for this runloop turn — see `save()`.
    private var savePending = false

    // MARK: - Settings, membership, shop

    private(set) var tasks: [TaskItem]
    var order = 0
    var blocked: [String] = ["ig", "tt", "rd"] { didSet { save() } }
    /// The apps iOS actually shields, chosen through `FamilyActivityPicker`.
    ///
    /// This — not `blocked` — is what blocking enforces. `blocked` is the Redeem strip's menu of
    /// what you say you are unlocking *for*, which the reference already treats as cosmetic
    /// because the price does not depend on it. Until Screen Time is authorized there is no
    /// selection to make and this stays empty, which is exactly when the Settings screen says
    /// blocking is not connected.
    var selection = FamilyActivitySelection() { didSet { save() } }
    var defaultMinutes = 50 { didSet { save() } }
    /// A daily ceiling on miles spent buying screen time. `0` is off, which is the default —
    /// nobody is opted into a limit they did not ask for.
    var spendLimit = 0 { didSet { save() } }


    /// Hours of flying aimed at per calendar week. Zero is no goal, which is the default — the
    /// app does not set a target on anyone's behalf.
    ///
    /// Hours, not miles: a goal is about the studying, and miles are what the studying buys. It
    /// is measured the same way the qualifying-hours ledger is, so a goal and a tier never
    /// disagree about what counted — completed flights only, diversions paying nothing here too.
    var weeklyGoal = 0 { didSet { save() } }
    var notifications = true { didSet { save() } }
    var liveActivity = true { didSet { save() } }
    /// The paid plan.
    /// The effective plan. **Never assign this directly** — `setPlus(_:source:)` is the only
    /// writer, because two independent things can grant it and neither may silently revoke the
    /// other's grant. Reads are free; it is what every ceiling and every tier gate consults.
    private(set) var plus = false { didSet { save() } }

    /// Who granted Business Class. A purchase and the developer switch are both legitimate, and a
    /// store downgrade must not take away a plan the developer switch is holding open.
    enum PlusSource { case store, developer }

    /// What RevenueCat last said. Not persisted as itself — it is seeded from the stored `plus` at
    /// launch so the plan survives until the store actually contradicts it, rather than blinking
    /// off in the seconds before the SDK answers (or forever, if there is no SDK key at all).
    private var storePlus = false
    /// The developer switch's own grant, persisted so it survives a relaunch while testing.
    private var devPlus = false

    func setPlus(_ active: Bool, source: PlusSource) {
        switch source {
        case .store: storePlus = active
        case .developer: devPlus = active
        }
        plus = storePlus || devPlus
        save()
    }
    var horizon = 60 { didSet { save() } }
    var excluded: Set<String> = ["msg", "maps"] { didSet { save() } }
    /// The name the member put on their card — empty until they give one or sign in.
    var member = "" { didSet { save() } }
    /// What a card, a pass or a gift prints: the member's name, or a neutral placeholder. Never a
    /// sample person — the old default was "Olivia Reyes", which put a stranger's name on every
    /// card of anyone who skipped sign-in.
    var cardName: String {
        let name = member.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Tempus member" : name
    }

    // MARK: - Developer mode

    /// Off by default, hidden behind seven taps on the Settings title, and — see `Dev.available` —
    /// absent entirely from any release build, TestFlight included, because everything it opens is something the app
    /// otherwise charges miles or money for.
    var devMode = false { didSet { save() } }
    /// Lets the pay sheet accept a tap in place of Face ID. For the Simulator, which has no
    /// biometry unless it has been explicitly enrolled.
    var devSkipBiometrics = false { didSet { save() } }
    /// Suspends the focus guard's strikes, so leaving the app while testing does not divert.
    var devIgnoreFocusGuard = false { didSet { save() } }
    /// Asks Settings to open the developer sheet on arrival. Seam-only; never persisted.
    var devSheet = false
    /// Asks Home to shove the deck's top card this far sideways and then open the morph from the
    /// card's own *measured* rect. Seam-only (`-tempusMorphDrag`); never persisted. See the note
    /// on `Seams.morphDrag` for what it proves — it is the only route in that exercises the
    /// measurement rather than a rect written down in the seam itself.
    var seamMorphDrag: CGFloat?

    /// Whether the developer switch is currently holding Business Class open.
    var devHasPlus: Bool { devPlus }
    /// The day you joined. Status periods are anchored on it.
    private(set) var firstRun: TimeInterval
    private(set) var homeAirport: Airport
    /// The chosen card face per tier.
    var cardVariant: [Int] = Array(repeating: 0, count: Status.tiers.count) { didSet { save() } }
    private(set) var founderSerial: Int
    private(set) var founderIssued: TimeInterval?
    private(set) var ownedFaces: [String] = []
    private(set) var ownedHeaders: [String] = []
    private(set) var sentGifts: [SentGift] = []
    /// Gifts awaiting accept/decline on this device. See `ReceivedGift` — nothing populates this
    /// today but a debug seam; it is the honest shape of what a server would fill.
    private(set) var receivedGifts: [ReceivedGift] = []
    /// Credits to the balance that are not flights — an accepted gift, today.
    private(set) var credits: [CreditEntry] = []

    /// The Concourse's open item, its gift sheet, and the scroll it returns to.
    struct ShopSelection: Equatable {
        var kind: PurchaseKind
        var id: String
        var rect: CGRect
    }
    var shopSelection: ShopSelection?
    var shopLeaving = false
    var giftOpen: CGRect?
    var giftFace: String?
    var giftSent: TimeInterval = 0
    /// A transfer refusal or an unresolved connection. Only a server receipt announces delivery.
    var giftFailed: String?
    var giftAwaitingConfirmation: Bool { pendingGift != nil }

    /// The app a shield asked to unlock. It only *names* the app — Redeem still charges the same
    /// price, and can still refuse.
    var requestedUnlockApp: String?

    // MARK: - Payment and paywall

    /// The paywall.
    enum PaywallState: String { case open, closing }
    var paywall: PaywallState?
    /// An order awaiting confirmation.
    var payFlow: Order?
    enum PayCheck: String { case check, paid, out }
    var payCheck: PayCheck?

    /// Business class was interrupted by leaving the app; iOS owns the home screen, so all we can
    /// do is say so on return.
    var stayOpenToast = false
    private var toastTask: Task<Void, Never>?

    /// What the launch arguments asked for, kept so screens can honour the ones that are about
    /// timing rather than state (open a sheet, run a set-piece, start onboarding part-way).
    var launchSeams = Seams()

    // MARK: - Derived

    /// The deck's front card.
    var task: TaskItem? { tasks.isEmpty ? nil : tasks[order % tasks.count] }
    var total: Double { Double(minutes) * 60 }
    /// The spendable balance. Linked members hold one bank, so this — not `miles` — is what Home,
    /// Redeem, the Concourse, the shield and the pay sheet display.
    ///
    /// **A pending link contributes nothing.** A request is real the moment it is sent, but the
    /// bank is not shared until the other side accepts — so a link's `miles` (always 0 until then
    /// anyway) is excluded outright while `pending`, rather than trusted to already be zero.
    var pool: Int { miles + linkedMiles }

    /// `link.miles` is the old, local-only shape (still what a demo seam or a link accepted with
    /// no backend behind it carries); `pot` is the real shared pool a `linkPairID` backs. Adding
    /// them costs nothing when only one is ever nonzero, and keeps every old reading of `link.miles`
    /// (`giftLinkSelfCheck` pins one) true without this app pretending the two are the same number.
    private var linkedMiles: Int {
        guard let l = link, !l.isPending else { return 0 }
        return l.miles + pot
    }
    var status: Status.Snapshot { Status.of(log: hourLog, plus: plus, anchor: firstRun) }
    /// What a completed flight banks.
    var earned: Int { Status.earn(minutes: minutes, rate: rate, mult: status.mult) }
    /// The ×1.0 figure, shown beside `earned` on preflight.
    var baseEarn: Int { Status.earn(minutes: minutes, rate: rate, mult: 1) }
    /// What leaving now is worth, under the current policy.
    var stakeMiles: Int {
        policy == .partial
            ? Status.earn(minutes: max(1, Int((elapsed / 60).rounded())), rate: rate, mult: status.mult)
            : earned
    }
    var stakeLabel: String {
        biz
            ? "lose \(stakeMiles) mi \u{00b7} \u{2212}15 mi \u{00b7} \u{2212}2 h"
            : (policy == .partial ? "keep " : "lose ") + "\(stakeMiles) mi"
    }
    var gateUp: Bool { gate != nil && gate?.closing == nil }

    var memberSince: String {
        let candidates = [firstRun] + flights.map(\.t) + hourLog.map(\.t)
        let d = Date(timeIntervalSince1970: candidates.min() ?? firstRun)
        let f = DateFormatter()
        f.dateFormat = "MMM yyyy"
        f.locale = Locale(identifier: "en_GB")
        return f.string(from: d)
    }

    var founderSerialString: String { String(format: "%03d", founderSerial) }

    var founderIssuedString: String {
        guard let founderIssued else { return "\u{2014}" }
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy"
        f.locale = Locale(identifier: "en_GB")
        return f.string(from: Date(timeIntervalSince1970: founderIssued))
    }

    /// The status bar's treatment.
    var barDark: Bool {
        phase.isDark
            // Status Club's header band is now always dark enough to carry white ink (see
            // `StatusScreen.band`), and that band is what sits under the status bar. Here and not
            // in `Phase.isDark`, deliberately: `homeBarDark` reads `isDark`, and the *bottom* of
            // this screen is still pale `sky100`, so the home indicator must stay dark.
            || phase == .status
            || (phase == .ob && obDark)
            || (phase == .landed && tierUp != nil && !diverted)
            // `== .open`, not `!= nil` — the same rule `RootView`'s `StageEffect` is keyed on,
            // and for the same reason. Read as `!= nil` the bar flipped back on the frame
            // `paywall` was cleared, which is 420 ms into a 620 ms stage restore: a trait change
            // and a full repaint landing in the middle of the close, which is what read as the
            // screen jittering at the top. Starting the restore when the close starts puts the
            // bar on the same clock as everything else that is restoring.
            || paywall == .open
    }

    /// The Live Activity payload, or nil when nothing should be showing.
    var liveFlight: (subject: String, minutes: Int, endsAt: Date, no: String, dest: Destination?)? {
        guard phase == .flying, let endsAt, liveActivity, let task else { return nil }
        return (task.title, minutes, endsAt, flightNo, destination)
    }

    // MARK: - Init

    /// - Parameter applyingSeams: whether to read the process's launch arguments. False only for
    ///   `accountSelfCheck`, which builds throwaway models: a seam would make the check behave
    ///   differently depending on how the app was launched, and — worse — some seams schedule work
    ///   that calls `save()` *after* the check has finished restoring the real blob.
    init(stored: Stored? = nil, applyingSeams: Bool = true) {
        let s = stored ?? Stored()
        let now = Date().timeIntervalSince1970

        milesJournal = s.milesJournal ?? MilesJournal(balance: max(0, s.miles ?? 50))
        pendingGift = s.pendingGift
        pendingGiftReceipts = s.pendingGiftReceipts ?? []
        firstRun = s.firstRun ?? now
        miles = s.miles ?? 50
        tasks = s.tasks ?? AppModel.seedTasks
        defaultMinutes = s.defaultMin ?? 50
        minutes = s.defaultMin ?? 50
        founderSerial = s.fdrSerial ?? Int.random(in: 1...100)
        homeAirport = Geography.byCode(s.homeAp ?? "SYD")
        let hasOnboarded = s.onboarded ?? false
        onboarded = hasOnboarded
        phase = hasOnboarded ? .home : .ob
        deal = phase == .ob

        blocked = s.blocked ?? ["ig", "tt", "rd"]
        spendLimit = s.spendLimit ?? 0
        weeklyGoal = s.weeklyGoal ?? 0
        if let d = s.selection,
           let sel = try? JSONDecoder().decode(FamilyActivitySelection.self, from: d) {
            selection = sel
        }
        notifications = s.notif ?? true
        liveActivity = s.live ?? true
        // Seeded, not decided: the store has not answered yet, and until it does the last thing
        // it said stands. Paired with `save()` writing `storePlus` rather than `plus` — the two
        // have to name the same quantity or a developer grant survives as an unrevokable one.
        storePlus = s.plus ?? false
        // A developer grant only counts where developer mode exists: a `devPlus` bit banked by a
        // debug build must not keep Business Class open in a store build of the same install.
        devPlus = Dev.available && (s.devPlus ?? false)
        plus = storePlus || devPlus
        devMode = s.devMode ?? false
        devSkipBiometrics = s.devSkipBio ?? false
        devIgnoreFocusGuard = s.devIgnoreGuard ?? false
        rate = s.rate ?? 0.25
        spend = s.spend ?? 1
        policy = s.policy.flatMap(DivertPolicy.init(rawValue:)) ?? .none
        horizon = s.horizon ?? 60
        excluded = Set(s.excluded ?? ["msg", "maps"])
        // A blob saved under the old default still carries the sample name; that was never theirs.
        member = s.member == "Olivia Reyes" ? "" : (s.member ?? "")
        hourLog = s.hlog ?? []
        periodAck = s.periodAck ?? -1
        flights = s.flights ?? []
        marks = s.marks ?? Marks()
        link = s.link
        linkPairID = s.linkPairID
        pot = s.pot ?? 0
        linkInviteID = s.linkInviteID
        pendingPotCredits = s.potCredits ?? []
        mergedPairs = s.mergedPairs ?? []
        spends = s.spends ?? []
        ownedFaces = s.ownedFaces ?? []
        ownedHeaders = s.ownedHeaders ?? []
        sentGifts = s.sentGifts ?? []
        receivedGifts = s.receivedGifts ?? []
        credits = s.credits ?? []
        founderIssued = s.fdrIssued
        landedFrom = s.landedFrom

        // An unlock only survives if it has not already expired.
        if let u = s.unlocked, u.until > now { unlocked = u }

        if let v = s.cardV, v.count == Status.tiers.count { cardVariant = v }

        Geography.setHome(homeAirport.code)

        // A flight in the air survives a relaunch: the deadline is wall-clock, so the flight has
        // been running the whole time the app was dead.
        if let ends = s.endsAt, let ph = s.phase.flatMap(Phase.init(rawValue:)), ph == .flying {
            minutes = s.minutes ?? minutes
            destination = s.destination
            operatedBy = s.operatedBy
            passHeader = s.passHeader
            biz = s.biz ?? false
            flightNo = s.flightNo ?? flightNo
            endsAt = Date(timeIntervalSince1970: ends)
            phase = .flying
            spentChances = s.strikes ?? 0
        }

        if phase == .flying { LiveActivityController.reattach() }
        if unlocked != nil { UnlockActivityController.reattach() }
        // Running out of chances diverts the flight, wherever the guard was looking.
        focusGuard.onDiverted = { [weak self] in self?.divert() }
        // A strike that does not end the flight still has to reach the disk before the app can be
        // swiped away — `saveNow`, because `save()` waits for a runloop turn a dying process may
        // never get.
        focusGuard.onStrike = { [weak self] in
            guard let self else { return }
            self.spentChances = self.focusGuard.strikes
            self.saveNow()
        }
        if applyingSeams && Dev.seams { applyLaunchArguments() }
        ready = true
        startExpiryWatch()
        if phase == .flying { startTicking() }
    }

    // A fresh install starts with nothing to fly — a deck of subjects nobody wrote is a demo,
    // not a member's own list. `HomeScreen.emptyState` is the front door for a member with none.
    static let seedTasks: [TaskItem] = []

    // MARK: - The transition engine

    /// The only thing allowed to change `phase`.
    func go(_ next: Phase, _ type: TransitionType = .none, dir: Int = 1) {
        guard next != phase else { return }
        let from = phase
        phase = next
        guard type != .none else { trans = nil; return }
        transTask?.cancel()
        trans = Transition(type: type, dir: dir, from: from)
        let key = trans?.key
        transTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(type.teardown))
            guard !Task.isCancelled, let self, self.trans?.key == key else { return }
            self.trans = nil
        }
        save()
    }

    /// Swap the phase with no cross-fade, because something else — a morph, a circle, a screen's
    /// own animation — is covering the cut.
    func goDirect(_ next: Phase) {
        transTask?.cancel()
        phase = next
        trans = nil
        save()
    }

    // MARK: - Morph and circle

    func openFlight(from rect: CGRect?) {
        // Economy is capped at 90 minutes per flight.
        minutes = plus ? defaultMinutes : min(90, defaultMinutes)
        biz = false
        penalty = false
        guard let rect else {
            go(.preflight, .zoom)
            return
        }
        morphRect = rect
        morph = Morph(rect: rect, mode: .open, next: .preflight)
    }

    func closePreflight() {
        // A gate still retracting owns the screen; running two transitions over each other reads
        // as a flicker.
        if gate != nil {
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(260))
                self?.closePreflight()
            }
            return
        }
        guard let rect = morphRect else {
            go(.home, .zoom)
            return
        }
        // The open cuts the phase under the rect at the one moment the rect covers the whole
        // screen — the end. The close is that clip backwards, so its cut is at the start: Home
        // goes under the still-full-screen rect now, unseen, and the rect then shrinks onto the
        // card with Home already around it. Swapping at the *end* instead (tried on 18 Sep 2026)
        // leaves Preflight showing around the shrinking rect and cuts the whole ground navy →
        // Home in one frame when the rect lands, which is exactly the cut the mirror is meant
        // to hide.
        goDirect(.home)
        morph = Morph(rect: rect, mode: .close, next: nil)
    }

    /// The one door from a shield tap or a `tempus://withdraw` link into Redeem.
    ///
    /// **A flight in the air outranks both.** `goDirect(.redeem)` only assigns `phase`, so leaving
    /// `.flying` that way makes the tick task return at its own `phase == .flying` guard — `land()`
    /// is never reached, the next `save()` drops `endsAt`/`minutes`/`destination` because those are
    /// only written while flying, the Live Activity keeps counting down for a flight that no longer
    /// exists, and `FocusGuard` is left running so a later strike diverts a flight that ended
    /// minutes ago. Twenty minutes of flying vanished with no landing, no divert and no miles.
    ///
    /// The app the shield named is still remembered, so it is waiting in Redeem after landing.
    func requestUnlock(app: String?) {
        if let app { requestedUnlockApp = app }
        guard phase != .flying else { return }
        go(.redeem, .perm)
    }

    /// Called by the morph when its clock runs out. Both directions swap the phase here, under
    /// cover: opening swaps the instant the rect has grown opaque over the whole screen, closing
    /// swaps the instant it has shrunk back down over the card — the swap is invisible either way
    /// because the rect matches whatever it is sitting on at that exact moment.
    func morphFinished() {
        if let m = morph, let next = m.next {
            goDirect(next)
        }
        morph = nil
    }

    func circleGo(from point: CGPoint, to next: Phase) {
        circle = CircleReveal(x: point.x, y: point.y, next: next)
        if next == .home { deal = true }
    }

    func circleCovered() {
        guard let c = circle else { return }
        goDirect(c.next)
    }

    func circleGone() { circle = nil }

    func closeCardDesign(saving variant: Int? = nil) {
        statusIntro = nil
        cardDesignFrom = nil
        // "Use this design" must land in the same write the reference makes (`setCardV` before
        // `closeCardDesign(n)`): without it Status Club underneath still holds the old face, so
        // the moment the exiting copy finishes its fade the card snaps back to what it replaced —
        // the flicker on every return from a saved change.
        if let variant {
            // `cardVariant`'s own `didSet` (line ~317) would save the whole model here, and
            // `goDirect` below saves it again right after — two full encodes on the busiest frame
            // in the app. `cardVariant` is otherwise written only from `init`/`restore`, so
            // toggling `ready` around this one write skips just this eager save; `didSet` itself
            // stays untouched for every other caller, present or future.
            ready = false
            cardVariant[status.idx] = variant
            ready = true
        }
        cardDesignOut = variant ?? cardVariant[status.idx]
        goDirect(.status)
    }

    // MARK: - The flight lifecycle

    /// Issue the pass.
    func board() {
        flightNo = "TP " + String(format: "%04d", Int.random(in: 100...999))
        // With no owned headers the pass always flies the house band; with n owned, the chance of
        // flying one is min(0.94, 0.8 + 0.03n), chosen uniformly.
        if ownedHeaders.isEmpty {
            passHeader = nil
        } else {
            let chance = min(0.94, 0.8 + Double(ownedHeaders.count) * 0.03)
            passHeader = Double.random(in: 0..<1) < chance ? ownedHeaders.randomElement() : nil
        }
        go(.pass, .sink)
    }

    /// Tear the pass. No transition — the tear owns the moment.
    func depart(operatedBy carrier: Carriers.Operated?) {
        self.operatedBy = carrier
        elapsed = 0
        diverted = false
        hasLanded = false
        // A new flight owes nothing. `flightEnded` clears this too, but a departure is the one
        // place that must not inherit a count — a flight restored and then abandoned rather than
        // landed leaves `spentChances` set, and the next departure would start a chance down.
        spentChances = 0
        let dest = Geography.destination(forMinutes: minutes)
        destination = dest
        let deadline = Date().addingTimeInterval(total / speed)
        endsAt = deadline
        go(.flying, .none)
        startTicking()
        raiseLiveActivity(startedAt: deadline.addingTimeInterval(-total / speed), endsAt: deadline)
        save()
    }

    /// The activity is a convenience surface, not the flight. It is raised once at takeoff and
    /// counts itself down from the deadline; nothing here ticks.
    private func raiseLiveActivity(startedAt: Date, endsAt: Date) {
        guard liveActivity, let task else { return }
        LiveActivityController.start(
            subject: task.title,
            flightNo: flightNo,
            origin: homeAirport.code,
            destination: destination,
            businessClass: biz,
            extendMiles: Int(ceil(5 * rate)),
            startedAt: startedAt,
            endsAt: endsAt,
            stakeLabel: stakeLabel
        )
    }

    func startFlightClock() { startTicking() }

    private func startTicking() {
        tickTask?.cancel()
        guard phase == .flying, let endsAt else { return }
        hasLanded = false
        // The guard runs with the clock, so a flight restored after a relaunch is watched too.
        // `flightBegan` is a no-op while one is already running, so extending — which restarts the
        // clock — never hands back a spent chance.
        // Developer mode never arms the guard at all: `leftApp` and `sample` both guard on
        // `running`, so leaving it un-armed switches the whole machine off at one point rather
        // than at each of its callers.
        // Business class is watched too — it just cannot be diverted. Skipping the guard there
        // meant the cabin that is meant to be the *strictest* was the only one where picking the
        // phone up cost nothing and nobody said a word.
        if !(Dev.available && devMode && devIgnoreFocusGuard) {
            focusGuard.flightBegan(canDivert: !biz, spent: spentChances)
        }
        // Back-derived, never accumulated: the deadline is the truth, so the clock cannot drift,
        // stall or double-count while the app is backgrounded.
        let startAt = endsAt.addingTimeInterval(-total / speed)
        tickTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.phase == .flying else { return }
                let e = Date().timeIntervalSince(startAt) * self.speed
                if e >= self.total {
                    self.elapsed = self.total
                    self.land()
                    return
                }
                self.elapsed = e
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    /// Touchdown. The order of these writes is load-bearing — see the comments.
    private func land() {
        guard !hasLanded else { return }
        hasLanded = true
        tickTask?.cancel()
        focusGuard.flightEnded()
        spentChances = 0

        // Capture the destination and the origin *before* home moves, or the record names the city
        // you are now sitting in as where you set off from.
        let dest = destination ?? Geography.destination(forMinutes: minutes)
        let origin = homeAirport
        landedAt = dest
        landedFrom = origin.code

        // Base miles first, at the multiplier held *before* this flight's hours land: a flight that
        // pushes you into Premier still pays at the old rate. The new one applies from the next.
        let banked = earned
        // Linked members' flights fill the shared pot, not personal — "fills as either of you
        // lands" is the whole point of the pair. `link.isPending` guards this the same way it
        // guards `pool`: nothing is shared until a request is actually accepted.
        if let pairID = linkPairID, let l = link, !l.isPending {
            queuePotCredit(pair: pairID, amount: banked, label: "Flight \(flightNo)")
        } else {
            miles += banked
        }
        bankedMiles = banked

        diverted = false
        biz = false
        penalty = false
        endsAt = nil

        let gained = Double(minutes) / 60
        let now = Date().timeIntervalSince1970
        let before = Status.of(log: hourLog, plus: plus, anchor: firstRun)
        let after = Status.of(log: hourLog + [Status.HourEntry(t: now, h: gained)],
                              plus: plus, anchor: firstRun)

        // The ledger keeps 180 days: the current period and the one that decides its carry-over.
        hourLog = hourLog.filter { $0.t > now - Status.windowSeconds * 2 }
            + [Status.HourEntry(t: now, h: gained)]

        let up = after.idx > before.idx ? after.idx : nil
        tierUp = up
        // Read the tier's own bonus, not the plan-adjusted one.
        if let up, Status.tiers[up].bonus > 0 { miles += Status.tiers[up].bonus }

        logFlight(from: origin, to: dest, minutes: minutes, miles: banked, diverted: false)

        if let t = task { tasks.removeAll { $0.id == t.id } }
        order = 0

        homeAirport = Geography.byCode(dest.code)
        Geography.setHome(dest.code)

        LiveActivityController.end()
        go(.landed, .zoom)
        save()
    }

    /// Leave early. Under `none` a divert pays nothing; under `partial` it pays for the minutes
    /// actually flown. Neither writes the hours ledger — a diverted flight qualifies for nothing.
    ///
    /// **Business class forfeits everything, whatever the policy says.** The cabin is locked for
    /// the whole flight and the guard ends it on the first lapse — leaving the app once, or moving
    /// the phone once. Paying partial credit for that would make the strict cabin the *cheaper*
    /// way to fly, since a member could arm it, pick the phone up a minute in, and still be paid
    /// for the minute. "Partial credit" is a setting about economy's ordinary change of mind; it
    /// is not a discount on a rule the member opted into at preflight.
    func divert() {
        let mins = max(1, Int((elapsed / 60).rounded()))
        // Read before the reset below clears it.
        let wasBiz = biz
        leftAt = mins
        diverted = true
        endsAt = nil
        biz = false
        penalty = false
        tickTask?.cancel()
        focusGuard.flightEnded()
        spentChances = 0

        let keep = policy == .partial && !wasBiz
            ? Status.earn(minutes: mins, rate: rate, mult: status.mult)
            : 0
        if keep > 0 { miles += keep }
        bankedMiles = keep
        let dest = destination ?? Geography.destination(forMinutes: minutes)
        landedFrom = homeAirport.code
        logFlight(from: homeAirport, to: dest, minutes: mins, miles: keep, diverted: true)
        LiveActivityController.end()
        go(.landed, .zoom)
        save()
    }

    /// Business class only. Three costs at once: no miles for the flight, 15 off the balance, and
    /// two qualifying hours removed from the period.
    func emergencyExit() {
        guard phase == .flying else { return }
        let mins = max(1, Int((elapsed / 60).rounded()))
        leftAt = mins
        diverted = true
        penalty = true
        biz = false
        endsAt = nil
        tickTask?.cancel()
        focusGuard.flightEnded()
        spentChances = 0
        miles = max(0, miles - 15)
        bankedMiles = 0
        let now = Date().timeIntervalSince1970
        hourLog = hourLog.filter { $0.t > now - Status.windowSeconds * 2 }
            + [Status.HourEntry(t: now, h: -2)]
        let dest = destination ?? Geography.destination(forMinutes: minutes)
        landedFrom = homeAirport.code
        logFlight(from: homeAirport, to: dest, minutes: mins, miles: 0, diverted: true)
        LiveActivityController.end()
        go(.landed, .zoom)
        save()
    }

    /// The router between the two ways out.
    func endFlight() {
        if biz { openGate(.exit) } else { divert() }
    }

    /// Five more minutes, and five more minutes of deadline. The destination is untouched:
    /// extending a flight adds time and miles but can never move where it is going.
    func extend() {
        minutes += 5
        endsAt = endsAt?.addingTimeInterval(5 * 60 / speed)
        startTicking()
        if let endsAt {
            LiveActivityController.update(startedAt: endsAt.addingTimeInterval(-total / speed),
                                          endsAt: endsAt, stakeLabel: stakeLabel)
        }
        save()
    }

    /// Changing the clock multiplier mid-flight preserves the remaining *flight* time rather than
    /// the remaining wall-clock time.
    private func rescaleForSpeed(from previous: Double) {
        guard previous != speed, phase == .flying, let ends = endsAt else { return }
        let now = Date()
        endsAt = now.addingTimeInterval(max(0, ends.timeIntervalSince(now)) * previous / speed)
        startTicking()
    }

    // MARK: - The archive

    /// The single writer, so a landing and a divert produce the same record.
    private func logFlight(from origin: Airport, to dest: Destination,
                           minutes mins: Int, miles earnedMi: Int, diverted divertedFlag: Bool) {
        let carrier = operatedBy ?? Carriers.forRoute(from: origin.code, to: dest.code, seed: flightNo)
        var rec = FlightRecord(
            id: "f\(Date().timeIntervalSince1970)",
            t: Date().timeIntervalSince1970,
            from: origin.code, fromCity: origin.city,
            to: dest.code, toCity: dest.city, country: dest.country,
            minutes: mins, miles: earnedMi, diverted: divertedFlag,
            subject: task?.title ?? "Flight",
            no: flightNo,
            ac: carrier.ac,
            pat: carrier.livery,
            hdr: passHeader,
            milestone: nil
        )

        // Milestones are mutually exclusive, ordered, and judged against `marks` rather than
        // against the archive, so none can ever be awarded twice. A diverted flight earns none and
        // does not advance the ledger at all — not even `count`.
        if !divertedFlag {
            let n = marks.count + 1
            if !marks.first {
                rec.milestone = .first
            } else if !rec.country.isEmpty && !marks.countries.contains(rec.country) {
                rec.milestone = .country
            } else if n == 100 {
                rec.milestone = .hundred
            } else if mins >= 240 && !marks.four {
                rec.milestone = .four
            } else if mins > marks.longestMin {
                rec.milestone = .long
            }
            marks = Marks(
                first: true,
                countries: !rec.country.isEmpty && !marks.countries.contains(rec.country)
                    ? marks.countries + [rec.country] : marks.countries,
                longestMin: max(marks.longestMin, mins),
                count: n,
                four: marks.four || mins >= 240
            )
        }

        flights = Array(([rec] + flights).prefix(200))
    }

    // MARK: - The gates

    func openGate(_ kind: GateState.Kind) {
        gateTask?.cancel()
        gate = GateState(kind: kind, closing: nil)
    }

    /// `after` runs once the gate has cleared, which is how the emergency exit is deferred until
    /// the screen is free.
    func closeGate(_ way: GateState.Closing = .down, then after: (() -> Void)? = nil) {
        gateTask?.cancel()
        if gate != nil { gate?.closing = way }
        gateTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1200))
            guard !Task.isCancelled else { return }
            self?.gate = nil
            after?()
        }
    }

    func confirmGate() {
        guard let g = gate else { return }
        if g.kind == .exit {
            closeGate(.up) { [weak self] in self?.emergencyExit() }
        } else {
            biz = true
            board()
            closeGate(.up)
        }
    }

    func cancelGate() {
        if gate?.kind == .board { biz = false }
        closeGate(.down)
    }

    // MARK: - The economy

    /// Miles spent buying screen time since local midnight.
    ///
    /// Read off the statement rather than counted into a stored total, so it cannot drift and
    /// needs no rollover: midnight moves and the answer changes with it. `mins > 0` is what marks
    /// a line as an unlock — `payOrder` writes the minutes only for `.unlock`, and the dial cannot
    /// sell fewer than five.
    var spentToday: Int {
        let midnight = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
        return spends.filter { $0.t >= midnight && $0.mins > 0 }.reduce(0) { $0 + $1.cost }
    }

    /// The most that can be spent on an unlock right now.
    ///
    /// **Every affordability check reads this, not `pool`** — the dial, the button, and the
    /// shield's offer — so no surface can offer time Redeem is about to refuse. Concourse stock
    /// is not capped: this is a limit on screen time, not on card faces.
    var unlockAllowance: Int {
        AppModel.allowance(pool: pool, limit: spendLimit, spent: spentToday)
    }

    /// Hours flown since this calendar week began — the goal's numerator.
    ///
    /// The week is the phone's own, so it starts on whatever day the member's locale says it
    /// does. A goal that reset on a day the calendar disagreed with would be wrong twice a week
    /// for half the world.
    var goalHoursThisWeek: Double {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        cal.firstWeekday = Calendar.current.firstWeekday
        let start = cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        return AppModel.goalHours(flights, since: start.timeIntervalSince1970)
    }

    /// The sum itself, with nothing read off the model, so `goalSelfCheck` can pin it — the same
    /// split `allowance` uses below and for the same reason.
    static func goalHours(_ flights: [FlightRecord], since: TimeInterval) -> Double {
        let minutes = flights
            .filter { !$0.diverted && $0.t >= since }
            .reduce(0) { $0 + $1.minutes }
        return Double(minutes) / 60
    }

    /// 0…1 for a goal of `goal` hours against `flown`, clamped at both ends.
    static func goalFraction(flown: Double, goal: Int) -> Double {
        guard goal > 0 else { return 0 }
        return Swift.min(1, Swift.max(0, flown / Double(goal)))
    }

    /// 0…1, and never past 1 — the bar fills, it does not overflow. `goalMet` is what says the
    /// week is done, so a surface never has to compare two floats itself.
    var goalProgress: Double { AppModel.goalFraction(flown: goalHoursThisWeek, goal: weeklyGoal) }
    var goalMet: Bool { weeklyGoal > 0 && goalHoursThisWeek >= Double(weeklyGoal) }

    /// The clamp itself, with nothing read off the model, so `spendLimitSelfCheck` can pin it.
    /// Two edges make it worth pinning: a limit set higher than the balance must not invent miles,
    /// and a limit lowered below what has already been spent today must not go negative.
    static func allowance(pool: Int, limit: Int, spent: Int) -> Int {
        guard limit > 0 else { return pool }
        return max(0, min(pool, limit - spent))
    }

    /// Whether the limit, rather than the balance, is what is standing in the way. The two want
    /// different words: one is "earn more", the other is "come back tomorrow".
    ///
    /// **Asked about a price, because that is the only way the question has an answer.** This was
    /// `spentToday >= spendLimit` — true only once the limit was exhausted to the mile. But the
    /// affordability test is `cost <= unlockAllowance`, and the allowance bites the moment
    /// `limit − spent < cost`. Across that whole band a refusal *caused* by the limit was reported
    /// as a shortfall: "you need 15 mi more", under a balance of 400, where earning fifteen more
    /// would have changed nothing. `SharedStore.limitReached` had the headroom-based form all
    /// along, so the shield and the app gave two different reasons for one refusal.
    func limitIsTheObstacle(for cost: Int) -> Bool {
        spendLimit > 0 && cost > unlockAllowance && cost <= pool
    }

    /// No headroom left at all — nothing on the dial is buyable today. What Settings and the
    /// shared store mean by the same name.
    var limitReached: Bool { spendLimit > 0 && spentToday >= spendLimit }

    /// The only place miles leave the balance, for the common case: the order's full cost fits in
    /// the personal balance. Synchronous, offline, no round trip — unchanged from before a shared
    /// pot existed. `payOrderShared` is the only other writer, and it funnels back through
    /// `commit(_:cost:)` below rather than repeating this accounting.
    func payOrder(_ u: Order) {
        guard u.kind != .gift, u.cost >= 0, miles >= u.cost else { return }
        miles -= u.cost
        commit(u, cost: u.cost)
    }

    /// What changing the blocked apps costs, once there is a selection to change. The first pick
    /// is free — onboarding asks for it before a single mile has been flown for.
    static let selectionChangeCost = 60

    /// True when writing `next` over the current selection would cost `selectionChangeCost`:
    /// a selection already exists and `next` differs from it.
    func selectionChangeCharges(_ next: FamilyActivitySelection) -> Bool {
        !selectionIsEmpty(selection) && next != selection
    }

    private func selectionIsEmpty(_ s: FamilyActivitySelection) -> Bool {
        s.applicationTokens.isEmpty && s.categoryTokens.isEmpty && s.webDomainTokens.isEmpty
    }

    /// The one writer of the selection outside onboarding. Free for a first pick; otherwise the
    /// selection only moves once the miles have, so a refusal leaves the old apps blocked.
    @MainActor
    func changeSelection(to next: FamilyActivitySelection) async -> PayOutcome {
        guard next != selection else { return .ok }
        guard selectionChangeCharges(next) else { selection = next; return .ok }
        guard pool >= Self.selectionChangeCost else { return .refused }
        let outcome = await payOrderShared(Order(kind: .apps, cost: Self.selectionChangeCost,
                                                 name: "Blocked apps changed"))
        if outcome == .ok { selection = next }
        return outcome
    }

    /// Three ways an order handed to the shared pot can go. Never conflate `.refused` (the pot
    /// genuinely did not have it) with `.unavailable` (the pot could not be reached) — a member
    /// told they can't afford miles they actually have is the one failure this feature cannot have.
    enum PayOutcome: Equatable { case ok, refused, unavailable }

    /// The async sibling of `payOrder`, for an order whose cost may exceed the personal balance.
    /// Debits personal first — synchronous, cannot be raced — then asks the server for the rest.
    /// A refusal or a failure rolls that debit back, so an order that does not go through never
    /// leaves the balance short.
    @MainActor
    @discardableResult
    func payOrderShared(_ u: Order) async -> PayOutcome {
        if u.kind == .gift { return await payGift(u) }
        let mine = min(miles, u.cost)
        let shortfall = u.cost - mine
        guard shortfall > 0 else {
            payOrder(u)
            return .ok
        }
        guard let pairID = linkPairID, let backend, Backend.isConfigured, backend.isLinked else {
            // Nothing here is "can't afford it" — the shortfall exists because the caller believed
            // `pool` covered it, and `pool` only counts a pot this device can actually reach.
            return .unavailable
        }
        miles -= mine
        do {
            guard let newPot = try await backend.spendShared(pair: pairID, amount: shortfall, label: u.name) else {
                miles += mine
                save()
                return .refused
            }
            pot = newPot
            potStale = false
            commit(u, cost: u.cost)
            return .ok
        } catch {
            miles += mine
            save()
            return .unavailable
        }
    }

    /// Grants and records an order once its cost is settled — the spend line, and whatever the
    /// kind grants (stock ownership, a sent gift, or a running unlock). Shared by `payOrder` and
    /// `payOrderShared`'s success path, so there is exactly one place that does this.
    private func commit(_ u: Order, cost: Int) {
        if cost > 0 {
            // The statement records movements of miles, so a free grant leaves no line.
            spends = Array(([SpendEntry(t: Date().timeIntervalSince1970, label: u.name,
                                        mins: u.kind == .unlock ? u.mins : 0, cost: cost)]
                            + spends).prefix(120))
        }

        switch u.kind {
        case .face, .header, .gift:
            if u.kind == .face, let id = u.itemID, !ownedFaces.contains(id) { ownedFaces.append(id) }
            if u.kind == .header, let id = u.itemID, !ownedHeaders.contains(id) { ownedHeaders.append(id) }
            if u.kind == .gift {
                let g = SentGift(t: Date().timeIntervalSince1970,
                                 who: u.who ?? "", email: u.whoEmail,
                                 amt: u.amt, face: u.face)
                sentGifts.insert(g, at: 0)
                giftSent = g.t
            }
            // Concourse stock is granted: no timer, no app to open.

        case .apps:
            // The caller writes the selection once the miles have moved — see `changeSelection`.
            break

        case .unlock:
            let now = Date().timeIntervalSince1970
            let extending = u.extend && unlocked?.id == u.itemID
            // Extending stacks onto the existing deadline and sums the cost, so the running unlock
            // knows its total price. Swapping to another app is not an extend — the miles already
            // spent on the old one are gone.
            let from = extending ? max(now, unlocked?.until ?? now) : now
            unlocked = Unlock(
                id: u.itemID ?? "",
                name: u.name,
                cost: extending ? (unlocked?.cost ?? 0) + u.cost : u.cost,
                mins: u.mins,
                until: from + Double(u.mins) * 60
            )
            startExpiryWatch()
        }
        save()
    }

    /// One visible balance, with an ordered local outbox behind it. Ordinary earning and
    /// redemption never await a connection; only transfers must reconcile first.
    private func changeConfirmedMiles(_ delta: Int) {
        applyingConfirmedMiles = true
        miles += delta
        applyingConfirmedMiles = false
    }

    @MainActor
    private func flushMilesJournal(repairing: Bool = true) async throws {
        guard let backend, let owner = backend.userID else { throw BackendError.notLinked }
        if let previous = milesJournal.owner, previous != owner {
            throw BackendError.rejected("These miles belong to another account. Sign in to that account to send a gift.")
        }
        milesJournal.owner = owner
        saveNow()
        do {
            repeat {
                let wallet = milesJournal.wallet
                let through = try await backend.syncMiles(milesJournal)
                guard backend.userID == owner, milesJournal.wallet == wallet else { throw BackendError.notLinked }
                milesJournal.acknowledge(through: through)
                saveNow()
            } while !milesJournal.pending.isEmpty
        } catch {
            // One repair, one retry, then the refusal stands — see `repairMilesWallet`.
            guard repairing, BackendError.isWalletMismatch(error), await repairMilesWallet() else { throw error }
            try await flushMilesJournal(repairing: false)
        }
    }

    /// **A phone the account does not recognise repairs itself, once.**
    ///
    /// `reconcile_miles` allows exactly one miles stream per account — that is what stops a cloned
    /// install importing its balance a second time — and refuses any other with "Restore the
    /// latest account backup before transferring miles." A fresh `MilesJournal` is minted on every
    /// install that has no saved one (a reinstall, an erased install, a second device), so that
    /// phone could never send or accept a gift again, and the instruction in the message was not
    /// one the app could carry out: signing in after onboarding *pushes* this phone's state over
    /// the cloud backup, so the journal it names is already gone.
    ///
    /// The repair is to ask the account which stream is real (`my_wallet()`, schema part eight)
    /// and adopt it. **Nothing visible moves**: `miles` is this phone's own figure and is not
    /// touched. What is dropped is an outbox the server has never seen and never will — entries
    /// on a stream that does not exist for this account — so the only consequence is that the
    /// server's idea of the transferable balance is its own, which is what it was going to be
    /// either way.
    @MainActor
    private func repairMilesWallet() async -> Bool {
        guard let backend, let owner = backend.userID else { return false }
        guard let server = try? await backend.myWallet() else { return false }
        guard backend.userID == owner else { return false }
        guard server.wallet != milesJournal.wallet || server.sequence != milesJournal.sequence else { return false }
        milesJournal.adopt(wallet: server.wallet, sequence: server.sequence, owner: owner)
        saveNow()
        return true
    }

    /// Server text is written for whoever holds the database, not for a member looking at a gift
    /// they cannot accept: "Restore the latest account backup before transferring miles" names an
    /// action this app has never offered. `repairMilesWallet` is that action, and it has already
    /// been tried by the time this line is written — so what is left to say is that the gift is
    /// still there.
    @MainActor
    private static func giftFailureText(_ error: Error) -> String {
        guard BackendError.isWalletMismatch(error) else { return Backend.describe(error) }
        return "This phone's miles could not be matched to your account. Nothing was lost — the gift is still waiting."
    }

    @MainActor
    private func payGift(_ order: Order) async -> PayOutcome {
        guard !giftNetworking else { return .unavailable }
        guard let backend, let owner = backend.userID, Backend.isConfigured else {
            giftFailed = "Connect and sign in to send a gift."
            return .unavailable
        }
        if let pendingGift, pendingGift.order.id != order.id {
            giftFailed = "Your previous gift is awaiting confirmation. Its miles are reserved."
            return .unavailable
        }
        giftNetworking = true
        defer { giftNetworking = false }
        do {
            if pendingGift == nil {
                guard order.amt > 0, order.cost >= order.amt, order.cost <= pool else { return .refused }
                try await flushMilesJournal()
                guard backend.userID == owner, order.cost <= pool else { return .refused }
                let personal = min(miles, order.cost)
                guard personal == order.cost || linkPairID != nil else { return .refused }
                pendingGift = PendingGift(order: order, owner: owner, wallet: milesJournal.wallet,
                    entries: milesJournal.pending, sequence: milesJournal.sequence,
                    personal: personal, pair: personal < order.cost ? linkPairID : nil,
                    fromName: cardName)
                changeConfirmedMiles(-personal)
                // Reservation + retry payload travel in the SAME durable snapshot.
                saveNow()
            }
            return try await settlePendingGift()
        } catch {
            giftFailed = pendingGift == nil ? Self.giftFailureText(error)
                : "This gift is awaiting confirmation. Its miles are reserved; reconnect to finish sending."
            return .unavailable
        }
    }

    @MainActor
    private func settlePendingGift() async throws -> PayOutcome {
        guard let pending = pendingGift, let backend,
              pending.owner == backend.userID, pending.wallet == milesJournal.wallet else {
            throw BackendError.notLinked
        }
        let result = try await backend.sendGift(pending)
        guard pendingGift?.order.id == pending.order.id,
              backend.userID == pending.owner, milesJournal.wallet == pending.wallet else {
            throw BackendError.notLinked
        }
        guard result.state == "sent" || result.state == "refused" else { throw BackendError.transport }
        milesJournal.acknowledge(through: result.sequence)
        pendingGift = nil
        if result.state == "sent" {
            if let balance = result.pot { pot = balance; potStale = false }
            giftFailed = nil
            commit(pending.order, cost: pending.order.cost)
            saveNow()
            return .ok
        }
        // Only a durable server refusal releases the reservation, never a timeout.
        changeConfirmedMiles(pending.personal)
        giftFailed = result.reason ?? "The gift could not be sent. No miles were spent."
        saveNow()
        return .refused
    }

    /// **Accepting says something, always.** A gift delivered by the server is claimed through
    /// `receive_gift`, and every way that can fail — no backend, signed out, the wallet refused,
    /// the network down — used to leave the row sitting there with nothing having happened and
    /// nothing said, which is indistinguishable from a dead button. The claim is still durable
    /// (it is queued in `pendingGiftReceipts` and retried on the next foreground), but the
    /// failure is now named in `giftFailed`, which Status Club prints under the Requests card.
    func acceptGift(_ id: TimeInterval) {
        guard let g = receivedGifts.first(where: { $0.t == id }) else { return }
        giftFailed = nil
        guard let remoteID = g.remoteID else {
            receivedGifts.removeAll { $0.t == id }
            creditGift(from: g.from, amount: g.amt)
            return
        }
        if !pendingGiftReceipts.contains(where: { $0.remoteID == remoteID }) {
            pendingGiftReceipts.append(g)
            saveNow()
        }
        guard backend != nil, Backend.isConfigured else {
            giftFailed = "Connect an account to accept this gift. It will be waiting."
            return
        }
        guard !giftNetworking else {
            giftFailed = "Finishing the last gift first — this one is next."
            return
        }
        Task { @MainActor [weak self] in await self?.resumeGifts() }
    }

    /// Finish interrupted operations before syncing later offline spends. Otherwise a newer
    /// batch could overtake the transfer's frozen sequence. Called on launch and foreground.
    @MainActor
    private func resumeGifts() async {
        guard !giftNetworking, let backend else { return }
        guard backend.isLinked else {
            // Only when this device is actually holding a claim: a launch with nothing pending has
            // nothing to report, and this line is printed under Status Club's Requests card.
            if !pendingGiftReceipts.isEmpty {
                giftFailed = "Sign in to accept this gift. It will be waiting."
            }
            return
        }
        giftNetworking = true
        defer { giftNetworking = false }
        do {
            if pendingGift != nil { _ = try await settlePendingGift() }
            try await flushMilesJournal()
            for gift in pendingGiftReceipts {
                guard let id = gift.remoteID else { continue }
                let journal = milesJournal
                let receipt = try await backend.acceptGift(id: id, journal: journal)
                guard backend.userID == journal.owner, milesJournal.wallet == journal.wallet else {
                    throw BackendError.notLinked
                }
                milesJournal.acknowledge(through: receipt.sequence)
                if receipt.amount > 0, milesJournal.receive(id) {
                    changeConfirmedMiles(receipt.amount)
                    credits.insert(CreditEntry(t: Date().timeIntervalSince1970,
                        label: "Gift from \(gift.from)", amt: receipt.amount), at: 0)
                }
                pendingGiftReceipts.removeAll { $0.remoteID == id }
                receivedGifts.removeAll { $0.remoteID == id }
                saveNow()
            }
        } catch {
            // Keep the durable operation for the next foreground/retry. Local spending stays live.
            giftFailed = pendingGift == nil ? Self.giftFailureText(error)
                : "This gift is awaiting confirmation. Its miles are reserved; reconnect to finish sending."
        }
    }

    private func creditGift(from: String, amount: Int) {
        miles += amount
        credits.insert(CreditEntry(t: Date().timeIntervalSince1970,
                                   label: "Gift from \(from)", amt: amount), at: 0)
        save()
    }

    /// Declining a local seam just drops it; declining a real one tells the server too, so the row
    /// stops showing up in `openGifts().incoming` on every other device this member owns.
    func declineGift(_ id: TimeInterval) {
        guard let i = receivedGifts.firstIndex(where: { $0.t == id }) else { return }
        let g = receivedGifts.remove(at: i)
        save()
        guard let remoteID = g.remoteID, let backend, Backend.isConfigured else { return }
        Task { @MainActor in
            guard backend.isLinked else { return }
            try? await backend.declineGift(id: remoteID)
        }
    }

    /// Mirrors a real invite into the `link`/`linkInviteID` pair this app already displays and
    /// acts on, so `acceptLinkRequest`/`declineLinkRequest`/`withdrawLinkRequest` know which server
    /// row to answer. `LinkInvite` only carries `fromUser`, a user id this model has no reason to
    /// know — `iSent` is how the two directions are told apart instead.
    func showInvite(_ invite: LinkInvite, iSent: Bool) {
        linkInviteID = invite.id
        let at = ISO8601DateFormatter().date(from: invite.createdAt)?.timeIntervalSince1970
            ?? Date().timeIntervalSince1970
        link = LinkAccount(name: iSent ? invite.toName : invite.fromName,
                           email: iSent ? invite.toEmail : nil,
                           miles: 0, at: at, pending: true, requestedByThem: !iSent)
    }

    /// Accepting an incoming link request is what actually shares the bank. With a live backend
    /// and a real invite behind it (`linkInviteID`, set by `showInvite`), this asks the server
    /// first — a pair that only exists on one phone shares nothing — and adopts the pot it comes
    /// back with. With no server, or no invite behind `link` (a demo seam), it is exactly the old
    /// purely local accept.
    ///
    /// `Backend.isLinked` is `@MainActor`, so it can only be read from inside the `Task` below —
    /// the decision between the two paths is made there, not in this synchronous entry point.
    /// A build with no `backend` at all (every self-check model, and every unconfigured install)
    /// never creates the `Task`, so the local path stays perfectly synchronous for them.
    func acceptLinkRequest() {
        guard let l = link, l.isIncomingRequest else { return }
        guard let inviteID = linkInviteID, let backend, Backend.isConfigured else {
            applyLocalAccept()
            return
        }
        let name = l.name
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard backend.isLinked else { self.applyLocalAccept(); return }
            guard let pair = try? await backend.acceptInvite(id: inviteID) else {
                // Still open server-side; leave `link` exactly as it was so the member can retry
                // rather than silently losing the request.
                return
            }
            self.linkPairID = pair.id
            self.pot = pair.miles
            self.potStale = false
            self.linkInviteID = nil
            var l = self.link ?? LinkAccount(name: name, miles: 0, at: Date().timeIntervalSince1970)
            l.name = name
            l.pending = false
            l.requestedByThem = nil
            self.link = l
            await self.mergePersonalMiles(into: pair.id)
        }
    }

    private func applyLocalAccept() {
        guard var l = link, l.isIncomingRequest else { return }
        l.pending = false
        l.requestedByThem = nil
        link = l
    }

    /// Declines an incoming request, or withdraws one this device sent — both just drop `link`
    /// locally; the difference is only which side answers the real invite, when there is one.
    func declineLinkRequest() {
        guard link?.isIncomingRequest == true else { return }
        answerInvite()
    }

    /// This device's own outgoing request, taken back. `LinkedScreen` cancels the same way it
    /// declines an incoming one — `link = nil` — so this exists to also tell the server, when
    /// there is a real invite behind the request.
    func withdrawLinkRequest() {
        guard let l = link, l.isPending, !l.isIncomingRequest else { return }
        answerInvite()
    }

    /// The local drop is unconditional and synchronous for both callers above — there is no local
    /// vs. server difference in what a decline or a withdrawal leaves behind. Telling the server is
    /// the only part that needs `Backend.isLinked`, so it is the only part inside the `Task`.
    private func answerInvite() {
        let inviteID = linkInviteID
        link = nil
        linkInviteID = nil
        guard let inviteID, let backend, Backend.isConfigured else { return }
        Task { @MainActor [weak self] in
            guard backend.isLinked else { return }
            // Withdrawing and declining are the same RPC shape from opposite ends; either 404s
            // harmlessly if the other side already answered it.
            try? await self?.backend?.declineInvite(id: inviteID)
            try? await self?.backend?.withdrawInvite(id: inviteID)
        }
    }

    /// Ends a linked pair. With a live backend and a real pair behind `link`, this asks the server
    /// for this member's half of the pot (`unlinkPair` — the odd mile stays behind, see `Backend`)
    /// and credits it to personal before dropping the link. With no server, or no real pair behind
    /// this link, it is a local-only reset. Already `@MainActor`, so `backend.isLinked` reads
    /// directly here — unlike the synchronous entry points above, there is no isolation boundary
    /// to cross.
    @MainActor
    func unlinkAccount() async {
        guard link != nil else { return }
        guard let pairID = linkPairID, let backend, Backend.isConfigured, backend.isLinked else {
            link = nil
            linkPairID = nil
            pot = 0
            potStale = false
            save()
            return
        }
        // Nothing moves until the server confirms — a failure here leaves the pair intact rather
        // than dropping it locally and losing the pot's remaining share.
        guard (try? await backend.unlinkPair(pair: pairID)) != nil else { return }
        link = nil
        linkPairID = nil
        pot = 0
        potStale = false
        save()
        // The share comes back through the payout, not the reply — see `Backend.unlinkPair`.
        await collectPayouts()
    }

    /// Credits whatever the server is holding for this member from an unlink — theirs or the
    /// other side's — and writes the statement line that says where the miles came from. Safe to
    /// call any time; a claim of nothing is a no-op.
    @MainActor
    private func collectPayouts() async {
        guard let backend, Backend.isConfigured, backend.isLinked,
              let claimed = try? await backend.claimPayouts(), claimed > 0 else { return }
        miles += claimed
        credits.insert(CreditEntry(t: Date().timeIntervalSince1970,
                                   label: "Shared bank unlinked", amt: claimed), at: 0)
        save()
    }

    /// Queues a landing's earn for the shared pot and fires an immediate retry — `land()`'s only
    /// caller, so an earn is never dropped even if the pot cannot be reached the instant it lands.
    private func queuePotCredit(pair: String, amount: Int, label: String) {
        guard amount > 0 else { return }
        pendingPotCredits.append(PotCredit(id: Date().timeIntervalSince1970, pair: pair,
                                           amount: amount, label: label, op: UUID().uuidString))
        save()
        Task { @MainActor [weak self] in await self?.flushPendingPotCredits() }
    }

    /// Retries every queued landing credit against the shared pot, oldest first, stopping at the
    /// first one that still cannot be delivered so a later flight's credit never lands ahead of an
    /// earlier one's. Safe to call any time — an empty queue, or no reachable backend, returns at
    /// once — and never polled; `kickSharedBank` and `refreshOnForeground` are its only callers.
    @MainActor
    func flushPendingPotCredits() async {
        guard let backend, Backend.isConfigured, backend.isLinked else { return }
        while let credit = pendingPotCredits.first {
            let op = credit.op ?? UUID().uuidString
            if credit.op == nil { pendingPotCredits[0].op = op; save() }
            guard let newPot = try? await backend.earnShared(pair: credit.pair, amount: credit.amount,
                                                              label: credit.label, op: op) else {
                potStale = true
                return
            }
            pot = newPot
            potStale = false
            pendingPotCredits.removeFirst()
            save()
        }
    }

    /// **Linking merges the two banks, at once.** The pot used to start empty and fill from the
    /// next landing on, so two members who linked with 3,000 mi and 81 mi between them saw a
    /// shared bank of 0 and concluded the link was broken. Each phone now deposits its own
    /// personal balance into the pot the first time it sees the pair live — the accepter from
    /// `acceptLinkRequest`, the sender from the next `refreshSharedBank` that finds a real pair —
    /// so `pool` never changes: the same miles are simply held by the pair instead of the member.
    ///
    /// `deposit_to_pair`, not `earnShared`: a landing's credit is capped at 2,000 a call and 3,000
    /// a rolling day, and a balance is neither. **Nothing is zeroed until the server answers**, so
    /// a deposit that cannot be delivered leaves the miles exactly where they are and `potStale`
    /// set; the next screen that refreshes tries again. A dropped reply is safe either way — the
    /// member's own ledger line is the idempotency key, so the retry answers with the same pot.
    @MainActor
    private func mergePersonalMiles(into pair: String) async {
        guard !mergedPairs.contains(pair) else { return }
        guard let backend, Backend.isConfigured, backend.isLinked, let owner = backend.userID else { return }
        let amount = miles
        guard amount > 0 else { mergedPairs.append(pair); save(); return }
        // The server pays the deposit out of the reconciled wallet, so the journal is delivered
        // first and the local debit is a confirmed one — journaling it too would spend it twice.
        guard (try? await flushMilesJournal()) != nil,
              let settled = try? await backend.depositShared(pair: pair, journal: milesJournal,
                                                             owner: owner, amount: amount),
              backend.userID == owner else {
            potStale = true
            return
        }
        milesJournal.acknowledge(through: settled.sequence)
        changeConfirmedMiles(-min(amount, miles))
        pot = settled.pot
        potStale = !pendingPotCredits.isEmpty
        mergedPairs.append(pair)
        save()
    }

    /// Received gifts, fetched fresh. The same "no push" fact the shared bank already lives with —
    /// nothing tells this device a gift arrived, so it is picked up wherever this device already
    /// asks the server something (a foreground, or opening Status Club — see `refreshSharedBank`).
    /// Replaces the array outright rather than merging: `openGifts().incoming` already excludes
    /// anything this member has answered, from any device, so there is nothing stale to preserve.
    @MainActor
    private func refreshGifts() async {
        guard let backend, Backend.isConfigured, backend.isLinked,
              let incoming = try? await backend.openGifts().incoming else { return }
        receivedGifts = incoming.map { g in
            ReceivedGift(t: ISO8601DateFormatter().date(from: g.createdAt)?.timeIntervalSince1970
                            ?? Date().timeIntervalSince1970,
                         from: g.fromName, amt: g.amount, face: g.face, remoteID: g.id)
        }
    }

    /// Fetches the pot fresh from the server, and refreshes received gifts alongside it — both are
    /// facts nothing pushes to this device, so both need picking up wherever this device already
    /// asks the server something. Safe to call on foreground and after any shared movement; nothing
    /// here polls. Also the one place a sender discovers their invite was accepted elsewhere —
    /// there is no push, so a still-pending `link` is reconciled against whatever pair the server
    /// now has.
    @MainActor
    func refreshSharedBank() async {
        guard let backend, Backend.isConfigured, backend.isLinked else { return }
        // **Deliver what this phone still owes the pot before reading the pot back.** A landing
        // whose `earn_to_pair` could not be reached queues a `PotCredit` and sets `potStale`;
        // this function then fetched the server's figure, wrote it over `pot` and cleared
        // `potStale` — so the member's own miles vanished from the pool on the next screen that
        // asked, and the app called the number confirmed. Home, Redeem, Linked and Status Club
        // all arrive through here, and only launch and foregrounding flushed the queue, so the
        // miles came back whenever the app was next backgrounded and not before.
        await flushPendingPotCredits()
        let pair: LinkPair?
        do {
            pair = try await backend.currentPair()
        } catch {
            potStale = true
            return
        }
        // Either side may have unlinked since this phone last looked; the half owed is waiting.
        await collectPayouts()
        await refreshGifts()
        guard let pair else {
            // No pair server-side — never linked, or the other side unlinked from under us.
            if link?.isPending == false { link = nil; linkPairID = nil }
            pot = 0
            potStale = false
            save()
            return
        }
        linkPairID = pair.id
        pot = pair.miles
        // A credit the flush above could not deliver is still owed to this figure.
        potStale = !pendingPotCredits.isEmpty
        // The sender's side of a merge: this phone only learns its invite was accepted here.
        await mergePersonalMiles(into: pair.id)
        if var l = link, l.isPending {
            l.pending = false
            l.requestedByThem = nil
            link = l
        } else if link == nil || link?.name == AppModel.unnamedPartner {
            // **The partner has a name, and it is still on the invite.** `LinkPair` carries two
            // user ids and nothing else, and there is no profile table to look one up in — so a
            // device that never saw the invite itself (a reinstall, a second phone) used to show
            // the placeholder for the life of the link. The invite row survives being accepted
            // and RLS lets both ends read it, so `partnerName()` reads the name back off it. The
            // placeholder is only what stands there while that call is out, or if it finds
            // nothing — and an already-placeholdered link is upgraded the next time it is asked.
            let recovered = try? await backend.partnerName()
            link = LinkAccount(name: recovered.flatMap { $0 } ?? AppModel.unnamedPartner,
                               email: link?.email,
                               miles: link?.miles ?? 0,
                               at: link?.at ?? Date().timeIntervalSince1970,
                               log: link?.log ?? [])
        }
        save()
    }

    /// Fires a best-effort flush-then-refresh: once when the backend first arrives (app launch,
    /// via `backend`'s `didSet`), and again from `refreshOnForeground`. Never a poll — each call is
    /// one attempt, not a timer. `flushPendingPotCredits`/`refreshSharedBank` each already no-op
    /// when `Backend.isLinked` is false, so this only needs the synchronous-safe checks.
    private func kickSharedBank() {
        guard backend != nil, Backend.isConfigured else { return }
        Task { @MainActor [weak self] in
            await self?.resumeGifts()
            await self?.flushPendingPotCredits()
            await self?.refreshSharedBank()
        }
    }

    /// One owner of expiry: when the deadline passes the unlock clears, and the shield goes back up.
    ///
    /// Also the one place that knows an unlock has just started or moved, so it is where the Live
    /// Activity is raised. It is armed from `init`, from every `payOrder(.unlock)`, and nowhere
    /// else, which makes it the only hook that cannot miss one.
    private func startExpiryWatch() {
        expiryTask?.cancel()
        guard let u = unlocked else { return }

        if liveActivity {
            UnlockActivityController.start(name: u.name,
                                           startedAt: Date(timeIntervalSince1970: u.until - Double(u.mins) * 60),
                                           until: Date(timeIntervalSince1970: u.until))
        }

        expiryTask = Task { @MainActor [weak self] in
            let wait = u.until - Date().timeIntervalSince1970
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard !Task.isCancelled, let self, self.unlocked?.until == u.until else { return }
            self.clearUnlock()
        }
    }

    /// An unlock stops being live. **The only place that says so.**
    ///
    /// Three sites used to write `unlocked = nil; save()` by hand — the expiry task, the foreground
    /// refresh, and the erase — which is three chances for one of them to forget a step the day a
    /// step is added. Raising a Live Activity was exactly such a step.
    private func clearUnlock() {
        guard unlocked != nil else { return }
        unlocked = nil
        expiryTask?.cancel()
        expiryTask = nil
        UnlockActivityController.end()
        save()
    }

    /// Called when the app comes back to the foreground: a deadline may have passed while away.
    func refreshOnForeground() {
        if let u = unlocked, u.expired { clearUnlock() }
        // Nothing here may have changed and the shield can still be stale: Screen Time can be
        // granted or revoked in iOS Settings while Tempus is closed, and neither writes anything
        // this model would notice. Reconciling costs a mirror write and settles it either way.
        reconcileBlocking()
        if phase == .flying { startTicking() }
        if biz && phase == .flying { showStayOpenToast() }
        kickSharedBank()
    }

    private func showStayOpenToast() {
        toastTask?.cancel()
        stayOpenToast = true
        toastTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(2600))
            guard !Task.isCancelled else { return }
            self?.stayOpenToast = false
        }
    }

    // MARK: - Tasks

    func addTask(title: String) {
        let id = "t\(Int(Date().timeIntervalSince1970 * 1000))"
        tasks.insert(TaskItem(id: id, title: title,
                              miles: Status.earn(minutes: defaultMinutes, rate: rate, mult: 1)),
                     at: 0)
        order = 0
        dropID = id
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            if self?.dropID == id { self?.dropID = nil }
        }
        save()
    }

    func updateTask(id: String, title: String) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[i].title = title
        save()
    }

    func deleteTask(id: String) {
        tasks.removeAll { $0.id == id }
        order = 0
        save()
    }

    func advanceDeck() { order += 1 }

    func setDefaultMinutes(_ m: Int) {
        defaultMinutes = m
        minutes = m
        save()
    }

    func setHomeAirport(_ code: String) {
        homeAirport = Geography.byCode(code)
        Geography.setHome(code)
        save()
    }

    /// Onboarding hands back what it collected.
    func finishOnboarding(blocked apps: [String], minutes m: Int, home code: String?, limit: Int) {
        blocked = apps.isEmpty ? ["ig"] : apps
        setDefaultMinutes(m)
        spendLimit = max(0, limit)
        if let code { setHomeAirport(code) }
        deal = true
        onboarded = true
        go(.home, .none)
        save()
    }

    // MARK: - Persistence

    /// Every field optional, so an older blob still decodes.
    struct Stored: Codable {
        var onboarded: Bool?
        var miles: Int?
        var milesJournal: MilesJournal?
        var pendingGift: PendingGift?
        var pendingGiftReceipts: [ReceivedGift]?
        var tasks: [TaskItem]?
        var blocked: [String]?
        var selection: Data?
        var defaultMin: Int?
        var spendLimit: Int?
        var weeklyGoal: Int?
        var homeAp: String?
        var firstRun: TimeInterval?
        var member: String?
        var notif: Bool?
        var live: Bool?
        var plus: Bool?
        var devPlus: Bool?
        var devMode: Bool?
        var devSkipBio: Bool?
        var devIgnoreGuard: Bool?
        var rate: Double?
        var spend: Double?
        var policy: String?
        var horizon: Int?
        var excluded: [String]?
        var unlocked: Unlock?
        var hlog: [Status.HourEntry]?
        var periodAck: Int?
        var flights: [FlightRecord]?
        var marks: Marks?
        var cardV: [Int]?
        var fdrSerial: Int?
        var fdrIssued: TimeInterval?
        var link: LinkAccount?
        /// The shared pot: which real pair backs `link`, its last-known value, and any landing
        /// credit still waiting to reach it. `potStale` is deliberately absent — every launch
        /// starts unconfirmed regardless of what was last on disk.
        var linkPairID: String?
        var pot: Int?
        var mergedPairs: [String]?
        var linkInviteID: String?
        var potCredits: [PotCredit]?
        var spends: [SpendEntry]?
        var ownedFaces: [String]?
        var ownedHeaders: [String]?
        var sentGifts: [SentGift]?
        var receivedGifts: [ReceivedGift]?
        var credits: [CreditEntry]?

        // A flight in the air. The reference does not persist these — it is a browser demo and a
        // reload loses the flight. A phone can be killed mid-flight, so the deadline and everything
        // needed to redraw the flight survive here.
        var phase: String?
        var endsAt: TimeInterval?
        var minutes: Int?
        var destination: Destination?
        var operatedBy: Carriers.Operated?
        var passHeader: String?
        var biz: Bool?
        var strikes: Int?
        var flightNo: String?

        /// The airport the last landing departed from, for the arrival screen's route strip.
        /// Optional like every other field here, so an old blob without it just draws the strip
        /// with no origin label rather than failing to decode.
        var landedFrom: String?
    }

    static let storeKey = "tempus.app.v2"

    /// Wipe the install back to a first launch. Developer mode only.
    ///
    /// The stored blob is removed by the caller; this resets the live model to match, because the
    /// blob is only read in `init` and nothing else re-reads it.
    func eraseAndRestart() {
        restore(from: AppModel(stored: nil))
        goDirect(.ob)
        deal = true
    }

    /// Copy another model's entire state over this one, live.
    ///
    /// `Stored` is read in `init` and nowhere else, so the only way to adopt a different save file
    /// mid-session is to build a model from it and move the fields across. An erase and a cloud
    /// restore are the same act with a different blob, so they run the same body — a field added
    /// to `Stored` that is forgotten here is forgotten by both, never by one.
    ///
    /// `ready` goes down first so the writes below cannot each persist the file they are undoing.
    private func restore(from fresh: AppModel) {
        ready = false
        tickTask?.cancel(); tickTask = nil
        expiryTask?.cancel(); expiryTask = nil
        focusGuard.flightEnded()
        spentChances = 0
        LiveActivityController.end()
        UnlockActivityController.end()

        miles = fresh.miles
        milesJournal = fresh.milesJournal
        pendingGift = fresh.pendingGift
        pendingGiftReceipts = fresh.pendingGiftReceipts
        tasks = fresh.tasks
        blocked = fresh.blocked
        defaultMinutes = fresh.defaultMinutes
        minutes = fresh.minutes
        member = fresh.member
        notifications = fresh.notifications
        liveActivity = fresh.liveActivity
        rate = fresh.rate
        spend = fresh.spend
        policy = fresh.policy
        horizon = fresh.horizon
        excluded = fresh.excluded
        homeAirport = fresh.homeAirport
        firstRun = fresh.firstRun
        founderSerial = fresh.founderSerial
        founderIssued = fresh.founderIssued
        cardVariant = fresh.cardVariant
        hourLog = fresh.hourLog
        periodAck = fresh.periodAck
        flights = fresh.flights
        spends = fresh.spends
        marks = fresh.marks
        ownedFaces = fresh.ownedFaces
        ownedHeaders = fresh.ownedHeaders
        sentGifts = fresh.sentGifts
        receivedGifts = fresh.receivedGifts
        credits = fresh.credits
        link = fresh.link
        linkPairID = fresh.linkPairID
        pot = fresh.pot
        // A restore (an erase, or a cloud pull) means the number on screen has not been confirmed
        // by this session — same reasoning as a cold launch.
        potStale = true
        linkInviteID = fresh.linkInviteID
        pendingPotCredits = fresh.pendingPotCredits
        mergedPairs = fresh.mergedPairs
        unlocked = fresh.unlocked
        endsAt = fresh.endsAt
        destination = fresh.destination
        landedAt = fresh.landedAt
        landedFrom = fresh.landedFrom
        operatedBy = fresh.operatedBy
        passHeader = fresh.passHeader
        biz = fresh.biz
        diverted = fresh.diverted
        penalty = fresh.penalty
        leftAt = fresh.leftAt
        bankedMiles = fresh.bankedMiles
        elapsed = fresh.elapsed
        hasLanded = fresh.hasLanded
        tierUp = fresh.tierUp
        speed = fresh.speed
        devMode = fresh.devMode
        devSkipBiometrics = fresh.devSkipBiometrics
        devIgnoreFocusGuard = fresh.devIgnoreFocusGuard
        setPlus(fresh.devPlus, source: .developer)
        setPlus(fresh.storePlus, source: .store)
        onboarded = fresh.onboarded
        // Four fields used to be missing here while being present in `Stored`, `init` and `save`.
        // `restore` ends in a `save()` that pushes the result back to the account, so a sign-in on
        // a second phone did not merely fail to read them — it overwrote them at source, and the
        // first phone lost them on its next pull.
        spendLimit = fresh.spendLimit
        weeklyGoal = fresh.weeklyGoal
        selection = fresh.selection
        Geography.setHome(homeAirport.code)

        ready = true
        save()
    }

    static func load() -> Stored? {
        guard let data = UserDefaults.standard.data(forKey: storeKey) else { return nil }
        return try? JSONDecoder().decode(Stored.self, from: data)
    }

    /// Persist, on the next runloop turn.
    ///
    /// **Encoding the store is not free, and `save()` is called from nearly every `didSet` in this
    /// class.** `Stored` carries 200 flights, the hours ledger, the statement, the owned catalogue
    /// and the whole selection blob; `JSONEncoder` walks all of it on the main thread, and
    /// `syncSharedStore()` follows with a second encode into the App Group. A dial drag used to
    /// pay that bill many times a second — the file already said so — and, worse,
    /// `closeCardDesign` pays it through `goDirect` on the exact frame the card studio begins its
    /// exit fade. Tens of milliseconds spent encoding during a 220 ms cross-fade is dropped
    /// frames, and a cross-fade that drops its first frames does not read as slow: it reads as a
    /// *flicker*, which is precisely what has been reported coming back from the studio.
    ///
    /// So this coalesces. Every caller keeps calling `save()` as often as it likes and at most one
    /// encode happens per runloop turn, off the frame that asked for it. The exposure that buys is
    /// one turn of unsaved state, which `saveNow()` closes at the two moments that actually matter
    /// — going to the background, and terminating.
    func save() {
        guard ready, !savePending else { return }
        savePending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.savePending = false
            self.saveNow()
        }
    }

    /// Encode and write immediately, skipping the coalescing. For the moments that cannot afford
    /// to lose a runloop turn: backgrounding, termination, and anything that must be on disk
    /// before another process reads it.
    func saveNow() {
        guard ready else { return }
        savePending = false
        var s = Stored()
        s.onboarded = onboarded
        s.miles = miles
        s.milesJournal = milesJournal
        s.pendingGift = pendingGift
        s.pendingGiftReceipts = pendingGiftReceipts
        s.tasks = tasks
        s.blocked = blocked
        s.selection = selectionData
        s.defaultMin = defaultMinutes
        s.spendLimit = spendLimit
        s.weeklyGoal = weeklyGoal
        s.homeAp = homeAirport.code
        s.firstRun = firstRun
        s.member = member
        s.notif = notifications
        s.live = liveActivity
        // What the STORE last said, never the effective value — `init` seeds `storePlus` from
        // this, so writing the OR'd `plus` here would launder a developer grant into a
        // purchase that no longer has a switch to turn it off.
        s.plus = storePlus
        s.devPlus = devPlus
        s.devMode = devMode
        s.devSkipBio = devSkipBiometrics
        s.devIgnoreGuard = devIgnoreFocusGuard
        s.rate = rate
        s.spend = spend
        s.policy = policy.rawValue
        s.horizon = horizon
        s.excluded = Array(excluded)
        s.unlocked = unlocked
        s.hlog = hourLog
        s.periodAck = periodAck
        s.flights = Array(flights.prefix(200))
        s.marks = marks
        s.cardV = cardVariant
        s.fdrSerial = founderSerial
        s.fdrIssued = founderIssued
        s.link = link
        s.linkPairID = linkPairID
        s.pot = pot
        s.mergedPairs = mergedPairs
        s.linkInviteID = linkInviteID
        s.potCredits = pendingPotCredits
        s.spends = spends
        s.ownedFaces = ownedFaces
        s.ownedHeaders = ownedHeaders
        s.sentGifts = sentGifts
        s.receivedGifts = receivedGifts
        s.credits = credits
        s.landedFrom = landedFrom

        if phase == .flying, let endsAt {
            s.phase = Phase.flying.rawValue
            s.endsAt = endsAt.timeIntervalSince1970
            s.minutes = minutes
            s.destination = destination
            s.operatedBy = operatedBy
            s.passHeader = passHeader
            s.biz = biz
            s.flightNo = flightNo
            s.strikes = spentChances
        }

        if let data = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(data, forKey: AppModel.storeKey)
            // The same bytes go to the cloud copy, debounced — `save()` runs on nearly every
            // mutation and a dial drag calls it many times a second. Nil until a member has signed
            // in to backup, so an unlinked install does no work here at all.
            // `save()` is nonisolated and `Backend` is main-actor, so this hops. The nonisolated
            // check in front of it means an unconfigured build and an unlinked member never even
            // make the Task.
            if Backend.isConfigured, let backend {
                Task { @MainActor in backend.schedulePush(data) }
            }
        }
        syncSharedStore()
    }

    /// Set once, at launch, by whoever owns the `Backend`. Weak-by-convention rather than an
    /// `@Observable` dependency: the model must keep working identically when it is nil, which is
    /// every build with no Supabase project and every member who never signed in.
    ///
    /// Also the app-launch hook for the shared pot: `TempusApp` assigns this once, after a
    /// previous session's sign-in has already come back from the Keychain, so the moment it lands
    /// is the moment a flush-then-refresh is worth trying.
    var backend: Backend? { didSet { kickSharedBank() } }

    /// Replace this install's entire state with a restored save file, live.
    ///
    /// `Stored` is only read in `init`, so there is no way to adopt a blob mid-session except to
    /// build a fresh model from it and copy the fields across — which is exactly what
    /// `eraseAndRestart` already does with `AppModel(stored: nil)`. This is that same body with
    /// the blob passed in, so the two can never drift: a restore and an erase move identical
    /// state, and anything a future field needs copying gets copied by both or neither.
    func adopt(_ stored: Stored?) {
        restore(from: AppModel(stored: stored))
    }

    /// A sign-in just succeeded. Exchange its token for a Supabase session, then decide which save
    /// file wins. Returns true when a cloud save was adopted, so the caller can route to a member
    /// who is already set up rather than walk them through onboarding again.
    ///
    /// **A restore only ever runs on an install that has not been onboarded** — the new-phone case,
    /// which is the only thing the copy promises. An install that already carries its own history
    /// pushes that up instead, because adopting a cloud blob over live local state would silently
    /// delete miles, passes and a flight log the member can see on screen.
    ///
    /// Nothing here is allowed to fail loudly: a member signing in for their name on the card did
    /// not ask for a backup and must not be shown its errors. `Backend.state` carries them for
    /// Settings to report.
    ///
    /// ponytail: no merge and no last-write-wins, because with one device there is nothing to
    /// resolve. Two phones on one account need the server to own the balance — that is the shared
    /// bank, not this.
    @MainActor
    @discardableResult
    func linkBackup(idToken: String, nonce: String?, provider: AuthProvider) async -> Bool {
        guard let backend, Backend.isConfigured else { return false }
        do {
            try await backend.link(idToken: idToken, nonce: nonce, provider: provider)
        } catch {
            return false
        }
        if onboarded {
            // The bytes `save()` last wrote are already the snapshot; re-encoding would only risk
            // producing a different one.
            if let data = UserDefaults.standard.data(forKey: AppModel.storeKey) {
                await backend.push(data)
            }
            return false
        }
        guard let data = try? await backend.pull(),
              let stored = try? JSONDecoder().decode(Stored.self, from: data),
              stored.onboarded == true else { return false }
        adopt(stored)
        return true
    }

    /// The one door in and out of an account. `Identity` puts the name on the card and `Backend`
    /// holds the session that backs it up, and the two only ever move together: a sign-in that
    /// forgets the link leaves backup silently off for the rest of that install's life, and a
    /// sign-out that forgets it keeps pushing this phone's state into the account that just left.
    ///
    /// The result is three-way because onboarding routes on it — a cancel stays where it is, a
    /// plain sign-in walks on, and a cloud save that was adopted lands on Home instead.
    @MainActor
    @discardableResult
    func signIn(_ provider: AuthProvider, identity: Identity, email: String = "") async -> SignInResult {
        let ok: Bool
        switch provider {
        case .apple: ok = await identity.signInWithApple()
        case .google: ok = await identity.signInWithGoogle()
        case .email: ok = await identity.signInWithEmail(email)
        }
        guard ok else { return .failed }
        guard let token = identity.lastIDToken else { return .signedIn }
        let restored = await linkBackup(idToken: token, nonce: identity.lastNonce, provider: provider)
        // Apple's authorization code can be exchanged for five minutes and never again, so the
        // refresh token it buys is banked now — it is what `deleteAccount` revokes later, which is
        // the half of deletion Apple asks of every app that offers Sign in with Apple.
        if provider == .apple, let code = identity.lastAppleCode { await backend?.storeAppleCode(code) }
        return restored ? .restored : .signedIn
    }

    enum SignInResult { case failed, signedIn, restored }

    /// Signing out takes the backup session with it. What is on this phone stays on this phone;
    /// what it stops doing is writing to somebody else's row.
    @MainActor
    func signOutAccount(_ identity: Identity) {
        identity.signOut()
        backend?.signOut()
    }

    /// Everything this app has ever written on this phone, in the three places it writes: the
    /// model's own blob, the account, and the App Group — which has to go too, or the extensions
    /// keep shielding against a balance that no longer exists. The shield comes down with it, or
    /// the phone stays locked out of apps the app no longer has any record of blocking.
    ///
    /// One writer for two callers: developer mode's "Erase this install" and deleting the account,
    /// which promises the member that nothing of theirs survives on either side.
    @MainActor
    func wipeInstall(_ identity: Identity) {
        UserDefaults.standard.removeObject(forKey: Self.storeKey)
        signOutAccount(identity)
        SharedStore.shared.write(balance: 0, spendRate: 1, blocked: [], unlockedID: nil,
                                 unlockedUntil: nil, flying: false, flightEndsAt: nil,
                                 selection: nil, allowance: 0)
        Blocking.clear()
        eraseAndRestart()
    }

    /// Re-derive the shield from state that has not changed.
    ///
    /// `save()` is what normally drives this, and it only runs when something was written. But
    /// authorization is granted and revoked outside this process entirely, so there are moments —
    /// coming back to the foreground, answering the Connect button — where the model is right and
    /// the world is not. This writes the mirror and nothing else; the persisted blob is untouched,
    /// so it is safe to call when there is nothing to persist.
    func reconcileBlocking() { syncSharedStore() }

    /// Mirror everything the extensions need. They run in their own processes and can see nothing
    /// of this model except what lands in the App Group.
    private func syncSharedStore() {
        SharedStore.shared.write(
            balance: pool,
            spendRate: spend,
            blocked: blocked,
            unlockedID: unlocked?.id,
            unlockedUntil: unlocked?.until,
            flying: phase == .flying,
            flightEndsAt: endsAt?.timeIntervalSince1970,
            selection: selectionData,
            allowance: unlockAllowance
        )
        SharedStore.shared.write(horizon: horizon)
        // The mirror is what `Blocking` reads, so raising the shield has to come after writing it
        // and never before. An unlock also arms the one wake-up the app cannot perform itself:
        // its deadline will pass with Tempus closed, and only the monitor can put the shield back.
        let authorized = screenTimeAuthorized
        Blocking.apply(authorized: authorized)
        Blocking.scheduleReshield(at: unlocked.map { Date(timeIntervalSince1970: $0.until) },
                                  authorized: authorized)
    }

    /// `FamilyActivitySelection` is Codable but its tokens are opaque, so it round-trips as a blob
    /// — the one shape both `Stored` and the App Group can carry. Empty means nothing selected,
    /// which `SharedStore.shouldShield` reads as "nothing to shield".
    private var selectionData: Data? {
        guard !selection.applicationTokens.isEmpty
                || !selection.categoryTokens.isEmpty
                || !selection.webDomainTokens.isEmpty else { return nil }
        return try? JSONEncoder().encode(selection)
    }

    // MARK: - Seam hooks
    //
    // The launch seams drive the same writes the UI does, so nothing can drift. They live behind
    // these few methods because the state they touch is otherwise `private(set)`.

    func replaceHourLog(_ entries: [Status.HourEntry]) { hourLog = entries }

    /// One unlock's worth of statement, dated now, so `spentToday` reads it. Minutes are what mark
    /// a line as screen time rather than Concourse stock, so they have to be non-zero.
    func seamSpend(_ cost: Int) {
        spends.insert(SpendEntry(t: Date().timeIntervalSince1970, label: "Instagram",
                                 mins: max(1, Int((Double(cost) / spend).rounded())), cost: cost),
                      at: 0)
    }

    /// The one door the launch seams write flight and balance state through. Keeping it to a
    /// single method means the properties stay `private(set)` and every seam write is visible in
    /// one place, next to the lifecycle that normally owns them.
    func seamInstall(miles: Int? = nil,
                     flightNo: String? = nil,
                     destination: Destination? = nil,
                     operatedBy: Carriers.Operated? = nil,
                     landedAt: Destination? = nil,
                     landedFrom: String? = nil,
                     leftAt: Int? = nil,
                     bankedMiles: Int? = nil) {
        if let miles { self.miles = miles }
        if let flightNo { self.flightNo = flightNo }
        if let destination { self.destination = destination }
        if let operatedBy { self.operatedBy = operatedBy }
        if let landedAt { self.landedAt = landedAt }
        if let landedFrom { self.landedFrom = landedFrom }
        if let leftAt { self.leftAt = leftAt }
        if let bankedMiles { self.bankedMiles = bankedMiles }
    }

    func prependSeededFlights(_ records: [FlightRecord]) {
        flights = Array((records + flights).prefix(200))
    }

    func setSeamBusiness(_ on: Bool) { biz = on }

    /// `-tempusHeader H01`: owns a shop header outright and stamps it onto the pass being issued.
    /// `board()` picks a header at random from what is owned, so this is the only way to put a
    /// *known* bought band on `-tempusPhase pass` — which is what the band's width is checked on.
    func seamWearHeader(_ id: String) {
        if !ownedHeaders.contains(id) { ownedHeaders.append(id) }
        passHeader = id
    }

    /// Puts a pending incoming request on screen — `-tempusRequest` — so the Status Club banner
    /// can be seen and screenshotted. Writes the same fields a real request would arrive through
    /// (`link.pending`/`requestedByThem`, `receivedGifts`); it authorizes the screen the way every
    /// other seam does, it does not fabricate a person the app then pretends is real elsewhere —
    /// nothing outside this debug path can ever populate either.
    func seedIncomingRequest(gifts: Int = 1) {
        setPlus(true, source: .developer)
        let now = Date().timeIntervalSince1970
        link = LinkAccount(name: "Priya Raman", email: "priya@example.com", miles: 0, at: now,
                           log: [], pending: true, requestedByThem: true)
        // More than one is what the gifts card's pager exists for, so the seam can seed more than
        // one — `-tempusGifts 5`. Each is a different sender, amount and face, because a pager
        // over five identical cards proves nothing about whether it is paging.
        let senders = ["Jonah Webb", "Priya Raman", "Marcus Hale", "Ines Duarte", "Theo Lund"]
        let faces = ShopCatalog.gifts
        receivedGifts = (0..<max(1, gifts)).map { i in
            ReceivedGift(t: now - Double(i) * 60,
                         from: senders[i % senders.count],
                         amt: 250 + i * 50,
                         face: faces.isEmpty ? nil : faces[i % faces.count].id)
        }
        save()
    }

    func markSeamPenalty() {
        diverted = true
        penalty = true
    }

    /// Start the clock for a flight a seam dropped us into mid-air.
    func beginSeamCountdown() {
        spentChances = 0
        let deadline = Date().addingTimeInterval(total / speed)
        endsAt = deadline
        elapsed = 0
        startFlightClock()
        // A seam flight is a real flight, so it gets the real island — otherwise the pill is
        // only ever walkable by tearing a pass by hand.
        raiseLiveActivity(startedAt: Date(), endsAt: deadline)
    }

    /// Stamp the Founders issue date the first time the tier is held.
    func stampFounderIssueIfNeeded() {
        guard status.founders, founderIssued == nil else { return }
        founderIssued = Date().timeIntervalSince1970
        save()
    }
}

// MARK: - The signed-in member

extension AppModel {
    /// The name on the card follows the account, once there is one.
    ///
    /// Only ever an upgrade: signing in fills an empty name with the account's, and signing out
    /// leaves the last real one in place. A name
    /// the member has since chosen by hand is never overwritten, which is why this compares against
    /// the account's own name before writing.
    func adoptAccountName(_ account: Account?) {
        guard let account else { return }
        let name = account.displayName
        guard !name.isEmpty, member.isEmpty || member == name else { return }
        member = name
    }
}

// MARK: - Screen Time

extension AppModel {
    /// Whether the OS has granted Tempus the right to see and shield apps.
    ///
    /// Blocking is not live until this is `true`. Nothing in the interface may imply otherwise —
    /// see the Settings screen's "Screen Time not connected" state, which is that promise.
    var screenTimeAuthorized: Bool {
        AuthorizationCenter.shared.authorizationStatus == .approved
    }

    /// Whether anything is actually selected for shielding. `Blocking` raises no shield on an
    /// empty selection, so this is the honest test for "a shield could happen to this member".
    var hasAppsToShield: Bool {
        !selection.applicationTokens.isEmpty
            || !selection.categoryTokens.isEmpty
            || !selection.webDomainTokens.isEmpty
    }

    /// Ask for Screen Time authorization.
    ///
    /// Onboarding's permission screen calls this and then continues **whatever the answer is** —
    /// the reference simply advances, and a refusal is a legitimate way to use the app: every
    /// flow works with blocking mocked. It cannot succeed in the simulator or without the
    /// entitlement, so a failure here is expected rather than exceptional.
    @discardableResult
    func requestScreenTimeAuthorization() async -> Bool {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            return true
        } catch {
            return false
        }
    }
}
