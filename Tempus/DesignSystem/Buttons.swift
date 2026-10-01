import SwiftUI

/// `Button`'s five paint treatments. Named on the type, not nested, so `TButtonStyle` can
/// reference them without dragging `TButton`'s content generic along.
enum TButtonVariant {
    case primary, secondary, outline, ghost, onDark
}

/// `Button`'s three heights. `sm`/`md`/`lg`, same names as the reference.
enum TButtonSize {
    case sm, md, lg
}

/// The pill button — every primed action in the app runs through this. Press state comes from
/// `ButtonStyle`'s own `isPressed`, which (unlike the reference's manual `onPointerDown`/`Up`/
/// `Leave` tracking) always resolves even when the system cancels the gesture mid-press — the
/// reference's own comment flags the missing `onPointerCancel` as a gap; the native control
/// doesn't have that gap to begin with.
struct TButton<Content: View>: View {
    var variant: TButtonVariant = .primary
    var size: TButtonSize = .md
    var fullWidth: Bool = false
    var disabled: Bool = false
    /// Leading icon, rendered before `content`.
    var icon: Image? = nil
    /// Trailing icon, rendered after `content`.
    var iconAfter: Image? = nil
    var action: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        Button(action: action) {
            HStack(spacing: TSpace.s2) {
                icon
                content()
                iconAfter
            }
            .frame(maxWidth: fullWidth ? .infinity : nil)
        }
        .buttonStyle(TButtonStyle(variant: variant, size: size, disabled: disabled))
        .disabled(disabled)
    }
}

/// `TButton("Board now") { onBoard() }` — the common case, a plain text label.
extension TButton where Content == Text {
    init(
        _ title: String,
        variant: TButtonVariant = .primary,
        size: TButtonSize = .md,
        fullWidth: Bool = false,
        disabled: Bool = false,
        icon: Image? = nil,
        iconAfter: Image? = nil,
        action: @escaping () -> Void
    ) {
        self.init(
            variant: variant, size: size, fullWidth: fullWidth, disabled: disabled,
            icon: icon, iconAfter: iconAfter, action: action
        ) { Text(title) }
    }
}

private struct TButtonPaint {
    var background: Color
    var foreground: Color
    var shadow: TShadow
    var border: Color
    var borderWidth: CGFloat
}

private extension TButtonVariant {
    var paint: TButtonPaint {
        switch self {
        case .primary:
            return TButtonPaint(background: TColor.surfaceAccent, foreground: TColor.textOnAccent,
                                 shadow: .accent, border: .clear, borderWidth: 1)
        case .secondary:
            return TButtonPaint(background: TColor.surfaceInverse, foreground: TColor.textOnDark,
                                 shadow: .card, border: .clear, borderWidth: 1)
        case .outline:
            return TButtonPaint(background: .clear, foreground: TColor.textPrimary,
                                 shadow: .none, border: TColor.borderStrong, borderWidth: 1.5)
        case .ghost:
            return TButtonPaint(background: .clear, foreground: TColor.textSecondary,
                                 shadow: .none, border: .clear, borderWidth: 1)
        case .onDark:
            return TButtonPaint(background: TColor.glassOnDark, foreground: TColor.textOnDark,
                                 shadow: .none, border: TColor.borderInverse, borderWidth: 1)
        }
    }
}

private extension TButtonSize {
    var height: CGFloat {
        switch self { case .sm: return 36; case .md: return 48; case .lg: return 56 }
    }
    var horizontalPadding: CGFloat {
        switch self { case .sm: return 16; case .md: return 24; case .lg: return 32 }
    }
    var fontSize: CGFloat {
        switch self { case .sm: return 14; case .md: return 16; case .lg: return 17 }
    }
}

private struct TButtonStyle: ButtonStyle {
    var variant: TButtonVariant
    var size: TButtonSize
    var disabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        let p = variant.paint
        let s = size
        configuration.label
            .font(TFont.core(.semibold, s.fontSize))
            .tracking(-0.01 * s.fontSize)
            .foregroundStyle(p.foreground)
            .frame(height: s.height)
            .padding(.horizontal, s.horizontalPadding)
            .background(Capsule().fill(p.background))
            .overlay(Capsule().stroke(p.border, lineWidth: p.borderWidth))
            .tpShadow(p.shadow)
            // Flattened before anything fades it. `.opacity` pushes down to every leaf, so an
            // ungrouped fade dims the pill and its shadow separately and the shadow comes up
            // through the middle of its own button — the accent shadow on a primary button being
            // the same copper the pill is. Callers fade this too (the paywall's buy button when
            // there is nothing to buy), so the group sits below both. See CLAUDE.md.
            .compositingGroup()
            .scaleEffect(configuration.isPressed && !disabled ? TPress.scale : 1)
            .opacity(disabled ? 0.4 : 1)
            .animation(.glide(TDur.fast), value: configuration.isPressed)
            .animation(.linear(duration: TDur.fast), value: disabled)
    }
}

// MARK: - IconButton

/// `IconButton`'s five paint treatments.
enum TIconButtonTone {
    case light, sunken, onDark, accent, bare
}

/// `IconButton`'s three diameters: `sm`=36, `md`=44, `lg`=52.
enum TIconButtonSize {
    case sm, md, lg
}

/// A round, icon-only button — back buttons, close buttons, the chrome that isn't a labelled
/// action. `content` is the icon itself (usually an `Image(systemName:)`), matching the
/// reference's `children`-is-the-icon shape rather than a named `systemImage` parameter, so a
/// caller can also drop in a custom glyph.
struct IconButton<Content: View>: View {
    var tone: TIconButtonTone = .light
    var size: TIconButtonSize = .md
    /// Becomes the accessibility label — every icon-only control needs one, there being no
    /// visible text to read.
    var label: String
    var disabled: Bool = false
    var action: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        Button(action: action) { content() }
            .buttonStyle(TIconButtonStyle(tone: tone, size: size, disabled: disabled))
            .disabled(disabled)
            .accessibilityLabel(label)
    }
}

private struct TIconButtonPaint {
    var background: Color
    var foreground: Color
    var shadow: TShadow
}

private extension TIconButtonTone {
    var paint: TIconButtonPaint {
        switch self {
        case .light: return TIconButtonPaint(background: TColor.surfaceCard, foreground: TColor.textPrimary, shadow: .card)
        case .sunken: return TIconButtonPaint(background: TColor.surfaceSunken, foreground: TColor.textPrimary, shadow: .none)
        case .onDark: return TIconButtonPaint(background: TColor.glassOnDark, foreground: TColor.textOnDark, shadow: .none)
        case .accent: return TIconButtonPaint(background: TColor.surfaceAccent, foreground: TColor.textOnAccent, shadow: .accent)
        case .bare: return TIconButtonPaint(background: .clear, foreground: TColor.textSecondary, shadow: .none)
        }
    }
}

private extension TIconButtonSize {
    var diameter: CGFloat {
        switch self { case .sm: return 36; case .md: return 44; case .lg: return 52 }
    }
}

private struct TIconButtonStyle: ButtonStyle {
    var tone: TIconButtonTone
    var size: TIconButtonSize
    var disabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        let p = tone.paint
        let d = size.diameter
        configuration.label
            .foregroundStyle(p.foreground)
            .frame(width: d, height: d)
            .background(Circle().fill(p.background))
            .tpShadow(p.shadow)
            // Flattened before anything fades it. `.opacity` pushes down to every leaf, so an
            // ungrouped fade dims the pill and its shadow separately and the shadow comes up
            // through the middle of its own button — the accent shadow on a primary button being
            // the same copper the pill is. Callers fade this too (the paywall's buy button when
            // there is nothing to buy), so the group sits below both. See CLAUDE.md.
            .compositingGroup()
            .scaleEffect(configuration.isPressed && !disabled ? TPress.scale : 1)
            .opacity(disabled ? 0.4 : 1) // no opacity transition in the source, unlike Button
            .animation(.glide(TDur.fast), value: configuration.isPressed)
    }
}

// MARK: - ButtonSlot

/// A slot in a button row that either hugs its own content's width or stretches to take what's
/// left over — the shape preflight's row needs (a fixed "Business class" toggle beside a
/// `fullWidth` "Board now"). Not a reference component; lifted out so no screen hand-rolls the
/// `flex: 0 0 auto` vs `flex: 1` split itself.
struct ButtonSlot<Content: View>: View {
    var flexible: Bool = true
    @ViewBuilder var content: () -> Content

    var body: some View {
        content().frame(maxWidth: flexible ? .infinity : nil)
    }
}
