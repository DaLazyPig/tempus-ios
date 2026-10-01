import QuartzCore
import SwiftUI

/// Drives `step` from 0 to 1 against a real elapsed clock for `seconds`, roughly 60 times a
/// second, and always finishes on exactly 1. Cancelling the surrounding task stops it where it
/// stands — which is what releasing a hold early has to do — so callers check `Task.isCancelled`
/// before treating the ramp as finished.
///
/// Every hand-driven number in the app runs off this rather than off `withAnimation`, because the
/// reference drives them from `requestAnimationFrame` and reads the wall clock each frame: a
/// fixed-step animation drifts, and a hold that drifts lies about how long it has left.
func tpRamp(_ seconds: Double, step: (Double) -> Void) async {
    let t0 = CACurrentMediaTime()
    while true {
        let k = min(1, (CACurrentMediaTime() - t0) / seconds)
        step(k)
        if k >= 1 { return }
        do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
    }
}

// MARK: - Entrance risers

/// The staggered entrance every screen plays on arrival: opacity 0→1 and 18pt of travel, over
/// 460 ms on the glide curve, delayed `i * 70 ms`. Wrap each child of a screen in one, numbered
/// down the page.
///
/// The `revealed` flag lives inside the riser rather than in the screen, because the CSS this
/// ports runs on mount with `animation-fill-mode: both` — there is nothing for a screen to decide.
struct Rise<Content: View>: View {
    var i: Int = 0
    @ViewBuilder var content: () -> Content

    var body: some View {
        Riser(duration: 0.46, delay: Double(i) * 0.07, content: content)
    }
}

/// Onboarding's slower riser — 680 ms, delayed `120 + i * 130 ms`. Longer settle, wider stagger.
/// Despite the name the reference also uses it for the Home deck's header and footer.
struct ORise<Content: View>: View {
    var i: Int = 0
    @ViewBuilder var content: () -> Content

    var body: some View {
        Riser(duration: 0.68, delay: 0.12 + Double(i) * 0.13, content: content)
    }
}

/// `tp-enter`: `opacity: 0 → 1`, `translateY(18px) → 0`, fill mode both.
private struct Riser<Content: View>: View {
    let duration: Double
    let delay: Double
    @ViewBuilder var content: () -> Content
    @State private var revealed = false
    @Environment(\.tpSuppressRise) private var suppressed

    var body: some View {
        // `suppressed` is read as well as `revealed` so the screen is complete on its very first
        // frame: `@State` cannot be seeded from the environment, and a one-frame flash of an empty
        // page is the whole bug this exists to remove.
        let shown = revealed || suppressed
        content()
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 18)
            .onAppear {
                // Latch it, so a later flip of the flag cannot un-reveal a settled screen.
                guard !suppressed else { revealed = true; return }
                withAnimation(.glide(duration).delay(delay)) { revealed = true }
            }
    }
}

/// Mounts every `Rise`/`ORise` beneath it already revealed, with no entrance to play.
///
/// For screens that are *uncovered* rather than arrived at — the one case today is Status Club as
/// the card studio fades off it. A staggered entrance is how a screen introduces itself on arrival;
/// replaying it under a departing overlay just means the overlay finishes first and hands over a
/// blank page. See the note at the call site in `RootView`.
private struct TPSuppressRiseKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var tpSuppressRise: Bool {
        get { self[TPSuppressRiseKey.self] }
        set { self[TPSuppressRiseKey.self] = newValue }
    }
}

// MARK: - Number animation

/// A balance that rolls from its previous value to its new one over 850 ms on a cubic-out curve,
/// grouped `en-US` ("1,240"). It shows `value` outright on first appearance and does nothing when
/// the value has not moved, so arriving on a screen is not an excuse to re-count.
///
/// Not interchangeable with `CountUp`, which always starts from zero.
struct MilesTicker: View {
    var value: Int
    @State private var shown: Int

    init(value: Int) {
        self.value = value
        _shown = State(initialValue: value)
    }

    var body: some View {
        Text(shown.formatted(.number.locale(Locale(identifier: "en_US"))))
            .task(id: value) {
                let from = shown, to = value
                guard from != to else { return }
                await tpRamp(0.85) { k in
                    shown = Int((Double(from) + Double(to - from) * TEase.out(k)).rounded())
                }
            }
    }
}

/// A number that counts up **from zero** to `to` on every change of the target, over `seconds` on
/// a cubic-out curve. Ungrouped, because the reference prints it raw; `format` is there for the
/// one caller that wants a sign in front of it.
///
/// The landing screen's "status earned" readout uses this; the home balance uses `MilesTicker`.
struct CountUp: View {
    var to: Int
    var seconds: Double = 0.9
    var format: (Int) -> String = { String($0) }
    @State private var v = 0

    var body: some View {
        Text(format(v))
            .task(id: to) {
                await tpRamp(seconds) { k in
                    v = Int((Double(to) * TEase.out(k)).rounded())
                }
            }
    }
}
