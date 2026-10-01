import SwiftUI

/// The two set-pieces the router cannot express, because each owns its own clock and swaps the
/// phase underneath itself.

// MARK: - The copper card ⇄ navy screen morph

/// Opening, the deck stays on screen while a copper rect grows to fill the phone and turn navy;
/// only then does the phase change, instantly, under the covering rect. Closing is that same
/// clip played backwards: the phase changes back to Home first, under the still-full-screen
/// rect, and the navy rect then shrinks back into the card and turns copper with Home already
/// around it. Either way the cut happens while the rect covers the screen, which is what makes
/// it invisible; this view only ever asks "where is the rect right now".
///
/// **Deliberately not what the reference does.** `source_of_truth.html`'s own close swaps
/// `setPhaseRaw('home')` *before* the rect moves at all, fades the rect's opacity out as it
/// shrinks, blurs it on a different curve than the open (open: a flat 6px; close: 5px→1px —
/// neither end matches the open's), and runs 780ms against the open's 600ms. None of that is a
/// mirror of the open, it is a second, differently-tuned animation that happens to run in the
/// opposite direction. Asked for explicitly as "inverse the animation" — same rect math, same
/// opacity (1, always), same blur curve, same 600ms — so this view does that instead.
struct MorphRect: View {
    let morph: AppModel.Morph
    let onDone: () -> Void

    @State private var on = false

    /// Both ends are plain points. Mixing points with fractions leaves the width uninterpolatable,
    /// which makes the right edge jump instead of growing off-screen.
    private var open: Bool { morph.mode == .open }

    /// 0 = sitting on the card, 1 = filling the screen.
    private var t: Double {
        open ? (on ? 1 : 0) : (on ? 0 : 1)
    }

    var body: some View {
        GeometryReader { geo in
            let full = CGRect(origin: .zero, size: geo.size)
            let card = morph.rect
            let frame = CGRect(
                x: TEase.lerp(card.minX, full.minX, t),
                y: TEase.lerp(card.minY, full.minY, t),
                width: TEase.lerp(card.width, full.width, t),
                height: TEase.lerp(card.height, full.height, t)
            )

            ZStack(alignment: .topLeading) {
                // The veil blurs the edges of the screen while the rect travels, leaving the
                // centre sharp. CSS does this with a masked backdrop-filter; the material plus the
                // same radial mask is the closest SwiftUI equivalent.
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .mask(
                        RadialGradient(
                            colors: [.clear, .black],
                            center: .center,
                            startRadius: geo.size.width * 0.32,
                            endRadius: geo.size.width * 0.82
                        )
                    )
                    .opacity(blurOn ? 1 : 0)
                    .allowsHitTesting(false)
                    .animation(.glide(0.62), value: blurOn)

                // Same formula both ways — `t` already encodes the direction — so the rect is
                // opaque start to finish and the close is a true mirror rather than a shrink
                // wearing a fade on top of it.
                RoundedRectangle(cornerRadius: TEase.lerp(32, 0, t), style: .continuous)
                    .fill(Color(
                        red: TEase.lerp(0.722, 0.137, t),
                        green: TEase.lerp(0.435, 0.224, t),
                        blue: TEase.lerp(0.322, 0.357, t)
                    ))
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
                    .blur(radius: 6 * (1 - t))
                    .animation(.glide(0.56), value: on)
                    .animation(.glide(0.52), value: t)
            }
            .allowsHitTesting(false)
        }
        // On the GeometryReader, not on the ZStack inside it: `geo.size` is the *safe-area* size,
        // so a rect grown to `geo.size` from the screen's top-left stopped short by the top and
        // bottom insets combined — 93pt of light ground left standing at the bottom of a screen
        // that is supposed to be covered, for the ~300ms until the phase swap paints it navy.
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .task {
            // A frame's grace so the rect is painted at its start position before it moves.
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(16))
            withAnimation(.glide(0.56)) { on = true }
            // Same 600 ms both ways — a close that took longer than the open it mirrors would
            // not read as the same clip run backwards.
            try? await Task.sleep(for: .milliseconds(600))
            onDone()
        }
    }

    private var blurOn: Bool { open ? on : !on }
}

// MARK: - The circle reveal

/// A circle grows from the point that was tapped until it covers everything, the phase changes
/// underneath it, and then it fades. Only Home ⇄ Settings uses it.
struct CircleRevealView: View {
    let reveal: AppModel.CircleReveal
    let onCovered: () -> Void
    let onGone: () -> Void

    @State private var scale: CGFloat = 0.02
    @State private var opacity: Double = 1

    private static let size: CGFloat = 2300

    var body: some View {
        Circle()
            .fill(reveal.next == .settings ? TColor.white : TColor.cloud100)
            .frame(width: Self.size, height: Self.size)
            .scaleEffect(scale)
            .position(x: reveal.x, y: reveal.y)
            .opacity(opacity)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .task {
                await Task.yield()
                withAnimation(.glide(0.94)) { scale = 1 }
                try? await Task.sleep(for: .milliseconds(960))
                onCovered()
                try? await Task.sleep(for: .milliseconds(40))
                withAnimation(.glide(0.42)) { opacity = 0 }
                try? await Task.sleep(for: .milliseconds(480))
                onGone()
            }
    }
}

// MARK: - The business-class toast

/// iOS owns the home screen, so a business-class flight cannot bounce anyone back into Tempus the
/// way the reference does. What survives is saying so on return.
struct StayOpenToast: View {
    @State private var shown = false

    var body: some View {
        VStack {
            Spacer()
            HStack(spacing: 9) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(hex: 0xe0a08e))
                Text("Business class \u{00b7} Tempus stays open")
                    .font(TFont.core(.semibold, 14))
                    .foregroundStyle(TColor.cloud100)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Capsule().fill(TColor.navy900))
            .tpShadow(.overlay)
            .padding(.bottom, 96)
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 26)
            .scaleEffect(shown ? 1 : 0.96)
        }
        .allowsHitTesting(false)
        .onAppear { withAnimation(.glide(0.32)) { shown = true } }
    }
}
