import SwiftUI
import UIKit

/// Adds a new subject, or renames an existing one when `model.editTask` is set. The reference is
/// one absolutely-positioned overlay — a single scrim div plus a floating input pill — not a
/// system sheet, so this is drawn the same way every other floating surface in this app is
/// (`ChoiceSheet`, `GateScreen`, `PaywallSheet`, `PaySheet`, `CircleRevealView`): a plain view
/// stacked into `RootView`'s `ZStack`, not `.sheet(isPresented:)`. A real system sheet draws its
/// *own* backdrop treatment behind whatever it presents — a second dim/blur pass this view cannot
/// see or turn off from the inside — so however this pill's own background was painted, the app
/// was always showing one scrim more than the reference does. Matching the reference's one-scrim
/// count means not presenting this as a sheet at all, not painting a second layer to blend the
/// first one away.
///
/// The reference draws its own QWERTY here because it is simulating a phone inside a browser; we
/// use the real keyboard, so only the floating input pill and the add/edit copy switch are ported
/// — the `Key`/`KROWS_*` keyboard-drawing is reference-only and is not.
struct AddSheet: View {
    @Environment(AppModel.self) private var model
    @State private var text = ""
    /// Raised 80ms after the pill mounts — see the delay in `onAppear` below.
    @FocusState private var focused: Bool
    @State private var keyboard = KeyboardTracker()
    /// The reference's `tp-fade` / `tp-pillin` / `tp-fadeout`, as two flags flipped inside their
    /// own `withAnimation`. Not `.transition`s: this view is inserted into `RootView`'s stack with
    /// `.transition(.identity)`, and a child's `.transition` inside a subtree that arrives whole
    /// never plays — the scrim was cutting in on one frame with `.transition(.opacity)` on it.
    @State private var scrimOn = false
    /// **The pill's entrance does not wait for the keyboard.** It used to: the pill was hidden
    /// until `KeyboardTracker` reported a frame and then faded in, linearly, across the keyboard's
    /// own rise — so it reached full opacity on the exact frame the keyboard landed, and the
    /// sequence read as keyboard first, pill second. The reference starts `tp-pillin` (420 ms) 60 ms
    /// after mount, in parallel with the keyboard's `tp-rise`, and that is what this does. Only the
    /// *lift* (`keyboard.lift`, below) is the keyboard's: it is written inside the tracker's own
    /// `withAnimation`, on the keyboard's own curve, so the pill rides the keyboard's top edge up
    /// while its own fade is still playing — one movement, arriving together.
    @State private var pillOn = false

    /// Nil for a fresh subject; the task being renamed otherwise. Read fresh at submit time too,
    /// rather than captured once, so a stale copy can never cause the wrong branch to run.
    private var editing: TaskItem? { model.editTask }

    var body: some View {
        ZStack(alignment: .bottom) {
            // The one scrim — same token every other overlay in the app dims behind itself with.
            // `tp-fade`/`tp-fadeout`: opacity only, 260ms, `--ease-glide` both ways.
            TColor.overlayScrim
                .ignoresSafeArea()
                .opacity(scrimOn ? 1 : 0)
                .onTapGesture(perform: dismiss)

            HStack(spacing: 12) {
                // Bare, not `TTextField`: the pill around it already is the field's surface, and
                // the reference's input carries no border, background or label of its own.
                TextField(editing != nil ? "Subject name" : "New subject", text: $text)
                    .focused($focused)
                    .submitLabel(.done)
                    .font(TFont.core(.medium, 17))
                    .foregroundStyle(TColor.textPrimary)
                    .tint(TColor.copper500)
                    .textInputAutocapitalization(editing != nil ? .never : .sentences)
                    .onSubmit(submit)

                TButton(editing != nil ? "Save" : "Add", variant: .primary, size: .sm) {
                    submit()
                }
            }
            .padding(.leading, 22)
            .padding(.trailing, 8)
            .frame(height: 60)
            .background(Capsule().fill(TColor.surfaceCard))
            .tpShadow(.overlay)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
            // `RootView`'s outer `ZStack` unions its children's full frames — this screen included,
            // under `.ignoresSafeArea(edges: .all)` — so the stack always reports full screen
            // height, keyboard region included, which defeats SwiftUI's automatic keyboard
            // avoidance for every child mounted inside it. Riding the keyboard's own frame
            // notifications is the fix: the pill sits 12pt above the *keyboard's* top edge instead
            // of 12pt above the safe area, and lifts in step with it.
            .padding(.bottom, keyboard.lift)
            // `tp-pillin`: translateY(26px) scale(.96) → identity, opacity 0→1, 420 ms glide, not an
            // off-screen slide. `tp-fadeout` (out) is opacity 1→0 only, 220 ms on `--ease-exit`:
            // the pill fades in place, it doesn't slide back down.
            .opacity(pillOn ? 1 : 0)
            .scaleEffect(pillOn ? 1 : 0.96, anchor: .bottom)
            .offset(y: pillOn ? 0 : 26)
        }
        // SwiftUI applies a keyboard inset of its own to this stack — not the full keyboard, just
        // enough to land the pill a couple of hundred points above where the manual lift already
        // put it. Two mechanisms fighting over the same edge is what parked the bar in the middle
        // of the screen. Turning the automatic one off makes the lift below the only one.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onAppear {
            text = editing?.title ?? ""
            withAnimation(.glide(0.26)) { scrimOn = true }
            Task {
                // `tp-pillin 420ms 60ms`.
                try? await Task.sleep(for: .milliseconds(60))
                guard !Task.isCancelled else { return }
                withAnimation(.glide(0.42)) { pillOn = true }
                // The reference doesn't focus its input the instant the pill mounts either — it
                // waits 80ms (`setTimeout(...,80)`) before calling `.focus()`. Raising
                // `@FocusState` in the same transaction that inserts this view races the insertion:
                // the request lands before the window has anything to make first responder, and
                // is silently dropped — the keypad simply never opens.
                try? await Task.sleep(for: .milliseconds(20))
                guard !Task.isCancelled else { return }
                focused = true
                // A hardware keyboard (or the Simulator with the software one off) posts no frame
                // at all, and a seeded lift would then park the pill over an empty gap for the
                // whole session. Half a second is long enough for any real keyboard to have
                // announced itself; after that the pill settles to the bottom edge instead.
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled, !keyboard.reported else { return }
                withAnimation(.glide(0.26)) { keyboard.lift = 0 }
            }
        }
    }

    private func dismiss() {
        // A second tap on the scrim while the first is still fading out.
        guard scrimOn else { return }
        focused = false
        withAnimation(.glide(0.26)) { scrimOn = false }
        withAnimation(.exit(0.22)) { pillOn = false }
        // The reference's `shut()`: fade, then unmount 300 ms later. Clearing `editTask` waits for
        // the unmount too, or "Save" flips to "Add" on a pill that is still on screen.
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            model.editTask = nil
            model.addSheet = false
        }
    }

    private func submit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // An empty field submits nothing, but it is still a way out — pressing the keyboard's own
        // Done key (or tapping Add/Save) with nothing typed dismisses rather than silently doing
        // nothing, which is otherwise indistinguishable from the keyboard being stuck.
        guard !trimmed.isEmpty else { dismiss(); return }
        if let editing = model.editTask {
            model.updateTask(id: editing.id, title: trimmed)
        } else {
            model.addTask(title: trimmed)
        }
        dismiss()
    }
}

/// The first keyboard of a process loads UIKit's keyboard bundle on the main thread — several
/// hundred milliseconds in which every SwiftUI animation stops. Paid inside `AddSheet`, that
/// reads as scrim first, pill and keyboard second; the reference's entrance timings were never
/// the problem. `ScreenWarm` pays it in idle time at launch instead: becoming and resigning first
/// responder in the same runloop turn loads the bundle without ever presenting the keyboard.
/// `KeyboardTracker` observes `keyboardWillChangeFrameNotification`; a frame posted by this
/// warm-up is harmless, and may even seed `lastLift` for a fresh install.
enum KeyboardWarm {
    @MainActor static func run() {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).compactMap(\.keyWindow).first else { return }
        let field = UITextField(frame: .zero)
        field.autocorrectionType = .no
        window.addSubview(field)
        field.becomeFirstResponder()
        field.resignFirstResponder()
        field.removeFromSuperview()
    }
}

/// Tracks the system keyboard's rising/falling frame so `AddSheet`'s pill can sit directly above
/// it instead of underneath it — see the note on `RootView`'s outer `ZStack` above. Mutated from
/// `NotificationCenter`'s escaping closures, so this is a reference type per CLAUDE.md's warning
/// on `@State` written through an escaping closure's copy of the view, not a `@State` struct
/// field itself (only the *instance* is `@State`, so it survives `AddSheet`'s own re-renders).
///
/// Internal rather than file-private: Status Club's Founders invite has the same field under the
/// same keyboard, and one observer reused beats a second copy of this class.
@Observable
final class KeyboardTracker {
    /// What a bottom-pinned pill should be lifted by, as a **stored** value.
    ///
    /// Stored, and computed in `apply` below, because deriving it in `body` reads
    /// `TSafeArea.insets` — the live key-window read CLAUDE.md forbids in any body. It was safe
    /// only by accident while the keyboard-down value short-circuited the read; the moment a pill
    /// mounted already lifted, the first body of the sheet read the window and the router logged
    /// `AttributeGraph: cycle detected` and stopped building layers.
    ///
    /// Seeded with the last lift a keyboard produced, so a pill that mounts *before* its keyboard
    /// has arrived can already be drawn where the keyboard is about to put it — the reference pins
    /// its pill at a fixed `bottom:262` and lets the drawn keyboard rise to meet it, and this is the
    /// only way to know that number on a real phone before the keyboard says it. Zero until the
    /// first keyboard a fresh install raises; the frame notification corrects a stale guess (a
    /// predictive bar toggled, a different keyboard) on the keyboard's own curve. **The pill never
    /// waits for that notification**: a real phone's keyboard takes its time to arrive, and a pill
    /// gated on it is a pill that appears after the keyboard.
    var lift: CGFloat = KeyboardTracker.lastLift
    /// The keyboard's overlap with the screen; zero while it is down.
    private(set) var height: CGFloat = 0
    /// Whether any keyboard frame has arrived this instance — the seed above is a guess until one does.
    private(set) var reported = false
    private static var lastLift: CGFloat {
        get { CGFloat(UserDefaults.standard.double(forKey: "tempus.keyboard.lift")) }
        set { UserDefaults.standard.set(Double(newValue), forKey: "tempus.keyboard.lift") }
    }
    private var tokens: [NSObjectProtocol] = []

    init() {
        // `keyboardWillChangeFrameNotification` alone covers both directions — on hide, its frame
        // already reports the keyboard moved off screen, so a second `willHide` observer would
        // just race this one's animation with an instant snap to zero.
        tokens.append(NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillChangeFrameNotification,
            object: nil, queue: .main) { [weak self] note in
                self?.apply(note)
            })
    }

    deinit {
        let center = NotificationCenter.default
        tokens.forEach { center.removeObserver($0) }
    }

    private func apply(_ note: Notification) {
        guard let info = note.userInfo,
              let frame = (info[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue,
              let duration = info[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double
        else { return }
        let screenHeight = UIScreen.main.bounds.height
        let next = max(0, screenHeight - frame.origin.y)
        // `next` is the keyboard's overlap with the **screen**. A stack laid out inside the safe
        // area already sits `TSafeArea.insets.bottom` above the screen's bottom edge, so padding
        // it by the full height puts the pill exactly that inset too high — and the home indicator
        // is under the keyboard at that point anyway. Read here, in a notification handler, never
        // in a body.
        let lifted = next > 0 ? max(0, next - TSafeArea.insets.bottom) : 0
        reported = true
        if lifted > 0, lifted != Self.lastLift { Self.lastLift = lifted }
        withAnimation(Self.curve(info[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int,
                                 duration)) { height = next; lift = lifted }
    }

    /// The keyboard's own curve, so the pill rides it instead of chasing it.
    ///
    /// A real keyboard reports raw **7** — UIKit's private keyboard curve, which is not one of the
    /// four public cases and has no SwiftUI equivalent. This used to hardcode `easeInOut`, and
    /// easeInOut's slow start falls behind precisely where the keyboard is moving fastest: the
    /// pill spent most of the rise well below the keyboard's top edge and only caught up at the
    /// very end, which is what read as the bar landing somewhere in the middle of the screen.
    /// Linear tracks the real thing far more closely over the part of the travel you can see.
    ///
    /// The public curves (0…3) genuinely do turn up for some programmatic frame changes, so they
    /// are honoured as themselves rather than flattened into the same answer.
    private static func curve(_ raw: Int?, _ duration: Double) -> Animation {
        switch raw.flatMap(UIView.AnimationCurve.init(rawValue:)) {
        case .easeInOut: return .easeInOut(duration: duration)
        case .easeIn: return .easeIn(duration: duration)
        case .easeOut: return .easeOut(duration: duration)
        default: return .linear(duration: duration)
        }
    }
}

/// Picks the home airport from every airport the map knows. Reuses the settings' own bottom-sheet
/// chrome (the system sheet) around the picker wheel — distinct from onboarding's own wheel, this
/// one commits on a tap as well as on a drag/flick settle.
struct AirportSheet: View {
    @Environment(AppModel.self) private var model
    @State private var index = 0

    /// Sydney first, then every airport, then the six always-present fallbacks, sorted by city.
    ///
    /// This used to exclude the *current home* and claimed, in this comment, to be matching the
    /// reference by doing so. It was not. The reference's `AIRPORTS()` seeds `seen` with `SYD`
    /// alone and skips nothing else — and it memoises into `_APS`, so the list is built once and
    /// never tracks where home moves to. Excluding the live home meant `onAppear`'s
    /// `firstIndex { $0.code == home }` found nothing for any home outside SYD and the six
    /// fallbacks: the wheel opened on the alphabetically first city and "Set airport" committed
    /// it. Land in Tokyo, open the sheet, and it silently offered to move you to Adelaide.
    ///
    /// Sorted with `localizedStandardCompare`, which is the reference's `localeCompare`. Swift's
    /// `<` compares Unicode scalars, so "São Paulo" (ã is U+00E3) sorted *after* "Sydney".
    private var airports: [Airport] {
        var seen: Set<String> = []
        var list: [Airport] = []
        func add(_ code: String) {
            guard !seen.contains(code) else { return }
            seen.insert(code)
            list.append(Geography.byCode(code))
        }
        add("SYD")
        // Every airport, the current home included. Excluding it meant `onAppear`'s
        // `firstIndex { $0.code == home }` found nothing for any home outside SYD and the six
        // fallbacks, so the wheel opened on the alphabetically first city and "Set airport" —
        // the only control that looks like "done" — silently moved you to Adelaide.
        for a in Geography.all { add(a.code) }
        for code in ["JFK", "CDG", "FRA", "SFO", "YYZ", "GRU"] { add(code) }
        return list.sorted { $0.city.localizedStandardCompare($1.city) == .orderedAscending }
    }

    var body: some View {
        let list = airports
        VStack(spacing: 0) {
            Text("Home airport")
                .tpLabelStyle()
                .foregroundStyle(TColor.textMuted)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 22)

            SettingsAirportWheel(list: list, index: $index)
                .padding(.top, 16)

            TButton("Set airport", variant: .primary, size: .lg, fullWidth: true) {
                guard list.indices.contains(index) else { return }
                model.setHomeAirport(list[index].code)
                model.airportSheet = false
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 30)
        }
        .presentationDetents([.height(400)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(TRadius.xl)
        .onAppear {
            index = list.firstIndex { $0.code == model.homeAirport.code } ?? 0
        }
    }
}

/// The picker's own live drag/settle state. A reference type on purpose — it is mutated from a
/// drag callback and from a delayed settle, exactly the shape of callback CLAUDE.md already
/// flags as unsafe against plain `@State` written through an escaping closure's copy of the view.
@Observable
private final class AirportWheelState {
    var off: Double = 0
    var dragStartOffset: Double = 0
    var dragging = false
    var settleTarget: Int?
    /// The row a tick was last fired for during the live drag — so a drag ticks once per row
    /// crossed rather than once per touch-move frame. Reset at the start of each drag.
    var lastTickRow: Int?
}

/// iOS-style picker: tracks the finger (or a tap's position) with no easing while live, then
/// glide-settles to the nearest row. `ROW = 46`; up to 3.2 rows either side of centre render.
private struct SettingsAirportWheel: View {
    let list: [Airport]
    @Binding var index: Int
    @State private var w = AirportWheelState()

    private static let rowHeight: CGFloat = 46
    private static let wheelHeight: CGFloat = 250

    private var maxIndex: Int { max(0, list.count - 1) }

    var body: some View {
        GeometryReader { geo in
            let center = geo.size.height / 2
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(TColor.surfaceSunken)
                    .frame(height: Self.rowHeight)
                    .padding(.horizontal, 4)

                ForEach(Array(list.enumerated()), id: \.element.code) { i, airport in
                    row(airport, i: i)
                }

                fadeMask(top: true)
                fadeMask(top: false)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !w.dragging {
                            w.dragging = true
                            w.dragStartOffset = w.off
                            w.settleTarget = nil
                            w.lastTickRow = Int(w.off.rounded())
                        }
                        w.off = clampLive(w.dragStartOffset - value.translation.height / Self.rowHeight)
                        // One buzz per row crossed under the finger, not one per frame.
                        let row = clampIndex(w.off)
                        if row != w.lastTickRow {
                            w.lastTickRow = row
                            Haptics.dialTick()
                        }
                    }
                    .onEnded { value in
                        w.dragging = false
                        let moved = max(abs(value.translation.height), abs(value.translation.width)) > 6
                        let target = moved
                            ? w.dragStartOffset - value.predictedEndTranslation.height / Self.rowHeight
                            : w.dragStartOffset + (value.startLocation.y - center) / Self.rowHeight
                        w.settleTarget = clampIndex(target)
                    }
            )
        }
        .frame(height: Self.wheelHeight)
        .onAppear { w.off = Double(index) }
        .task(id: w.settleTarget) {
            guard let target = w.settleTarget else { return }
            let start = w.off
            await tpRamp(0.42) { k in w.off = start + (Double(target) - start) * TEase.out(k) }
            guard !Task.isCancelled else { return }
            w.off = Double(target)
            index = target
        }
    }

    @ViewBuilder
    private func row(_ airport: Airport, i: Int) -> some View {
        let d = Double(i) - w.off
        if abs(d) <= 3.2 {
            let on = abs(d) < 0.5
            HStack {
                Text(airport.city)
                    .font(TFont.core(on ? .semibold : .regular, 20))
                    .tracking(-0.02 * 20)
                    .foregroundStyle(on ? TColor.textPrimary : TColor.textSecondary)
                Spacer(minLength: 12)
                Text(airport.code)
                    .font(TFont.data(.medium, 13))
                    .tracking(0.1 * 13)
                    .foregroundStyle(on ? TColor.textAccent : TColor.textMuted)
            }
            .padding(.horizontal, 24)
            .frame(height: Self.rowHeight)
            .frame(maxWidth: .infinity)
            // CSS's `perspective:700px` on a 46pt row is a fairly aggressive perspective; this is
            // an approximation — SwiftUI's normalised `perspective` isn't a 1:1 unit conversion.
            .rotation3DEffect(.degrees(-d * 13), axis: (x: 1, y: 0, z: 0), perspective: 0.28)
            .scaleEffect(CGFloat(1 - min(0.3, abs(d) * 0.07)))
            .opacity(max(0.08, 1 - abs(d) * 0.3))
            .offset(y: d * Self.rowHeight)
        }
    }

    @ViewBuilder
    private func fadeMask(top: Bool) -> some View {
        LinearGradient(
            colors: top ? [TColor.cloud100, TColor.cloud100.opacity(0)]
                        : [TColor.cloud100.opacity(0), TColor.cloud100],
            startPoint: .top, endPoint: .bottom
        )
        .frame(height: 64)
        .frame(maxHeight: .infinity, alignment: top ? .top : .bottom)
        .allowsHitTesting(false)
    }

    private func clampLive(_ v: Double) -> Double { min(Double(maxIndex) + 0.4, max(-0.4, v)) }
    private func clampIndex(_ v: Double) -> Int { min(maxIndex, max(0, Int(v.rounded()))) }
}
