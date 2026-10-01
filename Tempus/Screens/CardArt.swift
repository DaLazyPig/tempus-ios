import SwiftUI
import UIKit

/// The membership card: its twenty faces, the palettes their surroundings are mixed from, and the
/// two views that draw one — `StatusCard` (a settled face) and `FoundersBack` (the only reverse).
///
/// Every face is authored on a 340 × 214 canvas with absolute pixel positions, so that is how they
/// are drawn here: a fixed-size `ZStack` with `.at(left:top:…)` putting each layer exactly where the
/// reference's CSS puts it, then one `scaleEffect` to fit wherever the card lands. Re-expressing
/// twenty layouts as stacks and spacers would drift the moment one number changed.
///
/// The pigments below are **artwork, not tokens**: each belongs to one face and is never reused as
/// UI colour, which is why they live here rather than in `TColor`.
enum CardArt {

    // MARK: - Canvas

    static let width: CGFloat = 340
    static let height: CGFloat = 214
    static let radius: CGFloat = 20
    /// The one 3D-flip perspective in the app — derived from the card's own width rather than
    /// eyeballed, so a card flipped anywhere reads as the same physical object. `HomeScreen`'s
    /// deck-card flip reads this too; see its own flip modifier for why a hardcoded `0.3` there
    /// used to disagree with this derivation.
    static let flipPerspective: CGFloat = width / 1400

    /// The built-in face names, per tier, in the order the picker offers them. Index 0 is the one
    /// face economy can keep — the house-flower "Stella" for the four flown tiers, "Gold" for
    /// Founders.
    static let names: [[String]] = [
        ["Stella", "Baseline", "Grid", "Stacked"],
        ["Stella", "Baseline", "Centred"],
        ["Stella", "Baseline", "Corner orbit", "Full width"],
        ["Stella", "Stella field", "Baseline", "Fuselage"],
        ["Gold", "Chalk", "Void", "Damask", "Crystal"]
    ]

    /// How many built-in faces a tier has.
    static func count(tier: Int) -> Int { names[clamp(tier, 0, names.count - 1)].count }

    /// A slot in a tier's face set: either one of the built-ins above, or a face bought in the
    /// Concourse, which joins the tier's own set so the studio treats it like any other.
    struct Face: Identifiable, Hashable {
        var id: Int
        var name: String
        var shop: ShopFace?
    }

    static func faces(tier: Int, owned: [String] = []) -> [Face] {
        let t = clamp(tier, 0, names.count - 1)
        var out = names[t].enumerated().map { Face(id: $0.offset, name: $0.element, shop: nil) }
        for id in owned {
            guard let f = ShopCatalog.face(id: id), f.t == t else { continue }
            out.append(Face(id: out.count, name: f.name, shop: f))
        }
        return out
    }

    /// A stored index from an older build can point past the end of a tier's set; it is pulled back
    /// into range rather than rendering a hole.
    static func slot(_ v: Int, in set: [Face]) -> Int { clamp(v, 0, max(0, set.count - 1)) }

    static func shopFace(tier: Int, variant: Int, owned: [String]) -> ShopFace? {
        let set = faces(tier: tier, owned: owned)
        guard !set.isEmpty else { return nil }
        return set[slot(variant, in: set)].shop
    }

    // MARK: - The surroundings a face brings with it

    /// The chrome a card sits inside — the studio's ground, the Status Club header band, the ink and
    /// the buttons drawn over them. A face chooses its own surroundings, so the page follows the
    /// card rather than the tier.
    struct Theme: Equatable {
        var bg: Color
        var ink: Color
        var mute: Color
        var accent: Color
        var rule: Color
        var chip: Color
        var chipInk: Color
        var idle: Color
        var btn: Color
        var btnInk: Color
        /// Whether the ground is dark enough that ink flips to light.
        var dark: Bool
        /// The reference's `hdr`: only a shop face carries one; the built-in tiers keep their own.
        var band: Color? = nil
    }

    /// The four flown tiers plus a Founders-toned fallback.
    private static let base: [Theme] = [
        Theme(bg: hex(0xbcd3ea), ink: hex(0x152740), mute: hex(0x4c6684), accent: hex(0x9d5230),
              rule: hex(0x152740, 0.16), chip: hex(0x152740, 0.10), chipInk: hex(0x3a5673),
              idle: hex(0x152740, 0.20), btn: hex(0x152740), btnInk: hex(0xf2f5fa), dark: false),
        Theme(bg: hex(0x1b3a5c), ink: hex(0xf2f5fa), mute: hex(0xa6bcd8), accent: hex(0xe6b08f),
              rule: hex(0xf2f5fa, 0.14), chip: hex(0xf2f5fa, 0.14), chipInk: hex(0xcfdcee),
              idle: hex(0xf2f5fa, 0.24), btn: hex(0xb86f52), btnInk: hex(0xffffff), dark: true),
        Theme(bg: hex(0xecd3c1), ink: hex(0x4a2a19), mute: hex(0x8a5f47), accent: hex(0x9d5230),
              rule: hex(0x4a2a19, 0.18), chip: hex(0x4a2a19, 0.10), chipInk: hex(0x7a4229),
              idle: hex(0x4a2a19, 0.22), btn: hex(0x7a4229), btnInk: hex(0xfff6f0), dark: false),
        Theme(bg: hex(0xc9ced4), ink: hex(0x141a24), mute: hex(0x4d5765), accent: hex(0x8a5a34),
              rule: hex(0x141a24, 0.16), chip: hex(0x141a24, 0.10), chipInk: hex(0x39424f),
              idle: hex(0x141a24, 0.22), btn: hex(0x141a24), btnInk: hex(0xf0e6d6), dark: false),
        Theme(bg: hex(0x63512f), ink: hex(0xf8f0dd), mute: hex(0xdccdab), accent: hex(0xf3e3bf),
              rule: hex(0xf8f0dd, 0.20), chip: hex(0xf8f0dd, 0.16), chipInk: hex(0xf4e9d2),
              idle: hex(0xf8f0dd, 0.30), btn: hex(0xf3e3bf), btnInk: hex(0x3b2f18), dark: true)
    ]

    /// Founders is the only tier whose five faces are five different materials rather than five
    /// arrangements of one, so its surroundings follow the chosen face.
    private static let foundersThemes: [Theme] = [
        base[4],
        Theme(bg: hex(0xcfccc5), ink: hex(0x141416), mute: hex(0x4f4f53), accent: hex(0x7d6b45),
              rule: hex(0x141416, 0.18), chip: hex(0x141416, 0.09), chipInk: hex(0x333337),
              idle: hex(0x141416, 0.24), btn: hex(0x141416), btnInk: hex(0xf6f4f0), dark: false),
        Theme(bg: hex(0x3a3c42), ink: hex(0xf4ecdd), mute: hex(0xc0b9ab), accent: hex(0xe8c964),
              rule: hex(0xf4ecdd, 0.18), chip: hex(0xf4ecdd, 0.14), chipInk: hex(0xeee6d6),
              idle: hex(0xf4ecdd, 0.28), btn: hex(0xf0e6d6), btnInk: hex(0x26272b), dark: true),
        Theme(bg: hex(0x6b3020), ink: hex(0xfbeee0), mute: hex(0xdfb9a0), accent: hex(0xf3e3bf),
              rule: hex(0xfbeee0, 0.20), chip: hex(0xfbeee0, 0.16), chipInk: hex(0xf6e3ce),
              idle: hex(0xfbeee0, 0.30), btn: hex(0xf3e3bf), btnInk: hex(0x4a1f13), dark: true),
        Theme(bg: hex(0x39434e), ink: hex(0xf2f7fc), mute: hex(0xb7c3d0), accent: hex(0xeaf1f8),
              rule: hex(0xf2f7fc, 0.18), chip: hex(0xf2f7fc, 0.14), chipInk: hex(0xe6edf5),
              idle: hex(0xf2f7fc, 0.28), btn: hex(0xeef4fa), btnInk: hex(0x242c34), dark: true)
    ]

    /// The milled-aluminium Prestige face reads as a light card, so its surroundings go dark grey
    /// instead of the light grey the other Prestige faces sit against.
    private static let metal = Theme(
        bg: hex(0x5f666d), ink: hex(0xf2f5fa), mute: hex(0xc6ccd3), accent: hex(0xe6b08f),
        rule: hex(0xf2f5fa, 0.16), chip: hex(0xf2f5fa, 0.14), chipInk: hex(0xe8ecf1),
        idle: hex(0xf2f5fa, 0.26), btn: hex(0xf0e6d6), btnInk: hex(0x2a2f36), dark: true)

    private static let headerColours: [Color] = [
        hex(0x5b76a0), hex(0x526d99), hex(0xc0804d), hex(0x454c57), hex(0x7d6841)
    ]
    private static let foundersHeaders: [Color] = [
        hex(0x7d6841), hex(0xb3afa7), hex(0x55585f), hex(0x8a4230), hex(0x55616e)
    ]

    private static func isMetal(_ tier: Int, _ v: Int) -> Bool { tier == 3 && v == 6 }

    /// A bought face brings its own surroundings, mixed off the card's own colour and held a step
    /// away so the card still reads as an object sitting on a surface rather than blending into it.
    private static func shopTheme(_ f: ShopFace) -> Theme {
        let ground = ShopCatalog.groundColor(f.ground)
        let dark = ShopCatalog.groundIsDark(f.ground)
        // A dark face gets a mid ground rather than a darker one, so the card is always the darkest
        // or the lightest thing on screen.
        let bg = mix(ground, .white, dark ? 0.62 : 0.5)
        // The reference mixes a light face 0.46 toward black and then darkens until luma ≤ 126 — a
        // mid grey, asked for lighter on 18 Sep 2026. A light face now takes 0.34 and is *lightened*
        // until luma ≥ 160; a dark face keeps the reference's 0.18.
        //
        // **The original reason for that 160 is gone, and the number is still right.** It was
        // chosen to keep every light band on the *dark-ink* side of `isDark`'s 150 rather than
        // straddling it — and Status Club has since stopped flipping its ink at all, so there is
        // no longer a side to stay on. What the loop still buys is a light face's band landing at
        // a *predictable* value instead of wherever its ground happened to sit, which is what
        // lets `band(behind:)` deepen it by a fixed amount and know the answer carries white
        // (160 → ~100). Do not "restore" this to the reference's darkening: it would undo the
        // lighter bands asked for on 18 Sep for no gain.
        var band = mix(ground, .black, dark ? 0.18 : 0.34)
        var steps = 0
        while !dark && steps < 10 && luma(band) < 160 {
            band = mix(band, .white, 0.14)
            steps += 1
        }
        return Theme(
            bg: bg, ink: hex(0x1a1c20), mute: hex(0x1a1c20, 0.6), accent: mix(ground, .black, 0.2),
            rule: hex(0x1a1c20, 0.16), chip: hex(0x1a1c20, 0.08), chipInk: hex(0x2a2c32),
            idle: hex(0x1a1c20, 0.22), btn: hex(0x1a1c20), btnInk: hex(0xf6f4f0),
            // The reference hard-codes this false for every shop face, however dark it reads.
            dark: false, band: band)
    }

    /// Resolution order: an owned shop face at this slot wins; then Founders' own five materials;
    /// then the Prestige-metal special case; then the tier's static base theme.
    static func theme(tier: Int, variant: Int, owned: [String] = []) -> Theme {
        if let f = shopFace(tier: tier, variant: variant, owned: owned) { return shopTheme(f) }
        if tier == Status.founderIndex {
            return foundersThemes[clamp(variant, 0, foundersThemes.count - 1)]
        }
        if isMetal(tier, variant) { return metal }
        return base[clamp(tier, 0, base.count - 1)]
    }

    /// The band Status Club paints behind the card, and the panel the studio grows from.
    static func header(tier: Int, variant: Int, owned: [String] = []) -> Color {
        // `hdr`, not `bg`: the reference paints a shop face's band with the colour mixed toward
        // black above, so a white face sits on a grey band rather than on a copy of itself.
        if let f = shopFace(tier: tier, variant: variant, owned: owned) { return shopTheme(f).band ?? shopTheme(f).bg }
        if tier == Status.founderIndex {
            return foundersHeaders[clamp(variant, 0, foundersHeaders.count - 1)]
        }
        if isMetal(tier, variant) { return hex(0x5f666d) }
        return headerColours[clamp(tier, 0, headerColours.count - 1)]
    }

    /// The colour actually painted behind the card on Status Club, derived from `header`.
    ///
    /// It always moves *away* from the face — a band that just repeats it reads as one flat
    /// surface rather than a card sitting on something — but only ever toward a ground white ink
    /// still holds, because that screen's title and header controls are white on every face.
    ///
    /// A dark face's band lifts toward the page ground; everything else deepens toward navy. The
    /// branch tests the *lifted* colour rather than the header, which is what makes it
    /// threshold-safe: the lift is taken only when its own result is already provably dark, so
    /// neither branch can land a band straddling `isDark`'s 150 and flipping between two
    /// neighbouring variants.
    ///
    /// Lives here rather than in `StatusScreen` so `statusBandSelfCheck` can put every tier,
    /// every variant and all 191 shop faces through it — the one thing that silently breaks when
    /// either table gains a row.
    static func band(behind header: Color) -> Color {
        let lifted = mix(header, Color(hex: 0xf2f5fa), 0.22)
        return isDark(lifted) ? lifted : mix(header, Color(hex: 0x101d31), 0.55)
    }

    // MARK: - The three the router and the screens call

    /// The ground a face brings with it — what the card studio paints behind the deck, and what the
    /// window fills with so nothing flashes through during the cut.
    ///
    /// ponytail: `owned` defaults to empty because `RootView` has no list to hand it, so a purchased
    /// face fills the *safe area* with its tier's base ground rather than its own mixed one, while
    /// the studio itself (which does pass `owned`) paints correctly over the top. Thread the owned
    /// list through `RootView.cardDesignGround` if that seam ever shows.
    static func ground(tier: Int, variant: Int, owned: [String] = []) -> Color {
        theme(tier: tier, variant: variant, owned: owned).bg
    }

    /// Whether ink over that ground flips to light.
    static func isDark(tier: Int, variant: Int, owned: [String] = []) -> Bool {
        theme(tier: tier, variant: variant, owned: owned).dark
    }

    /// The same judgement for one arbitrary colour: standard luma weights, dark below 150.
    static func isDark(_ colour: Color) -> Bool { luma(colour) < 150 }

    // MARK: - Colour arithmetic

    static func mix(_ a: Color, _ b: Color, _ t: Double) -> Color {
        let x = a.tpParts, y = b.tpParts
        return Color(.sRGB,
                     red: x.r + (y.r - x.r) * t,
                     green: x.g + (y.g - x.g) * t,
                     blue: x.b + (y.b - x.b) * t,
                     opacity: 1)
    }

    private static func luma(_ c: Color) -> Double {
        let p = c.tpParts
        return (p.r * 0.299 + p.g * 0.587 + p.b * 0.114) * 255
    }

    private static func hex(_ v: UInt32, _ o: Double = 1) -> Color { Color(hex: v, opacity: o) }

    static func clamp(_ v: Int, _ a: Int, _ b: Int) -> Int { max(a, min(b, v)) }
}

private extension Color {
    /// sRGB components, for mixing and luma. `UIColor` is the only route to them.
    var tpParts: (r: Double, g: Double, b: Double, a: Double) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b), Double(a))
    }
}

// MARK: - Drawing primitives

/// A CSS gradient angle is measured clockwise from "to top"; SwiftUI wants two unit points.
private func cssLinear(_ deg: Double, _ stops: [Gradient.Stop]) -> LinearGradient {
    let r = deg * .pi / 180
    let dx = sin(r) / 2, dy = -cos(r) / 2
    return LinearGradient(stops: stops,
                          startPoint: UnitPoint(x: 0.5 - dx, y: 0.5 - dy),
                          endPoint: UnitPoint(x: 0.5 + dx, y: 0.5 + dy))
}

private func s(_ v: UInt32, _ o: Double, _ at: Double) -> Gradient.Stop {
    Gradient.Stop(color: Color(hex: v, opacity: o), location: at)
}

/// The diagonal gloss every face but Fuselage and the Founders materials is topped with. `t` is the
/// black the gradient lands on.
private func sheen(_ t: Double) -> LinearGradient {
    cssLinear(140, [s(0xffffff, 0.16, 0), s(0xffffff, 0, 0.48), s(0x000000, t, 1)])
}

/// `repeating-linear-gradient`: bands measured along an axis, drawn perpendicular to it. One
/// primitive covers Signature's pinstripe, Fuselage's linework and Gold's.
private struct Stripes: View {
    /// The CSS gradient angle.
    var angle: Double
    var period: CGFloat
    /// `(from, to, colour)` offsets inside one period.
    var bands: [(CGFloat, CGFloat, Color)]

    var body: some View {
        Canvas { ctx, size in
            let d = (size.width * size.width + size.height * size.height).squareRoot()
            ctx.translateBy(x: size.width / 2, y: size.height / 2)
            ctx.rotate(by: .degrees(angle - 90))
            var x = (-d / 2 / period).rounded(.down) * period
            while x < d / 2 {
                for b in bands {
                    ctx.fill(Path(CGRect(x: x + b.0, y: -d / 2, width: b.1 - b.0, height: d)),
                             with: .color(b.2))
                }
                x += period
            }
        }
    }
}

/// `repeating-radial-gradient`: concentric hairline rings. Premier's three grounds are the same
/// pattern at three centres and three periods.
private struct Rings: View {
    var centre: UnitPoint
    /// The radius the first ring starts at.
    var inner: CGFloat
    var thickness: CGFloat
    var period: CGFloat
    var colour: Color

    var body: some View {
        Canvas { ctx, size in
            let cx = centre.x * size.width, cy = centre.y * size.height
            let far = [CGPoint(x: 0, y: 0), CGPoint(x: size.width, y: 0),
                       CGPoint(x: 0, y: size.height), CGPoint(x: size.width, y: size.height)]
                .map { hypot($0.x - cx, $0.y - cy) }.max() ?? 0
            var r = inner + thickness / 2
            while r <= far {
                ctx.stroke(Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)),
                           with: .color(colour), lineWidth: thickness)
                r += period
            }
        }
    }
}

/// The house mark: a stadium ring holding a four-pointed star, the star's tips meeting the inside of
/// the ring at top, bottom, left and right. The star is one path with an even-odd hole punched
/// through it — that is what gives it its pinched waist.
private struct HouseMark: View {
    /// Half the unscaled box, so a caller can place the mark by its centre.
    static let halfW: CGFloat = 14.67
    static let halfH: CGFloat = 20.09

    var colour: Color
    var scale: CGFloat
    var opacity: Double = 1

    var body: some View {
        ZStack {
            Capsule().stroke(colour, lineWidth: 1.83)
            StarMark().fill(colour, style: FillStyle(eoFill: true))
        }
        .frame(width: Self.halfW * 2, height: Self.halfH * 2)
        .opacity(opacity)
        .scaleEffect(scale)
    }
}

private struct StarMark: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addPath(lobes(tip: 19.17, wing: 13.76, waist: 12.46, in: rect))
        p.addPath(lobes(tip: 13.71, wing: 9.84, waist: 8.91, in: rect))
        return p
    }

    /// One four-pointed outline: four cubics from tip to tip through the four wings.
    private func lobes(tip: CGFloat, wing: CGFloat, waist: CGFloat, in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: c.x + x, y: c.y + y) }
        var p = Path()
        p.move(to: at(0, -tip))
        p.addCurve(to: at(wing, 0), control1: at(0, -waist), control2: at(waist, 0))
        p.addCurve(to: at(0, tip), control1: at(waist, 0), control2: at(0, waist))
        p.addCurve(to: at(-wing, 0), control1: at(0, waist), control2: at(-waist, 0))
        p.addCurve(to: at(0, -tip), control1: at(-waist, 0), control2: at(0, -waist))
        p.closeSubpath()
        return p
    }
}

/// The house flower: four teardrop petals around a shared centre, optionally cored in gold.
private struct Caulis: View {
    /// Half the unscaled box, so a caller can place the flower by its centre.
    static let half: CGFloat = 20

    var colour: Color
    var scale: CGFloat
    var opacity: Double = 1
    var core: Bool = true

    var body: some View {
        ZStack {
            CaulisShape().fill(colour)
            if core {
                RoundedRectangle(cornerRadius: 2.6, style: .continuous)
                    .fill(Color(hex: 0xe0b23a))
                    .frame(width: 9, height: 9)
            }
        }
        .frame(width: Self.half * 2, height: Self.half * 2)
        .opacity(opacity)
        .scaleEffect(scale)
    }
}

private struct CaulisShape: Shape {
    func path(in rect: CGRect) -> Path {
        var petal = Path()
        petal.move(to: .zero)
        petal.addCurve(to: CGPoint(x: 0, y: -20),
                       control1: CGPoint(x: 8, y: -6), control2: CGPoint(x: 8, y: -16))
        petal.addCurve(to: .zero,
                       control1: CGPoint(x: -8, y: -16), control2: CGPoint(x: -8, y: -6))
        petal.closeSubpath()

        var p = Path()
        for a in [0.0, 90, 180, 270] {
            let t = CGAffineTransform(translationX: rect.midX, y: rect.midY)
                .rotated(by: a * .pi / 180)
            p.addPath(petal.applying(t))
        }
        return p
    }
}

/// The small corner wordmark. Its `.2em` tracking is bespoke to the card — wider than the label
/// token used everywhere else.
private func mark(_ colour: Color) -> some View {
    Text(verbatim: "TEMPUS")
        .font(TFont.data(.medium, 11))
        .tracking(0.2 * 11)
        .foregroundStyle(colour)
        .fixedSize()
}

/// Prestige's four interlocking orbits: the same 300 × 148 ellipse four times, each turned 30°
/// further and each a step fainter.
private struct Orbit: View {
    var body: some View {
        ZStack {
            ForEach(Array([0.5, 0.42, 0.34, 0.28].enumerated()), id: \.offset) { i, o in
                Ellipse()
                    .stroke(Color(hex: 0xe2c496, opacity: o), lineWidth: 1)
                    .rotationEffect(.degrees(Double(i) * 30))
            }
        }
        .frame(width: 300, height: 148)
        .at(left: 20, top: 33)
    }
}

private struct OrbitWash: View {
    var body: some View {
        ZStack {
            cssLinear(200, [s(0x000000, 0.28, 0), s(0x000000, 0, 1)])
            EllipticalGradient(stops: [s(0xffeccd, 0.22, 0), s(0xffeccd, 0, 0.6)],
                               center: UnitPoint(x: 0.2, y: 0),
                               startRadiusFraction: 0, endRadiusFraction: 1.05)
        }
    }
}

/// Eight metal studs, spread between the two inset edges. Fuselage only.
private struct RivetRow: View {
    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<8, id: \.self) { i in
                if i > 0 { Spacer(minLength: 0) }
                Circle()
                    .fill(RadialGradient(
                        stops: [s(0xf4f6f8, 1, 0), s(0x8c9299, 1, 0.7), s(0x63696f, 1, 1)],
                        center: UnitPoint(x: 0.32, y: 0.28), startRadius: 0, endRadius: 8))
                    .overlay(
                        Circle()
                            .fill(cssLinear(180, [s(0x000000, 0, 0.5), s(0x000000, 0.4, 1)]))
                            .blur(radius: 1.2)
                            .clipShape(Circle())
                    )
                    .frame(width: 8, height: 8)
                    .shadow(color: Color(hex: 0xffffff, opacity: 0.5), radius: 0.5, x: 0, y: 1)
            }
        }
        .frame(width: CardArt.width - 44)
    }
}

// MARK: - Absolute placement on the card canvas

private extension View {
    /// CSS `position:absolute` on the 340 × 214 card: name the edges the reference names, and pass
    /// `boxHeight` for display type whose line box is shorter than its glyphs (`font: 700 62px/.78`).
    func at(left: CGFloat? = nil, right: CGFloat? = nil,
            top: CGFloat? = nil, bottom: CGFloat? = nil,
            boxHeight: CGFloat? = nil, align: Alignment = .leading) -> some View {
        let w: CGFloat? = (left != nil && right != nil) ? CardArt.width - left! - right! : nil
        let h: CGFloat? = boxHeight
            ?? ((top != nil && bottom != nil) ? CardArt.height - top! - bottom! : nil)
        let anchor = Alignment(
            horizontal: left != nil ? .leading : (right != nil ? .trailing : .center),
            vertical: top != nil ? .top : (bottom != nil ? .bottom : .center))
        return frame(width: w, height: h, alignment: align)
            .frame(width: CardArt.width, height: CardArt.height, alignment: anchor)
            .offset(x: left ?? (right.map { -$0 } ?? 0), y: top ?? (bottom.map { -$0 } ?? 0))
    }

    /// Place a mark by its centre: `.at` positions a box's edge, and every logo and flower in the
    /// catalogue is given as a centre point in card coordinates.
    func centred(x: CGFloat, y: CGFloat, halfW: CGFloat, halfH: CGFloat) -> some View {
        at(left: x - halfW, top: y - halfH)
    }
}

/// The member's name, in Outfit, as every face sets it.
private func holder(_ name: String, _ size: CGFloat, _ colour: Color) -> some View {
    Text(name)
        .font(TFont.core(.semibold, size))
        .foregroundStyle(colour)
        .fixedSize()
}

/// A tier wordmark: its own typeface, its own tracking, and a line box that matches the CSS one.
private func wordmark(_ text: String, _ face: TCardFont, _ size: CGFloat,
                      track: CGFloat, _ colour: Color) -> some View {
    Text(verbatim: text)
        .font(face.font(size))
        .tracking(track * size)
        .foregroundStyle(colour)
        .fixedSize()
}

// MARK: - The five Founders materials

/// Ground and washes only — no type, no flower. The front stacks its art on top of this and the
/// back reuses it whole, which is what makes a light face flip to a light back.
private struct FoundersMaterial: View {
    let slot: Int

    var body: some View {
        ZStack {
            switch slot {
            case 0:
                cssLinear(158, [s(0x7d6435, 1, 0), s(0xdfc48c, 1, 0.19), s(0xad8d52, 1, 0.4),
                                s(0xf0dcae, 1, 0.57), s(0xbda067, 1, 0.75), s(0x836a39, 1, 1)])
                Stripes(angle: 92, period: 4,
                        bands: [(0, 1, Color(hex: 0xffffff, opacity: 0.15)),
                                (1, 2, Color(hex: 0x000000, opacity: 0.07))])
            case 1:
                Color(hex: 0xf6f4f0)
            case 2:
                Color(hex: 0x111214)
            case 3:
                cssLinear(160, [s(0x4d2317, 1, 0), s(0x2c120b, 1, 0.52), s(0x431d12, 1, 1)])
            default:
                Color(hex: 0x05070a)
            }
        }
    }
}

/// The wash a Founders material carries over its ground — drawn under the type on the front, and
/// straight onto the back.
private struct FoundersWash: View {
    let slot: Int

    var body: some View {
        ZStack {
            switch slot {
            case 0:
                Color.clear
            case 1:
                EllipticalGradient(stops: [s(0xffffff, 0.8, 0), s(0xffffff, 0, 0.56)],
                                   center: UnitPoint(x: 0.14, y: 0),
                                   startRadiusFraction: 0, endRadiusFraction: 1.0)
                cssLinear(202, [s(0x101112, 0.09, 0), s(0x101112, 0, 0.58)])
            case 2:
                EllipticalGradient(stops: [s(0xffffff, 0.05, 0), s(0xffffff, 0, 0.62)],
                                   center: UnitPoint(x: 0.5, y: 0.34),
                                   startRadiusFraction: 0, endRadiusFraction: 1.1)
                cssLinear(204, [s(0x000000, 0.42, 0), s(0x000000, 0, 0.66)])
            case 3:
                EllipticalGradient(stops: [s(0xffe0ba, 0.18, 0), s(0xffe0ba, 0, 0.58)],
                                   center: UnitPoint(x: 0.78, y: -0.08),
                                   startRadiusFraction: 0, endRadiusFraction: 1.08)
                cssLinear(206, [s(0x000000, 0.45, 0), s(0x000000, 0, 0.6)])
            default:
                cssLinear(122, [s(0xdfe6ee, 0.24, 0), s(0xdfe6ee, 0.04, 0.26), s(0xffffff, 0, 0.46),
                                s(0xdfe6ee, 0.14, 0.68), s(0xdfe6ee, 0.02, 1)])
                RoundedRectangle(cornerRadius: 38, style: .continuous)
                    .fill(cssLinear(140, [s(0xffffff, 0.14, 0), s(0xffffff, 0, 0.62)]))
                    .overlay(RoundedRectangle(cornerRadius: 38, style: .continuous)
                        .strokeBorder(Color(hex: 0xffffff, opacity: 0.28), lineWidth: 1))
                    .frame(width: 280, height: 280)
                    .rotationEffect(.degrees(24))
                    .at(left: -40, top: -70)
                cssLinear(90, [s(0xffffff, 0, 0), s(0xffffff, 0.75, 0.38), s(0xffffff, 0, 1)])
                    .frame(height: 1).at(left: 0, right: 0, top: 0)
                cssLinear(90, [s(0xffffff, 0, 0), s(0xffffff, 0.45, 0.62), s(0xffffff, 0, 1)])
                    .frame(height: 1).at(left: 0, right: 0, bottom: 0)
            }
        }
    }
}

/// Gold is the one material with a specular streak over everything, type included.
private struct FoundersGloss: View {
    let slot: Int

    var body: some View {
        if slot == 0 {
            cssLinear(118, [s(0xffffff, 0, 0.34), s(0xffffff, 0.34, 0.47), s(0xffffff, 0, 0.6)])
        }
    }
}

// MARK: - The faces

/// One built-in face, drawn at true size. Ground first, then the layers in the order the reference
/// stacks them.
private struct BuiltinFace: View {
    let tier: Int
    let slot: Int
    let name: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            switch tier {
            case 0: essential
            case 1: signature
            case 2: premier
            case 3: prestige
            default: founders
            }
        }
        .frame(width: CardArt.width, height: CardArt.height)
    }

    // MARK: Essential — #eef1f5, Big Shoulders Display

    private static let essInk = Color(hex: 0x23395b)
    private static let essDim = Color(hex: 0x23395b, opacity: 0.42)
    private static let essMark = Color(hex: 0x23395b, opacity: 0.5)
    private static let essRule = Color(hex: 0x23395b, opacity: 0.28)

    @ViewBuilder private var essential: some View {
        Color(hex: 0xeef1f5)
        switch slot {
        case 0:
            // Watermark: one mark at card scale, cropped by the edge and sunk to 14%.
            HouseMark(colour: Self.essInk, scale: 5.2, opacity: 0.14)
                .centred(x: 276, y: 108, halfW: HouseMark.halfW, halfH: HouseMark.halfH)
            sheen(0.06)
            mark(Self.essMark).at(left: 22, top: 22)
            wordmark("ESSEN", .essential, 62, track: 0.01, Self.essInk)
                .at(left: 22, top: 60, boxHeight: 62 * 0.78)
            wordmark("TIAL", .essential, 62, track: 0.01, Self.essDim)
                .at(left: 22, top: 110, boxHeight: 62 * 0.78)
            holder(name, 16, Self.essInk).at(left: 22, bottom: 22)
        case 1:
            sheen(0.06)
            holder(name, 16, Self.essInk).at(left: 22, top: 22)
            mark(Self.essMark).at(right: 22, top: 22)
            wordmark("ESSENTIAL", .essential, 78, track: 0.01, Self.essInk)
                .at(left: 22, right: 22, bottom: 22, boxHeight: 78 * 0.78)
        case 2:
            sheen(0.06)
            Rectangle().fill(Self.essRule).frame(height: 1).at(left: 0, right: 0, top: 52)
            Rectangle().fill(Self.essRule).frame(height: 1).at(left: 0, right: 0, top: 161)
            Rectangle().fill(Self.essRule).frame(width: 1).at(left: 84, top: 0, bottom: 0)
            Rectangle().fill(Self.essRule).frame(width: 1).at(left: 255, top: 0, bottom: 0)
            VStack(spacing: 0) {
                wordmark("ESSENTIAL", .essential, 34, track: 0.05, Self.essInk)
                    .frame(height: 34 * 0.8)
                Spacer(minLength: 0)
                holder(name, 13, Color(hex: 0x23395b, opacity: 0.72))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 22)
            .frame(width: 172, height: 110)
            .background(Color(hex: 0xffffff, opacity: 0.55))
            .overlay(Rectangle().strokeBorder(Color(hex: 0x23395b, opacity: 0.5), lineWidth: 1))
            .at(left: 84, top: 52)
        default:
            sheen(0.06)
            mark(Self.essMark).at(right: 22, top: 22)
            VStack(alignment: .leading, spacing: 2) {
                wordmark("ESSEN", .essential, 62, track: 0.01, Self.essInk)
                    .frame(height: 62 * 0.78)
                wordmark("TIAL", .essential, 62, track: 0.01, Self.essDim)
                    .frame(height: 62 * 0.78)
            }
            .at(left: 22, top: 44)
            holder(name, 16, Self.essInk).at(left: 22, bottom: 22)
        }
    }

    // MARK: Signature — #56719b under a pinstripe, Cormorant Garamond

    private static let sigMark = Color(hex: 0xffffff, opacity: 0.7)
    private static let sigName = Color(hex: 0xffffff, opacity: 0.9)

    @ViewBuilder private var signature: some View {
        Color(hex: 0x56719b)
        Stripes(angle: 118, period: 9, bands: [(0, 1, Color(hex: 0xffffff, opacity: 0.18))])
        sheen(0.09)
        switch slot {
        case 0:
            mark(Self.sigMark).at(right: 22, top: 22)
            HouseMark(colour: .white, scale: 1.206)
                .centred(x: 170, y: 71, halfW: HouseMark.halfW, halfH: HouseMark.halfH)
            wordmark("Signature", .signature, 54, track: 0, .white)
                .at(left: 22, right: 22, top: 112, boxHeight: 54 * 0.9, align: .center)
            holder(name, 15, Self.sigName).at(left: 0, right: 0, bottom: 22, align: .center)
        case 1:
            holder(name, 16, .white).at(left: 22, top: 22)
            mark(Self.sigMark).at(right: 22, top: 22)
            wordmark("Signature", .signature, 56, track: 0.01, .white)
                .at(left: 22, bottom: 22, boxHeight: 56 * 0.9)
        default:
            mark(Self.sigMark).at(right: 22, top: 22)
            wordmark("Signature", .signature, 62, track: 0, .white)
                .at(left: 22, right: 22, top: 74, boxHeight: 62 * 0.9, align: .center)
            holder(name, 15, Self.sigName).at(left: 0, right: 0, bottom: 22, align: .center)
        }
    }

    // MARK: Premier — #96552d under ring texture, Bodoni Moda

    private static let prmInk = Color(hex: 0xf7e9df)
    private static let prmMark = Color(hex: 0xf7e9df, opacity: 0.7)
    private static let prmName = Color(hex: 0xf7e9df, opacity: 0.82)

    @ViewBuilder private var premier: some View {
        Color(hex: 0x96552d)
        switch slot {
        case 2:
            Rings(centre: UnitPoint(x: 0.92, y: 0.06), inner: 22, thickness: 1, period: 23,
                  colour: Color(hex: 0xffffff, opacity: 0.2))
        case 3:
            Rings(centre: UnitPoint(x: 0.5, y: 0.5), inner: 17, thickness: 0.8, period: 17.8,
                  colour: Color(hex: 0xffffff, opacity: 0.16))
        default:
            Rings(centre: UnitPoint(x: 0.5, y: 0.5), inner: 25, thickness: 1, period: 26,
                  colour: Color(hex: 0xffffff, opacity: 0.22))
        }
        switch slot {
        case 0:
            sheen(0.09)
            mark(Self.prmMark).at(right: 22, top: 22)
            HouseMark(colour: Self.prmInk, scale: 1.6667)
                .centred(x: 170, y: 70, halfW: HouseMark.halfW, halfH: HouseMark.halfH)
            wordmark("PREMIER", .premier, 30, track: 0.14, Self.prmInk)
                .at(left: 22, right: 22, top: 130, boxHeight: 30, align: .center)
            holder(name, 15, Self.prmName).at(left: 0, right: 0, bottom: 22, align: .center)
        case 1:
            sheen(0.09)
            mark(Self.prmMark).at(right: 22, top: 22)
            VStack(spacing: 16) {
                wordmark("PREMIER", .premier, 32, track: 0.14, Self.prmInk).frame(height: 32)
                holder(name, 15, Self.prmInk)
            }
            .frame(width: CardArt.width, height: CardArt.height)
        case 2:
            sheen(0.12)
            mark(Self.prmMark).at(left: 22, top: 22)
            wordmark("PREMIER", .premier, 32, track: 0.14, Self.prmInk)
                .at(left: 22, bottom: 56, boxHeight: 32)
            holder(name, 15, Self.prmName).at(left: 22, bottom: 24)
        default:
            sheen(0.14)
            holder(name, 15, Self.prmInk).at(left: 22, top: 22)
            mark(Self.prmMark).at(right: 22, top: 22)
            wordmark("PREMIER", .premier, 42, track: 0.05, Self.prmInk)
                .at(left: 22, right: 22, top: 92, boxHeight: 42, align: .center)
        }
    }

    // MARK: Prestige — #08090c, Syne

    private static let prsInk = Color(hex: 0xf0e6d6)
    private static let prsName = Color(hex: 0xf0e6d6, opacity: 0.85)

    @ViewBuilder private var prestige: some View {
        switch slot {
        case 0:
            Color(hex: 0x08090c)
            Orbit()
            OrbitWash()
            HouseMark(colour: .white, scale: 1.155)
                .centred(x: 170, y: 71, halfW: HouseMark.halfW, halfH: HouseMark.halfH)
            wordmark("PRESTIGE", .prestige, 27, track: 0.08, Self.prsInk)
                .at(left: 26, right: 26, top: 116, boxHeight: 27, align: .center)
            holder(name, 15, Self.prsName).at(left: 0, right: 0, top: 154, align: .center)
        case 1:
            Color(hex: 0x08090c)
            OrbitWash()
            HouseMark(colour: .white, scale: 1.3)
                .centred(x: 58, y: 52, halfW: HouseMark.halfW, halfH: HouseMark.halfH)
            HouseMark(colour: .white, scale: 0.7, opacity: 0.75)
                .centred(x: 160, y: 34, halfW: HouseMark.halfW, halfH: HouseMark.halfH)
            HouseMark(colour: .white, scale: 0.95, opacity: 0.85)
                .centred(x: 250, y: 66, halfW: HouseMark.halfW, halfH: HouseMark.halfH)
            HouseMark(colour: .white, scale: 0.55, opacity: 0.6)
                .centred(x: 306, y: 132, halfW: HouseMark.halfW, halfH: HouseMark.halfH)
            wordmark("PRESTIGE", .prestige, 27, track: 0.08, Self.prsInk)
                .at(left: 26, right: 26, bottom: 60, boxHeight: 27)
            holder(name, 15, Self.prsName).at(left: 26, bottom: 26)
        case 2:
            Color(hex: 0x08090c)
            Orbit()
            OrbitWash()
            wordmark("PRESTIGE", .prestige, 29, track: 0.08, Self.prsInk)
                .at(left: 26, right: 26, bottom: 64, boxHeight: 29)
            holder(name, 15, Self.prsInk).at(left: 26, bottom: 26)
        default:
            // Fuselage: milled aluminium. The one face that hand-rolls its own gloss.
            cssLinear(158, [s(0x7f858c, 1, 0), s(0xc9ced4, 1, 0.22), s(0x9aa1a8, 1, 0.42),
                            s(0xe2e6ea, 1, 0.58), s(0xa2a8af, 1, 0.74), s(0x767c83, 1, 1)])
            Stripes(angle: 92, period: 4,
                    bands: [(0, 1, Color(hex: 0xffffff, opacity: 0.16)),
                            (1, 2, Color(hex: 0x000000, opacity: 0.05))])
            fuselageRule.at(left: 0, right: 0, top: 56)
            fuselageRule.at(left: 0, right: 0, bottom: 56)
            RivetRow().at(left: 22, right: 22, top: 22)
            RivetRow().at(left: 22, right: 22, bottom: 22)
            wordmark("PRESTIGE", .prestige, 30, track: 0.09, Color(hex: 0x565c63))
                .shadow(color: Color(hex: 0xffffff, opacity: 0.65), radius: 0, x: 0, y: 1)
                .shadow(color: Color(hex: 0x000000, opacity: 0.3), radius: 0, x: 0, y: -1)
                .at(left: 26, right: 26, top: 82, boxHeight: 30)
            holder(name, 15, Color(hex: 0x4c5259))
                .shadow(color: Color(hex: 0xffffff, opacity: 0.55), radius: 0, x: 0, y: 1)
                .at(left: 26, top: 126)
            cssLinear(118, [s(0xffffff, 0, 0.38), s(0xffffff, 0.28, 0.48), s(0xffffff, 0, 0.58)])
        }
    }

    private var fuselageRule: some View {
        Rectangle()
            .fill(Color(hex: 0x000000, opacity: 0.28))
            .frame(height: 1)
            .shadow(color: Color(hex: 0xffffff, opacity: 0.45), radius: 0, x: 0, y: 1)
    }

    // MARK: Founders — five materials, all set in Italiana

    /// The damask's six-flower grid, as `(x, y)` centres.
    private static let damaskFlowers: [(x: CGFloat, y: CGFloat)] = [
        (60, 40), (170, 40), (280, 40), (60, 174), (170, 174), (280, 174)
    ]

    @ViewBuilder private var founders: some View {
        FoundersMaterial(slot: slot)
        switch slot {
        case 0:
            Caulis(colour: Color(hex: 0xfff7e2, opacity: 0.5), scale: 1.1883, core: false)
                .centred(x: 55, y: 55.97, halfW: Caulis.half, halfH: Caulis.half)
            Caulis(colour: Color(hex: 0x3a2b0e, opacity: 0.5), scale: 1.1883, core: false)
                .centred(x: 55, y: 57, halfW: Caulis.half, halfH: Caulis.half)
            wordmark("FOUNDERS", .founders, 34, track: 0.16, Color(hex: 0x382a0e, opacity: 0.74))
                .shadow(color: Color(hex: 0xfff8e4, opacity: 0.6), radius: 0, x: 0, y: 1)
                .shadow(color: Color(hex: 0x000000, opacity: 0.18), radius: 0, x: 0, y: -1)
                .at(left: 24, right: 24, bottom: 58, boxHeight: 34)
            holder(name, 15, Color(hex: 0x32260c, opacity: 0.78)).at(left: 24, bottom: 26)
        case 1:
            Caulis(colour: Color(hex: 0x101112), scale: 5.625)
                .shadow(color: Color(hex: 0x101112, opacity: 0.32), radius: 4, x: 0, y: 7)
                .centred(x: 275, y: 91, halfW: Caulis.half, halfH: Caulis.half)
            FoundersWash(slot: slot)
            wordmark("FOUNDERS", .founders, 31, track: 0.2, Color(hex: 0x101112))
                .at(left: 26, right: 26, bottom: 48, boxHeight: 31)
            holder(name, 15, Color(hex: 0x101112, opacity: 0.75)).at(left: 26, bottom: 26)
        case 2:
            FoundersWash(slot: slot)
            Caulis(colour: Color(hex: 0xf2efe8), scale: 1.16)
                .centred(x: 170, y: 91, halfW: Caulis.half, halfH: Caulis.half)
            holder(name, 14, Color(hex: 0xf0e6d6, opacity: 0.9)).at(left: 26, bottom: 26)
            Text(verbatim: "FOUNDERS")
                .font(TFont.data(.regular, 9))
                .tracking(0.32 * 9)
                .foregroundStyle(Color(hex: 0xe2c496, opacity: 0.8))
                .fixedSize()
                .at(right: 26, bottom: 27)
        case 3:
            ForEach(Self.damaskFlowers.indices, id: \.self) { n in
                Caulis(colour: Color(hex: 0xe8ce97), scale: 0.8, opacity: 0.26, core: false)
                    .centred(x: Self.damaskFlowers[n].x, y: Self.damaskFlowers[n].y,
                             halfW: Caulis.half, halfH: Caulis.half)
            }
            FoundersWash(slot: slot)
            cssLinear(96, [s(0xa1793c, 1, 0), s(0xf0dcae, 1, 0.42),
                           s(0xc8a25f, 1, 0.68), s(0x8f6a33, 1, 1)])
                .frame(height: 46)
                .shadow(color: Color(hex: 0xfff8e4, opacity: 0.4), radius: 0, x: 0, y: 1)
                .shadow(color: Color(hex: 0x000000, opacity: 0.35), radius: 0, x: 0, y: -1)
                .at(left: 0, right: 0, top: 84)
            // `text-indent` cancels the trailing letter-space, so the wordmark optically centres.
            wordmark("FOUNDERS", .founders, 27, track: 0.26, Color(hex: 0x341508))
                .offset(x: 0.26 * 27)
                .at(left: 26, right: 26, top: 84, boxHeight: 46, align: .center)
            holder(name, 15, Color(hex: 0xf2e2cd)).at(left: 26, right: 26, top: 146, align: .center)
        default:
            FoundersWash(slot: slot)
            Caulis(colour: Color(hex: 0xeef4fa, opacity: 0.55), scale: 1.5417)
                .centred(x: 277, y: 71, halfW: Caulis.half, halfH: Caulis.half)
            wordmark("FOUNDERS", .founders, 33, track: 0.18, Color(hex: 0xeef4fa))
                .at(left: 26, right: 26, bottom: 56, boxHeight: 33)
            holder(name, 15, Color(hex: 0xeef4fa, opacity: 0.8)).at(left: 26, bottom: 26)
        }
        FoundersGloss(slot: slot)
    }
}

/// A face bought in the Concourse. Its ground and its art are stored markup, so it goes through the
/// shop renderer rather than being drawn here; only the member's name is substituted in, exactly as
/// the reference does it — a literal replace of the sample identity.
private struct ShopFaceView: View {
    let face: ShopFace
    let name: String

    var body: some View {
        MarkupView(face.inner(for: name),
                   background: face.ground,
                   designSize: CGSize(width: CardArt.width, height: CardArt.height),
                   width: CardArt.width,
                   cornerRadius: CardArt.radius)
    }
}

// MARK: - The settled card

/// The settled card face, drawn at card scale and shrunk to fit wherever it lands.
///
/// Founders is the only tier with a back, and only where the caller opts in: a card in the picker
/// can be swiped through but not turned over. The flip swaps which face is mounted at the halfway
/// point rather than relying on backface culling, which SwiftUI has no equivalent for.
struct StatusCard: View {
    var tier: Int
    var variant: Int
    var name: String
    var width: CGFloat = CardArt.width
    var owned: [String] = []
    var flippable: Bool = false
    var serial: String = "001"
    var issued: String = "\u{2014}"
    var miles: Int = 0

    @State private var flipped = false
    @State private var showBack = false

    private var set: [CardArt.Face] { CardArt.faces(tier: tier, owned: owned) }
    private var k: Int { CardArt.slot(variant, in: set) }
    private var twoSided: Bool { flippable && tier == Status.founderIndex }
    private var scale: CGFloat { width / CardArt.width }

    var body: some View {
        card
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: CardArt.width * scale, height: CardArt.height * scale,
                   alignment: .topLeading)
            .onChange(of: twoSided) { _, now in
                if !now { flipped = false; showBack = false }
            }
    }

    @ViewBuilder private var card: some View {
        if twoSided {
            ZStack {
                front.opacity(showBack ? 0 : 1)
                back
                    .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0),
                                      perspective: CardArt.flipPerspective)
                    .opacity(showBack ? 1 : 0)
            }
            .rotation3DEffect(.degrees(flipped ? 180 : 0), axis: (x: 0, y: 1, z: 0),
                              perspective: CardArt.flipPerspective)
            .contentShape(Rectangle())
            .onTapGesture { turn() }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Membership card")
            .accessibilityHint("Turn the card over")
        } else {
            front
        }
    }

    @ViewBuilder private var front: some View {
        Group {
            if let shop = set.indices.contains(k) ? set[k].shop : nil {
                ShopFaceView(face: shop, name: name)
            } else {
                BuiltinFace(tier: tier, slot: set.indices.contains(k) ? set[k].id : 0, name: name)
            }
        }
        .frame(width: CardArt.width, height: CardArt.height)
        .cardEdge()
    }

    private var back: some View {
        FoundersBack(name: name, serial: serial, issued: issued, miles: miles,
                     variant: set.indices.contains(k) ? set[k].id : 0,
                     shop: set.indices.contains(k) ? set[k].shop : nil)
            .cardEdge()
    }

    /// The faces swap at the instant the card is edge-on, which on `.glide` is **not** halfway
    /// through: cubic-bezier(.22,.61,.36,1) reaches 90° at 20% of the duration (solved, not
    /// eyeballed — 144 ms of 720). The swap used to wait until 360 ms, by which point the card
    /// was ~157° round and `rotation3DEffect` (no backface culling) was showing the front face
    /// mirrored for ~215 ms before snapping to the back — the Founders flip's flicker.
    private func turn() {
        let next = !flipped
        withAnimation(.glide(0.72)) { flipped = next }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(144))
            showBack = next
        }
    }
}

private extension View {
    /// The card's own drop shadow and the 1px inner highlight along its top edge.
    func cardEdge() -> some View {
        clipShape(RoundedRectangle(cornerRadius: CardArt.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: CardArt.radius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [Color(hex: 0xffffff, opacity: 0.16), .clear],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 1)
            )
            // `0 18px 34px -20px rgba(16,29,49,.5)` — through `ShadowLayer.css`: σ = 34/2, and
            // the −20 spread folds into the alpha, not the blur. See Theme/Shadows.swift.
            .shadow(color: Color(hex: 0x101d31, opacity: 0.1197), radius: 17, x: 0, y: 18)
    }
}

// MARK: - The Founders reverse

/// The only face in the club with a back, and it is cut from the same material as the front: same
/// ground, same washes, same ink. Four fields only — issued, edition, miles, name.
struct FoundersBack: View {
    var name: String
    var serial: String
    var issued: String
    var miles: Int
    /// Which of the five built-in materials to wear.
    var variant: Int = 0
    /// A bought face wears its own ground instead, with the ink triad taken from how dark it reads.
    var shop: ShopFace?

    private struct Skin {
        var ink: Color
        var mute: Color
        var rule: Color
        var mark: Color
    }

    private static let skins: [Skin] = [
        Skin(ink: Color(hex: 0x34270c, opacity: 0.92), mute: Color(hex: 0x34270c, opacity: 0.62),
             rule: Color(hex: 0x34270c, opacity: 0.22), mark: Color(hex: 0x3a2b0e, opacity: 0.45)),
        Skin(ink: Color(hex: 0x101112), mute: Color(hex: 0x101112, opacity: 0.56),
             rule: Color(hex: 0x101112, opacity: 0.16), mark: Color(hex: 0x101112)),
        Skin(ink: Color(hex: 0xf2efe8), mute: Color(hex: 0xf2efe8, opacity: 0.58),
             rule: Color(hex: 0xf2efe8, opacity: 0.16), mark: Color(hex: 0xf2efe8)),
        Skin(ink: Color(hex: 0xf7e6d4), mute: Color(hex: 0xf7e6d4, opacity: 0.6),
             rule: Color(hex: 0xf7e6d4, opacity: 0.2), mark: Color(hex: 0xe8ce97)),
        Skin(ink: Color(hex: 0xeef4fa), mute: Color(hex: 0xeef4fa, opacity: 0.6),
             rule: Color(hex: 0xeef4fa, opacity: 0.16), mark: Color(hex: 0xeef4fa, opacity: 0.62))
    ]

    private var slot: Int { CardArt.clamp(variant, 0, Self.skins.count - 1) }

    /// Which way this face's ink runs — light on a dark ground, dark on a light one. The scrim in
    /// `material` and the triad in `skin` both key off it, so they can never disagree.
    private var shopDark: Bool { shop.map { ShopCatalog.groundIsDark($0.ground) } ?? false }

    private var skin: Skin {
        guard let shop else { return Self.skins[slot] }
        return shopDark
            ? Skin(ink: Color(hex: 0xf4eee2, opacity: 0.94),
                   mute: Color(hex: 0xf4eee2, opacity: 0.6),
                   rule: Color(hex: 0xf4eee2, opacity: 0.16),
                   mark: Color(hex: 0xf4eee2, opacity: 0.6))
            : Skin(ink: Color(hex: 0x181a1e, opacity: 0.92),
                   mute: Color(hex: 0x181a1e, opacity: 0.55),
                   rule: Color(hex: 0x181a1e, opacity: 0.14),
                   mark: Color(hex: 0x181a1e, opacity: 0.55))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            material

            Caulis(colour: skin.mark, scale: 0.47667, opacity: 0.9, core: false)
                .centred(x: 39, y: 37, halfW: Caulis.half, halfH: Caulis.half)

            HStack(alignment: .top, spacing: 18) {
                field("DATE ISSUED", issued, align: .leading)
                Spacer(minLength: 0)
                field("EDITION", "No. \(serial) of 100", align: .trailing)
            }
            .at(left: 26, right: 26, top: 78)

            Rectangle().fill(skin.rule).frame(height: 1).at(left: 26, right: 26, top: 128)

            HStack(alignment: .bottom, spacing: 18) {
                VStack(alignment: .leading, spacing: 0) {
                    label("MILES")
                    // `tpText`, matching `ShopItemScreen`'s own preview of this same card face —
                    // a formatted mile count clips a round digit's right edge otherwise.
                    tpText(miles.formatted(.number.locale(Locale(identifier: "en_US"))), size: 24, track: -0.035)
                        .font(TFont.core(.bold, 24))
                        .monospacedDigit()
                        .foregroundStyle(skin.ink)
                        .padding(.top, 10)
                }
                Spacer(minLength: 0)
                field("NAME", name, align: .trailing)
            }
            .at(left: 26, right: 26, top: 150)
        }
        .frame(width: CardArt.width, height: CardArt.height)
    }

    @ViewBuilder private var material: some View {
        if let shop {
            // `materialOnly`: the face's own painted layers, with its wordmark, holder name and
            // house mark left off — the same "ground and washes only" rule the built-in reverse
            // below follows. The reference's `shopBackHTML` paints `f.ground` and nothing else,
            // which is a different card whenever the colour lives in the art rather than in the
            // ground (`Bullion`: `#1a1508` under a gold gradient, so its back read near-black
            // against a gold front). See `MarkupStore.material(_:)`.
            MarkupView(shop.inner, background: shop.ground,
                       designSize: CGSize(width: CardArt.width, height: CardArt.height),
                       width: CardArt.width, cornerRadius: CardArt.radius, materialOnly: true)
            // **Held back, so the record on top of it reads.** The ink triad is chosen once, from
            // how dark the *ground* is, and a face's art does not have to agree with its ground
            // across the whole card — `Bullion` is gold over `#1a1508`, so light ink sat on gold at
            // the top and on near-black at the bottom. The front solves this by setting its own
            // type per region; a back with four fixed fields cannot. One flat scrim in the ink's
            // own direction gives every field the same contrast on any material, and a card back
            // being quieter than its front is what a card back is.
            Color(shopDark ? .black : .white).opacity(0.38)
            cssLinear(202, [s(0x000000, 0.16, 0), s(0x000000, 0, 0.58)])
        } else {
            FoundersMaterial(slot: slot)
            FoundersWash(slot: slot)
            FoundersGloss(slot: slot)
        }
    }

    private func label(_ text: String) -> some View {
        Text(verbatim: text)
            .font(TFont.data(.medium, 9))
            .tracking(0.18 * 9)
            .foregroundStyle(skin.mute)
            .fixedSize()
    }

    private func field(_ title: String, _ value: String,
                       align: HorizontalAlignment) -> some View {
        VStack(alignment: align, spacing: 0) {
            label(title)
            Text(value)
                .font(TFont.core(.semibold, 15))
                .foregroundStyle(skin.ink)
                .padding(.top, 11)
        }
        .multilineTextAlignment(align == .trailing ? .trailing : .leading)
    }
}
