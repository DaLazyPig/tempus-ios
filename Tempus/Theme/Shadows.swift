import SwiftUI

/// The shadow roles. CSS shadows stack several layers; SwiftUI's `.shadow` also stacks, so each
/// role applies its layers in the same order the token declares them.
///
/// Every role resolves to exactly **two** layers — a role that declares one pads with a
/// transparent second. That fixed shape is deliberate: `tpShadow` has to produce the same view
/// type whichever role it is handed, or a conditional shadow (`biz ? .accent : .none`) would
/// change the *structure* of the tree rather than a value in it, which both rebuilds the whole
/// subtree and makes the change uninterpolable. With a fixed shape it animates, as the CSS
/// `transition: box-shadow` it ports does.
enum TShadow {
    case none, card, raised, overlay, accent

    /// One layer: colour, SwiftUI blur radius, y offset. Authored through `css(_:_:blur:spread:y:)`
    /// rather than by hand — see the note there for why the spread cannot be ignored.
    struct ShadowLayer {
        let color: Color
        let radius: CGFloat
        let y: CGFloat

        init(_ color: Color, _ radius: CGFloat, _ y: CGFloat) {
            self.color = color
            self.radius = radius
            self.y = y
        }

        static let clear = ShadowLayer(.clear, 0, 0)

        /// A CSS `box-shadow: 0 {y}px {blur}px {spread}px rgba(hex, alpha)`, in SwiftUI's terms.
        ///
        /// **The spread is not decoration, and it cannot be folded into the blur.** CSS insets the
        /// caster by `|spread|` *before* blurring it, so almost the whole shadow ends up hidden
        /// behind the opaque box and only a soft rim escapes. SwiftUI has no spread: `.shadow`
        /// always casts from the full silhouette. This port used to compensate by shrinking the
        /// blur — `radius = (blur - |spread|) / 2` at the authored alpha — which keeps the shadow
        /// the full width of the card and merely sharpens it, so every surface in the app wore a
        /// hard band roughly three times too dark. That is one bug, repeated everywhere, and it is
        /// what every "unnatural shadow" report was about.
        ///
        /// The fold that *is* correct is into the alpha. CSS blur is 2σ, so σ = blur/2; the
        /// intensity a straight edge casts at distance `d` outside the shadow's own edge is
        /// Φ(−d/σ). With the inset, the caster's edge sits `|spread|` outside the shadow edge, so
        /// it is lit to `alpha · Φ(spread/σ)`; without one it is lit to `alpha' · Φ(0)` = `alpha'/2`.
        /// Matching the two gives `alpha' = 2 · alpha · Φ(spread/σ)`, and the falloff outside the
        /// box is the same Gaussian tail either way. A zero spread returns the alpha unchanged.
        static func css(_ hex: UInt32, _ alpha: Double,
                        blur: CGFloat, spread: CGFloat = 0, y: CGFloat) -> ShadowLayer {
            let sigma = blur / 2
            let fade = sigma > 0 ? 2 * normalCDF(Double(spread / sigma)) : 1
            return ShadowLayer(Color(hex: hex, opacity: alpha * Swift.min(1, fade)), sigma, y)
        }

        /// The same conversion where the shadow takes a live colour rather than a token — a themed
        /// button casting in its own paint, say. Returns the opacity to paint that colour at.
        static func cssAlpha(_ alpha: Double, blur: CGFloat, spread: CGFloat) -> Double {
            let sigma = blur / 2
            guard sigma > 0 else { return alpha }
            return alpha * Swift.min(1, 2 * normalCDF(Double(spread / sigma)))
        }

        /// Zelen & Severo 26.2.17 — the standard normal CDF to ~7.5e-8, which is several orders
        /// more precision than a shadow alpha can carry. Here only so the table above can be
        /// written as the CSS it ports instead of as pre-chewed constants.
        static func normalCDF(_ x: Double) -> Double {
            let t = 1 / (1 + 0.2316419 * abs(x))
            let d = 0.3989422804014327 * exp(-x * x / 2)
            let p = d * t * (0.319381530 + t * (-0.356563782 + t * (1.781477937
                    + t * (-1.821255978 + t * 1.330274429))))
            return x >= 0 ? 1 - p : p
        }
    }

    // Static, so a body evaluation reads the tokens rather than rebuilding them.
    // 0 1px 2px rgba(35,57,91,.04), 0 8px 24px -12px rgba(35,57,91,.16)
    private static let cardLayers = (ShadowLayer.css(0x23395b, 0.04, blur: 2, y: 1),
                                     ShadowLayer.css(0x23395b, 0.16, blur: 24, spread: -12, y: 8))
    // 0 2px 4px rgba(35,57,91,.05), 0 18px 40px -18px rgba(35,57,91,.24)
    private static let raisedLayers = (ShadowLayer.css(0x23395b, 0.05, blur: 4, y: 2),
                                       ShadowLayer.css(0x23395b, 0.24, blur: 40, spread: -18, y: 18))
    // 0 24px 64px -20px rgba(16,29,49,.38)
    private static let overlayLayer = ShadowLayer.css(0x101d31, 0.38, blur: 64, spread: -20, y: 24)
    // 0 12px 28px -14px rgba(184,111,82,.6)
    private static let accentLayer = ShadowLayer.css(0xb86f52, 0.6, blur: 28, spread: -14, y: 12)

    // On a dark ground every one of the tints above is *lighter* than what it falls on, so it
    // stops being a shadow and becomes a halo: copper at 60% over navy700 is the glow that ringed
    // every Next button in onboarding. A shadow is an absence of light, so on dark grounds the
    // colour goes to the darkest ink in the palette and the opacity comes down — a real shadow on
    // a dark surface is nearly invisible, and that is the correct amount of it. The blurs match
    // their light-ground counterparts, so a surface does not change shape when it changes ground.
    private static let darkCard = ShadowLayer(Color(hex: 0x070d17, opacity: 0.14), 12, 8)
    private static let darkRaised = ShadowLayer(Color(hex: 0x070d17, opacity: 0.18), 20, 18)
    private static let darkAccent = ShadowLayer(Color(hex: 0x070d17, opacity: 0.20), 14, 12)

    func layers(onDark: Bool) -> (ShadowLayer, ShadowLayer) {
        guard onDark else { return layers }
        switch self {
        case .none:    return (.clear, .clear)
        case .card:    return (Self.darkCard, .clear)
        case .raised:  return (Self.darkRaised, .clear)
        // Already near-black, and it is the shadow a sheet casts over the whole app rather than
        // one cast onto a dark panel — correct on either ground.
        case .overlay: return (Self.overlayLayer, .clear)
        case .accent:  return (Self.darkAccent, .clear)
        }
    }

    var layers: (ShadowLayer, ShadowLayer) {
        switch self {
        case .none:    return (.clear, .clear)
        case .card:    return Self.cardLayers
        case .raised:  return Self.raisedLayers
        case .overlay: return (Self.overlayLayer, .clear)
        case .accent:  return (Self.accentLayer, .clear)
        }
    }
}

/// Whether the surface under this subtree is dark. Set it once at the root of a dark screen;
/// `tpShadow` and `OBPrimaryButton` both read it, so no individual call site has to know.
private struct TDarkGroundKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    var tpDarkGround: Bool {
        get { self[TDarkGroundKey.self] }
        set { self[TDarkGroundKey.self] = newValue }
    }
}

extension View {
    func tpDarkGround(_ on: Bool = true) -> some View { environment(\.tpDarkGround, on) }
}

/// Reads the ground out of the environment, which a plain `View` extension cannot do.
private struct TShadowModifier: ViewModifier {
    @Environment(\.tpDarkGround) private var onDark
    let shadow: TShadow

    func body(content: Content) -> some View {
        let (a, b) = shadow.layers(onDark: onDark)
        // `.shadow` is a filter, and SwiftUI pushes a filter down to every leaf it can reach —
        // so on a card it shadows each label and rule *separately*, printing soft grey blobs
        // across the card's own face instead of one silhouette behind it. CSS `box-shadow` is a
        // property of the box, which is what the tokens describe, so flatten first.
        return content
            .compositingGroup()
            .shadow(color: a.color, radius: a.radius, x: 0, y: a.y)
            .shadow(color: b.color, radius: b.radius, x: 0, y: b.y)
    }
}

extension View {
    func tpShadow(_ shadow: TShadow) -> some View {
        modifier(TShadowModifier(shadow: shadow))
    }

    /// `--ring-focus: 0 0 0 3px rgba(184,111,82,.35)`
    func tpFocusRing(_ radius: CGFloat, active: Bool = true) -> some View {
        overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Color(hex: 0xb86f52, opacity: 0.35), lineWidth: 3)
                .opacity(active ? 1 : 0)
        }
    }
}
