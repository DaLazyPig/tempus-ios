import SwiftUI
import UIKit

/// Type, one-for-one with the reference's `--font-*`, `--size-*`, `--weight-*`, `--track-*`,
/// `--lh-*` and the composed `--text-*` roles.
///
/// Outfit carries everything a person reads and every large numeral — geometric, even-width
/// digits, so readouts stay steady without a mono. DM Mono is reserved for small uppercase
/// boarding-pass labels and flight codes only.
enum TFont {

    // MARK: - Families

    /// `--font-core`
    enum Core: String {
        case light = "Outfit-Light"
        case regular = "Outfit-Regular"
        case medium = "Outfit-Medium"
        case semibold = "Outfit-SemiBold"
        case bold = "Outfit-Bold"
        case extraBold = "Outfit-ExtraBold"
    }

    /// `--font-data`
    enum Data: String {
        case regular = "DMMono-Regular"
        case medium = "DMMono-Medium"
    }

    static func core(_ weight: Core, _ size: CGFloat) -> Font {
        .custom(weight.rawValue, fixedSize: size)
    }

    /// Scales with Dynamic Type, for the roles that should. Screens that must not reflow (the
    /// boarding pass, the card faces, the dial) use `core(_:_:)` above, which is fixed.
    static func coreScaled(_ weight: Core, _ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(weight.rawValue, size: size, relativeTo: style)
    }

    static func data(_ weight: Data, _ size: CGFloat) -> Font {
        .custom(weight.rawValue, fixedSize: size)
    }

    // MARK: - Size scale (1.25 ratio, tuned)

    static let sizeDisplay: CGFloat = 64
    static let sizeTitle1: CGFloat = 40
    static let sizeTitle2: CGFloat = 30
    static let sizeTitle3: CGFloat = 23
    static let sizeBodyLg: CGFloat = 18
    static let sizeBody: CGFloat = 16
    static let sizeBodySm: CGFloat = 14
    static let sizeCaption: CGFloat = 12
    static let sizeMicro: CGFloat = 11
    static let sizeReadout: CGFloat = 56
    static let sizeReadoutSm: CGFloat = 28

    /// The shared size for every dial that sets a real quantity full-bleed: Preflight's minutes,
    /// Redeem's cost, onboarding's daily cap. (Consistency sweep, Sep 2026 — the three used to run
    /// 116/108/96, one literal apiece; this is Redeem's own figure, since Redeem was the one
    /// already carried at this value.) Two dials deliberately do not use it as-is:
    ///  - **Redeem's own shrink** while an unlock is running is a real, different number
    ///    (`sizeDialValueUnlocked`), not this token, so the banner has room.
    ///  - **The in-flight countdown** (`FlyingScreen`) is read-only and sets mm:ss, a wider
    ///    string than any of these pickers ever show — it keeps its own size rather than being
    ///    squeezed to fit this one.
    static let sizeDialValue: CGFloat = 108
    /// Redeem's price readout while the unlock banner is up — a real shrink to make room for the
    /// banner, kept as a stated fraction of `sizeDialValue` rather than an independent literal.
    static let sizeDialValueUnlocked: CGFloat = sizeDialValue * (84.0 / 108.0)
    /// The gift amount, which sits inside a modal card rather than a full screen — two-fifths of
    /// the shared dial size, which is what actually fits that card's own padding.
    static let sizeDialValueModal: CGFloat = sizeDialValue * 0.4

    // MARK: - Line height

    static let lhTight: CGFloat = 1.02
    static let lhHeading: CGFloat = 1.14
    static let lhBody: CGFloat = 1.5
    static let lhRelaxed: CGFloat = 1.65

    // MARK: - Tracking, in em

    static let trackDisplay: CGFloat = -0.03
    static let trackHeading: CGFloat = -0.02
    static let trackBody: CGFloat = 0
    static let trackLabel: CGFloat = 0.16
    static let trackData: CGFloat = 0.02

    // MARK: - Composed roles

    static var display: Font { core(.bold, sizeDisplay) }
    static var title1: Font { core(.bold, sizeTitle1) }
    static var title2: Font { core(.semibold, sizeTitle2) }
    static var title3: Font { core(.semibold, sizeTitle3) }
    static var body: Font { core(.regular, sizeBody) }
    static var label: Font { data(.medium, sizeMicro) }
    static var readout: Font { core(.bold, sizeReadout) }
}

extension View {
    /// Applies a role's tracking and line spacing together, since CSS states them in one
    /// shorthand and getting one without the other is the usual way type drifts off-spec.
    ///
    /// `track` is in em, as the token declares it; `lineHeight` is the CSS unitless multiple.
    func tpType(size: CGFloat, track: CGFloat = 0, lineHeight: CGFloat? = nil) -> some View {
        // SwiftUI's lineSpacing is the gap *between* lines, not the line box, so the font's own
        // line height has to come out of the CSS multiple.
        let spacing = lineHeight.map { max(0, size * ($0 - 1.2)) } ?? 0
        return self.tracking(track * size).lineSpacing(spacing)
    }

    /// The uppercase boarding-pass label: DM Mono medium 11 / 0.16em, always upper-cased.
    func tpLabelStyle() -> some View {
        font(TFont.label)
            .textCase(.uppercase)
            .tracking(TFont.trackLabel * TFont.sizeMicro)
    }
}

/// A large readout at the design's letter-spacing, kerned *between* glyphs only.
///
/// SwiftUI's `.tracking()` (and `.kerning()` with it) also applies the spacing after the final
/// glyph, so at the negative values this app's big numerals use, the computed line measures
/// narrower than its own ink and `Text` clips whatever overflows — invisible on a digit whose
/// right edge is already near-vertical ("1", "4", "7"), but a flat-cut right side on a round one
/// ("0", "6", "8", "9"). Use this instead of `Text(...).tracking(...)` for any readout large
/// enough, and negatively tracked enough, for that to show — the in-flight countdown and the
/// preflight/redeem minute dials all qualify.
func tpText(_ string: String, size: CGFloat, track: CGFloat) -> Text {
    Text(tpKerned(string, track * size))
}

private func tpKerned(_ string: String, _ kern: CGFloat) -> AttributedString {
    var text = AttributedString(string)
    guard text.characters.count > 1 else { return text }
    text[text.startIndex..<text.index(text.endIndex, offsetByCharacters: -1)].kern = kern
    return text
}

#if DEBUG
/// The kern stops one character short of the end, and stepping back needs a character to step
/// back over. Both degenerate strings are real: a one-second countdown reads "1", and an empty
/// one is one bad divisor away.
func typographySelfCheck() {
    assert(tpKerned("", -8).runs.allSatisfy { $0.kern == nil }, "an empty string has nothing to kern")
    assert(tpKerned("8", -8).runs.allSatisfy { $0.kern == nil }, "a lone glyph has nothing to kern between")

    let ten = tpKerned("10", -8)
    let kerned = ten.runs.filter { $0.kern != nil }
    assert(kerned.count == 1 && String(ten[kerned[0].range].characters) == "1",
           "the spacing lands between the glyphs, never after the last one — that is what clipped the zero")
}
#endif

/// The five membership-tier typefaces. Each tier's card is set in its own face — that identity is
/// the design, so these ship as real files rather than mapping onto system stacks.
///
/// `resolved` falls back to a system face of the same character if a file is missing, so a card
/// still renders (in the wrong type) rather than silently becoming Helvetica with no clue why.
enum TCardFont: String, CaseIterable {
    /// Essential — condensed grotesque.
    case essential = "BigShouldersDisplay-Bold"
    /// Signature — old-style serif.
    case signature = "CormorantGaramond-Regular"
    /// Premier — modern didone.
    case premier = "BodoniModa-Bold"
    /// Prestige — geometric extended.
    case prestige = "Syne-ExtraBold"
    /// Founders — high-contrast display serif.
    case founders = "Italiana-Regular"
    /// One display use outside the tier ladder.
    case archivo = "ArchivoBlack-Regular"

    func font(_ size: CGFloat) -> Font {
        TCardFont.installed.contains(rawValue)
            ? .custom(rawValue, fixedSize: size)
            : fallback(size)
    }

    private func fallback(_ size: CGFloat) -> Font {
        switch self {
        case .essential, .prestige, .archivo:
            return .system(size: size, weight: .black, design: .default)
        case .signature, .premier, .founders:
            return .system(size: size, weight: .regular, design: .serif)
        }
    }

    /// Resolved once at launch. `UIFont(name:)` returning nil is the only reliable signal that a
    /// PostScript name is wrong or the file was never bundled.
    static let installed: Set<String> = {
        Set(TCardFont.allCases.map(\.rawValue).filter { UIFont(name: $0, size: 12) != nil })
    }()

    /// Named in the debug self-check so a missing or misnamed font file is caught at launch
    /// rather than discovered as a wrong-looking card weeks later.
    static var missing: [String] {
        allCases.map(\.rawValue).filter { !installed.contains($0) }
    }
}
