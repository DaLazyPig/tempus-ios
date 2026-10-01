import Foundation

/// Hours in the air buy status, miles buy screen time, and the two never mix.
///
/// Status runs fixed 90-day periods anchored on the day you joined: what you fly in one period sets
/// the tier you *carry* into the next, so a tier is earned once and then has to be earned again.
/// Status is **derived, never stored** — write to the hours ledger, never to a tier, so a rolling
/// window can take a tier away as well as give one.
enum Status {

    struct Tier: Hashable {
        let k: String
        let name: String
        /// The three-letter register printed on the card.
        let mono: String
        /// Qualifying hours in a period needed to earn it.
        let gate: Double
        /// Earn multiplier.
        let mult: Double
        /// One-off miles paid on reaching it.
        let bonus: Int
        /// Founders is by invitation: unreachable through the hours gate.
        var invite: Bool = false
        /// Lifetime hours that grant it instead.
        var life: Double = 0
    }

    static let tiers: [Tier] = [
        Tier(k: "ess", name: "Essential", mono: "ESS", gate: 0, mult: 1, bonus: 0),
        Tier(k: "sig", name: "Signature", mono: "SIG", gate: 30, mult: 1.1, bonus: 0),
        Tier(k: "prm", name: "Premier", mono: "PRM", gate: 75, mult: 1.2, bonus: 10),
        Tier(k: "prs", name: "Prestige", mono: "PRS", gate: 120, mult: 1.3, bonus: 20),
        Tier(k: "fdr", name: "Founders", mono: "FDR", gate: 1e9, mult: 1.4, bonus: 0,
             invite: true, life: 10000)
    ]

    static let founderIndex = 4
    static let founderHours: Double = 10000
    /// Economy tops out at Signature.
    static let freeTop = 1
    /// A status period: 90 days.
    static let windowSeconds: TimeInterval = 90 * 86400

    /// One entry in the qualifying-hours ledger.
    struct HourEntry: Codable, Hashable {
        /// Epoch seconds.
        var t: TimeInterval
        /// Hours — negative for the emergency-exit penalty.
        var h: Double
    }

    /// Everything the status surfaces read. Recomputed on every access; never persisted.
    struct Snapshot: Hashable {
        var hours: Double
        var idx: Int
        var tier: Tier
        var next: Tier?
        var lifetime: Double
        var founders: Bool
        /// Economy has earned above its ceiling.
        var capped: Bool
        /// The next tier exists but the plan cannot reach it.
        var locked: Bool
        var period: Int
        var start: TimeInterval
        var end: TimeInterval
        var daysLeft: Int
        var carried: Int
        var earnIdx: Int
        /// Flights logged inside this period.
        var flights: Int
        /// Hours still needed to hold the tier being carried.
        var hold: Double
        var holding: Bool
        var toNext: Double
        var pct: Double
        var mult: Double
        var bonus: Int
        /// The tier's own multiplier, regardless of plan — what the tier is *offering*.
        var offer: Double
    }

    /// The highest tier `hours` earns outright. Economy is clamped to Signature.
    static func rawTier(hours: Double, plus: Bool) -> Int {
        var idx = 0
        for (i, t) in tiers.enumerated() where hours >= t.gate { idx = i }
        return plus ? idx : min(idx, freeTop)
    }

    /// The whole ladder, resolved.
    ///
    /// - Parameters:
    ///   - log: the qualifying-hours ledger.
    ///   - plus: whether the paid plan is held.
    ///   - anchor: the day you joined — periods are measured from it, not from a rolling window.
    static func of(log: [HourEntry], plus: Bool, anchor: TimeInterval, now: TimeInterval? = nil) -> Snapshot {
        let t0 = now ?? Date().timeIntervalSince1970
        let base = anchor > 0 ? anchor : t0
        let p = max(0, Int(floor((t0 - base) / windowSeconds)))
        let start = base + Double(p) * windowSeconds
        let end = start + windowSeconds

        func sum(_ a: TimeInterval, _ b: TimeInterval) -> Double {
            log.reduce(0) { $1.t >= a && $1.t < b ? $0 + $1.h : $0 }
        }

        let hours = max(0, sum(start, end))
        let prev = p > 0 ? sum(start - windowSeconds, start) : 0
        // Last period's tier, uncapped — what you carry in.
        let carried = p > 0 ? rawTier(hours: prev, plus: true) : 0
        let earnIdx = rawTier(hours: hours, plus: true)

        var idx = max(carried, earnIdx)
        let ceiling = plus ? 4 : freeTop
        if idx > ceiling { idx = ceiling }

        // Clamped like `hours` above: the emergency-exit penalty (`-2`) can outrun what a short
        // test flight banked, and an unclamped sum surfaces as a negative "HOURS" stat on Status
        // Club rather than the zero a member has actually never gone below.
        let lifetime = max(0, log.reduce(0) { $0 + $1.h })
        let founders = plus && lifetime >= founderHours
        if founders { idx = founderIndex }

        let tier = tiers[idx]
        let nx = idx + 1 < tiers.count ? tiers[idx + 1] : nil
        let next = (nx?.invite == false) ? nx : nil

        let holdIdx = min(idx, ceiling, 3)
        let flights = log.filter { $0.t >= start && $0.t < end }.count

        return Snapshot(
            hours: hours,
            idx: idx,
            tier: tier,
            next: next,
            lifetime: lifetime,
            founders: founders,
            capped: !plus && earnIdx > 1,
            locked: next != nil && !plus && idx + 1 > 1,
            period: p,
            start: start,
            end: end,
            daysLeft: max(0, Int(ceil((end - t0) / 86400))),
            carried: carried,
            earnIdx: earnIdx,
            flights: flights,
            hold: founders ? 0 : max(0, tiers[holdIdx].gate - hours),
            holding: founders ? true : earnIdx >= holdIdx,
            toNext: next.map { max(0, $0.gate - hours) } ?? 0,
            pct: next.map { max(0.02, min(1, (hours - tier.gate) / ($0.gate - tier.gate))) } ?? 1,
            mult: plus ? tier.mult : 1,
            bonus: plus ? tier.bonus : 0,
            offer: tier.mult
        )
    }

    /// What a flight of `mins` banks at a given status. The single place miles are computed for a
    /// length of flight, so no surface can quote a number different from the one banked.
    static func earn(minutes: Int, rate: Double, mult: Double) -> Int {
        Int(ceil(Double(minutes) * rate * mult))
    }

    /// Hours formatted to at most five characters.
    static func h1(_ n: Double) -> String {
        if n >= 1e6 { return "\(Int((n / 1e6).rounded()))M" }
        if n >= 10000 {
            let v = (n / 100).rounded() / 10
            var s = String(format: n < 100000 ? "%.1f" : "%.0f", v)
            if s.hasSuffix(".0") { s.removeLast(2) }
            return s + "K"
        }
        if n >= 1000 { return "\(Int(n.rounded()))" }
        if n >= 100 { return "\((n * 10).rounded() / 10)".replacingOccurrences(of: ".0", with: "") }
        return String(format: "%.1f", (n * 10).rounded() / 10)
    }
}
