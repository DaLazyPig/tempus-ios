import SwiftUI

/// The reference's SVG geometry, verbatim: a viewBox 390×122 showing only the crown of a circle
/// of radius 540 centred 600pt below it — the apex sits at y=60. Shared by `DialView` (layout,
/// gesture) and `DialStrip` (paint), so both scale off the same numbers.
fileprivate enum DialGeometry {
    static let width: CGFloat = 390
    static let height: CGFloat = 122
    static let cx: CGFloat = 195
    static let cy: CGFloat = 600
    static let radius: CGFloat = 540
    static let top: CGFloat = cy - radius // 60

    /// The original window: symmetric about the marker, out to the box's own edges and a little
    /// past. Every dial in the app draws this except onboarding's cap.
    static let fullCull: Double = 34

    /// Where a growing arc starts: one quarter, anchored left.
    ///
    /// The box is 390 wide on a radius of 540, so its own edges sit at ±21.2° — and by then the
    /// arc has dropped R(1 − cos a) = 36pt and each tick is tilted 21°, which reads as the ends of
    /// a wheel curling down into the frame rather than as a dial. Culling at 16° keeps the arc
    /// shallow (a 21pt drop, the last tick landing at x=46). See `DialView.Style.growingArc` for
    /// what happens to this window as the value rises.
    static let arcCull: Double = 16

    /// Ticks stop being painted a little before the hard cull, so the strip ends in a fade rather
    /// than a cut. The reference's own pair is 32 against 34; the ratio is what generalises.
    static let fadeRatio: Double = 32.0 / 34.0
    static var fullFade: Double { fullCull * fadeRatio }
    /// The gap between the two — how much arc the ticks have to die off in at the cull.
    static var tailFade: Double { fullCull - fullFade }

    /// What a tick past the end of the range is painted at, against a live one.
    ///
    /// The run-out exists so a dial at the bottom of its travel still reads as an instrument
    /// rather than as half a graphic — but painted at the *same* weight as the ticks either side
    /// of it, it also says the wheel keeps going, which is the one thing it must not say. Ghosted
    /// to a fifth (down from a third — a third still read as "more ticks", not "no more ticks",
    /// against the app's low-contrast tint), the strip still fills the frame and the end of
    /// travel is legible without a word of copy.
    /// Zero: the paint past either end is laid out (so the arc stays symmetric and the end-stop
    /// tick keeps its place) but not drawn. It was ghosted to a fifth for a while, and a dial
    /// scrolled hard against its end still showed a grey tail — asked for as blank.
    static let runOutDim: Double = 0

    /// The end-stop: the tick at `min` and the tick at `max`.
    ///
    /// A first pass drew this at the tint colour, one weight step above a major (0.9 → 1) and
    /// eight points taller (30 → 38). Screenshotted against the app's actual tint — `steel600` on
    /// `.light`, `cloud100` on `.dark` — the two were indistinguishable at a glance: a 10% opacity
    /// difference on an already-thin line is not a signal, it is noise. The fix is colour, not
    /// weight: the end-stop is now painted in the *marker's* copper, not the strip's tint, so it
    /// reads as a second, fixed landmark rather than one more tick in the ramp — and at `min` or
    /// `max` it sits directly under the copper marker itself, so the two visually fuse into one
    /// solid block. That fusion *is* the "you have arrived" signal a screenshot cannot fake with
    /// weight alone. Height and width still step up from a major (30/2.5 → 46/4.2), close to the
    /// marker's own 54×4, so the shape reads as a wall even before the colour is read.
    static let endStopHeight: CGFloat = 46
    static let endStopWidth: CGFloat = 4.2
}

/// The curved "altimeter" tick dial behind every numeric picker in the app — preflight study
/// minutes, the in-flight countdown readout, and the redeem cost. Drag sideways to change the
/// value; ticks slide past a fixed copper marker that never itself moves.
struct DialView: View {
    enum Tone { case dark, light }

    /// How much of the wheel is drawn, and which way a drag turns it.
    ///
    /// **`standard` is every dial that sets a real quantity** — preflight's study minutes, the
    /// in-flight countdown, Redeem's cost, a gift's amount. It is the reference's own geometry and
    /// its own drag direction, and it is not up for redesign: those dials work.
    ///
    /// **`growingArc` is onboarding's daily cap, and nothing else.** Its window is a function of
    /// the value: at Off only the quarter of the arc left of the marker is drawn, and as the cap
    /// rises the window opens out on both sides until it is the full symmetric spread `standard`
    /// always shows. A dial that is off is a quarter of an instrument; a dial at 300 is a whole
    /// one. A drag also carries the strip along under the finger rather than against it. Scoped to
    /// a parameter because the change was asked for on the onboarding screen and applying it to
    /// `DialView` outright redrew four dials nobody wanted touched.
    enum Style { case standard, growingArc }

    @Binding var value: Double
    var min: Double
    var max: Double
    var step: Double
    /// Degrees of arc between adjacent ticks. Preflight and redeem use `1.25`; the in-flight
    /// countdown (denser, since it reads continuously) uses `0.7`.
    var arcStep: Double = 1.75
    var tone: Tone = .dark
    /// `false` for a read-only readout (the in-flight countdown) — no gesture, no VoiceOver
    /// adjustable action, the value only ever changes from outside.
    var interactive: Bool = true
    var style: Style = .standard

    /// Set once at the start of a drag, cleared at the end — mirrors the reference's
    /// `drag.current = {x: clientX, v: value}`, captured fresh each gesture rather than reused
    /// across one, which is what makes the delta-from-start maths below correct.
    @State private var dragStartValue: Double?

    private func clampToStep(_ v: Double) -> Double {
        guard step > 0 else { return v }
        let snapped = (v / step).rounded() * step
        return Swift.min(max, Swift.max(min, snapped))
    }

    var body: some View {
        GeometryReader { geo in
            let scale = geo.size.width / DialGeometry.width
            ZStack {
                DialStrip(value: value, min: min, max: max, step: step, arcStep: arcStep,
                          tone: tone, style: style)
                // The fixed centre marker: it never moves, the ticks slide past it.
                RoundedRectangle(cornerRadius: 2 * scale, style: .continuous)
                    .fill(TColor.copper500)
                    .frame(width: 4 * scale, height: 54 * scale)
                    .position(x: DialGeometry.cx * scale, y: (DialGeometry.top + 12) * scale)
            }
            .contentShape(Rectangle())
            .gesture(interactive ? dragGesture(trackWidth: geo.size.width) : nil)
            .accessibilityElement()
            .accessibilityValue(Text(String(format: "%g", value)))
            .accessibilityAdjustableAction { direction in
                guard interactive else { return }
                switch direction {
                case .increment: value = clampToStep(value + step)
                case .decrement: value = clampToStep(value - step)
                @unknown default: break
                }
            }
        }
        .aspectRatio(DialGeometry.width / DialGeometry.height, contentMode: .fit)
    }

    /// How many degrees of arc are drawn each side of the marker.
    ///
    /// `standard` is the reference's own symmetric window and never moves. `growingArc` opens with
    /// the value: at the bottom of the scale only the left arm is drawn, out to `arcCull`, and the
    /// right arm is not drawn at all — so the ticks run in from the left, meet the marker and stop,
    /// which is a quarter of a dial. As the value rises the left arm widens to the full window and
    /// the right one opens from nothing to meet it, so the arc grows into the whole spread.
    ///
    /// Progress is measured against `max` rather than `min...max` because the cap dial's scale runs
    /// below its own zero: Off is the bottom of what can be *chosen*, and the ticks under it are a
    /// run-out, not a range. Clamped, so a value in the run-out still reads as the starting quarter.
    ///
    /// `nonisolated` and `static` so `dialSelfCheck` can drive it without a `Canvas`.
    nonisolated static func window(style: DialView.Style, value: Double, max: Double) -> (Double, Double) {
        switch style {
        case .standard:
            return (DialGeometry.fullCull, DialGeometry.fullCull)
        case .growingArc:
            let p = Swift.max(0, Swift.min(1, max > 0 ? value / max : 0))
            return (TEase.lerp(DialGeometry.arcCull, DialGeometry.fullCull, p),
                    TEase.lerp(0, DialGeometry.fullCull, p))
        }
    }

    /// How strongly a tick `a` degrees from the marker is painted, before the major/minor weight.
    ///
    /// The ramp is measured against the *full* window, never the current one. Scaling it to a
    /// narrow window — the cap dial at Off, 16° wide — compressed the same fade into a quarter of
    /// the arc, so the one arm that dial is meant to draw was a ghost by the time it reached the
    /// frame. The tail is what ends the strip, so the cull is still a fade rather than a cut
    /// whatever width the window is.
    ///
    /// `nonisolated` and `static` so `dialSelfCheck` can drive it without a `Canvas`.
    nonisolated static func fade(_ a: Double, cull: Double) -> Double {
        Swift.max(0, Swift.min(1 - abs(a) / DialGeometry.fullFade,
                               (cull - abs(a)) / DialGeometry.tailFade))
    }

    /// How heavily tick `i` of `0...count` is painted, and how big it is drawn.
    ///
    /// Three cases, and the point of all three is that a dial should say where its travel ends
    /// without a word of copy:
    ///  - **the end-stop** (`i == 0` or `i == count`) — the last tick you can actually reach, drawn
    ///    heavier and taller than a major so the limit is a mark rather than an inference;
    ///  - **a live tick** — the reference's own 0.9 major / 0.45 minor;
    ///  - **the run-out** — the paint past either end, ghosted to `runOutDim`. The run-out exists so
    ///    a dial at the bottom of its travel still reads as an instrument instead of one arm of an
    ///    arc, but at full weight it also says the wheel keeps going, which is the one thing it
    ///    must not say.
    ///
    /// `nonisolated` and `static` so `dialSelfCheck` can drive it without a `Canvas`.
    nonisolated static func tick(_ i: Int, count: Int) -> (weight: Double, height: CGFloat, width: CGFloat, isEndStop: Bool) {
        let live = i >= 0 && i <= count
        if i == 0 || i == count {
            return (1, DialGeometry.endStopHeight, DialGeometry.endStopWidth, true)
        }
        let major = i % 5 == 0
        return ((major ? 0.9 : 0.45) * (live ? 1 : DialGeometry.runOutDim), major ? 30 : 17, 2.5, false)
    }

    /// `px = R · arcStep · π/180` in the reference is screen pixels per tick, valid only because
    /// its phone frame happens to render at exactly the SVG's own 390pt viewBox width. Scaling
    /// by the track's actual measured width generalises that to any layout width this draws at.
    private func dragGesture(trackWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                if dragStartValue == nil { dragStartValue = value }
                let scale = trackWidth / DialGeometry.width
                let pxPerTick = DialGeometry.radius * scale * arcStep * .pi / 180
                guard pxPerTick > 0, let start = dragStartValue else { return }
                // The reference's `move`: `next = clamp(d.v + (e.clientX - d.x) / px * step)` —
                // a drag to the right raises the value, and ticks travel right as the value rises
                // (see `DialStrip`), so the strip follows the finger. This used to subtract for
                // every dial but the cap's, on the strength of a comment claiming that was the
                // reference's direction; it was not, and every dial ran against the finger.
                let delta = (g.translation.width / pxPerTick) * step
                let next = clampToStep(start + delta)
                if next != value {
                    value = next
                    // Once per snapped step, not once per touch-move frame — `clampToStep`
                    // already dedupes that for us, so this only fires on an actual tick change.
                    Haptics.dialTick()
                }
            }
            .onEnded { _ in dragStartValue = nil }
    }
}

/// Pure paint: the tick strip itself, no gesture. Split out of `DialView` so layout/interaction
/// and drawing are two separate concerns — `DialView` owns the former, this owns the latter.
private struct DialStrip: View {
    var value: Double
    var min: Double
    var max: Double
    var step: Double
    var arcStep: Double
    var tone: DialView.Tone
    var style: DialView.Style

    var body: some View {
        Canvas { context, size in
            guard step > 0, max > min else { return }
            let scale = size.width / DialGeometry.width
            let idx = (value - min) / step
            let count = Int(((max - min) / step).rounded())
            guard count >= 0 else { return }
            // The reference hardcodes these tints as literal hex rather than the token that
            // resolves to the same value — using the token here is the fix its own spec flags.
            let tint = tone == .dark ? TColor.cloud100 : TColor.steel600

            let (leftCull, rightCull) = DialView.window(style: style, value: value, max: max)

            // **The strip runs on past both ends of the range.** A dial that stops dead at `min`
            // draws one arm of the arc and reads as a broken graphic rather than as an instrument
            // at the bottom of its travel — which is what Redeem (opening five steps above its
            // own minimum) and the cap dial at Off both looked like. These run-out ticks are paint
            // and nothing else: `DialView.clampToStep` still clamps the value to `min...max`, so
            // the marker cannot enter them. The reference has no equivalent; see CLAUDE.md.
            let pad = Int((Swift.max(leftCull, rightCull) / arcStep).rounded(.up))

            for i in -pad...(count + pad) {
                let a = (idx - Double(i)) * arcStep // value up ⇒ ticks travel right
                // `a < 0` is left of the marker (higher values), `a > 0` right of it. A growing
                // arc opens the two sides at different rates, so each has its own cull.
                let cull = a > 0 ? rightCull : leftCull
                guard cull > 0, abs(a) <= cull else { continue }
                let fade = DialView.fade(a, cull: cull)
                let (weight, h, w, isEndStop) = DialView.tick(i, count: count)
                let opacity = fade * weight
                guard opacity > 0.002 else { continue }

                let rect = CGRect(x: DialGeometry.cx - w / 2, y: DialGeometry.top, width: w, height: h)

                // Rotate the tick about the dial's true (off-screen) centre, exactly like the
                // source's `transform: rotate(a, CX, CY)`, then scale into canvas points.
                let toOrigin = CGAffineTransform(translationX: -DialGeometry.cx, y: -DialGeometry.cy)
                let rotate = CGAffineTransform(rotationAngle: a * .pi / 180)
                let backOut = CGAffineTransform(translationX: DialGeometry.cx, y: DialGeometry.cy)
                let toCanvas = CGAffineTransform(scaleX: scale, y: scale)
                let transform = toOrigin.concatenating(rotate).concatenating(backOut).concatenating(toCanvas)

                let path = Path(roundedRect: rect, cornerRadius: w / 2).applying(transform)
                // The end-stop paints in the marker's own copper, not the strip's tint — see
                // `DialGeometry.endStopHeight` for why colour, not just weight, is what makes it
                // unmistakable. `weight` is already 1 for an end-stop, so `opacity` here is just
                // the position fade — the same ramp every other tick uses, nothing special.
                context.fill(path, with: .color((isEndStop ? TColor.copper500 : tint).opacity(opacity)))
            }
        }
        // No implicit animation: the reference's own tick-group transition target is dead code
        // (nothing ever sets the group's own `transform`), so ticks redraw fresh on every value
        // change — during a drag that's every touch-move, which already reads as continuous.
    }
}
