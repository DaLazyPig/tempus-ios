import SwiftUI

// MARK: - Card

enum TCardTone {
    case light, sunken, dark, accent, outline
}

enum TCardPadding {
    case none, sm, md, lg
    var value: CGFloat {
        switch self { case .none: return 0; case .sm: return TSpace.s4; case .md: return TSpace.s5; case .lg: return TSpace.s6 }
    }
}

enum TCardRadius {
    case xs, sm, md, lg, xl, pill
    var value: CGFloat {
        switch self {
        case .xs: return TRadius.xs
        case .sm: return TRadius.sm
        case .md: return TRadius.md
        case .lg: return TRadius.lg
        case .xl: return TRadius.xl
        case .pill: return TRadius.pill
        }
    }
}

private struct TCardPaint {
    var background: Color
    var foreground: Color
    var shadow: TShadow
    var border: Color?
}

private extension TCardTone {
    var paint: TCardPaint {
        switch self {
        case .light: return TCardPaint(background: TColor.surfaceCard, foreground: TColor.textPrimary, shadow: .card, border: nil)
        case .sunken: return TCardPaint(background: TColor.surfaceSunken, foreground: TColor.textPrimary, shadow: .none, border: nil)
        case .dark: return TCardPaint(background: TColor.surfaceInverse, foreground: TColor.textOnDark, shadow: .raised, border: nil)
        case .accent: return TCardPaint(background: TColor.surfaceAccent, foreground: TColor.textOnAccent, shadow: .accent, border: nil)
        case .outline: return TCardPaint(background: TColor.surfaceCard, foreground: TColor.textPrimary, shadow: .none, border: TColor.borderSubtle)
        }
    }
}

/// The general-purpose surface: five tones, six radii, optional padding. iOS has no pointer
/// hover, so `interactive` (the reference's hover-lift) drives only the tap press-scale here —
/// the house rule ("press feedback scales to `TPress.scale` over `TDur.fast`"), not a literal
/// port of a `:hover` effect nothing on a touch screen can trigger.
struct TCard<Content: View>: View {
    var tone: TCardTone = .light
    var padding: TCardPadding = .md
    var radius: TCardRadius = .lg
    var interactive: Bool = false
    var action: (() -> Void)? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        if let action {
            Button(action: action) { content() }
                .buttonStyle(TCardStyle(tone: tone, padding: padding, radius: radius, pressable: interactive))
        } else {
            let p = tone.paint
            content()
                .padding(padding.value)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(p.foreground)
                .background(RoundedRectangle(cornerRadius: radius.value, style: .continuous).fill(p.background))
                .overlay(RoundedRectangle(cornerRadius: radius.value, style: .continuous).stroke(p.border ?? .clear, lineWidth: p.border == nil ? 0 : 1))
                .tpShadow(p.shadow)
        }
    }
}

private struct TCardStyle: ButtonStyle {
    var tone: TCardTone
    var padding: TCardPadding
    var radius: TCardRadius
    var pressable: Bool

    func makeBody(configuration: Configuration) -> some View {
        let p = tone.paint
        configuration.label
            .padding(padding.value)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(p.foreground)
            .background(RoundedRectangle(cornerRadius: radius.value, style: .continuous).fill(p.background))
            .overlay(RoundedRectangle(cornerRadius: radius.value, style: .continuous).stroke(p.border ?? .clear, lineWidth: p.border == nil ? 0 : 1))
            .tpShadow(p.shadow)
            .scaleEffect(pressable && configuration.isPressed ? TPress.scale : 1)
            .animation(.glide(TDur.fast), value: configuration.isPressed)
    }
}

// MARK: - Tag

enum TTagTone {
    case neutral, accent, ontime, delayed, diverted, onDark
}

private extension TTagTone {
    var paint: (background: Color, foreground: Color) {
        switch self {
        case .neutral: return (TColor.surfaceSunken, TColor.textSecondary)
        case .accent: return (TColor.surfaceAccentSoft, TColor.textAccent)
        case .ontime: return (TColor.statusOnTimeSoft, TColor.statusOnTime)
        case .delayed: return (TColor.statusDelayedSoft, TColor.statusDelayed)
        case .diverted: return (TColor.statusDivertedSoft, TColor.statusDiverted)
        case .onDark: return (TColor.glassOnDark, TColor.textOnDark)
        }
    }
}

/// The small uppercase pill — status words, category words. Always set in the label role
/// (DM Mono medium 11, 0.16em tracking, upper-cased), never a button.
struct Tag<Content: View>: View {
    var tone: TTagTone = .neutral
    @ViewBuilder var content: () -> Content

    var body: some View {
        let p = tone.paint
        HStack(spacing: 6) { content() }
            .tpLabelStyle()
            .foregroundStyle(p.foreground)
            .padding(.vertical, 5)
            .padding(.horizontal, 10)
            .background(Capsule().fill(p.background))
    }
}

extension Tag where Content == Text {
    init(_ text: String, tone: TTagTone = .neutral) {
        self.init(tone: tone) { Text(text) }
    }
}

// MARK: - StatusBanner

enum TBannerTone {
    case ontime, delayed, diverted, info, accent
}

private extension TBannerTone {
    var paint: (background: Color, foreground: Color) {
        switch self {
        case .ontime: return (TColor.statusOnTimeSoft, TColor.statusOnTime)
        case .delayed: return (TColor.statusDelayedSoft, TColor.statusDelayed)
        case .diverted: return (TColor.statusDivertedSoft, TColor.statusDiverted)
        case .info: return (TColor.surfaceSunken, TColor.textSecondary)
        case .accent: return (TColor.surfaceAccentSoft, TColor.textAccent)
        }
    }
}

/// An inline status block: an optional leading icon, a title, an optional body, an optional
/// trailing action — the shape "your flight is delayed" or "not connected to Screen Time" takes.
struct StatusBanner<Content: View, Action: View>: View {
    var tone: TBannerTone = .info
    var icon: Image? = nil
    var title: String? = nil
    @ViewBuilder var content: () -> Content
    @ViewBuilder var action: () -> Action

    var body: some View {
        let p = tone.paint
        HStack(alignment: .top, spacing: TSpace.s3) {
            if let icon {
                icon.padding(.top, 1)
            }
            VStack(alignment: .leading, spacing: 0) {
                if let title {
                    Text(title)
                        .font(TFont.core(.semibold, TFont.sizeBodySm))
                        .tpType(size: TFont.sizeBodySm, lineHeight: 1.35)
                }
                content()
                    .font(TFont.core(.regular, TFont.sizeBodySm))
                    .tpType(size: TFont.sizeBodySm, lineHeight: 1.45)
                    .opacity(0.85)
                    .padding(.top, title != nil ? 3 : 0)
            }
            // The text column takes the slack, so the block fills the width it is given and the
            // action sits at the trailing edge rather than wherever the copy happens to wrap.
            .frame(maxWidth: .infinity, alignment: .leading)
            action()
        }
        .foregroundStyle(p.foreground)
        .padding(TSpace.s4)
        .background(RoundedRectangle(cornerRadius: TRadius.md, style: .continuous).fill(p.background))
    }
}

extension StatusBanner where Content == EmptyView, Action == EmptyView {
    init(tone: TBannerTone = .info, icon: Image? = nil, title: String) {
        self.init(tone: tone, icon: icon, title: title, content: { EmptyView() }, action: { EmptyView() })
    }
}

extension StatusBanner where Action == EmptyView {
    init(tone: TBannerTone = .info, icon: Image? = nil, title: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.init(tone: tone, icon: icon, title: title, content: content, action: { EmptyView() })
    }
}

// MARK: - ScreenHeader

/// The title block every full screen opens with: an optional uppercase eyebrow, the big title,
/// optional leading (back button) and trailing (action) slots.
struct ScreenHeader<Leading: View, Trailing: View>: View {
    enum Tone { case light, dark }

    var eyebrow: String? = nil
    var title: String
    var tone: Tone = .light
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .top, spacing: TSpace.s4) {
            leading()
            VStack(alignment: .leading, spacing: 8) {
                if let eyebrow {
                    Text(eyebrow)
                        .tpLabelStyle()
                        .foregroundStyle(tone == .dark ? TColor.textOnDarkMuted : TColor.textMuted)
                }
                Text(title)
                    .font(TFont.core(.bold, TFont.sizeTitle1))
                    .tpType(size: TFont.sizeTitle1, track: TFont.trackHeading, lineHeight: TFont.lhHeading)
                    .foregroundStyle(tone == .dark ? TColor.textOnDark : TColor.textPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }
        .padding(.top, TSpace.s5)
        .padding(.horizontal, TSpace.gutter)
        .padding(.bottom, TSpace.s4)
    }
}

extension ScreenHeader where Leading == EmptyView, Trailing == EmptyView {
    init(eyebrow: String? = nil, title: String, tone: Tone = .light) {
        self.init(eyebrow: eyebrow, title: title, tone: tone, leading: { EmptyView() }, trailing: { EmptyView() })
    }
}

extension ScreenHeader where Leading == EmptyView {
    init(eyebrow: String? = nil, title: String, tone: Tone = .light, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.init(eyebrow: eyebrow, title: title, tone: tone, leading: { EmptyView() }, trailing: trailing)
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(eyebrow: String? = nil, title: String, tone: Tone = .light, @ViewBuilder leading: @escaping () -> Leading) {
        self.init(eyebrow: eyebrow, title: title, tone: tone, leading: leading, trailing: { EmptyView() })
    }
}
