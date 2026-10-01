import SwiftUI

/// The carrier layer.
///
/// Every flight in Tempus is operated by **aeroTempus**, callsign `AT`. The reference build's
/// carrier file is written in layers and its last two collapse a 200-carrier table, its country
/// routing and its 72 band patterns into this single carrier and six house liveries — everything
/// above those layers is dead at runtime. Verified by executing the reference, not by reading it.
///
/// What survives from the layers underneath is the *route* arithmetic: aircraft type and block
/// time still come from the great-circle distance, with twelve real scheduled pairs overriding it.
enum Carriers {

    static let iata = "AT"
    static let name = "aeroTempus"

    /// `cols` on the reference record: [field, mark, accent].
    static let light = Color(hex: 0xf4f7fb)
    static let blue = Color(hex: 0x1b52a0)
    static let accent = Color(hex: 0xe0b23a)

    /// The band box the liveries are authored against.
    static let bandSize = CGSize(width: 268, height: 90)

    // MARK: - Liveries

    /// The six house liveries. `at4` and `at6` are deliberately identical — the reference's
    /// comment claims six compositions and its code gives five. Reproduced as written; `at6` is
    /// also the fallback for an unknown id.
    enum Livery: String, CaseIterable, Codable {
        case at1, at2, at3, at4, at5, at6

        /// The field the marks sit on.
        var field: Color { self == .at5 ? blue : light }

        /// Every mark in the livery: position, scale, colour, opacity.
        var marks: [Mark] {
            switch self {
            case .at1:
                return [Mark(134, 45, 1.6, blue)]
            case .at2:
                return [Mark(100, 45, 1.2, blue), Mark(172, 45, 0.78, blue, 0.5)]
            case .at3:
                return [Mark(44, 45, 0.82, blue), Mark(89, 45, 0.92, blue),
                        Mark(134, 45, 1.15, blue), Mark(179, 45, 0.92, blue),
                        Mark(224, 45, 0.82, blue)]
            case .at4, .at6:
                return Livery.lattice(blue)
            case .at5:
                return [Mark(236, 45, 2.3, light, 0.95)]
            }
        }

        /// Three rows of the mark at 0.6, stepping in at 30, the outer rows offset by half a
        /// step so the lattice reads as brickwork rather than a column grid.
        ///
        /// **Deliberately not the reference's arithmetic.** The reference walks fixed starts
        /// (18 and 3) to fixed ends, which on a 268-wide band leaves the offset rows 18 in from
        /// the left and 40 in from the right, and the middle row 3 in from the left and 25 from
        /// the right — so the pattern runs out before the band does and the right-hand third
        /// reads as a blank margin, while the middle row's first mark is clipped by the left
        /// edge. Here each row is *centred* on the band instead: the count is the same, the step
        /// is the same, and the margins come out equal (29 / 29 and 14 / 14). Only the artwork of
        /// `at4` / `at6` changes — which livery a flight flies is still frozen by `livery(seed:)`
        /// and is not recomputed.
        private static func lattice(_ fill: Color) -> [Mark] {
            func row(_ count: Int, _ y: CGFloat) -> [Mark] {
                let span = CGFloat(count - 1) * 30
                let start = (bandSize.width - span) / 2
                return (0..<count).map { Mark(start + CGFloat($0) * 30, y, 0.6, fill) }
            }
            return row(8, 15) + row(9, 45) + row(8, 75)
        }
    }

    struct Mark {
        let x, y, scale: CGFloat
        let color: Color
        let opacity: Double

        init(_ x: CGFloat, _ y: CGFloat, _ scale: CGFloat, _ color: Color, _ opacity: Double = 1) {
            self.x = x; self.y = y; self.scale = scale; self.color = color; self.opacity = opacity
        }
    }

    /// Which livery a flight flies is drawn from its own code, so a pass keeps its livery for
    /// good: the archive re-derives the same one on every read.
    ///
    /// Shaped like FNV-1a over the seed's UTF-16 code units — but it is **not** FNV-1a, and must
    /// not be "corrected" into it. The reference computes `h = (h * 16777619) >>> 0` in
    /// JavaScript, where `h` is a float64: the product reaches ~7.2 × 10¹⁶, past the 2⁵³ mark
    /// where doubles stop being able to hold consecutive integers, so its low bits are rounded
    /// away before `>>> 0` truncates. Textbook 32-bit wrapping arithmetic gives a *different*
    /// answer for every seed but the empty string, which would repaint every pass ever issued.
    ///
    /// The second JavaScript-ism is `^`, which is `ToInt32` and therefore **signed** — `h` goes
    /// negative mid-loop, and the multiply is a negative float64 before `>>> 0` folds it back.
    ///
    /// Verified against the reference executed under node for all ten `carriersSelfCheck` seeds.
    static func livery(seed: String) -> Livery {
        var h: Double = 2166136261
        for unit in seed.utf16 {
            let x = Int32(bitPattern: UInt32(truncatingIfNeeded: Int64(h))) ^ Int32(unit)
            h = Double(UInt32(truncatingIfNeeded: Int64(Double(x) * 16777619)))
        }
        let all = Livery.allCases
        return all[Int(UInt32(h) % UInt32(all.count))]
    }

    /// The onboarding cover deck tears nine passes, showing the whole set of six.
    static let showcase: [Livery] = [.at1, .at2, .at3, .at4, .at5, .at6, .at3, .at5, .at1]

    // MARK: - Route

    /// Real scheduled pairs. Everything else is computed from distance.
    private static let pairs: [String: (block: Int, ac: String)] = [
        "SYD-SIN": (485, "A350-900"), "SYD-LHR": (1370, "787-9"),
        "SYD-LAX": (810, "A380-800"), "SYD-HND": (585, "787-9"),
        "SYD-HKG": (555, "A350-1000"), "SYD-DXB": (840, "A380-800"),
        "SYD-AKL": (200, "A320neo"), "SYD-MEL": (90, "737-800"),
        "SYD-PER": (300, "787-9"), "SYD-JNB": (855, "A380-800"),
        "SYD-DFW": (995, "787-9"), "SYD-SCL": (750, "787-9")
    ]

    /// What a flight is operated by. `seed` is the flight code, so the livery is stable.
    struct Operated: Codable, Hashable {
        var iata: String = Carriers.iata
        var name: String = Carriers.name
        var livery: Livery
        /// Aircraft type.
        var ac: String
        /// Block time in minutes.
        var block: Int
    }

    static func forRoute(from: String, to: String, seed: String?) -> Operated {
        let key = from + "-" + to
        let d: Double = Geography.distanceBetween(from, to)
        let raw: Double = (d / 875 * 60 + 30) / 5
        let computed: Int = Int(raw.rounded(.toNearestOrAwayFromZero)) * 5
        let block: Int = pairs[key]?.block ?? computed
        let ac: String = pairs[key]?.ac ?? aircraft(forKm: d)
        return Operated(livery: livery(seed: seed ?? (from + to)), ac: ac, block: block)
    }

    static func aircraft(forKm d: Double) -> String {
        switch d {
        case ..<1200: return "A320neo"
        case ..<3500: return "737-800"
        case ..<7000: return "A330-300"
        case ..<11000: return "787-9"
        default: return "777-300ER"
        }
    }

    // MARK: - Barcode

    /// Bar widths seeded from the flight code, so every stamp is individually issued.
    /// 26 bars, each 1–4 units wide.
    ///
    /// The seed fold is genuine signed 32-bit arithmetic (`h * 31 + c | 0`): that product stays
    /// under 2⁵³, so JavaScript computes it exactly and so can `Int32`.
    ///
    /// The LCG that follows is not. `h * 1103515245` reaches ~2.4 × 10¹⁸, far past 2⁵³, so the
    /// reference's float64 multiply rounds its low bits away before `& 0x7fffffff` masks it —
    /// exactly the trap in `livery(seed:)` above, and reproduced the same way. Exact 64-bit
    /// arithmetic here would print a different stamp on every pass.
    ///
    /// `Math.abs` is taken on a *widened* value, because `Int32.min` has no positive counterpart
    /// in 32 bits and JavaScript's answer is 2147483648, not zero.
    ///
    /// Verified bar-for-bar against the reference executed under node.
    static func barcode(seed: String?) -> [Int] {
        let s = seed?.isEmpty == false ? seed! : "TP"
        var fold: Int32 = 0
        for unit in s.utf16 {
            fold = fold &* 31 &+ Int32(unit)
        }
        var h = Double(abs(Int64(fold)))
        var out: [Int] = []
        for _ in 0..<26 {
            let m = UInt64(h * 1103515245 + 12345) & 0x7fffffff
            h = Double(m)
            out.append(1 + Int((m >> 7) % 4))
        }
        return out
    }
}

// MARK: - Drawing

/// The house mark: a stadium ring with a four-point star punched through it. The star and its
/// hole are one path with an even-odd fill — two separate shapes would not cut the hole.
struct CarrierMarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        // STAR
        p.move(to: CGPoint(x: 0, y: -19.17))
        p.addCurve(to: CGPoint(x: 13.76, y: 0),
                   control1: CGPoint(x: 0, y: -12.46), control2: CGPoint(x: 8.94, y: 0))
        p.addCurve(to: CGPoint(x: 0, y: 19.17),
                   control1: CGPoint(x: 8.94, y: 0), control2: CGPoint(x: 0, y: 12.46))
        p.addCurve(to: CGPoint(x: -13.76, y: 0),
                   control1: CGPoint(x: 0, y: 12.46), control2: CGPoint(x: -8.94, y: 0))
        p.addCurve(to: CGPoint(x: 0, y: -19.17),
                   control1: CGPoint(x: -8.94, y: 0), control2: CGPoint(x: 0, y: -12.46))
        p.closeSubpath()
        // HOLE
        p.move(to: CGPoint(x: 0, y: -13.71))
        p.addCurve(to: CGPoint(x: 9.84, y: 0),
                   control1: CGPoint(x: 0, y: -8.91), control2: CGPoint(x: 6.4, y: 0))
        p.addCurve(to: CGPoint(x: 0, y: 13.71),
                   control1: CGPoint(x: 6.4, y: 0), control2: CGPoint(x: 0, y: 8.91))
        p.addCurve(to: CGPoint(x: -9.84, y: 0),
                   control1: CGPoint(x: 0, y: 8.91), control2: CGPoint(x: -6.4, y: 0))
        p.addCurve(to: CGPoint(x: 0, y: -13.71),
                   control1: CGPoint(x: -6.4, y: 0), control2: CGPoint(x: 0, y: -8.91))
        p.closeSubpath()
        return p.offsetBy(dx: rect.midX, dy: rect.midY)
    }
}

/// One mark: the ring plus the punched star, drawn at the mark's own scale.
struct CarrierMarkView: View {
    let mark: Carriers.Mark

    var body: some View {
        ZStack {
            // `stroke`, not `strokeBorder`: SVG centres a stroke on the path, so the ring's outer
            // edge sits half a stroke *outside* the 29.34 × 40.18 box. Insetting it instead draws
            // the whole mark a stroke-width small — 3pt out of place at the pass band's scale.
            RoundedRectangle(cornerRadius: 14.67, style: .circular)
                .stroke(mark.color, lineWidth: 1.83)
                .frame(width: 29.34, height: 40.18)
            CarrierMarkShape()
                .fill(mark.color, style: FillStyle(eoFill: true))
                .frame(width: 29.34, height: 40.18)
        }
        .opacity(mark.opacity)
        .scaleEffect(mark.scale)
        .position(x: mark.x, y: mark.y)
    }
}

/// A carrier band, authored on 268 × 90 and scaled to whatever box it is given. Repeating
/// liveries crop rather than squash, so the archive tile slices the band instead of distorting it.
struct CarrierBandView: View {
    let livery: Carriers.Livery
    /// When false the band scales to fit; when true it fills and crops, which is what the
    /// narrow 268 × 52 layout does.
    var crop: Bool = false

    var body: some View {
        GeometryReader { geo in
            let sx = geo.size.width / Carriers.bandSize.width
            let sy = geo.size.height / Carriers.bandSize.height
            let s = crop ? max(sx, sy) : sx
            ZStack {
                livery.field
                ZStack {
                    ForEach(Array(livery.marks.enumerated()), id: \.offset) { _, mark in
                        CarrierMarkView(mark: mark)
                    }
                }
                .frame(width: Carriers.bandSize.width, height: Carriers.bandSize.height)
                .scaleEffect(s, anchor: .center)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
    }
}
