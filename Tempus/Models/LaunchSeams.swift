import CoreGraphics
import Foundation

/// Ways to drive a screen without synthetic taps, because the simulator takes none.
///
/// These are the native form of the reference's dev panel, and they keep its one rule: **a tier is
/// set by writing the hours ledger, never by overriding the tier itself**, so every screen is
/// always showing a state the app can actually reach.
///
/// ```
/// xcrun simctl launch booted com.crescerestudios.tempus -tempusPhase status -tempusTier 2
/// xcrun simctl launch booted com.crescerestudios.tempus -tempusPhase flying -tempusMinutes 1 -tempusBiz
/// xcrun simctl launch booted com.crescerestudios.tempus -tempusStep 4
/// xcrun simctl launch booted com.crescerestudios.tempus -tempusStep 2 -tempusAdvance -tempusCross white
/// xcrun simctl launch booted com.crescerestudios.tempus -tempusPhase status -tempusRequest
/// xcrun simctl launch booted com.crescerestudios.tempus -tempusGift
/// ```
extension AppModel {

    struct Seams {
        var phase: String?
        var step: Int?
        var advance = false
        var tier: Int?
        var hours: Double?
        var atRisk = false
        var miles: Int?
        var plus = false
        var dev = false
        var pay = false
        var minutes: Int?
        var biz = false
        var policy: String?
        var passes: Int?
        var goal: Int?
        var settle: Bool = false
        var gate = false
        var sheet = false
        var morph = false
        /// Plays the open and then, once it has settled on Preflight, the close — the only way to
        /// see the close's own timing without the tap that ends a real Preflight visit.
        var morphClose = false
        /// Drags the deck's top card this many points sideways and *then* opens from the card's
        /// own measured rect, rather than from the literal `morph` uses.
        ///
        /// This is the one seam that actually exercises the measurement, and it exists because
        /// the bug it pins is invisible to every other route in: the morph used to be handed a
        /// rect with the live drag transform baked into it, so a card tapped while it was still
        /// displaced grew its copper rect from off to one side. Pass a value and the card is
        /// visibly shoved sideways while the morph is fired — if the rect is clean the set-piece
        /// still grows from the card's resting frame in the middle of the deck, and if it is not
        /// the morph starts wherever the card was pushed to. A pass and a fail look nothing alike.
        var morphDrag: Double?
        var circleReveal = false
        var paywall = false
        /// Opens the paywall once the screen has settled, then closes it 1.5 s later — the only way
        /// to watch the stage behind it restore without a tap.
        var paywallClose = false
        var flown = false
        var limit: Int?
        var spent: Int?
        var shopItem: String?
        var cross: String?
        /// Closes the card studio on its own after a beat, saving the face at this index — the
        /// reverse morph is otherwise only reachable through a tap the Simulator cannot make.
        var cardClose: Int?
        /// Opens the card studio *from Status Club* once that screen has settled, which is the only
        /// way to see the entrance uncover the club's own ground — launching straight into
        /// `carddesign` has nothing behind it to uncover.
        var cardOpen = false
        /// A shop face id (`1.01`), owned outright and chosen for the current tier.
        var face: String?
        /// A shop header id (`H01`), owned outright and stamped onto the pass being issued —
        /// the only way to see a bought band on `-tempusPhase pass`, since `board()` picks one
        /// at random from what is owned.
        var header: String?
        /// Puts a pending incoming link request and a received gift on screen, so Status Club's
        /// request banner can be seen without a second person to actually send either.
        var request = false
        /// `-tempusGiftAccept`: answers the first seeded gift once the club has settled, so the
        /// card's exit can be recorded without a tap.
        var giftAccept = false
        /// How many gifts `-tempusRequest` seeds. One unless `-tempusGifts N` says otherwise —
        /// the pager on Status Club's gifts card only exists above one.
        var gifts = 1
        /// An outgoing link invite this device just sent, mirrored through the same `showInvite`
        /// a real server round trip would call — LinkedScreen's "waiting" state, without a second
        /// account to send the invite to.
        var linkSent = false
        /// A link already established locally (no server pair behind it) — LinkedScreen's "linked"
        /// state, the shape a member on a build with no backend, or from before this one shipped,
        /// would actually have. A real server-backed pair (a live pot, `potStale`) needs a second
        /// account and the schema provisioned, so it has no seam here — see the project's own note
        /// on what a seam may and may not fabricate.
        var linked = false
        /// Opens the gift wizard on its recipient step — otherwise only reachable through a
        /// Concourse tile tap the Simulator cannot make.
        var gift = false
        /// Arrives on Redeem through the Club's droplet, then leaves through it again — the one
        /// set-piece that is only ever reached by tapping "Redeem miles" and closing the screen,
        /// which is exactly the pair of taps the Simulator cannot make. `-tempusPhase redeem`
        /// lands there with no transition at all, so it cannot show this.
        var perm = false
        /// Opens Settings' "Cost per minute" `ChoiceSheet` on its own after a beat, then closes it
        /// again — the only way to watch the droplet play, since a `SetRow` tap is exactly the
        /// gesture the Simulator cannot make. Named for the sheet the user reported as motionless
        /// rather than generically, since a future seam for a different sheet may want its own
        /// timing.
        var settingsSpendSheet = false
        /// `-tempusAppsConfirm`: Settings raises the hold-to-confirm sheet for changing apps.
        var appsConfirm = false

        static func fromArguments(_ args: [String] = ProcessInfo.processInfo.arguments) -> Seams {
            var s = Seams()
            func value(_ flag: String) -> String? {
                guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
                let v = args[i + 1]
                return v.hasPrefix("-") ? nil : v
            }
            s.phase = value("-tempusPhase")
            s.step = value("-tempusStep").flatMap(Int.init)
            s.advance = args.contains("-tempusAdvance")
            s.tier = value("-tempusTier").flatMap(Int.init)
            s.hours = value("-tempusHours").flatMap(Double.init)
            s.atRisk = args.contains("-tempusAtRisk")
            s.miles = value("-tempusMiles").flatMap(Int.init)
            s.plus = args.contains("-tempusPlus") || args.contains("-tempusBusiness")
            s.dev = args.contains("-tempusDev")
            s.pay = args.contains("-tempusPay")
            s.minutes = value("-tempusMinutes").flatMap(Int.init)
            s.biz = args.contains("-tempusBiz")
            s.policy = value("-tempusPolicy")
            s.passes = value("-tempusPasses").flatMap(Int.init)
            s.goal = value("-tempusGoal").flatMap(Int.init)
            s.settle = args.contains("-tempusSettle")
            s.gate = args.contains("-tempusGate")
            s.sheet = args.contains("-tempusSheet")
            s.morph = args.contains("-tempusMorph")
            s.morphClose = args.contains("-tempusMorphClose")
            s.morphDrag = value("-tempusMorphDrag").flatMap(Double.init)
            s.circleReveal = args.contains("-tempusCircle")
            s.paywall = args.contains("-tempusPaywall")
            s.paywallClose = args.contains("-tempusPaywallClose")
            s.flown = args.contains("-tempusFlown")
            s.limit = value("-tempusLimit").flatMap(Int.init)
            s.spent = value("-tempusSpent").flatMap(Int.init)
            s.shopItem = value("-tempusShopItem")
            s.cross = value("-tempusCross")
            s.cardClose = value("-tempusCardClose").flatMap(Int.init)
            s.cardOpen = args.contains("-tempusCardOpen")
            s.face = value("-tempusFace")
            s.header = value("-tempusHeader")
            s.request = args.contains("-tempusRequest")
            s.giftAccept = args.contains("-tempusGiftAccept")
            s.gifts = value("-tempusGifts").flatMap(Int.init) ?? 1
            s.gift = args.contains("-tempusGift")
            s.linkSent = args.contains("-tempusLinkSent")
            s.linked = args.contains("-tempusLinked")
            s.perm = args.contains("-tempusPerm")
            s.settingsSpendSheet = args.contains("-tempusSettingsSheet")
            s.appsConfirm = args.contains("-tempusAppsConfirm")
            return s
        }

        var isEmpty: Bool {
            phase == nil && step == nil && tier == nil && hours == nil && miles == nil
                && minutes == nil && policy == nil && passes == nil && goal == nil && !settle && limit == nil && spent == nil && shopItem == nil && cross == nil && cardClose == nil && !cardOpen && face == nil && header == nil
                && !plus && !dev && !pay && !biz && !atRisk && !gate && !sheet && !morph && !morphClose && !circleReveal
                && !paywall && !flown && !request && !gift && !linkSent && !linked && !perm && !settingsSpendSheet
        }
    }

    func applyLaunchArguments() {
        let s = Seams.fromArguments()
        guard !s.isEmpty else { return }
        launchSeams = s

        if s.plus { setPlus(true, source: .developer) }
        // The seven-tap unlock cannot be driven in the Simulator, which takes no synthetic
        // taps — so developer mode gets a seam of its own, like every other screen here.
        if s.dev { devMode = true; devSkipBiometrics = true; devSheet = true }
        // The pay sheet only exists while an order does, and opening one takes taps the
        // Simulator cannot make — so the identity check gets a seam like every other set-piece.
        if s.pay {
            // Opened on a settled screen, the way a real tap opens it — the same reason
            // `-tempusMorph` waits. Raising it during the router's launch churn is not a state the
            // app can actually reach.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(2600))
                guard let self else { return }
                self.payFlow = Order(kind: .unlock, cost: Int(ceil(15 * self.spend)),
                                     name: "Instagram", itemID: "ig", mins: 15)
            }
        }
        if let m = s.miles { seamInstall(miles: m) }
        if let p = s.policy, let dp = DivertPolicy(rawValue: p) { policy = dp }
        if let m = s.minutes { minutes = m; defaultMinutes = m }
        if let t = s.tier { seedTier(t) }
        if let h = s.hours { addQualifyingHours(h) }
        if s.atRisk { seedAtRisk() }
        if let n = s.passes { seedPasses(n) }
        if let g = s.goal { weeklyGoal = max(0, g) }
        if s.flown, hourLog.isEmpty { addQualifyingHours(6) }
        if let l = s.limit { spendLimit = l }
        // `spentToday` is derived from the statement, never stored — so seeding it means writing
        // the line that would have produced it, the same rule `-tempusTier` follows in writing the
        // hours ledger rather than the tier.
        if let c = s.spent { seamSpend(c) }
        if s.request {
            seedIncomingRequest(gifts: s.gifts)
            if s.giftAccept {
                // No link request alongside, so the gifts card is the first thing on the page
                // and the recording sees all of it.
                link = nil
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(2600))
                    if let g = self?.receivedGifts.first { self?.acceptGift(g.t) }
                }
            }
        }
        if let id = s.header, ShopCatalog.header(id: id) != nil { seamWearHeader(id) }
        if s.linkSent { seedOutgoingInvite() }
        if s.linked { seedLocalLink() }
        if s.gift {
            setPlus(true, source: .developer)
            goDirect(.concourse)
            giftFace = ShopCatalog.gifts.first?.id
            giftOpen = CGRect(x: 24, y: 300, width: 154, height: 172)
        }

        if let name = s.phase {
            applySeamPhase(name, biz: s.biz, settle: s.settle)
        } else if s.step != nil || s.advance {
            // Asking for an onboarding screen is asking for onboarding, even on an install that
            // has already been through it.
            goDirect(.ob)
        }
        // Opened on a settled screen, the way a real tap opens it — the same reason `-tempusPay`
        // and `-tempusMorph` wait. Raised at launch it arrived on top of the deck's own deal, and
        // anything measured off the result was measuring the deal: the header's `ORise` travels
        // ~80pt during those same frames, which is indistinguishable from the page being shoved
        // up by a keyboard unless the two are separated in time.
        if s.sheet {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(2600))
                self?.addSheet = true
            }
        }
        if s.morph {
            // The morph grows out of the deck's top card, and the deck has to be laid out before
            // there is a card to grow from — so this waits a beat rather than firing at launch.
            // ponytail: the rect is the top card's frame on a 402pt-wide phone, close enough to
            // watch the set-piece. Nothing reads it back, so it does not have to be exact.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(2600))
                self?.openFlight(from: CGRect(x: 24, y: 215, width: 354, height: 320))
            }
        }
        // Handed to `HomeScreen`, which owns both the deck's gesture state and the measurement —
        // unlike `morph` above, nothing here can fire the open, because the whole point is that
        // the rect comes from the card rather than from a literal written down here.
        if let d = s.morphDrag { seamMorphDrag = CGFloat(d) }
        if s.morphClose {
            // Same open, then the close 1.5s after it lands on Preflight — long enough to see
            // the open finish before watching the close run as its mirror.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(2600))
                self?.openFlight(from: CGRect(x: 24, y: 215, width: 354, height: 320))
                try? await Task.sleep(for: .milliseconds(600 + 1500))
                self?.closePreflight()
            }
        }
        // The Concourse's item screen is an overlay a tap opens, so it gets a seam of its own:
        // `-tempusShopItem H01` opens that face or header on the shelf it belongs to.
        if let id = s.shopItem,
           let kind: PurchaseKind = ShopCatalog.face(id: id) != nil ? .face
               : (ShopCatalog.header(id: id) != nil ? .header : nil) {
            setPlus(true, source: .developer)
            goDirect(.concourse)
            shopSelection = ShopSelection(kind: kind, id: id,
                                          rect: CGRect(x: 24, y: 300, width: 154, height: 172))
        }
        if s.paywall { paywall = .open }
        if s.paywallClose {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(2600))
                self?.paywall = .open
                try? await Task.sleep(for: .milliseconds(1500))
                if self?.paywall == .open { self?.paywall = .closing }
            }
        }
        if s.perm {
            // Settled first, the way a real tap finds it — the same beat `-tempusMorph` waits —
            // then back out again, so both halves can be watched in one run.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(2600))
                self?.go(.redeem, .perm)
                try? await Task.sleep(for: .milliseconds(2600))
                self?.go(.status, .permout)
            }
        }
        if let id = s.face, let f = ShopCatalog.face(id: id) {
            // Granted the way the Concourse grants it, free, so the statement stays honest; then
            // chosen, so Status Club and the studio both open on it.
            payOrder(Order(kind: .face, cost: 0, name: f.name, itemID: id))
            let set = CardArt.faces(tier: status.idx, owned: ownedFaces)
            if let slot = set.firstIndex(where: { $0.shop?.id == id }) {
                cardVariant[status.idx] = slot
            }
        }
        if s.cardOpen {
            // The same beat `-tempusCardClose` waits, so Status Club has measured its hero before
            // the studio asks where it ends.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(2600))
                self?.cardDesignFrom = nil
                self?.goDirect(.carddesign)
            }
        }
        if let face = s.cardClose {
            // Settled first, the way a real tap finds it — the same beat `-tempusMorph` waits.
            // After `-tempusCardOpen` it waits one more beat, so the pair records Customise's
            // entrance *and* its exit over a Status Club that has measured itself.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(s.cardOpen ? 5200 : 2600))
                self?.closeCardDesign(saving: face)
            }
        }
        // Whichever gate belongs to the screen we landed on: boarding one on preflight,
        // leaving one on a flight already in the air.
        if s.gate {
            if phase == .flying { openGate(.exit) } else if phase == .preflight { openGate(.board) }
        }
    }

    private func applySeamPhase(_ name: String, biz wantsBiz: Bool, settle wantsSettle: Bool) {
        // The three flight phases are the only screens the router will not build without a
        // subject (`RootView`: `if warming || model.task != nil`), and no seam ever set one — so
        // `-tempusPhase flying` on a fresh install cut to the flying phase and drew its navy
        // ground and nothing else, which reads as a dead screen rather than as a missing task.
        // A real flight always has one, because the only way in is tapping a card.
        if ["preflight", "pass", "flying"].contains(name), tasks.isEmpty {
            addTask(title: "Organic chemistry")
        }
        switch name {
        case "tierup":
            // The celebration, driven the way a real landing drives it.
            let idx = max(1, status.idx)
            tierUp = idx
            seamInstall(landedAt: destination ?? Geography.destination(forMinutes: minutes),
                        bankedMiles: earned)
            goDirect(.landed)

        case "exited":
            // The exit bill: what an emergency exit leaves behind.
            seamInstall(landedAt: Geography.destination(forMinutes: minutes),
                        leftAt: max(1, minutes / 2), bankedMiles: 0)
            goDirect(.landed)
            markSeamPenalty()

        case "landed":
            // A plain arrival, driven the way a real landing drives it, origin included — so the
            // route strip has something to draw without waiting for a real flight.
            seamInstall(landedAt: destination ?? Geography.destination(forMinutes: minutes),
                        landedFrom: homeAirport.code, bankedMiles: earned)
            goDirect(.landed)

        case "flying":
            beginSeamFlight(biz: wantsBiz, settle: wantsSettle)

        case "pass":
            flightNoForSeam()
            goDirect(.pass)

        case "preflight":
            goDirect(.preflight)

        case "ob":
            goDirect(.ob)

        default:
            if let p = Phase(rawValue: name) { goDirect(p) }
        }
    }

    /// A flight already in the air, so the flying screen can be walked without waiting for a tear.
    private func beginSeamFlight(biz wantsBiz: Bool, settle: Bool = false) {
        flightNoForSeam()
        let dest = Geography.destination(forMinutes: minutes)
        seamInstall(destination: dest,
                    operatedBy: Carriers.forRoute(from: homeAirport.code, to: dest.code, seed: flightNo))
        setSeamBusiness(wantsBiz)
        goDirect(.flying)
        beginSeamCountdown()
        // `-tempusSettle` puts the settle overlay on screen straight away. The simulator has no
        // accelerometer and takes no synthetic shake, so without this the one screen a lapse
        // produces cannot be looked at without a phone in your hand.
        if settle {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(400))
                self?.focusGuard.simulateLapse()
            }
        }
    }

    private func flightNoForSeam() {
        seamInstall(flightNo: "TP " + String(format: "%04d", Int.random(in: 100...999)))
    }

    /// Enough passes to fill the archive, with real destinations and a diversion every fifth.
    func seedPasses(_ n: Int) {
        let subs = ["Organic chemistry", "Thesis draft", "Kanji review",
                    "Statistics", "Lit review", "Physiology"]
        let lengths = [22, 40, 50, 75, 95, 140, 240]
        let now = Date().timeIntervalSince1970
        var out: [FlightRecord] = []
        for i in 0..<n {
            let mins = lengths[i % lengths.count]
            let d = Geography.destination(forMinutes: mins)
            let from = homeAirport
            let no = "TP " + String(1000 + i * 7).prefix(4)
            // No seed, so the livery falls back to the route — which is what the reference's
            // own `seedPasses` does (`carrierFor(from,to)` with no third argument). A real
            // landing seeds with the flight number instead; this is the fixture, not the rule.
            let c = Carriers.forRoute(from: from.code, to: d.code, seed: nil)
            let div = i % 5 == 2
            out.append(FlightRecord(
                id: "seed\(now)-\(i)",
                // One every three days, going back.
                t: now - Double(i) * 86400 * 3,
                from: from.code, fromCity: from.city,
                to: d.code, toCity: d.city, country: d.country,
                minutes: mins,
                miles: Int(ceil(Double(mins) * (div ? 0.4 : 1) * rate)),
                diverted: div,
                subject: subs[i % subs.count],
                no: no,
                ac: c.ac,
                pat: c.livery,
                // Seeded passes carry no header, so they always draw the house band.
                hdr: nil,
                milestone: i == 0 ? .long : (i == 3 ? .country : nil)
            ))
        }
        prependSeededFlights(out)
    }

    /// Write the ledger so the tier is *earned*, never assigned.
    func seedTier(_ idx: Int) {
        let now = Date().timeIntervalSince1970
        if idx <= 0 {
            replaceHourLog([])
        } else {
            let t = Status.tiers[idx]
            let h = (t.invite ? Status.founderHours : t.gate) + 0.4
            replaceHourLog([Status.HourEntry(t: now, h: h)])
            // Founders is a plus tier; without the plan the ledger cannot express it.
            if t.invite { setPlus(true, source: .developer) }
        }
        periodAck = -1
        tierUp = nil
    }

    func addQualifyingHours(_ h: Double) {
        replaceHourLog(hourLog + [Status.HourEntry(t: Date().timeIntervalSince1970, h: h)])
    }

    /// LinkedScreen's "waiting" state, reached the way a real send does — through `showInvite`,
    /// not by poking `link` together by hand.
    func seedOutgoingInvite() {
        setPlus(true, source: .developer)
        let invite = LinkInvite(id: "seam-invite", fromUser: "seam-self", fromName: member,
                                 toEmail: "jordan@example.com", toName: "Jordan Ellis",
                                 createdAt: ISO8601DateFormatter().string(from: Date()),
                                 acceptedBy: nil, acceptedAt: nil, declinedAt: nil)
        showInvite(invite, iSent: true)
    }

    /// LinkedScreen's "linked" state with no server pair behind it — the shape an install with no
    /// backend configured, or one made before the shared pot shipped, actually has. `linkPairID`
    /// stays nil on purpose: a real pair needs a second account and the schema provisioned on the
    /// live project, neither of which a launch seam may fabricate.
    func seedLocalLink() {
        setPlus(true, source: .developer)
        let now = Date().timeIntervalSince1970
        link = LinkAccount(name: "Jordan Ellis", email: "jordan@example.com", miles: 340, at: now - 86400 * 9,
                           log: [LinkAccount.Entry(t: now - 3600, n: 40, label: "Study session", meta: "160 min")])
    }

    /// Carry a tier in from last period without re-earning it — the state that raises the
    /// "period closing" notice.
    func seedAtRisk() {
        let idx = max(1, status.idx)
        let gate = Status.tiers[idx].gate
        let p = status.period
        let lastPeriodStart = firstRun + Double(max(0, p - 1)) * Status.windowSeconds + 86400
        replaceHourLog([
            Status.HourEntry(t: lastPeriodStart, h: gate + 0.4),
            Status.HourEntry(t: Date().timeIntervalSince1970, h: max(0, gate - 4))
        ])
        periodAck = -1
    }
}
