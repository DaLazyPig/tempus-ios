import SwiftUI

// MARK: - The two OS bars

/// The reference draws its own status bar — clock, signal, wifi, battery — because it is a phone
/// mock inside a browser. On a device iOS draws all four for real, so this draws **nothing**: a
/// second clock painted over the system one would only ever disagree with it.
///
/// What is worth porting is the one decision the reference's bar carries: whether the ground under
/// it is dark. That is passed to the system bar as a colour-scheme preference — the app's own
/// colours are all explicit tokens, so nothing else moves when it flips. The reference's
/// `color 320ms glide` cross-fade is not ours to set; iOS animates the change itself.
///
/// Put exactly one of these in the app root, driven by `AppModel.barDark`.
struct TPStatusBar: View {
    var dark: Bool

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .preferredColorScheme(dark ? .dark : .light)
            .accessibilityHidden(true)
    }
}

/// iOS draws the home indicator, and manages its own contrast against whatever is beneath it, so
/// this draws no pill either — and the reference's swipe-up gesture is the real one the OS already
/// owns. What does survive is layout: the reference reserves a 34pt band at the bottom that content
/// never enters, which on most screens is simply the bottom safe area. Use this only on a screen
/// that deliberately runs its ground under the safe area, where the band has to be held open by
/// hand.
struct TPHomeBar: View {
    static let height: CGFloat = 34

    var body: some View {
        Color.clear
            .frame(height: Self.height)
            .accessibilityHidden(true)
    }
}

// MARK: - The floating nav

/// The two docked tabs — Fly and Club — plus the copper add button, in one dark capsule.
/// A tap on the tab you are already on is ignored, so the caller can transition unconditionally.
struct FloatingNav: View {
    var value: Phase
    var onChange: (Phase) -> Void
    var onAdd: () -> Void

    private static let tabs: [(v: Phase, label: String, icon: String)] = [
        (.home, "Fly", "airplane"),
        (.status, "Club", "creditcard")
    ]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Self.tabs, id: \.v) { tab in
                let on = tab.v == value
                Button {
                    guard !on else { return }
                    onChange(tab.v)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: tab.icon).font(.system(size: 19, weight: .regular))
                        Text(tab.label).font(TFont.core(.semibold, 15))
                    }
                    .padding(.horizontal, 22)
                    .frame(height: 52)
                    .foregroundStyle(on ? TColor.cloud100 : TColor.textOnDarkMuted)
                    .background(on ? TColor.surfaceInverseRaised : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
            }

            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(TColor.white)
                    .frame(width: 52, height: 52)
                    .background(TColor.surfaceAccent, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add a subject")
        }
        .padding(6)
        .background(TColor.surfaceInverse, in: Capsule())
        .tpShadow(.overlay)
        .animation(.glide(TDur.fast), value: value)
        .frame(maxWidth: .infinity)
        .padding(.bottom, 24)
    }
}

/// Keeps the nav mounted through its own exit slide: in over 460 ms on the glide curve, out over
/// 280 ms on the exit curve, unmounting 290 ms later — the 10 ms margin is what stops the last
/// frame being clipped.
///
/// The slide is keyed on its direction, so an exit interrupted by a re-entry restarts from the
/// bottom rather than inheriting half a slide.
///
/// The 120pt box is measured from the screen edge, as the reference measures it — `bottom:24` in
/// `FloatingNav` is a distance from the physical edge, not from the safe area — so this ignores
/// the bottom safe area itself rather than depending on its container doing so.
struct NavSlot<Content: View>: View {
    var show: Bool
    private let content: Content
    @State private var render: Bool
    @State private var out = false

    /// The nav's travel, and the height of the box it slides inside.
    private static var height: CGFloat { 120 }

    init(show: Bool, @ViewBuilder content: () -> Content) {
        self.show = show
        self.content = content()
        _render = State(initialValue: show)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if render {
                NavSlide(leaving: out, travel: Self.height) { content }
                    .id(out)
            }
        }
        .frame(height: Self.height)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .ignoresSafeArea(edges: .bottom)
        .zIndex(12)
        .task(id: show) {
            if show {
                render = true
                out = false
            } else if render {
                out = true
                try? await Task.sleep(for: .milliseconds(290))
                guard !Task.isCancelled else { return }
                render = false
                out = false
            }
        }
    }
}

/// `tp-navin` / `tp-navout`. Remounted whenever the direction changes, which is what makes the
/// restart clean — it always begins at the end it is travelling from.
private struct NavSlide<Content: View>: View {
    let leaving: Bool
    let travel: CGFloat
    private let content: Content
    @State private var y: CGFloat

    init(leaving: Bool, travel: CGFloat, @ViewBuilder content: () -> Content) {
        self.leaving = leaving
        self.travel = travel
        self.content = content()
        _y = State(initialValue: leaving ? 0 : travel)
    }

    var body: some View {
        content
            .offset(y: y)
            .onAppear {
                withAnimation(leaving ? .exit(0.28) : .glide(0.46)) {
                    y = leaving ? travel : 0
                }
            }
    }
}

// MARK: - The context pill

/// The pill at the top of a flight screen, naming the subject. Its trailing control is either a
/// plain close button or — once `holdLabel` is given — a `HoldCircle`, because leaving a flight in
/// progress must be held rather than tapped. While it is held the pill says what is being done, and
/// on a hold of 3 s or more it counts the seconds down, which is why the state lives out here.
struct FloatingPill: View {
    var label: String
    var dark: Bool
    var fading: Bool
    var holdLabel: String?
    var holdSeconds: Double
    var onClose: () -> Void
    @State private var hold: HoldState

    init(
        label: String,
        dark: Bool = true,
        fading: Bool = false,
        holdLabel: String? = nil,
        holdSeconds: Double = HoldState.base,
        onClose: @escaping () -> Void
    ) {
        self.label = label
        self.dark = dark
        self.fading = fading
        self.holdLabel = holdLabel
        self.holdSeconds = holdSeconds
        self.onClose = onClose
        _hold = State(initialValue: HoldState(seconds: holdSeconds))
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(text)
                .font(TFont.core(.semibold, 16))
                .foregroundStyle(dark ? TColor.cloud100 : TColor.navy700)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let holdLabel {
                HoldCircle(hold: hold, label: holdLabel, onDone: onClose)
            } else {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(TColor.navy700)
                        .frame(width: 44, height: 44)
                        .background(TColor.white, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
        }
        .padding(.leading, 22)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .background(dark ? TColor.glassOnDark : TColor.surfaceSunken, in: Capsule())
        .padding(.top, 16)
        .padding(.horizontal, 20)
        .opacity(fading ? 0 : 1)
        .animation(.exit(0.26), value: fading)
    }

    private var text: String {
        guard hold.holding, let holdLabel else { return label }
        guard holdSeconds >= 3 else { return holdLabel }
        return "\(holdLabel) \u{00b7} \(Int(ceil(holdSeconds * (1 - hold.p))))s"
    }
}
