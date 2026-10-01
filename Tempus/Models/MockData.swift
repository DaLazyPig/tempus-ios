import Foundation

/// The data layer.
///
/// 1. A deterministic 12-week flight history (seeded PRNG, so the numbers are stable across
///    launches and every chart agrees with every other chart).
/// 2. A **mock** of the OS screen-time API. Real iOS exposes this through Screen Time /
///    DeviceActivity with user consent; nothing here touches a real device. The shape — per-app,
///    per-day minute totals — matches what that API returns, so the analytics screen can be
///    pointed at the real source later without changing its code.
///
/// This is fabricated history. It drives the paywalled flight log, including its "at this rate"
/// projection: that number is seeded, not measured. If the log ever stops reading as clearly a
/// sample, it needs real DeviceActivity data behind it before it can be presented as the
/// reader's own.
enum MockData {

    // MARK: - PRNG

    /// mulberry32. Every operation is 32-bit; `Math.imul` is a wrapping 32-bit multiply, whose
    /// bit pattern `UInt32.&*` reproduces exactly.
    struct Mulberry {
        private var a: UInt32

        init(seed: UInt32) { a = seed }

        mutating func next() -> Double {
            a = a &+ 0x6D2B79F5
            var t = (a ^ (a >> 15)) &* (1 | a)
            t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
            return Double(t ^ (t >> 14)) / 4294967296
        }
    }

    // MARK: - Tables

    struct Subject: Identifiable, Hashable {
        let id: String
        let title: String
    }

    static let subjects: [Subject] = [
        Subject(id: "chem", title: "Organic chemistry"),
        Subject(id: "algebra", title: "Linear algebra"),
        Subject(id: "essay", title: "Essay draft"),
        Subject(id: "bio", title: "Cell biology")
    ]

    struct TrackedApp: Identifiable, Hashable {
        let id: String
        let label: String
        /// Lucide glyph name in the reference; mapped to an SF Symbol at the call site.
        let icon: String
        let base: Int
        var utility: Bool = false
    }

    static let apps: [TrackedApp] = [
        TrackedApp(id: "tt", label: "TikTok", icon: "music", base: 74),
        TrackedApp(id: "ig", label: "Instagram", icon: "instagram", base: 52),
        TrackedApp(id: "yt", label: "YouTube", icon: "youtube", base: 41),
        TrackedApp(id: "rd", label: "Reddit", icon: "message-circle", base: 23),
        TrackedApp(id: "sc", label: "Snapchat", icon: "ghost", base: 17),
        TrackedApp(id: "msg", label: "Messages", icon: "message-square", base: 14, utility: true),
        TrackedApp(id: "maps", label: "Maps", icon: "map", base: 6, utility: true)
    ]

    /// Four blocks of the day, so "when do you actually study" has an answer in words.
    struct Block: Identifiable, Hashable {
        let id: String
        let label: String
        let from: Int
        let to: Int
        var minutes: Int = 0
    }

    static let blocks: [Block] = [
        Block(id: "morning", label: "Morning", from: 5, to: 12),
        Block(id: "afternoon", label: "Afternoon", from: 12, to: 17),
        Block(id: "evening", label: "Evening", from: 17, to: 21),
        Block(id: "night", label: "Night", from: 21, to: 29)
    ]

    // MARK: - History

    struct Session: Hashable {
        let subject: String
        let title: String
        let planned: Int
        let minutes: Int
        let diverted: Bool
        let hour: Int
        let miles: Int
    }

    struct Day: Hashable {
        let date: String
        let ts: TimeInterval
        let dow: Int
        let weekend: Bool
        let sessions: [Session]
        let screen: [String: Int]
        let studied: Int
    }

    private static let dayMS: TimeInterval = 86400

    private static var cached: [Day]?

    /// 84 days ending today. Sessions cluster in the evening on weekdays and mid-morning at
    /// weekends; a slow upward trend in study time and a mild downward one in scrolling gives
    /// the charts something true to say.
    static var days: [Day] {
        if let cached { return cached }
        let built = build()
        cached = built
        return built
    }

    private static func build() -> [Day] {
        var rnd = Mulberry(seed: 20260807)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let today = cal.startOfDay(for: Date())

        let iso = DateFormatter()
        iso.dateFormat = "yyyy-MM-dd"
        iso.timeZone = TimeZone(secondsFromGMT: 0)
        iso.locale = Locale(identifier: "en_US_POSIX")

        var out: [Day] = []
        for i in stride(from: 83, through: 0, by: -1) {
            let date = today.addingTimeInterval(-Double(i) * dayMS)
            // JavaScript's getDay(): 0 = Sunday.
            let dow = cal.component(.weekday, from: date) - 1
            let weekend = dow == 0 || dow == 6

            var sessions: [Session] = []
            let count = Int(floor(rndNext(&rnd) * (weekend ? 2.6 : 3.4)))
                + (rndNext(&rnd) < (weekend ? 0.25 : 0.55) ? 1 : 0)
            for _ in 0..<count {
                let s = subjects[Int(rndNext(&rnd) * Double(subjects.count))]
                let planned = [25, 50, 50, 75, 90, 120][Int(rndNext(&rnd) * 6)]
                let diverted = rndNext(&rnd) < 0.17
                let minutes = diverted
                    ? max(4, Int((Double(planned) * (0.2 + rndNext(&rnd) * 0.5)).rounded()))
                    : planned
                let hour = weekend
                    ? [9, 10, 11, 14, 15, 16, 20][Int(rndNext(&rnd) * 7)]
                    : [8, 13, 16, 18, 19, 20, 21, 21, 22][Int(rndNext(&rnd) * 9)]
                // Minted by the same function a real landing mints with, at the base economy
                // rate. It used to be `planned * 2.4 * weight / 1.35`, which is roughly nine
                // times the live rate — a 50-minute flight worth 120 mi here and 13 mi flown for
                // real. Nothing rendered it, so nothing showed the disagreement, but a seeded
                // mile and an earned mile have to be the same unit or the first surface to put
                // them side by side is quoting two currencies.
                let miles = diverted ? 0 : Status.earn(minutes: planned, rate: 0.25, mult: 1)
                sessions.append(Session(subject: s.id, title: s.title, planned: planned,
                                        minutes: minutes, diverted: diverted, hour: hour,
                                        miles: miles))
            }

            var screen: [String: Int] = [:]
            for a in apps {
                let wk = weekend ? 1.42 : 1.0
                let drift = 1 - Double(83 - i) / 83 * (a.utility ? 0 : 0.19)
                let v = Double(a.base) * wk * drift * (0.55 + rndNext(&rnd) * 0.95)
                screen[a.id] = max(0, Int(v.rounded()))
            }

            out.append(Day(
                date: iso.string(from: date),
                ts: date.timeIntervalSince1970,
                dow: dow,
                weekend: weekend,
                sessions: sessions,
                screen: screen,
                studied: sessions.reduce(0) { $0 + ($1.diverted ? 0 : $1.minutes) }
            ))
        }
        return out
    }

    /// The draw order matters more than anything else here: every `rnd()` call must happen in the
    /// same sequence the reference makes them, or the whole history diverges. This wrapper exists
    /// so each draw is visibly one call at one point.
    private static func rndNext(_ r: inout Mulberry) -> Double { r.next() }

    // MARK: - Aggregations the analytics screen reads

    static func inRange(weeks: Int) -> [Day] {
        let all = days
        return weeks >= 12 ? all : Array(all.suffix(weeks * 7))
    }

    struct SubjectTotal: Identifiable, Hashable {
        let id: String
        let title: String
        var minutes: Int
        var flights: Int
        var diverted: Int
        var miles: Int
    }

    static func bySubject(weeks: Int) -> [SubjectTotal] {
        var out: [String: SubjectTotal] = [:]
        var order: [String] = []
        for d in inRange(weeks: weeks) {
            for s in d.sessions {
                if out[s.subject] == nil {
                    out[s.subject] = SubjectTotal(id: s.subject, title: s.title, minutes: 0,
                                                  flights: 0, diverted: 0, miles: 0)
                    order.append(s.subject)
                }
                out[s.subject]!.minutes += s.diverted ? 0 : s.minutes
                out[s.subject]!.flights += 1
                out[s.subject]!.miles += s.miles
                if s.diverted { out[s.subject]!.diverted += 1 }
            }
        }
        return order.compactMap { out[$0] }.sorted { $0.minutes > $1.minutes }
    }

    static func byBlock(weeks: Int, subject: String? = nil) -> [Block] {
        var out = blocks
        for d in inRange(weeks: weeks) {
            for s in d.sessions {
                if s.diverted { continue }
                if let subject, s.subject != subject { continue }
                let h = s.hour < 5 ? s.hour + 24 : s.hour
                let idx = out.firstIndex { h >= $0.from && h < $0.to } ?? 3
                out[idx].minutes += s.minutes
            }
        }
        return out
    }

    struct DowTotal: Identifiable, Hashable {
        var id: Int { dow }
        let label: String
        let dow: Int
        var minutes: Int
    }

    /// Monday-first, which is how the chart reads it.
    static func byDow(weeks: Int, subject: String? = nil) -> [DowTotal] {
        let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        var out = names.enumerated().map { DowTotal(label: $1, dow: $0, minutes: 0) }
        for d in inRange(weeks: weeks) {
            for s in d.sessions {
                if s.diverted { continue }
                if let subject, s.subject != subject { continue }
                out[d.dow].minutes += s.minutes
            }
        }
        return Array(out.dropFirst()) + [out[0]]
    }

    static func weekendSplit(weeks: Int, subject: String? = nil) -> (weekend: Int, weekday: Int) {
        var we = 0, wd = 0
        for d in inRange(weeks: weeks) {
            for s in d.sessions {
                if s.diverted { continue }
                if let subject, s.subject != subject { continue }
                if d.weekend { we += s.minutes } else { wd += s.minutes }
            }
        }
        return (we, wd)
    }

    struct DailyStudy: Identifiable, Hashable {
        var id: TimeInterval { ts }
        let ts: TimeInterval
        let minutes: Int
        let weekend: Bool
    }

    static func dailyStudy(weeks: Int) -> [DailyStudy] {
        inRange(weeks: weeks).map { DailyStudy(ts: $0.ts, minutes: $0.studied, weekend: $0.weekend) }
    }

    struct AppTotal: Identifiable, Hashable {
        let id: String
        let label: String
        let icon: String
        let utility: Bool
        var minutes: Int
        var perDay: Double
        var excluded: Bool
    }

    static func screenByApp(weeks: Int, excluded: Set<String> = []) -> [AppTotal] {
        let rows = inRange(weeks: weeks)
        var out = apps.map {
            AppTotal(id: $0.id, label: $0.label, icon: $0.icon, utility: $0.utility,
                     minutes: 0, perDay: 0, excluded: excluded.contains($0.id))
        }
        for d in rows {
            for i in out.indices { out[i].minutes += d.screen[out[i].id] ?? 0 }
        }
        for i in out.indices { out[i].perDay = Double(out[i].minutes) / Double(max(1, rows.count)) }
        return out.sorted { $0.minutes > $1.minutes }
    }

    struct Projection: Hashable {
        let perDay: Double
        let perWeekHours: Double
        let years: Double
        let daysOfLife: Double
        let horizon: Int
    }

    /// Counted minutes per day, extrapolated over the years a 19-year-old can expect to keep
    /// using a phone. Deliberately conservative — no compounding.
    static func projection(weeks: Int, excluded: Set<String> = [], yearsAhead: Int = 60) -> Projection {
        let perDay = screenByApp(weeks: weeks, excluded: excluded)
            .filter { !$0.excluded }
            .reduce(0.0) { $0 + $1.perDay }
        let totalDays = perDay * 365.25 * Double(yearsAhead) / 1440
        return Projection(perDay: perDay, perWeekHours: perDay * 7 / 60,
                          years: totalDays / 365.25, daysOfLife: totalDays, horizon: yearsAhead)
    }

    static var streak: Int {
        var n = 0
        for d in days.reversed() {
            if d.studied > 0 { n += 1 } else { break }
        }
        return n
    }

    struct Totals: Hashable {
        let minutes: Int
        let flights: Int
        let diverted: Int
        let miles: Int
        let days: Int
        let completion: Int
    }

    // MARK: - The real log

    /// The same six aggregations, over flights that were actually flown.
    ///
    /// **The study cards on the flight log read these, not the seeded history.** `MockData` is a
    /// fixture: twelve weeks of flights nobody took, with a day-of-week peak and a streak that
    /// belong to a PRNG. Presenting that behind a paid unlock as "your strongest stretch" is the
    /// screen telling the reader something about themselves that is not true — and a member who
    /// flies one session and opens the log sees a history they know they do not have.
    ///
    /// The screen-time half of that screen still reads the fixture, because per-app usage needs a
    /// `DeviceActivityReport` extension this app does not have, and it is labelled as a sample
    /// where it is shown. Everything derived from flights is now derived from flights.
    enum Real {
        private static var cal: Calendar {
            var c = Calendar(identifier: .gregorian)
            c.timeZone = .current
            return c
        }

        static func inRange(_ flights: [FlightRecord], weeks: Int) -> [FlightRecord] {
            let cutoff = Date().timeIntervalSince1970 - Double(weeks) * 7 * 86400
            return flights.filter { $0.t >= cutoff }
        }

        static func totals(_ flights: [FlightRecord], weeks: Int) -> Totals {
            let rows = inRange(flights, weeks: weeks)
            var minutes = 0, diverted = 0, miles = 0
            for f in rows {
                miles += f.miles
                if f.diverted { diverted += 1 } else { minutes += f.minutes }
            }
            return Totals(minutes: minutes, flights: rows.count, diverted: diverted, miles: miles,
                          days: weeks * 7,
                          completion: rows.isEmpty ? 0
                            : Int(((Double(rows.count - diverted) / Double(rows.count)) * 100).rounded()))
        }

        /// Keyed by the subject line the flight was flown under, which is what the member typed —
        /// there is no subject table behind a real flight, only the title on the record.
        static func bySubject(_ flights: [FlightRecord], weeks: Int) -> [SubjectTotal] {
            var out: [String: SubjectTotal] = [:]
            for f in inRange(flights, weeks: weeks) {
                let key = f.subject.isEmpty ? "Study" : f.subject
                var row = out[key] ?? SubjectTotal(id: key, title: key, minutes: 0, flights: 0,
                                                   diverted: 0, miles: 0)
                row.minutes += f.diverted ? 0 : f.minutes
                row.flights += 1
                row.miles += f.miles
                if f.diverted { row.diverted += 1 }
                out[key] = row
            }
            return out.values.sorted { $0.minutes > $1.minutes }
        }

        static func byDow(_ flights: [FlightRecord], weeks: Int, subject: String?) -> [DowTotal] {
            let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
            var out = names.enumerated().map { DowTotal(label: $1, dow: $0, minutes: 0) }
            let c = cal
            for f in inRange(flights, weeks: weeks) where !f.diverted {
                if let subject, f.subject != subject { continue }
                let d = c.component(.weekday, from: Date(timeIntervalSince1970: f.t)) - 1
                out[d].minutes += f.minutes
            }
            return Array(out.dropFirst()) + [out[0]]
        }

        static func byBlock(_ flights: [FlightRecord], weeks: Int, subject: String?) -> [Block] {
            var out = blocks
            let c = cal
            for f in inRange(flights, weeks: weeks) where !f.diverted {
                if let subject, f.subject != subject { continue }
                let raw = c.component(.hour, from: Date(timeIntervalSince1970: f.t))
                let h = raw < 5 ? raw + 24 : raw
                let idx = out.firstIndex { h >= $0.from && h < $0.to } ?? 3
                out[idx].minutes += f.minutes
            }
            return out
        }

        /// Consecutive days back from today carrying at least one completed flight. Today not
        /// having one yet does not break it — the streak is still alive until the day is.
        static func streak(_ flights: [FlightRecord]) -> Int {
            let c = cal
            let flown = Set(flights.filter { !$0.diverted }
                .map { c.startOfDay(for: Date(timeIntervalSince1970: $0.t)) })
            guard !flown.isEmpty else { return 0 }
            var day = c.startOfDay(for: Date())
            if !flown.contains(day) {
                guard let back = c.date(byAdding: .day, value: -1, to: day) else { return 0 }
                day = back
            }
            var n = 0
            while flown.contains(day) {
                n += 1
                guard let back = c.date(byAdding: .day, value: -1, to: day) else { break }
                day = back
            }
            return n
        }
    }

    static func totals(weeks: Int) -> Totals {
        let rows = inRange(weeks: weeks)
        var minutes = 0, flights = 0, diverted = 0, miles = 0
        for d in rows {
            for s in d.sessions {
                flights += 1
                miles += s.miles
                if s.diverted { diverted += 1 } else { minutes += s.minutes }
            }
        }
        return Totals(minutes: minutes, flights: flights, diverted: diverted, miles: miles,
                      days: rows.count,
                      completion: flights > 0 ? Int(((Double(flights - diverted) / Double(flights)) * 100).rounded()) : 0)
    }
}
