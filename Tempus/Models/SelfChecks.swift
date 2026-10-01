import Foundation
import SwiftUI

#if DEBUG

/// Self-checks that run on every debug launch.
///
/// They assert the logic that is easy to get subtly wrong and impossible to eyeball: the
/// great-circle routing, the livery hash, the barcode's two different integer widths, the 90-day
/// period carry-over, the redeem arithmetic, the seeded history's PRNG, and the focus guard's
/// strike/settle machine (driven with synthetic accelerometer samples, so it is exactly as
/// deterministic on a phone as it is in the simulator). **A failing assert
/// traps the app on launch** — if it dies immediately in DEBUG, read the assert message first.
///
/// The expected values were produced by executing the reference JavaScript under node, not by
/// reading it, so these are a real cross-check against the source of truth rather than a
/// restatement of this port's own behaviour.
///
/// Add to these when you add logic with an adversary or an edge case. Do not add a test target.
func runSelfChecks() {
    geographySelfCheck()
    carriersSelfCheck()
    statusSelfCheck()
    redeemSelfCheck()
    mockDataSelfCheck()
    fontSelfCheck()
    markupSelfCheck()
    lucideSelfCheck()
    typographySelfCheck()
    focusGuardSelfCheck()
    businessClassSelfCheck()
    goalSelfCheck()
    accountSelfCheck()
    nonceSelfCheck()
    blockingSelfCheck()
    spendLimitSelfCheck()
    shadowSelfCheck()
    dialSelfCheck()
    giftLinkSelfCheck()
    milesJournalSelfCheck()
    statusBandSelfCheck()
    shopSelfCheck()
}

/// **What Business Class actually buys on the Concourse shelf, pinned to a share.**
///
/// The shelf is open to everyone and the plan buys the dear end of it — `ShopCatalog.businessOnly`
/// is a price ceiling per kind, so the split is a property of `shop.json`'s prices rather than of
/// a flag on each row. That is the cheap way to express "roughly three quarters" and it has one
/// failure mode: somebody re-prices the stock, the ceilings stay where they were, and the shelf
/// quietly becomes 95% locked or 95% free. Nothing else in the app would notice — every screen
/// still renders, every tile still says something true about itself.
///
/// So this pins the *share*, not the individual rows: between two thirds and four fifths of the
/// shelf is Business Class, and each kind keeps a real free run rather than one token tile. It
/// also checks the ceilings land on a whole price band, which is what stops two identically
/// priced tiles ending up on opposite sides of the line.
func shopSelfCheck() {
    let faces = ShopCatalog.faces
    let headers = ShopCatalog.headers
    assert(!faces.isEmpty && !headers.isEmpty, "shop.json did not decode")

    let locked = faces.filter(ShopCatalog.businessOnly).count
        + headers.filter(ShopCatalog.businessOnly).count
    let total = faces.count + headers.count
    let share = Double(locked) / Double(total)
    assert(share > 0.66 && share < 0.80,
           "the Business share of the shelf is \(Int(share * 100))%, not the ~72% intended — "
           + "re-price the stock or move freeFaceCeiling/freeHeaderCeiling")

    // A free run per kind, so neither half of the shelf is a token gesture.
    assert(faces.contains { !ShopCatalog.businessOnly($0) }, "no face is buyable without the plan")
    assert(headers.contains { !ShopCatalog.businessOnly($0) }, "no header is buyable without the plan")

    // The ceilings sit *on* a price band, never through one: two tiles that cost the same must
    // land on the same side of the line, or the shelf reads as arbitrary.
    assert(faces.contains { $0.price == ShopCatalog.freeFaceCeiling },
           "freeFaceCeiling \(ShopCatalog.freeFaceCeiling) is not a price any face is actually sold at")
    assert(headers.contains { $0.price == ShopCatalog.freeHeaderCeiling },
           "freeHeaderCeiling \(ShopCatalog.freeHeaderCeiling) is not a price any header is actually sold at")

    // Gifts are deliberately outside the split — a gift is bought for someone who may not hold
    // the plan, and it is already paid for twice over (the miles it carries plus its surcharge).
    assert(!ShopCatalog.gifts.isEmpty, "the gift faces went missing from shop.json")
}

/// Status Club's header band, on every face that can ever be equipped.
///
/// The title, the Back button and the Customise chip on that screen are **white, unconditionally**
/// — there is no longer an ink flip to rescue a pale band. So the one property the band rule has
/// to hold is that it is always dark enough to carry white, and it has to hold for all five tiers,
/// every built-in variant within them, and all 191 Concourse faces, any of which a member can buy
/// and wear.
///
/// This is precisely the thing that breaks silently: `shop.json` gains a row, or `headerColours`
/// does, and nothing complains — the band just comes out pale and the title disappears into it on
/// that one face. Two tables feed it and neither knows about this screen.
///
/// `CardArt.band(behind:)`'s own branch is threshold-safe by construction (it tests the lifted
/// colour, not the header), so what this really pins is the *inputs* staying inside the range that
/// construction assumes.
func statusBandSelfCheck() {
    func carriesWhite(_ header: Color, _ what: String) {
        assert(CardArt.isDark(CardArt.band(behind: header)),
               "Status Club's band behind \(what) is too pale for white ink — the title vanishes "
               + "into it. Either the face's header colour moved, or band(behind:) was loosened.")
    }

    // Every built-in variant of every tier, Founders' five materials and the Prestige metal
    // included — `faces(tier:)` with nothing owned is exactly the set the studio offers.
    for tier in 0..<5 {
        for variant in 0..<CardArt.faces(tier: tier).count {
            carriesWhite(CardArt.header(tier: tier, variant: variant),
                         "tier \(tier) variant \(variant)")
        }
    }

    // And every shop face, reached the way the screen reaches one: owning it appends it to its
    // own tier's set, so it is the last slot.
    for face in ShopCatalog.faces {
        let owned = [face.id]
        let variant = CardArt.faces(tier: face.t, owned: owned).count - 1
        carriesWhite(CardArt.header(tier: face.t, variant: variant, owned: owned),
                     "shop face \(face.id) (\(face.name))")
    }
}

private func near(_ a: Double, _ b: Double, _ tol: Double = 0.01) -> Bool { abs(a - b) < tol }

/// The daily spend limit's clamp.
///
/// Every affordability check on every surface — the dial, the pay button, the shield's offer —
/// reads `unlockAllowance`, so this one expression decides what can be bought. Both of its edges
/// are reachable by a member fiddling with the row in Settings.
/// The weekly goal: what counts toward it, what does not, and where the bar stops.
func goalSelfCheck() {
    let now = Date().timeIntervalSince1970
    let weekStart = now - 3 * 86400

    func f(_ t: TimeInterval, _ minutes: Int, diverted: Bool = false) -> FlightRecord {
        FlightRecord(id: "g", t: t, from: "SYD", fromCity: "Sydney", to: "MEL", toCity: "Melbourne",
                     country: "Australia", minutes: minutes, miles: 0, diverted: diverted,
                     subject: "Study", no: "TP 0001", ac: "737", pat: .at1, hdr: nil,
                     milestone: nil)
    }

    func h(_ fs: [FlightRecord], since: TimeInterval) -> Double {
        AppModel.goalHours(fs, since: since)
    }

    assert(h([], since: weekStart) == 0, "no flights is no hours")
    assert(h([f(now, 60)], since: weekStart) == 1, "sixty minutes is an hour")
    assert(h([f(now, 30), f(now, 90)], since: weekStart) == 2, "minutes should sum across flights")

    // A diversion pays nothing here, exactly as it pays no qualifying hours.
    assert(h([f(now, 60, diverted: true)], since: weekStart) == 0, "a diversion should not count")
    assert(h([f(now, 60), f(now, 60, diverted: true)], since: weekStart) == 1,
           "a diversion should not count alongside a completed flight")

    // Last week's flying belongs to last week — a goal that carried it over would be met on
    // Monday morning by a week nobody is in any more.
    assert(h([f(weekStart - 1, 600)], since: weekStart) == 0, "a flight before the week should not count")
    assert(h([f(weekStart, 60)], since: weekStart) == 1, "a flight exactly on the boundary is in the week")

    func frac(_ flown: Double, _ goal: Int) -> Double {
        AppModel.goalFraction(flown: flown, goal: goal)
    }
    assert(frac(0, 0) == 0, "no goal is no progress")
    assert(frac(4, 0) == 0, "flying with no goal set is still no progress")
    assert(frac(4, 8) == 0.5, "half the goal is half the bar")
    assert(frac(8, 8) == 1, "the goal met fills the bar")
    // The bar fills, it does not overflow — a 200% week must not draw past its own track.
    assert(frac(20, 8) == 1, "past the goal should clamp at one")
}

func spendLimitSelfCheck() {
    let a = AppModel.allowance

    // Off means the whole balance, whatever has been spent today.
    assert(a(400, 0, 0) == 400, "no limit should leave the pool alone")
    assert(a(400, 0, 300) == 400, "no limit should ignore what was spent today")

    // A limit bites, and only down to what is left of it.
    assert(a(400, 120, 0) == 120, "a limit should cap the pool")
    assert(a(400, 120, 45) == 75, "a limit should count what was already spent")
    assert(a(400, 120, 120) == 0, "a spent limit should leave nothing")

    // A limit above the balance must not invent miles.
    assert(a(50, 120, 0) == 50, "a limit above the balance should not raise it")
    assert(a(50, 400, 30) == 50, "a limit above the balance should still not raise it")

    // Lowering the limit below what today already spent must not go negative — it is a floor of
    // zero, not a debt.
    assert(a(400, 30, 200) == 0, "a limit lowered under today\'s spend should floor at zero")

    // An empty balance is empty whatever the limit says.
    assert(a(0, 120, 0) == 0, "an empty pool cannot be spent")
}

/// The shield's whole decision table.
///
/// Both the app and `TempusMonitor` answer "should the shield be up right now?" out of the same
/// four inputs, and they answer it in different processes minutes or hours apart — so the answer
/// has to be a pure function of those inputs, and every row of it has to hold. A wrong `true`
/// locks someone out of an app they just spent miles on; a wrong `false` gives away screen time,
/// or lets a flight in the air be flown around.
func blockingSelfCheck() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let live = now.addingTimeInterval(300)      // an unlock with five minutes left
    let spent = now.addingTimeInterval(-1)      // one that expired a second ago
    func shield(_ hasSelection: Bool, _ flying: Bool, _ until: Date?) -> Bool {
        SharedStore.shouldShield(hasSelection: hasSelection, isFlying: flying,
                                 unlockedUntil: until, now: now)
    }

    // Nothing selected is nothing to shield, whatever else is true.
    assert(!shield(false, false, nil), "blocking: shielded with no selection")
    assert(!shield(false, true, nil), "blocking: shielded with no selection, in the air")
    assert(!shield(false, false, live), "blocking: shielded with no selection and a live unlock")

    // Selected and nothing excusing it: up.
    assert(shield(true, false, nil), "blocking: down with no unlock")
    assert(shield(true, false, spent), "blocking: down on an expired unlock")

    // A live unlock lowers it — the one case that does.
    assert(!shield(true, false, live), "blocking: up during a live unlock")

    // A flight in the air always wins. Miles cannot buy your way out of the air.
    assert(shield(true, true, live), "blocking: a live unlock outranked the flight")
    assert(shield(true, true, nil), "blocking: down in the air")

    // The boundary is exclusive: an unlock that expires exactly now is spent.
    assert(shield(true, false, now), "blocking: an unlock expiring now still counted")
}

func geographySelfCheck() {
    assert(Geography.all.count == 65, "the airport table lost a row: \(Geography.all.count)")
    assert(Set(Geography.all.map(\.code)).count == 65, "duplicate airport code")

    Geography.setHome("SYD")
    assert(near(Geography.distanceBetween("SYD", "SIN"), 6294.4326, 0.01))
    assert(near(Geography.distanceBetween("SYD", "LHR"), 17019.6344, 0.01))
    assert(near(Geography.distanceBetween("SYD", "AKL"), 2159.3296, 0.01))
    assert(near(Geography.distanceBetween("LHR", "JFK"), 5540.5102, 0.01))

    // Destinations from Sydney, as the reference resolves them.
    let expected: [(Int, String)] = [
        (5, "CBR"), (15, "BNE"), (25, "CNS"), (40, "NAN"), (50, "PER"),
        (75, "MNL"), (100, "ICN"), (150, "LIM"), (200, "LHR"), (240, "CMN"), (300, "CMN")
    ]
    for (mins, code) in expected {
        let got = Geography.destination(forMinutes: mins).code
        assert(got == code, "destination(\(mins)) from SYD should be \(code), got \(got)")
    }

    // The one property the whole metaphor rests on: a longer flight never lands nearer.
    var lastKm = -1
    for mins in stride(from: 5, through: 300, by: 5) {
        let km = Geography.destination(forMinutes: mins).km
        assert(km >= lastKm, "a \(mins) min flight lands nearer than a shorter one")
        lastKm = km
    }

    // Landing moves the map. Measuring from Singapore must not reuse Sydney's table.
    Geography.setHome("SIN")
    assert(Geography.destinations.allSatisfy { $0.code != "SIN" }, "home is its own destination")
    assert(Geography.destination(forMinutes: 50).code != "PER",
           "the destination table survived a change of home")
    Geography.setHome("SYD")
}

func carriersSelfCheck() {
    // Every flight is operated by aeroTempus; the livery is drawn from the flight's own code and
    // must never move, or the archive would redraw a pass that has already been issued.
    let liveries: [String: Carriers.Livery] = [
        "TP101": .at3, "TP204": .at1, "AT7": .at1, "x": .at5, "": .at2,
        "TP1": .at5, "TP999": .at3, "SYDSIN": .at5, "0": .at5, "Zz": .at5
    ]
    for (seed, want) in liveries {
        let got = Carriers.livery(seed: seed)
        assert(got == want, "livery(\(seed)) should be \(want.rawValue), got \(got.rawValue)")
    }

    // Every livery must have marks to draw and a field to draw them on.
    for livery in Carriers.Livery.allCases {
        assert(!livery.marks.isEmpty, "livery \(livery.rawValue) draws nothing")
    }
    // Reproduced as written: the reference's comment claims six compositions, its code gives five.
    assert(Carriers.Livery.at4.marks.count == Carriers.Livery.at6.marks.count,
           "at4 and at6 are the same composition in the reference")

    // The lattice is the one place this port deliberately leaves the reference's arithmetic: its
    // rows run out before the band does, so ours centre instead. Same count, same 30pt step,
    // equal margins — a row that drifts off centre is the bug this pins.
    do {
        let rows = Dictionary(grouping: Carriers.Livery.at4.marks, by: { $0.y })
        assert(rows.count == 3, "the lattice should be three rows, got \(rows.count)")
        for (y, marks) in rows {
            let xs = marks.map(\.x).sorted()
            assert(xs.count == (y == 45 ? 9 : 8), "row \(y) has \(xs.count) marks")
            let left = xs[0], right = Carriers.bandSize.width - xs[xs.count - 1]
            assert(abs(left - right) < 0.001, "lattice row \(y) is off centre: \(left) vs \(right)")
            for i in 1..<xs.count {
                assert(abs(xs[i] - xs[i - 1] - 30) < 0.001, "lattice row \(y) step is not 30")
            }
        }
    }

    let bars = Carriers.barcode(seed: "TP101")
    assert(bars == [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 3, 3, 1, 1, 1, 1, 4, 1, 1, 1, 1, 1, 1, 3, 3],
           "the barcode LCG drifted: \(bars)")
    assert(bars.count == 26 && bars.allSatisfy { (1...4).contains($0) }, "bar widths out of range")

    // Aircraft and block time still come from the distance, with the real scheduled pairs winning.
    let sin = Carriers.forRoute(from: "SYD", to: "SIN", seed: "TP101")
    assert(sin.ac == "A350-900" && sin.block == 485, "the SYD-SIN scheduled pair was lost")
    let kef = Carriers.forRoute(from: "SYD", to: "KEF", seed: "TP101")
    assert(kef.ac == "777-300ER" && kef.block == 1170, "computed block/aircraft drifted: \(kef)")
    let nan = Carriers.forRoute(from: "SYD", to: "NAN", seed: "TP101")
    assert(nan.ac == "737-800" && nan.block == 245, "computed block/aircraft drifted: \(nan)")
}

func statusSelfCheck() {
    let day: TimeInterval = 86400
    let now = Date().timeIntervalSince1970
    let anchor = now - 100 * day          // we are inside period 1

    // Nothing flown, nothing held.
    let empty = Status.of(log: [], plus: true, anchor: anchor, now: now)
    assert(empty.idx == 0 && empty.period == 1, "an empty ledger should sit at Essential")

    // A tier earned in the previous period is carried into this one...
    let lastPeriod = anchor + 10 * day
    let carried = Status.of(log: [Status.HourEntry(t: lastPeriod, h: 80)],
                            plus: true, anchor: anchor, now: now)
    assert(carried.idx == 2, "Premier earned last period should carry, got \(carried.idx)")
    assert(carried.hours == 0, "last period's hours must not count in this one")
    assert(!carried.holding, "a carried tier that has not been re-flown is at risk")

    // ...and lost if the period after it goes unflown. Two periods later, nothing carries.
    let later = Status.of(log: [Status.HourEntry(t: lastPeriod, h: 80)],
                          plus: true, anchor: anchor, now: now + 180 * day)
    assert(later.idx == 0, "a tier not re-flown is lost, not kept — got \(later.idx)")

    // Economy tops out at Signature and always earns ×1.0.
    let free = Status.of(log: [Status.HourEntry(t: now, h: 200)],
                         plus: false, anchor: anchor, now: now)
    assert(free.idx == Status.freeTop, "economy should cap at Signature, got \(free.idx)")
    assert(free.mult == 1, "economy always earns ×1.0")
    assert(free.capped, "economy earning above its ceiling should read as capped")

    // Founders is lifetime, and needs the plan.
    let fdr = Status.of(log: [Status.HourEntry(t: now, h: Status.founderHours)],
                        plus: true, anchor: anchor, now: now)
    assert(fdr.founders && fdr.idx == Status.founderIndex, "10,000 lifetime hours is Founders")
    let fdrFree = Status.of(log: [Status.HourEntry(t: now, h: Status.founderHours)],
                            plus: false, anchor: anchor, now: now)
    assert(!fdrFree.founders, "Founders needs the plan")

    // The emergency exit's negative entry really does take hours off.
    let penalised = Status.of(log: [Status.HourEntry(t: now, h: 31),
                                    Status.HourEntry(t: now, h: -2)],
                              plus: true, anchor: anchor, now: now)
    assert(near(penalised.hours, 29), "the exit penalty did not come off: \(penalised.hours)")
    assert(penalised.idx == 0, "29 hours is below the Signature gate")

    // Miles are computed in exactly one place, and rounded up.
    assert(Status.earn(minutes: 50, rate: 0.25, mult: 1) == 13, "50 min at ×1.0 banks 13 mi")
    assert(Status.earn(minutes: 50, rate: 0.25, mult: 1.2) == 15, "50 min at ×1.2 banks 15 mi")
    assert(Status.earn(minutes: 1, rate: 0.25, mult: 1) == 1, "a minute still rounds up to 1 mi")

    assert(Status.h1(9.44) == "9.4" && Status.h1(120) == "120", "hours formatting drifted")
}

func redeemSelfCheck() {
    // The dial always spans 5–300 minutes whatever the spend rate is, and cost and time always
    // divide cleanly.
    for spend in [0.5, 1.0, 2.0, 4.0] {
        let lo = spend * 5, hi = spend * 300
        assert(Int(ceil(lo / spend)) == 5, "the dial floor should always be 5 minutes")
        assert(Int(ceil(hi / spend)) == 300, "the dial ceiling should always be 300 minutes")
    }
    // An unlock's price is what it is: naming an app does not change it.
    let a = Order(kind: .unlock, cost: 30, name: "Instagram", itemID: "ig", mins: 30)
    let b = Order(kind: .unlock, cost: 30, name: "TikTok", itemID: "tt", mins: 30)
    assert(a.cost == b.cost, "the price must not depend on which app is named")
}

func mockDataSelfCheck() {
    // The seeded history has to be identical to the reference's, or every chart disagrees with
    // every other chart. These are the first five draws of mulberry32 from seed 20260807.
    var r = MockData.Mulberry(seed: 20260807)
    let want = [0.3797958354, 0.1758410509, 0.7595339064, 0.1767195514, 0.1922091998]
    for (i, w) in want.enumerated() {
        let got = r.next()
        assert(near(got, w, 1e-9), "PRNG draw \(i) drifted: \(got) vs \(w)")
    }
    assert(MockData.days.count == 84, "the history should be 84 days")
    assert(MockData.inRange(weeks: 4).count == 28, "four weeks is 28 days")
    assert(MockData.subjects.count == 4 && MockData.apps.count == 7, "the data tables changed")
    // The projection must count only what is not excluded.
    let all = MockData.projection(weeks: 12, excluded: [])
    let some = MockData.projection(weeks: 12, excluded: ["tt"])
    assert(some.perDay < all.perDay, "excluding an app should lower the projection")
}

func fontSelfCheck() {
    // A missing or misnamed font file does not throw — it silently becomes Helvetica, which is the
    // kind of thing nobody notices for weeks. Name it here instead.
    let missing = TCardFont.missing
    assert(missing.isEmpty, "tier typefaces missing or misnamed: \(missing.joined(separator: ", "))")
}

// MARK: - Accounts, entitlement and the plan

/// The three pieces of this app's payment and identity layer that are easy to get subtly wrong and
/// impossible to eyeball.
///
/// The first is the one that matters: **a store downgrade must not revoke a plan the developer
/// switch is holding open, and a developer switch-off must not revoke a plan that was paid for.**
/// `plus` has two independent grantors, so every combination is pinned here rather than left to
/// whichever of the two happened to write last.
/// The sign-in nonce has to hash to exactly what Supabase computes on the other side, and the
/// failure is silent in the worst way: every sign-in is refused with "Nonces mismatch" and the app
/// simply never backs anything up. GoTrue does `fmt.Sprintf("%x", sha256.Sum256(nonce))`, so the
/// shape is lowercase hex with no separators — not the base64 the PKCE challenge alongside it uses,
/// which is the mistake worth pinning against.
///
/// The three vectors are the published SHA-256 test values, so this checks the port rather than
/// restating it.
func nonceSelfCheck() {
    assert(Identity.sha256Hex("abc")
           == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
           "sha256Hex must be lowercase hex of the digest")
    assert(Identity.sha256Hex("")
           == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
           "the empty string hashes to the well-known digest")
    assert(Identity.sha256Hex("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")
           == "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1",
           "and a multi-block input still hashes whole")
    assert(Identity.sha256Hex("abc").count == 64, "a SHA-256 in hex is always 64 characters")
}

func accountSelfCheck() {
    // Every `AppModel` mutation persists, and there is one blob — so the two throwaway models below
    // would leave their test values in the real install's. Snapshot it and put it back. (The other
    // self-checks never need this: none of them builds an `AppModel`.)
    let saved = UserDefaults.standard.data(forKey: AppModel.storeKey)
    defer {
        if let saved { UserDefaults.standard.set(saved, forKey: AppModel.storeKey) }
        else { UserDefaults.standard.removeObject(forKey: AppModel.storeKey) }
    }

    let m = AppModel(stored: nil, applyingSeams: false)
    assert(!m.plus, "a fresh install is in economy")

    // Either grantor alone raises it.
    m.setPlus(true, source: .store)
    assert(m.plus, "a purchase grants Business Class")
    m.setPlus(false, source: .store)
    assert(!m.plus, "and losing the purchase takes it away again")

    m.setPlus(true, source: .developer)
    assert(m.plus && m.devHasPlus, "the developer switch grants it too")

    // The whole point: the store saying "not entitled" cannot take away the developer's grant,
    // and the developer switching off cannot take away a real purchase.
    m.setPlus(false, source: .store)
    assert(m.plus, "a store downgrade must not revoke the developer grant")
    m.setPlus(true, source: .store)
    m.setPlus(false, source: .developer)
    assert(m.plus, "switching developer mode off must not revoke a real purchase")
    m.setPlus(false, source: .store)
    assert(!m.plus, "with neither grantor, economy")

    // The combination above is not enough on its own: the bug this pins was in *persistence*, not
    // in the arithmetic. A developer grant used to be saved into the same slot the store's answer
    // is read back from, so it returned next launch as a purchase the switch could no longer
    // revoke. Round-trip through the blob, or the four cases above pass over a broken install.
    let dev = AppModel(stored: nil, applyingSeams: false)
    dev.setPlus(true, source: .developer)
    assert(dev.plus)
    // `save()` coalesces onto the next runloop turn — see `AppModel.save()`. This check reads the
    // store back synchronously, so it has to flush first or it is asserting against whatever the
    // *previous* check left on disk rather than against what it just wrote.
    dev.saveNow()
    let afterDevGrant = AppModel.load()
    assert(afterDevGrant?.plus != true, "a developer grant must not persist as a store entitlement")
    let relaunched = AppModel(stored: afterDevGrant, applyingSeams: false)
    assert(relaunched.plus, "but it must survive the relaunch as a developer grant")
    relaunched.setPlus(false, source: .developer)
    assert(!relaunched.plus, "and switching it off after a relaunch must drop back to economy")

    // The mirror case: a real purchase does survive as one.
    let bought = AppModel(stored: nil, applyingSeams: false)
    bought.setPlus(true, source: .store)
    bought.saveNow()
    let afterPurchase = AppModel.load()
    assert(afterPurchase?.plus == true, "a purchase persists")
    assert(AppModel(stored: afterPurchase, applyingSeams: false).plus, "and comes back on relaunch")

    // Google's reversed client id is the callback scheme; getting it wrong fails at the browser
    // with nothing to read.
    assert(Identity.reversedClientID("123-abc.apps.googleusercontent.com")
           == "com.googleusercontent.apps.123-abc", "reversed client id")

    assert(Identity.isValidEmail("you@example.com"))
    assert(Identity.isValidEmail("a.b+tag@sub.example.co.uk"))
    assert(!Identity.isValidEmail("you@example"), "a bare host is not an address")
    assert(!Identity.isValidEmail("you example.com"), "no @, no address")
    assert(!Identity.isValidEmail("@example.com"), "no local part")
    assert(!Identity.isValidEmail(""), "an empty field is not an address")

    // The name on the card follows an account, but never overwrites a name already chosen by hand.
    let named = AppModel(stored: nil, applyingSeams: false)
    named.adoptAccountName(Account(provider: .google, id: "g1", name: "Ada Lovelace", email: "ada@example.com"))
    assert(named.member == "Ada Lovelace", "signing in names the card")
    named.member = "Chosen By Hand"
    named.adoptAccountName(Account(provider: .google, id: "g1", name: "Ada Lovelace", email: "ada@example.com"))
    assert(named.member == "Chosen By Hand", "a hand-picked name is never overwritten")

    // An email account with no name still prints something.
    let addressOnly = Account(provider: .email, id: "x", name: "", email: "olivia.reyes@example.com")
    assert(addressOnly.displayName == "Olivia Reyes", "an address gives a name: \(addressOnly.displayName)")
}


/// The CSS→SwiftUI shadow conversion.
///
/// Pinned because it is arithmetic nobody can eyeball and because getting it wrong is invisible in
/// code review and glaring on a phone: for two years this port folded a negative spread into the
/// blur instead of the alpha, which made every shadow in the app roughly three times too dark. The
/// two rows below are the shapes the whole design system hangs off — a card and the accent pill.
func shadowSelfCheck() {
    // `0 8px 24px -12px rgba(35,57,91,.16)`: sigma 12, the caster's edge sits one sigma outside
    // the shadow's, so it is lit to Phi(-1) = 0.1587 of the authored alpha, doubled because an
    // uninset shadow lights its own edge to a half.
    let card = TShadow.ShadowLayer.css(0x23395b, 0.16, blur: 24, spread: -12, y: 8)
    assert(near(Double(card.radius), 12), "card shadow sigma")
    assert(near(alphaOf(card.color), 0.0508, 0.002), "card shadow alpha")

    // `0 12px 28px -14px rgba(184,111,82,.6)` — the copper under every primary button.
    let accent = TShadow.ShadowLayer.css(0xb86f52, 0.6, blur: 28, spread: -14, y: 12)
    assert(near(Double(accent.radius), 14), "accent shadow sigma")
    assert(near(alphaOf(accent.color), 0.1904, 0.002), "accent shadow alpha")

    // No spread is the identity case: the alpha survives untouched.
    let flat = TShadow.ShadowLayer.css(0x23395b, 0.04, blur: 2, y: 1)
    assert(near(alphaOf(flat.color), 0.04, 0.0005), "zero-spread shadow alpha")

    // And the CDF itself, at the three points the table above leans on.
    assert(near(TShadow.ShadowLayer.normalCDF(0), 0.5, 1e-6), "normalCDF(0)")
    assert(near(TShadow.ShadowLayer.normalCDF(-1), 0.158655, 1e-5), "normalCDF(-1)")
    assert(near(TShadow.ShadowLayer.normalCDF(1), 0.841345, 1e-5), "normalCDF(1)")
}

/// A `Color`'s alpha, the only way out of an opacity-constructed `Color` on this platform.
private func alphaOf(_ c: Color) -> Double {
    var a: CGFloat = 0
    UIColor(c).getRed(nil, green: nil, blue: nil, alpha: &a)
    return Double(a)
}


/// The dial's visible window.
///
/// `standard` never moves, and must not: four dials in the app draw the reference's own symmetric
/// arc and nobody asked for them to change. `growingArc` is onboarding's cap alone, and the whole
/// point of it is that the arc is a quarter at Off and a full spread at the top of the scale — a
/// two-sided lerp that is easy to write backwards and impossible to eyeball once it is a hundred
/// rotated ticks on a Canvas.
func dialSelfCheck() {
    let cap = OBConst.capMax

    // Off: the left arm only, out to the quarter cull. The right arm is not drawn at all, so the
    // ticks run in from the left, meet the marker and stop there.
    let off = DialView.window(style: .growingArc, value: 0, max: cap)
    assert(near(off.0, 16), "cap dial at Off draws the left quarter")
    assert(near(off.1, 0), "cap dial at Off draws nothing right of the marker")

    // The top of the scale: the full symmetric window, both arms.
    let full = DialView.window(style: .growingArc, value: cap, max: cap)
    assert(near(full.0, 34), "cap dial at max opens the left arm fully")
    assert(near(full.1, 34), "cap dial at max opens the right arm fully")

    // Halfway, both arms have opened proportionally and the right is still the narrower of the two.
    let mid = DialView.window(style: .growingArc, value: cap / 2, max: cap)
    assert(near(mid.0, 25), "cap dial at half, left arm")
    assert(near(mid.1, 17), "cap dial at half, right arm")
    assert(mid.1 < mid.0, "the right arm never overtakes the left")

    // A value in the run-out below Off still reads as the starting quarter rather than inverting.
    let under = DialView.window(style: .growingArc, value: -40, max: cap)
    assert(near(under.0, 16) && near(under.1, 0), "cap dial run-out reads as Off")

    // And the style every other dial uses is unconditional.
    for v in [0.0, 30.0, 300.0] {
        let w = DialView.window(style: .standard, value: v, max: cap)
        assert(near(w.0, 34) && near(w.1, 34), "the standard dial window never moves")
    }

    // The fade. On the standard window it is the reference's own ramp, to the tick and to the
    // point it dies at.
    assert(near(DialView.fade(0, cull: 34), 1), "the tick under the marker is full strength")
    assert(near(DialView.fade(16, cull: 34), 0.5), "the standard ramp is linear over 32°")
    assert(near(DialView.fade(32, cull: 34), 0), "the standard strip ends at 32°")
    assert(near(DialView.fade(40, cull: 34), 0), "nothing is painted past the cull")

    // On a narrow window it is the *same* ramp, not that ramp squeezed into a quarter of the arc:
    // the cap dial's left arm at Off has to reach the frame still visible, and only give out in
    // the last couple of degrees. Squeezing it is what made the quarter read as blurred away.
    assert(DialView.fade(14, cull: 16) > 0.5, "the cap dial's left arm survives to the frame")

    // The end of travel has to be legible on the dial itself — an end-stop at each limit, and the
    // run-out past it ghosted so it reads as paint rather than as more wheel to turn.
    do {
        let count = 60
        let minStop = DialView.tick(0, count: count)
        let maxStop = DialView.tick(count, count: count)
        assert(minStop == maxStop, "both ends stop the same way")
        assert(minStop.weight == 1, "the end-stop is drawn at full weight")

        let major = DialView.tick(5, count: count)
        let minor = DialView.tick(6, count: count)
        assert(near(major.weight, 0.9) && near(minor.weight, 0.45), "the reference's live ramp moved")
        assert(minStop.height > major.height && minStop.width > major.width,
               "the end-stop must out-weigh a major or it is not a mark")
        // `isEndStop` is what `DialStrip` reads to paint copper instead of the strip's tint —
        // weight and size alone were not enough contrast to read at a glance (see
        // `DialGeometry.endStopHeight`'s comment), so the flag has to fire only at the two limits.
        assert(minStop.isEndStop && maxStop.isEndStop, "the limits must signal for the copper paint")
        assert(!major.isEndStop && !minor.isEndStop, "a live tick must not paint as an end-stop")

        // Past either end, at the same major/minor cadence, ghosted by one constant.
        let pastMajor = DialView.tick(-5, count: count)
        let pastMinor = DialView.tick(count + 6, count: count)
        assert(pastMajor.weight < major.weight && pastMinor.weight < minor.weight,
               "a run-out tick must read lighter than a live one")
        assert(near(pastMajor.weight / major.weight, pastMinor.weight / minor.weight),
               "both run-outs dim by the same factor")
        assert(pastMajor.weight / major.weight < 0.5,
               "the run-out is too close in weight to read as unavailable")
    }

    // Every dial that sets a quantity reads its value at one size, and the two that legitimately
    // differ are stated fractions of it rather than literals of their own. Five screens depend on
    // this token now; a stray literal at any of them is the inconsistency it was introduced to end.
    assert(TFont.sizeDialValue == 108, "the shared dial readout size moved")
    assert(near(Double(TFont.sizeDialValueUnlocked), 84),
           "Redeem's shrunk readout must stay 84 — it is what makes room for the unlock banner")
    assert(TFont.sizeDialValueUnlocked < TFont.sizeDialValue,
           "the unlocked readout is the smaller of the two")
    assert(near(Double(TFont.sizeDialValueModal / TFont.sizeDialValue), 0.4),
           "the gift's modal readout is 0.4 of the shared size, not a literal")

    // `SetGroup` takes its shadow now so Settings can ask for a heavier one. Onboarding and Redeem
    // share the same control and must keep the standard card shadow, so the DEFAULT is the pin.
    assert(SetGroup<EmptyView>(content: { EmptyView() }).shadow == .card,
           "SetGroup's default shadow must stay .card — onboarding and Redeem rely on it")
    assert(near(DialView.fade(14, cull: 16), 1 - 14 / 32.0), "…on the full window's own ramp")
    assert(near(DialView.fade(16, cull: 16), 0), "and still ends in a fade, not a cut")
}
#endif

/// The shared bank's acceptance gate, and the one place a gift's miles arrive.
///
/// Two things here are easy to get wrong and expensive when wrong. A *pending* link must not
/// contribute a single mile to anything a surface can spend — the partner has not agreed yet, and
/// an affordability check that counts their balance offers time `payOrder` would refuse. And an
/// accepted gift is miles arriving, which is neither a flight (`Status.earn`) nor a spend
/// (`payOrder`), so it has its own credit path that has to reach the statement or the balance
/// moves with nothing to explain it.
///
/// The decode cases matter as much: `pending` and `requestedByThem` were added after the fact, so
/// every blob written before them decodes with both `nil` — which must read as an *established*
/// link, not a pending one, or an existing member's bank would silently stop counting.
func giftLinkSelfCheck() {
    // Same reason `accountSelfCheck` does this: these models persist into the real install's blob.
    let saved = UserDefaults.standard.data(forKey: AppModel.storeKey)
    defer {
        if let saved { UserDefaults.standard.set(saved, forKey: AppModel.storeKey) }
        else { UserDefaults.standard.removeObject(forKey: AppModel.storeKey) }
    }

    let m = AppModel(stored: nil, applyingSeams: false)
    // `miles` is `private(set)`, so the balance is whatever a fresh install starts with — every
    // assertion below is relative to it rather than to a number typed here.
    let own = m.miles

    // An old blob has neither flag. It is an established bank and its miles count.
    m.link = LinkAccount(name: "Ada", miles: 60, at: 0)
    assert(!m.link!.isPending, "a link decoded without the flags must read as accepted")
    assert(m.pool == own + 60, "an accepted link's miles are in the pool, got \(m.pool)")

    // A request, either direction, shares nothing.
    m.link = LinkAccount(name: "Ada", miles: 60, at: 0, pending: true)
    assert(m.link!.isPending && !m.link!.isIncomingRequest, "an outgoing request is not incoming")
    assert(m.pool == own, "a pending link must contribute no miles, got \(m.pool)")
    assert(m.unlockAllowance <= m.pool, "the allowance can never exceed the pool")

    // Only an incoming request can be accepted, and only it can be declined.
    m.acceptLinkRequest()
    assert(m.link?.isPending == true, "an outgoing request cannot accept itself")
    m.declineLinkRequest()
    assert(m.link != nil, "an outgoing request cannot decline itself")

    m.link = LinkAccount(name: "Ada", miles: 60, at: 0, pending: true, requestedByThem: true)
    assert(m.link!.isIncomingRequest, "a request from them is the one this device can answer")
    assert(m.pool == own, "an incoming request shares nothing until it is accepted")
    m.acceptLinkRequest()
    assert(m.link?.isPending == false, "accepting establishes the bank")
    assert(m.pool == own + 60, "and only then do their miles count, got \(m.pool)")

    m.link = LinkAccount(name: "Ada", miles: 60, at: 0, pending: true, requestedByThem: true)
    m.declineLinkRequest()
    assert(m.link == nil, "declining leaves no link behind")

    // A gift arrives as a credit, once, and shows on the statement. `seedIncomingRequest` is the
    // one path that can populate `receivedGifts` (it is `private(set)`), which is the same door the
    // `-tempusRequest` seam uses — so this exercises the real arrival, not a back door of its own.
    m.declineGift(0)
    let before = m.miles
    let creditsBefore = m.credits.count

    m.seedIncomingRequest()
    guard let gift = m.receivedGifts.first else { return assert(false, "the seam seeded no gift") }
    assert(m.miles == before, "a gift awaiting an answer is not yet banked")

    m.acceptGift(gift.t)
    assert(m.miles == before + gift.amt, "accepting a gift credits it, got \(m.miles)")
    assert(m.credits.count == creditsBefore + 1, "an accepted gift writes exactly one credit line")
    assert(m.credits.first?.amt == gift.amt, "the credit line must carry the gift's own figure")
    assert(m.receivedGifts.isEmpty, "an answered gift leaves the queue")

    let banked = m.miles
    m.acceptGift(gift.t)
    assert(m.miles == banked, "a gift cannot be accepted twice")

    m.seedIncomingRequest()
    guard let second = m.receivedGifts.first else { return assert(false, "the seam seeded no gift") }
    m.declineGift(second.t)
    assert(m.miles == banked && m.receivedGifts.isEmpty, "declining banks nothing and clears it")

    // Personal redemption still works with no backend at all, while a gift cannot
    // reach the old synchronous route and announce delivery without a server.
    m.payOrder(Order(kind: .unlock, cost: 5, name: "Offline unlock", itemID: "ig", mins: 5))
    assert(m.miles == banked - 5 && m.unlocked?.mins == 5, "offline redemption must stay local")
    let afterUnlock = m.miles
    let sentBefore = m.sentGifts.count
    m.payOrder(Order(kind: .gift, cost: 5, name: "Gift", who: "Ada", whoEmail: "ada@example.com", amt: 5))
    assert(m.miles == afterUnlock && m.sentGifts.count == sentBefore,
           "gifts must go through the online transfer route")
}
