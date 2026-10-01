import SwiftUI

// MARK: - TTextField

enum TTextFieldTone {
    case light, onDark
}

/// The reference's `Input` wraps a custom keyboard; this wraps the real one. Same field
/// appearance (52pt tall, 16pt radius, 1.5pt border, copper focus ring) — iOS supplies the
/// keyboard, `@FocusState` supplies `focus`.
struct TTextField: View {
    var label: String? = nil
    var hint: String? = nil
    var error: String? = nil
    var icon: Image? = nil
    var tone: TTextFieldTone = .light
    var placeholder: String = ""
    @Binding var text: String

    @FocusState private var focused: Bool

    private var borderColor: Color {
        if error != nil { return TColor.statusDiverted }
        if focused { return TColor.focusRing }
        return tone == .onDark ? TColor.borderInverse : TColor.borderSubtle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TSpace.s2) {
            if let label {
                Text(label)
                    .tpLabelStyle()
                    .foregroundStyle(tone == .onDark ? TColor.textOnDarkMuted : TColor.textMuted)
            }
            HStack(spacing: TSpace.s3) {
                icon
                TextField(placeholder, text: $text)
                    .focused($focused)
                    .font(TFont.core(.regular, TFont.sizeBody))
                    .foregroundStyle(tone == .onDark ? TColor.textOnDark : TColor.textPrimary)
            }
            .padding(.horizontal, 18)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: TRadius.md, style: .continuous)
                    .fill(tone == .onDark ? TColor.glassOnDark : TColor.surfaceCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: TRadius.md, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1.5)
            )
            .tpFocusRing(TRadius.md, active: focused)
            .animation(.glide(TDur.fast), value: focused)
            .animation(.glide(TDur.fast), value: error != nil)

            if let message = error ?? hint {
                Text(message)
                    .font(TFont.core(.regular, TFont.sizeCaption))
                    .tpType(size: TFont.sizeCaption, lineHeight: 1.4)
                    .foregroundStyle(error != nil ? TColor.statusDiverted : TColor.textMuted)
            }
        }
    }
}

// MARK: - SegmentedControl

enum TSegmentTone {
    case light, onDark
}

/// One option in a `SegmentedControl` — a value identity plus the label shown for it.
struct SegmentedOption<Value: Hashable>: Identifiable {
    let value: Value
    let label: String
    var id: Value { value }
}

/// A pill-track, pill-button segmented picker. Hand-rolled rather than `Picker(.segmented)`
/// because the reference's per-button colour crossfade (no sliding indicator) is the actual
/// design here, not an accident SwiftUI's native control happens to fix.
struct SegmentedControl<Value: Hashable>: View {
    var options: [SegmentedOption<Value>]
    @Binding var value: Value
    var tone: TSegmentTone = .light

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options) { option in
                let active = option.value == value
                Button {
                    value = option.value
                } label: {
                    Text(option.label)
                        .font(TFont.core(.semibold, 14))
                        .foregroundStyle(active ? TColor.textPrimary : (tone == .onDark ? TColor.textOnDarkMuted : TColor.textSecondary))
                        .frame(height: 38)
                        .padding(.horizontal, 18)
                        .background(
                            Capsule().fill(active ? (tone == .onDark ? TColor.cloud100 : TColor.surfaceCard) : Color.clear)
                        )
                        .tpShadow(active ? .card : .none)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(active ? [.isSelected] : [])
            }
        }
        .padding(4)
        .background(Capsule().fill(tone == .onDark ? TColor.glassOnDark : TColor.surfaceSunken))
        .animation(.glide(TDur.fast), value: value)
    }
}

// MARK: - GlassSwitch

/// The settings-list toggle (`app.jsx`'s own `GlassSwitch`, not `design-system.js`'s dead
/// `Switch`) — DS colours, with the press micro-interaction the source calls out by name: the
/// knob elongates from its anchored edge while held, then glides across on release, where the
/// toggle actually commits (mirrored here with a zero-distance `DragGesture`, so a cancelled
/// touch — lifted off after dragging away — still resolves cleanly, same as `Button`).
///
/// ponytail: the reference times background/transform/width as four separately-curved CSS
/// transitions (180-340ms). SwiftUI can't cleanly stack independent per-property durations that
/// change in the same transaction, so this ships two grouped animations (press vs. checked)
/// rather than four. Split further only if the squash-then-slide needs to match frame-for-frame.
struct GlassSwitch: View {
    @Binding var isOn: Bool

    private let w: CGFloat = 56, h: CGFloat = 34, knobRest: CGFloat = 28, knobStretched: CGFloat = 37
    @State private var pressed = false

    var body: some View {
        let kw = pressed ? knobStretched : knobRest
        let offset: CGFloat = 3 + (isOn ? (w - 6 - kw) : 0)

        return Capsule()
            .fill(isOn ? TColor.surfaceAccent : TColor.sky300)
            .frame(width: w, height: h)
            .scaleEffect(pressed ? 0.96 : 1)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(TColor.white)
                    .frame(width: kw, height: knobRest)
                    // The knob's own tiny contact shadow, not a `TShadow` role — a switch this
                    // small needs a shadow this small, well under `.card`'s own minimum.
                    .shadow(color: Color(hex: 0x23395b, opacity: 0.28), radius: 1.5, y: 1)
                    .offset(x: offset)
            }
            .animation(.glide(TDur.base), value: isOn)
            .animation(.glide(TDur.fast), value: pressed)
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in pressed = true }
                    .onEnded { _ in
                        pressed = false
                        isOn.toggle()
                    }
            )
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(isOn ? "On" : "Off")
    }
}

// MARK: - SetRow / SetGroup

/// One settings row: a label on the left, and on the right either an inline `control` (a
/// `GlassSwitch`) or a value string with a trailing chevron that taps through to a picker sheet.
/// `last` drops the row's bottom hairline — `SetGroup` sets it on the row it renders last, not
/// the caller of `SetGroup`.
struct SetRow: View {
    var label: String
    var value: String? = nil
    var last: Bool = false
    var action: (() -> Void)? = nil
    private var control: AnyView? = nil

    init(label: String, value: String? = nil, last: Bool = false, action: (() -> Void)? = nil) {
        self.label = label
        self.value = value
        self.last = last
        self.action = action
    }

    init<C: View>(label: String, last: Bool = false, @ViewBuilder control: () -> C) {
        self.label = label
        self.last = last
        self.control = AnyView(control())
    }

    var body: some View {
        Group {
            if let action {
                Button(action: action) { row }.buttonStyle(.plain)
            } else {
                row
            }
        }
    }

    private var row: some View {
        HStack(spacing: 14) {
            Text(label)
                .font(TFont.core(.medium, 16))
                .foregroundStyle(TColor.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if let control {
                control
            } else if let value {
                HStack(spacing: 6) {
                    Text(value)
                        .font(TFont.core(.regular, 15))
                        .foregroundStyle(TColor.textMuted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(TColor.sky400)
                }
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 56)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            if !last {
                Rectangle().fill(TColor.borderSubtle).frame(height: 1)
            }
        }
    }
}

/// A titled group of `SetRow`s in a shared card — the settings screen's "Flights" / "Screen
/// time" / "Account" sections.
struct SetGroup<Content: View>: View {
    /// Optional: onboarding's screen 3 carries the same card under its own headline, which is
    /// already the section title.
    var title: String? = nil
    /// Shared with onboarding's app-list screen and Redeem's app groups, which is why this is a
    /// parameter rather than a changed default: bumping it app-wide would also bump those two,
    /// which nobody asked for. Settings' own groups pass `.raised` — see `SettingsScreen`.
    var shadow: TShadow = .card
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title)
                    .tpLabelStyle()
                    .foregroundStyle(TColor.textMuted)
                    .padding(.leading, 2)
            }
            VStack(spacing: 0) { content() }
                .background(TColor.surfaceCard)
                .clipShape(RoundedRectangle(cornerRadius: TRadius.lg, style: .continuous))
                .tpShadow(shadow)
        }
        .padding(.top, 26)
    }
}

// MARK: - Picker-shaped rows

// The two rows that answer "which apps", in iOS's activity-picker shape: the selector on the
// leading edge, a 40pt tile, the name. Redeem and onboarding screen 3 both ask that question —
// one of the real selection, one of the six-name stand-in — so the rows live here rather than in
// either screen.

/// One row of the real selection. The icon and the name are iOS's — an `ApplicationToken` is
/// opaque, so `Label(token)` is the only thing that can draw them, and it draws them at the
/// ambient font size.
///
/// ponytail: the icon is sized by `.font`, because the label's `Icon` is type-erased and cannot be
/// made `.resizable()`. It cannot be checked in the simulator either — Family Controls only
/// authorizes on a device — so if the icons land off-metric on hardware, that number is the knob.
struct LiveRow<L: View>: View {
    let last: Bool
    @ViewBuilder var label: () -> L

    var body: some View {
        HStack(spacing: 14) {
            label()
                .labelStyle(.iconOnly)
                .font(.system(size: 34))
                .frame(width: 40, height: 40)
            label()
                .labelStyle(.titleOnly)
                .font(TFont.core(.regular, 17))
                .tracking(-0.02 * 17)
                .foregroundStyle(TColor.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .frame(height: 56)
        .overlay(alignment: .bottom) {
            if !last {
                Rectangle().fill(TColor.borderSubtle).frame(height: 1)
            }
        }
    }
}

/// One app in the unlock list: its selector, a monogram tile, its name, and — where the OS
/// picker shows a count and a chevron — the badge for the app that is open right now.
struct UnlockRow: View {
    let app: BlockableApp
    let on: Bool
    let open: Bool
    let last: Bool
    let tap: () -> Void

    var body: some View {
        Button(action: tap) {
            HStack(spacing: 14) {
                AppRowIndicator(on: on)
                Text(app.id.uppercased())
                    .font(TFont.data(.medium, 13))
                    .foregroundStyle(TColor.cloud100)
                    .frame(width: 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(on ? TColor.surfaceAccent : TColor.navy900))
                Text(app.label)
                    .font(TFont.core(on ? .semibold : .regular, 17))
                    .tracking(-0.02 * 17)
                    .foregroundStyle(on ? TColor.textPrimary : TColor.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if open { Tag("Open", tone: .ontime) }
            }
            .padding(.horizontal, 18)
            .frame(height: 56)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                if !last {
                    Rectangle().fill(TColor.borderSubtle).frame(height: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .animation(.glide(TDur.base), value: on)
        .accessibilityLabel(app.label)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }
}

/// The 24×24 selection dot beside each app in the unlock list.
struct AppRowIndicator: View {
    let on: Bool
    var body: some View {
        ZStack {
            Circle()
                .fill(on ? TColor.surfaceAccent : Color.clear)
                .overlay(Circle().strokeBorder(on ? TColor.surfaceAccent : TColor.borderDefault, lineWidth: 1.5))
            if on {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(TColor.white)
            }
        }
        .frame(width: 24, height: 24)
        .animation(.glide(TDur.base), value: on)
        .accessibilityHidden(true)
    }
}

// MARK: - Droplet motion

/// The teardrop entrance: a bottom-anchored horizontal squash from 0.46 plus a top corner radius
/// easing from 240 — `RootView`'s `.perm` rise plus the squash. Status Club → Redeem itself plays
/// the reference's plain `perm`; this squash is only for the settings sheets.
///
/// **Deliberately not the reference's `tp-rise`.** `ChoiceSheet` in `app.jsx` animates in with a
/// plain `translateY` slide (`tp-rise 460ms`) — the same entrance every other bottom sheet there
/// uses. Asked for by name: "instead of just animating up like the new page or overlay thingy,
/// instead use the tear drop animation to come up." So every settings sheet trades the reference's
/// rise for the squash-and-grow the Status Club → Redeem crossing already established, rather than
/// porting `tp-rise` faithfully — a one-screen divergence, kept because it was asked for outright.
///
/// **Not built as a `.transition()`.** The first version was: a `DropletShape: ViewModifier,
/// Animatable` with `hidden` as `animatableData`, installed as `.transition(.modifier(active:
/// identity:))` on `ChoiceSheet`'s panel, toggled by the caller flipping `sheet` inside
/// `withAnimation`. It built, and the scrim (a plain `.transition(.opacity)`) faded in correctly —
/// but recorded and stepped frame by frame, the panel itself never interpolated: it rendered its
/// fully-settled `identity` state on the very first frame after insertion, regardless of the
/// animation passed in. That is a known SwiftUI weak spot, not a mistake in this file — custom
/// `Animatable`-modifier transitions are unreliable in practice, which is almost certainly why
/// `RootView`'s own `.perm`/`.permout` (the transition this one copies its figures from) was never
/// built that way either: it drives plain `@State` progress (`pIn`/`pOut`) with `withAnimation`,
/// and feeds the result straight into ordinary `.clipShape`/`.scaleEffect`/`.offset` calls — no
/// `.transition()` in sight. `ChoiceSheet` now does the same: `hidden` is real `@State`, animated
/// on mount and before removal, read directly by the modifiers below. Removal only actually
/// happens once the close animation has run — the reference's own `closing` flag plus
/// `setTimeout`, which the `.transition()` version dropped on the assumption SwiftUI's removal
/// transition would do the same job for free. It does not, reliably, so the flag is back.
private enum Droplet {
    static func radius(hidden: CGFloat, rest: CGFloat) -> CGFloat { rest + (240 - rest) * hidden }
    static func scaleX(hidden: CGFloat) -> CGFloat { 1 - 0.54 * hidden }
    /// A screen height, not the panel's own — same reasoning as `RootView`'s `h`/`w`
    /// (`UIScreen.main.bounds`): this only has to push the panel comfortably off-screen while
    /// collapsed, and reading it from a `GeometryReader` that mounts alongside the very thing
    /// being animated is exactly the trap CLAUDE.md already documents for `ShopItemScreen`.
    static var offY: CGFloat { UIScreen.main.bounds.height }
}

// MARK: - HoldConfirmSheet

/// A priced change, confirmed by holding rather than tapping — the same droplet `ChoiceSheet`
/// rises in, carrying one figure and one hold bar. `HoldState` supplies the clock and every buzz
/// (a tick as the hold takes, climbing ticks, a firm one as it fires); letting go early cancels
/// with nothing spent. `onConfirm` runs after the sheet has sunk, so what follows (a payment, an
/// alert) never lands on top of a panel still leaving.
struct HoldConfirmSheet: View {
    var title: String
    var figure: String
    var note: String
    var holdLabel: String
    var cancelLabel: String
    var onConfirm: () -> Void
    var onCancel: () -> Void

    @State private var hidden: CGFloat = 1
    @State private var closing = false
    @State private var hold = HoldState(seconds: 1.2)

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                TColor.overlayScrim
                    .ignoresSafeArea()
                    .opacity(Double(1 - hidden))
                    .onTapGesture { shut(onCancel) }

                VStack(spacing: 0) {
                    Text(title)
                        .tpLabelStyle()
                        .foregroundStyle(TColor.textMuted)
                    Text(figure)
                        .font(TFont.core(.bold, 44))
                        .tpType(size: 44, track: -0.03)
                        .monospacedDigit()
                        .foregroundStyle(TColor.textPrimary)
                        .padding(.top, 14)
                    Text(note)
                        .font(TFont.core(.regular, 15))
                        .tpType(size: 15, lineHeight: 1.5)
                        .foregroundStyle(TColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 10)
                    holdBar.padding(.top, 26)
                    Button { shut(onCancel) } label: {
                        Text(cancelLabel)
                            .font(TFont.core(.semibold, 15))
                            .foregroundStyle(TColor.textSecondary)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                }
                .padding(.horizontal, 24)
                .padding(.top, 26)
                .padding(.bottom, 24 + geo.safeAreaInsets.bottom)
                .frame(maxWidth: .infinity)
                .background(TColor.surfaceCard)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: Droplet.radius(hidden: hidden, rest: TRadius.xl),
                        bottomLeadingRadius: 0, bottomTrailingRadius: 0,
                        topTrailingRadius: Droplet.radius(hidden: hidden, rest: TRadius.xl),
                        style: .continuous
                    )
                )
                .scaleEffect(x: Droplet.scaleX(hidden: hidden), y: 1, anchor: .bottom)
                .offset(y: Droplet.offY * hidden)
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .task { withAnimation(.glide(ChoiceSheetDur.rise)) { hidden = 0 } }
    }

    /// Copper fills left to right under the finger. The label names the action at rest and says
    /// to keep holding once the hold has taken, so a tap that does nothing explains itself.
    private var holdBar: some View {
        GeometryReader { bar in
            ZStack(alignment: .leading) {
                TColor.copper100
                TColor.copper500
                    .frame(width: bar.size.width * hold.p)
                    .animation(nil, value: hold.p)
                Text(hold.holding ? "Keep holding" : holdLabel)
                    .font(TFont.core(.semibold, 16))
                    .foregroundStyle(hold.p > 0.5 ? TColor.white : TColor.copper700)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 56)
        .clipShape(Capsule())
        .contentShape(Capsule())
        .scaleEffect(hold.holding ? TPress.scale : 1)
        .animation(.glide(TDur.fast), value: hold.holding)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in hold.start { shut(onConfirm) } }
                .onEnded { _ in hold.cancel() }
        )
        .onDisappear { hold.cancel() }
        .accessibilityLabel(holdLabel)
        .accessibilityAddTraits(.isButton)
        // A hold cannot be performed with VoiceOver's double-tap, so the action is offered directly.
        .accessibilityAction { shut(onConfirm) }
    }

    private func shut(_ then: @escaping () -> Void) {
        guard !closing else { return }
        closing = true
        hold.cancel()
        withAnimation(.glide(ChoiceSheetDur.sink)) { hidden = 1 }
        Task {
            try? await Task.sleep(for: .seconds(ChoiceSheetDur.sink))
            then()
        }
    }
}

// MARK: - ChoiceSheet

/// One option in a `ChoiceSheet` — a value identity, its label, and an optional detail line.
struct ChoiceOption<Value: Hashable>: Identifiable {
    let value: Value
    let label: String
    var detail: String? = nil
    var id: Value { value }
}

/// The reference's own timing for the sheet's rise and sink — `tp-rise 460ms` in,
/// `tp-kbout 300ms` out. Named constants rather than `TDur.base` (240ms) because a settings
/// sheet that opens and closes on the same duration is not what the reference does, and at
/// 240ms symmetric the droplet's squash-and-grow was so quick against a busy list that it read
/// as no animation at all — a real, reported bug, not a tuning nicety. Any caller driving
/// `ChoiceSheet`'s presence should animate with these, not with a generic token.
enum ChoiceSheetDur {
    static let rise: Double = 0.46
    static let sink: Double = 0.30
}

/// The generic settings picker sheet — single-select (a value binding) or multi-select (a `Set`
/// binding), behind every `SetRow` that opens a list. `hidden` is real `@State` (see `Droplet`'s
/// doc comment for why this is no longer built as a `.transition`) — 1 on mount, animated to 0
/// right away, and back to 1 before `onClose` actually removes the view, matching the reference's
/// own `closing` + `setTimeout`.
struct ChoiceSheet<Value: Hashable>: View {
    enum Selection {
        case single(Binding<Value>)
        case multi(Binding<Set<Value>>)
    }

    var title: String
    var note: String? = nil
    var options: [ChoiceOption<Value>]
    var selection: Selection
    var onClose: () -> Void
    /// Flip this from `false` to `true` to play the same sink a scrim tap or a single-select pick
    /// plays, without either. Every real dismissal already goes through one of those two — this
    /// exists only so a launch seam can show the close half of the droplet, since the Simulator
    /// takes no synthetic taps to trigger one itself.
    var dismiss: Bool = false

    /// 1 = fully collapsed at the bottom, off screen. 0 = settled. Starts collapsed so the very
    /// first rendered frame is already "hidden" and the rise plays from there — no `.transition`
    /// needed for the mount itself.
    @State private var hidden: CGFloat = 1
    /// Guards against a second tap (the scrim, or an option in the single-select case) re-firing
    /// the close animation while it is already running.
    @State private var closing = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                TColor.overlayScrim
                    .ignoresSafeArea()
                    .opacity(Double(1 - hidden))
                    .onTapGesture(perform: shut)

                VStack(spacing: 0) {
                    Text(title)
                        .tpLabelStyle()
                        .foregroundStyle(TColor.textMuted)
                        .frame(maxWidth: .infinity, alignment: .center)
                    if let note {
                        Text(note)
                            .font(TFont.core(.regular, 14))
                            .tpType(size: 14, lineHeight: 1.5)
                            .foregroundStyle(TColor.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 12)
                    }
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 8) {
                            ForEach(options) { option in
                                optionRow(option)
                            }
                        }
                    }
                    .padding(.top, 18)
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                // The stack is laid out inside the safe area, so a flat 30 parked the panel 34pt
                // clear of the screen edge with the page it covers showing in the gap. Pay the
                // inset as padding and let the panel itself reach the edge — the same shape of
                // correction `KeyboardTracker.lift` makes for the bottom-pinned pills.
                .padding(.bottom, 30 + TSafeArea.insets.bottom)
                .frame(maxHeight: geo.size.height * 0.82)
                // The clip carries the corner rounding, so a static background shape here would
                // cap the corners at `TRadius.xl` throughout the run and hide the wider, softer
                // radius the rise opens from. Clip first, then transform (CLAUDE.md's own
                // porting trap #4) — `.scaleEffect`/`.offset` after `.clipShape` move the already-
                // rounded content, rather than clipping the moved content against a stationary
                // rect and drawing the rounded tip over nothing.
                .background(TColor.surfaceCard)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: Droplet.radius(hidden: hidden, rest: TRadius.xl),
                        bottomLeadingRadius: 0, bottomTrailingRadius: 0,
                        topTrailingRadius: Droplet.radius(hidden: hidden, rest: TRadius.xl),
                        style: .continuous
                    )
                )
                .scaleEffect(x: Droplet.scaleX(hidden: hidden), y: 1, anchor: .bottom)
                .offset(y: Droplet.offY * hidden)
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .task {
            withAnimation(.glide(ChoiceSheetDur.rise)) { hidden = 0 }
        }
        .onChange(of: dismiss) { _, requested in
            if requested { shut() }
        }
    }

    /// Plays the sink, then removes the view once it has actually finished — the reference's own
    /// two-step close, not a `.transition` SwiftUI is trusted to run on removal for free.
    private func shut() {
        guard !closing else { return }
        closing = true
        withAnimation(.glide(ChoiceSheetDur.sink)) { hidden = 1 }
        Task {
            try? await Task.sleep(for: .seconds(ChoiceSheetDur.sink))
            onClose()
        }
    }

    private func isSelected(_ v: Value) -> Bool {
        switch selection {
        case .single(let b): return b.wrappedValue == v
        case .multi(let b): return b.wrappedValue.contains(v)
        }
    }

    private func pick(_ v: Value) {
        switch selection {
        case .single(let b):
            b.wrappedValue = v
            shut()
        case .multi(let b):
            if b.wrappedValue.contains(v) { b.wrappedValue.remove(v) } else { b.wrappedValue.insert(v) }
        }
    }

    @ViewBuilder
    private func optionRow(_ option: ChoiceOption<Value>) -> some View {
        let on = isSelected(option.value)
        Button { pick(option.value) } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(option.label)
                        .font(TFont.core(.semibold, 16))
                        .tpType(size: 16, lineHeight: 1.2)
                        .foregroundStyle(on ? TColor.cloud100 : TColor.textPrimary)
                    if let detail = option.detail {
                        Text(detail)
                            .font(TFont.core(.regular, 13))
                            .tpType(size: 13, lineHeight: 1.4)
                            .foregroundStyle(on ? TColor.textOnDarkMuted : TColor.textMuted)
                    }
                }
                Spacer(minLength: 0)
                if on {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(TColor.cloud100)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(minHeight: 56)
            .background(
                RoundedRectangle(cornerRadius: TRadius.md, style: .continuous)
                    .fill(on ? TColor.surfaceInverse : TColor.surfaceCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: TRadius.md, style: .continuous)
                    .strokeBorder(on ? TColor.surfaceInverse : TColor.borderSubtle, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .animation(.glide(TDur.base), value: on)
    }
}
