import SwiftUI
import UIKit

/// **Addition, not a port.** There are no haptics anywhere in the reference — it is a web page, and
/// `app.jsx` / `design-system.js` contain no `navigator.vibrate` and no haptics call at all. A hold
/// with no feedback is wrong on a phone, so the honest moments get one buzz each: the hold arms,
/// the ring climbs, the hold fires — and, in flight, a chance is spent, spent out, or won back.
/// Every generator in the app lives here, so there is exactly one place buzzing. Nothing here
/// changes a duration.
enum Haptics {
    private static let impact = UIImpactFeedbackGenerator(style: .light)
    private static let notice = UINotificationFeedbackGenerator()
    /// Held once and prepared once — a dial drag can cross a dozen steps a second, and a fresh
    /// generator (or a re-`prepare()`) per step is exactly the per-frame cost this is not
    /// supposed to have.
    private static let selection: UISelectionFeedbackGenerator = {
        let g = UISelectionFeedbackGenerator()
        g.prepare()
        return g
    }()

    /// Silenced while the debug self-checks run, so launching does not buzz in your hand.
    static var muted = false

    /// A light tick the moment a hold takes, and a warm-up so the climbing ticks are not late.
    static func armed() {
        guard !muted else { return }
        impact.prepare()
        notice.prepare()
        impact.impactOccurred(intensity: 0.35)
    }

    /// One rung of the climb. `intensity` rises with the ring.
    static func tick(_ intensity: Double) {
        guard !muted else { return }
        impact.impactOccurred(intensity: intensity)
    }

    /// The hold completed and the destructive thing is happening.
    static func done() {
        guard !muted else { return }
        notice.notificationOccurred(.success)
    }

    /// A chance just went.
    static func warned() {
        guard !muted else { return }
        notice.notificationOccurred(.warning)
    }

    /// The last chance went with it — the flight diverted.
    static func failed() {
        guard !muted else { return }
        notice.notificationOccurred(.error)
    }

    /// Back in the air.
    static func resumed() {
        guard !muted else { return }
        notice.notificationOccurred(.success)
    }

    /// One step of a dial or wheel turning under the finger — `DialView`'s drag and the settings
    /// airport wheel both fire this once per step crossed, never once per frame. Quieter than a
    /// hold's climb on purpose: a drag can cross many of these in a second.
    static func dialTick() {
        guard !muted else { return }
        selection.selectionChanged()
    }
}

/// The clock behind a press-and-hold. `p` is the fill, 0…1, advanced off the real elapsed time
/// rather than a fixed-step animation, so a 10-second hold takes ten seconds even under load.
///
/// Two behaviours the controls depend on: releasing before completion cancels cleanly — `p` returns
/// to 0 and nothing is called — and on completion `p` snaps back to 0 rather than resting full, so
/// the ring empties the instant it fires. A hold that has fired stays fired until the finger lifts;
/// keeping it down does not re-fire.
@Observable
final class HoldState {
    /// `HOLD_MS = 900`. Ending a flight is destructive, so it takes a deliberate hold.
    static let base: Double = 0.9

    /// How long this hold runs. The flight screen's exit passes 10 s for a locked cabin.
    var seconds: Double

    private(set) var p: Double = 0
    /// True from the first frame after touch-down, not on touch-down itself — the reference's
    /// `p > 0` test, and the presentation lags by a frame in the same way.
    var holding: Bool { p > 0 }

    private var task: Task<Void, Never>?
    private var lastTick = 0

    init(seconds: Double = HoldState.base) {
        self.seconds = seconds
    }

    /// Starts the hold, or does nothing if one is already running. `onDone` fires once, at the end.
    func start(_ onDone: @escaping () -> Void) {
        guard task == nil else { return }
        lastTick = 0
        Haptics.armed()
        // One tick per ring segment: six over a short hold, one per second over a long one, which
        // is also where the pill's own countdown label changes.
        let ticks = max(6, Int(seconds.rounded()))
        task = Task { @MainActor in
            await tpRamp(seconds) { k in
                p = k
                let n = Int(k * Double(ticks))
                if n > lastTick && n < ticks {
                    lastTick = n
                    Haptics.tick(0.35 + 0.65 * k)
                }
            }
            guard !Task.isCancelled else { return }
            p = 0
            Haptics.done()
            onDone()
        }
    }

    /// Release, or anything else that should abandon the hold. No callback, no state change.
    func cancel() {
        task?.cancel()
        task = nil
        p = 0
        lastTick = 0
    }
}

/// The 44pt circular dismiss control with a copper ring that fills as it is held. The ring is
/// invisible until the hold takes and snaps away the moment it fires — no transition on either,
/// deliberately, so the fill only ever reads as the finger's own progress.
///
/// The state is owned by the caller so that a surrounding label can read `p` and count down.
struct HoldCircle: View {
    var hold: HoldState
    /// Accessibility label, e.g. "Hold to divert".
    var label: String
    var onDone: () -> Void

    var body: some View {
        ZStack {
            Circle().fill(TColor.white)
            Image(systemName: "xmark")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(TColor.navy700)
        }
        .overlay {
            // r = 20 inside the 44 box; C = 2π·20 ≈ 125.664, which `trim` expresses as a fraction.
            // Rotated so the fill starts at twelve o'clock and runs clockwise.
            Circle()
                .trim(from: 0, to: hold.p)
                .stroke(TColor.copper500, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: 40, height: 40)
                .rotationEffect(.degrees(-90))
                .opacity(hold.holding ? 1 : 0)
                .animation(nil, value: hold.p)
        }
        .frame(width: 44, height: 44)
        .contentShape(Circle())
        .scaleEffect(hold.holding ? TPress.scale : 1)
        .animation(.glide(TDur.fast), value: hold.holding)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in hold.start(onDone) }
                .onEnded { _ in hold.cancel() }
        )
        .onDisappear { hold.cancel() }
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
    }
}

/// The pill-shaped end-flight control, used on the Live Activity and the shield. The fill is drawn
/// per frame with no transition of its own, and while it is held the pill stops naming the action
/// and starts naming the price: `sub` is what letting go will cost.
struct HoldPill: View {
    var label: String
    /// Shown in place of `label` while held — the stake, e.g. "lose 12 mi".
    var sub: String?
    /// Full width and 56pt tall instead of 44.
    var block: Bool
    var onDone: () -> Void
    @State private var hold: HoldState

    init(
        label: String,
        sub: String? = nil,
        block: Bool = false,
        holdSeconds: Double = HoldState.base,
        onDone: @escaping () -> Void
    ) {
        self.label = label
        self.sub = sub
        self.block = block
        self.onDone = onDone
        _hold = State(initialValue: HoldState(seconds: holdSeconds))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                HoldPill.ground
                TColor.copper500.opacity(0.6)
                    .frame(width: geo.size.width * hold.p)
                Text(hold.holding ? (sub ?? label) : label)
                    .font(TFont.core(.semibold, size))
                    .foregroundStyle(hold.holding ? TColor.statusDivertedSoft : HoldPill.idle)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: block ? 56 : 44)
        .frame(maxWidth: .infinity)
        .clipShape(Capsule())
        .contentShape(Capsule())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in hold.start(onDone) }
                .onEnded { _ in hold.cancel() }
        )
        .onDisappear { hold.cancel() }
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
    }

    private var size: CGFloat {
        hold.holding && sub != nil ? 12 : (block ? 16 : 14)
    }

    /// Two literals the reference states raw rather than as tokens.
    private static let ground = Color(hex: 0xa65a4a, opacity: 0.28)
    private static let idle = Color(hex: 0xe0a08e)
}
