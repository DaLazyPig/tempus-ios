import Observation
import SwiftUI

/// The task deck and the app's front door. Owns two set-pieces it hands off rather than plays
/// itself: opening a subject measures the copper card and starts the morph into Preflight
/// (`model.openFlight(from:)`), and Settings opens as a circle reveal from the tapped button
/// (`model.circleGo(from:to:)`).
struct HomeScreen: View {
    @Environment(AppModel.self) private var model

    /// The deck's own touch state.
    @State private var g = DeckGesture()
    /// The top card's frame in window space, so `open()` can hand the morph an accurate rect.
    /// There is no separate scaled "phone frame" in the native app the way there is in the browser
    /// reference — the whole app *is* the phone — so window space is exactly the space the morph
    /// needs, with no `rectInPhone`-style conversion required. A `RectBox` rather than
    /// `@State`: a geometry read that lands in state re-runs this whole screen's `body` — deck,
    /// footer and all — every time the number moves, to record something only `open()` ever
    /// reads. The measurement is taken outside the card's pose transforms (see the note at the
    /// bottom of `cardView`), so it is the card's *resting* frame and a drag does not move it.
    @State private var topCardRect = RectBox()
    /// The settings button's frame in window space, kept fresh for the circle reveal.
    @State private var settingsButtonRect = RectBox()
    /// A throwaway measure target for back cards, which share `cardView`'s modifier chain with the
    /// top card (for identity stability across the top⇄back swap) but never need their own rect.
    @State private var deckScratchRect = RectBox()
    /// The front face's flip button, in window space — read by `dragGesture` so a tap starting on
    /// the button never also starts (or ends) the card's own drag/tap handling. See `flipCard()`.
    @State private var flipButtonRect = RectBox()

    private static let depth = 3
    private static let throwDistance: CGFloat = 560
    /// Three RGB stops the stack's background interpolates across as a card is dragged away.
    /// Stop 0 is exactly `--copper-500`; stop 2 is *close to* but not exactly `--sky-300` — the
    /// reference records it as its own literal rather than aliasing the token, so this does too.
    private static let ramp: [(Double, Double, Double)] = [(184, 111, 82), (150, 174, 209), (188, 204, 226)]

    var body: some View {
        VStack(spacing: 0) {
            headerRow

            if model.weeklyGoal > 0 {
                Rise(i: 0) { GoalStrip() }
            }

            if let notice {
                Rise(i: 0) {
                    HomeNoticeBanner(title: notice.title, message: notice.message) {
                        model.periodAck = model.status.period
                    }
                }
            }

            Group {
                if model.tasks.isEmpty {
                    emptyState
                } else {
                    ZStack {
                        ForEach(visibleCards, id: \.task.id) { entry in
                            cardView(task: entry.task, i: entry.i)
                        }
                    }
                    // The reference's card is a content-box: `width:100%` is the 342pt column,
                    // and its 26pt padding is added *outside* that, so the card's painted box is
                    // 52pt wider than the column and its right edge — and both back cards' —
                    // runs off the screen and is clipped. Anchored left, hanging right.
                    .padding(.trailing, -52)
                    .contentShape(Rectangle())
                    // Detached entirely while the card is turned over, rather than attached and
                    // guarded from inside: a zero-distance `DragGesture` on the container is one
                    // more thing for the back face's buttons to win against on every tap, and it
                    // has nothing to do while `flipped`.
                    .gesture(canGesture ? dragGesture : nil)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, 52)

            footer
        }
        .padding(.horizontal, 24)
        // 124 clears the floating nav — a 64pt capsule sitting 24pt off the physical edge —
        // by 36pt. Dropping it from 150 carries the footer down 26pt and, since the stack
        // is the flexible row, re-centres the cards 13pt lower with it.
        .padding(.bottom, 124)
        // `AddSheet` is a sibling overlay in `RootView`'s stack, not a child of this screen, but
        // SwiftUI's automatic keyboard avoidance reaches every unopted-out view under the same
        // window — so the moment its text field focused, this VStack's own proposed height
        // shrank by the keyboard's, and the whole deck slid up behind it. `AddSheet`'s pill
        // already rides the keyboard on its own (`KeyboardTracker.lift`); Home has no business
        // moving for a keyboard it cannot even see, so it opts its own layout out.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        // **The balance is read here, so it is refreshed here.** The shared pot is a cached
        // number (`AppModel.pot`, persisted) that only a pull from `currentPair()` can move, and
        // until now the four things that pulled were launch, foregrounding, Linked and Status
        // Club — none of them this screen, which is the one that actually draws the figure. So a
        // member whose partner had just landed sat on Home looking at a stale total until they
        // happened to background the app or detour into the Club. One GET on arrival closes that;
        // `refreshSharedBank` also flushes queued credits and collects payouts on the way
        // through, and no-ops entirely with no backend configured.
        //
        // ponytail: a pull where the number is read, not a live channel. Two phones still only
        // agree as often as either one opens Home. Supabase Realtime on `link_pairs` is the
        // upgrade path if that is ever not enough — a websocket and a reconnect policy for a
        // figure that is already honest about being unconfirmed (`potStale`).
        .task { await model.refreshSharedBank() }
        .task { await runMorphDragSeam() }
        .task(id: g.pressToken) { await runHoldTimer() }
        .task(id: g.throwDir) { await runThrowAdvance() }
        .task(id: model.deal) { await runDealClear() }
    }

    // MARK: - Header

    /// The header's four chrome icons: a sunken 44pt disc, but tinted `steel-600` rather than
    /// the tone's default ink — the one place the reference paints these buttons differently
    /// from every other back/close button in the app.
    private func headerIcon(_ glyph: LucideGlyph, _ size: CGFloat) -> some View {
        LucideIcon(glyph: glyph, size: size, color: TColor.steel600)
    }

    @ViewBuilder
    private var headerRow: some View {
        let row = HStack(spacing: 8) {
            IconButton(tone: .sunken, size: .md, label: "Passes", action: {
                model.go(.passes, .lift, dir: 1)
            }) {
                headerIcon(.ticket, 20)
            }

            IconButton(tone: .sunken, size: .md, label: "Flight log", action: {
                model.go(.stats, .lift, dir: 1)
            }) {
                headerIcon(.barChart3, 20)
            }

            IconButton(tone: .sunken, size: .md, label: "The Concourse", action: {
                model.go(.concourse, .lift, dir: 1)
            }) {
                headerIcon(.shoppingBag, 19)
            }

            IconButton(tone: .sunken, size: .md, label: "Settings", action: {
                let r = settingsButtonRect.rect
                let center = CGPoint(x: r.midX, y: r.midY)
                model.circleGo(from: center, to: .settings)
            }) {
                headerIcon(.settings, 20)
            }
            .measureRect(into: settingsButtonRect, in: TStage.space)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.top, 30)

        if model.deal {
            ORise(i: 0) { row }
        } else {
            row
        }
    }

    // MARK: - Weekly goal

/// The week's goal, on the one screen that is open every time the app is. Off by default and
/// absent entirely when it is off — a target nobody set has nothing to say.
///
/// It states a position and stops. There is no streak to break, no colour that turns angry on a
/// Sunday and no copy that notices you are behind: the bar is where it is. Missing a week costs
/// nothing, which is the whole reason it is safe to put on the home screen.
private struct GoalStrip: View {
    @Environment(AppModel.self) private var model

    private var flown: Double { model.goalHoursThisWeek }

    private var figure: String {
        let h = (flown * 10).rounded() / 10
        return h == h.rounded() ? "\(Int(h))" : String(format: "%.1f", h)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text("This week").tpLabelStyle().foregroundStyle(TColor.textMuted)
                Spacer()
                Text(model.goalMet ? "\(figure) h \u{00b7} goal met"
                                   : "\(figure) of \(model.weeklyGoal) h")
                    .font(TFont.core(.semibold, 13))
                    .foregroundStyle(model.goalMet ? TColor.textAccent : TColor.textSecondary)
                    .monospacedDigit()
            }
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(TColor.surfaceSunken)
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(model.goalMet ? TColor.surfaceAccent : TColor.sky400)
                            .frame(width: geo.size.width * model.goalProgress)
                    }
            }
            .frame(height: 6)
            .animation(.glide(0.56), value: model.goalProgress)
        }
        .padding(.top, 20)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("This week: \(figure) of \(model.weeklyGoal) hours flown"))
    }
}

// MARK: - Tier-ending notice

    private var notice: (title: String, message: String)? {
        let s = model.status
        guard s.idx > 0, !s.holding, s.daysLeft <= 21, model.periodAck != s.period else { return nil }
        let title = "\(s.tier.name) ends \(fmtDay(s.end))"
        let message = "This period closes in \(s.daysLeft) days on \(Status.h1(s.hours)) h. "
            + "Fly \(Status.h1(s.hold)) h more to carry \(s.tier.name) into the next one."
        return (title, message)
    }

    private func fmtDay(_ t: TimeInterval) -> String {
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        f.locale = Locale(identifier: "en_GB")
        return f.string(from: Date(timeIntervalSince1970: t))
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 0) {
            // Covers both a fresh install (`seedTasks` is empty — no demo deck to clear away)
            // and a member who has deleted every subject, so the copy names neither.
            Text("No subjects yet")
                .font(TFont.core(.bold, 30))
                .tpType(size: 30, track: -0.035, lineHeight: 1.14)
                .foregroundStyle(TColor.textPrimary)
                .multilineTextAlignment(.center)

            Text("Add one to book your first flight.")
                .font(TFont.core(.regular, 16))
                .tpType(size: 16, lineHeight: 1.5)
                .foregroundStyle(TColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, 14)

            Button {
                model.editTask = nil
                model.addSheet = true
            } label: {
                Text("Add a subject")
                    .font(TFont.core(.semibold, 16))
                    .foregroundStyle(TColor.white)
                    .padding(.horizontal, 26)
                    .frame(height: 52)
                    .background(Capsule().fill(TColor.surfaceAccent))
            }
            .padding(.top, 22)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - The stack

    private struct DeckEntry { let task: TaskItem; let i: Int }

    private var visibleCards: [DeckEntry] {
        guard !model.tasks.isEmpty else { return [] }
        let n = min(Self.depth, model.tasks.count)
        return (0..<n).map { i in
            DeckEntry(task: model.tasks[(model.order + i) % model.tasks.count], i: i)
        }
    }

    private var canGesture: Bool { g.throwDir == 0 && !g.flipped }

    private var dragGesture: some Gesture {
        // `.global` so `value.startLocation` lands in the same space `flipButtonRect` is
        // measured in (`.measureRect(..., in: .global)`) — `translation` is a delta and is
        // identical in either space, so this changes nothing else the gesture reads.
        DragGesture(minimumDistance: 0, coordinateSpace: TStage.space)
            .onChanged { value in
                // A touch starting on the flip button is the button's, not the deck's: skip
                // every state change (no press-and-hold, no throw, no `open()`) so the two
                // never fight over the same tap. The button owns its own `Button` gesture, so
                // this only has to stay out of its way — see `flipCard()`.
                guard canGesture, !flipButtonRect.rect.contains(value.startLocation) else { return }
                if !g.dragging {
                    g.dragging = true
                    g.movedPastHoldThreshold = false
                    g.pressToken += 1
                }
                let d = value.translation.width
                if abs(d) > 8 { g.movedPastHoldThreshold = true }
                g.dx = d
            }
            .onEnded { value in
                guard canGesture, g.dragging else { return }
                g.dragging = false
                let d = value.translation.width
                if abs(d) < 8 {
                    g.dx = 0
                    open()
                } else if abs(d) > 72 {
                    let dir: Int = d < 0 ? -1 : 1
                    g.throwDir = dir
                    g.dx = CGFloat(dir) * Self.throwDistance
                } else {
                    g.dx = 0
                }
            }
    }

    /// Measures the top card against window space and hands it to the morph. `nil` when there is
    /// nothing to measure — the model's own fallback is a plain zoom, a designed path not a bug.
    private func open() {
        let rect = topCardRect.rect
        let ok = rect.width > 0 && rect.height > 0
        model.openFlight(from: ok ? rect : nil)
    }

    /// The front face's own affordance for turning the card over — the long-press keeps working
    /// (`runHoldTimer()`), this is just a second, discoverable way to reach the same state.
    private func flipCard() {
        guard canGesture else { return }
        g.flipped = true
    }

    /// A round "turn this over" control, sitting on the same line as `DeckOpenAffordance` and
    /// immediately after it. `dragGesture` reads `flipButtonRect` so its own tap-to-open never
    /// fires underneath this one — see the comment there.
    ///
    /// **Not in the reference, and deliberately so.** The reference turns a card over with a 480ms
    /// long press and draws no control for it at all; that press still works here. This is the
    /// second, discoverable way in, asked for explicitly, and it belongs beside the play button
    /// rather than in the top-trailing corner it used to occupy — one row of card controls, not
    /// two opposite corners of one.
    private var flipButton: some View {
        IconButton(tone: .onDark, size: .sm, label: "Flip card", action: flipCard) {
            Image(systemName: "arrow.2.squarepath")
                .font(.system(size: 15, weight: .medium))
        }
        // The same rim `DeckOpenAffordance` wears. Without it this disc was 14% white next to
        // a 20% disc with a 40% border, and on every entrance — the deal, the morph's close —
        // the two faded in on one clock but the fainter one *read* as arriving second.
        .overlay {
            Circle().strokeBorder(Color.white.opacity(0.4), lineWidth: 1.5)
                .allowsHitTesting(false)
        }
        .measureRect(into: flipButtonRect, in: TStage.space)
    }

    /// The deck card's 3D flip, wrapping the front face and swapping in `back` at the instant the
    /// card is edge-on — CSS `backface-visibility: hidden`, rather than a cross-fade.
    ///
    /// **There is exactly one clock.** This used to swap which face was *drawn* on a
    /// `Task.sleep` timed to fire when the animation was expected to reach 90° — a hand-derived
    /// constant (`0.64s * 0.20`) assuming `Animation.glide`'s own bezier and that the transaction
    /// started in the same runloop tick as the timer. Both assumptions were already fragile with
    /// one call site (the hold gesture); a second call site (the flip button) is exactly the kind
    /// of change that desyncs a parallel clock like that. `Animatable.animatableData` sidesteps
    /// the whole class of bug: `angle` here *is* the same value SwiftUI is actively interpolating
    /// for `rotation3DEffect` below, read back at every intermediate frame of the animation, so
    /// "edge-on" is computed from the actual live rotation rather than guessed from a duration —
    /// correct for any curve, any duration, and any call site that ever sets `flipped`.
    private struct DeckFlipEffect: ViewModifier, Animatable {
        var angle: Double
        let back: DeckCardBack

        var animatableData: Double {
            get { angle }
            set { angle = newValue }
        }

        func body(content: Content) -> some View {
            let showBack = angle > 90
            ZStack {
                content.opacity(showBack ? 0 : 1)
                // The back's own 180° turn is a *pre-orientation*, not a second camera shot: it
                // exists only so that, once the whole ZStack below rotates by the live `angle`,
                // the back's total attitude (180 + angle) comes out right-reading instead of
                // mirrored. The reference gets this for free — CSS `perspective` is one property
                // set on an ancestor three levels up (`perspective:1400` on the card's outer
                // div), so the browser projects the *combined* rotateY(180)×rotateY(angle) matrix
                // exactly once. `rotation3DEffect(perspective:)` has no such ancestor form: the
                // parameter is baked into that one call's own matrix, so passing a non-zero value
                // here as well as on the outer call below made SwiftUI apply two separate
                // projective divides to the back face — correct at the two rest states (0 and
                // 180, where the extra divide degenerates to identity) but visibly warped
                // everywhere in between, which is exactly the second half of every turn (the
                // half where the back is the one on screen). `perspective: 0` makes this call a
                // pure, flat rotation — no vanishing point of its own — so the only projection
                // applied anywhere is the outer call's, matching the reference's single ancestor
                // perspective. `StatusCard`/`ShopItemScreen` carry the same doubled perspective
                // on their own flips and read fine there only because they swap faces with a
                // discrete `Task.sleep` timer instead of a live `Animatable` angle — two rendered
                // frames, not sixty, so the mid-turn warp never gets a chance to show.
                back
                    .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0), perspective: 0)
                    .opacity(showBack ? 1 : 0)
                    .allowsHitTesting(showBack)
            }
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0),
                              perspective: CardArt.flipPerspective)
        }
    }

    /// One transform per card: rotation, scale and offset, branched at the *value* level (top vs
    /// back) rather than the view level, so every card is built through the same modifier chain
    /// and keeps its SwiftUI identity when `advanceDeck()` moves it from index 0 to the back.
    private struct CardPose: Equatable {
        var x: CGFloat
        var rotation: Double
        var scale: CGFloat
        var y: CGFloat
    }

    @ViewBuilder
    private func cardView(task: TaskItem, i: Int) -> some View {
        let top = i == 0
        let prog = min(1, abs(g.dx) / 150)
        let d = max(0, Double(i) - Double(prog))
        let muted = d > 0.5
        let face = DeckCardFace(title: task.title, bg: tint(d), muted: muted, liveDrag: g.live) {
            if top { flipButton }
        }

        // The back face (hold-to-flip, or the flip button) is only ever shown on the top card,
        // but it has to stay in every card's view tree — not behind an if/else — for the same
        // identity-preservation reason as the pose below.
        let flipped = top && g.flipped

        let pose: CardPose = top
            ? CardPose(x: g.dx, rotation: Double(g.dx) * 0.04, scale: 1, y: 0)
            : CardPose(x: 0, rotation: d * 3.2, scale: CGFloat(1 - d * 0.05), y: -CGFloat(d) * 30)
        let poseAnim: Animation? = top ? topOffsetAnimation : (g.live ? nil : .glide(0.36))
        // Only the top card's opacity ever animates (the throw fade). A back card has no opacity
        // transition at all, so a card landing at the back after a throw snaps straight to full
        // opacity while its pose glides — it reads as sliding back in from off-screen.
        let opacity: Double = top ? (g.throwDir != 0 ? 0 : 1) : 1
        let opacityAnim: Animation? = top ? topOpacityAnimation : nil

        face
            .modifier(DeckFlipEffect(angle: flipped ? 180 : 0, back: DeckCardBack(
                task: task,
                onEdit: {
                    g.flipped = false
                    model.editTask = task
                    model.addSheet = true
                },
                onDelete: {
                    g.flipped = false
                    model.deleteTask(id: task.id)
                },
                onTurnBack: { g.flipped = false }
            )))
            .animation(top ? .glide(Self.flipDuration) : nil, value: flipped)
        // Opacity's animation sits inner to the pose's, so a nil opacity animation (the back-card
        // case) can never clobber the pose animation attached outside it in the same transaction.
        .opacity(opacity)
        .animation(opacityAnim, value: opacity)
        // `translateY() scale() rotate()` in CSS applies right-to-left, so the translate is the
        // outermost transform. SwiftUI applies modifiers bottom-up, so the same order reads
        // reversed here: rotate innermost, then scale, then translateY, then translateX outermost.
        .rotationEffect(.degrees(pose.rotation), anchor: .bottom)
        .scaleEffect(pose.scale, anchor: .bottom)
        .offset(y: pose.y)
        .offset(x: pose.x)
        .animation(poseAnim, value: pose)
        .frame(maxWidth: .infinity)
        .zIndex(Double(9 - i))
        .modifier(CardEntranceModifier(kind: entranceKind(i: i, taskID: task.id)))
        // **Last in the chain, and that is the whole point.** This used to sit immediately under
        // the face, *inside* the pose's `.rotationEffect`/`.scaleEffect`/`.offset` above. Those
        // are render transforms — they leave the layout frame alone, but they do carry a
        // descendant `GeometryReader`'s `.global` frame with them, so the drag's offset and its
        // rotation baked straight into the rect `open()` hands the morph. The symptom was a
        // copper rect that grew from off to one side: tap a card inside the 300 ms settle after a
        // cancelled swipe, or tap the incoming card while it is still gliding up from the back of
        // the deck, and the last thing written was a mid-animation pose rather than a resting
        // card. Out here the measurement is of the layout slot, which no pose and no entrance
        // ever moves — identical to the old reading at rest, and correct during motion.
        .measureRect(into: top ? topCardRect : deckScratchRect, in: TStage.space)
    }

    private var topOffsetAnimation: Animation? {
        g.dragging ? nil : (g.throwDir != 0 ? .exit(0.22) : .glide(0.30))
    }

    /// The reference's own pairing, confirmed against `app.jsx`: thrown, `transform 220ms {EX},
    /// opacity 170ms linear`; settling back, `transform 300ms {E}, opacity 200ms linear` — the
    /// transform eases (`.exit`/`.glide` above), the opacity fades at a flat linear rate. Not a
    /// stray `.linear`.
    private var topOpacityAnimation: Animation? {
        g.throwDir != 0 ? .linear(duration: 0.17) : .linear(duration: 0.20)
    }

    private func entranceKind(i: Int, taskID: String) -> CardEntrance {
        if model.deal { return .deal(delayMs: Double(Self.depth - 1 - i) * 95) }
        if i == 0, model.dropID == taskID { return .drop }
        return .none
    }

    private func tint(_ d: Double) -> Color {
        let i = max(0, min(Self.ramp.count - 2, Int(d.rounded(.down))))
        let t = max(0.0, min(1.0, d - Double(i)))
        let a = Self.ramp[i]
        let b = Self.ramp[i + 1]
        return Color(
            red: (a.0 + (b.0 - a.0) * t) / 255,
            green: (a.1 + (b.1 - a.1) * t) / 255,
            blue: (a.2 + (b.2 - a.2) * t) / 255
        )
    }

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        let content = VStack(spacing: 0) {
            Text(model.homeAirport.city)
                .font(TFont.core(.bold, 44))
                .tracking(-0.05 * 44)
                .foregroundStyle(TColor.navy700)

            HStack(spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    MilesTicker(value: model.pool)
                        .font(TFont.core(.bold, 26))
                        .foregroundStyle(TColor.textAccent)
                        .monospacedDigit()
                    Text("mi")
                        .font(TFont.data(.medium, 14))
                        .foregroundStyle(TColor.textAccent)
                        .opacity(0.75)
                }

                Button {
                    model.statusIntro = nil
                    model.go(.status, .lift, dir: 1)
                } label: {
                    Text(model.status.tier.name.uppercased())
                        .tpLabelStyle()
                        .foregroundStyle(TColor.steel700)
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(Capsule().fill(TColor.sky200))
                }
            }
            .padding(.top, 12)
        }
        .padding(.top, 2)

        if model.deal {
            ORise(i: 2) { content }
        } else {
            content
        }
    }

    // MARK: - Async seams

    /// The hold-to-flip timer: 480 ms unbroken by movement or release. `.task(id:)` bound to
    /// `pressToken` means a fresh press automatically supersedes (cancels) whatever the previous
    /// one was waiting on — the same contract as the reference's `clearTimeout`.
    private func runHoldTimer() async {
        guard g.pressToken > 0 else { return }
        try? await Task.sleep(for: .milliseconds(480))
        guard !Task.isCancelled, g.dragging, !g.movedPastHoldThreshold else { return }
        g.dragging = false
        g.dx = 0
        g.flipped = true
    }

    /// `-tempusMorphDrag <points>`: shove the top card sideways, then open the morph from the
    /// card's own measured rect.
    ///
    /// The only seam that exercises the measurement — `-tempusMorph` hands `openFlight` a literal
    /// written down in `LaunchSeams`, so it cannot see this class of bug at all. What it pins is
    /// that a *displaced* card still opens from where the card rests: the morph used to be handed
    /// a rect with the drag transform baked in, and the copper rect grew from off to one side.
    /// Watch where the rect starts, not where it ends — both runs end full-screen.
    private func runMorphDragSeam() async {
        guard let dx = model.seamMorphDrag else { return }
        model.seamMorphDrag = nil
        // The deck has to be laid out before there is a card to measure, and the measurement has
        // to have had a frame to land — same beat `-tempusMorph` waits for the same reason.
        try? await Task.sleep(for: .milliseconds(2600))
        guard !Task.isCancelled, !model.tasks.isEmpty else { return }
        withAnimation(.glide(0.30)) { g.dx = dx }
        // Long enough that the card is visibly over there when the morph fires, short enough that
        // the settle has not taken it home again.
        try? await Task.sleep(for: .milliseconds(320))
        guard !Task.isCancelled else { return }
        open()
    }

    /// A committed throw holds 210 ms off-screen before the deck actually advances.
    private func runThrowAdvance() async {
        guard g.throwDir != 0 else { return }
        try? await Task.sleep(for: .milliseconds(210))
        guard !Task.isCancelled else { return }
        model.advanceDeck()
        g.throwDir = 0
        g.dx = 0
    }

    private static let flipDuration: Double = 0.64

    /// The deck deals itself in once and then stops announcing it, exactly as the reference's own
    /// `useEffect([deal])` clears the flag 2200 ms after it was set.
    private func runDealClear() async {
        guard model.deal else { return }
        try? await Task.sleep(for: .milliseconds(2200))
        guard !Task.isCancelled else { return }
        model.deal = false
    }
}

// MARK: - Gesture state

/// The deck's touch-driven state: horizontal drag, throw-out, and the hold-to-flip gesture.
///
/// A reference type on purpose. This screen mutates it from drag callbacks and from delayed
/// `.task` continuations, and CLAUDE.md already paid for the lesson that mutating plain `@State`
/// through an escaping closure's copy of the view can silently fail to invalidate the live one —
/// that is how the tear gesture once moved nothing at all. A class sidesteps it: every copy of
/// this `View` struct holds the same instance, so a write from any of them is always visible.
@Observable
private final class DeckGesture {
    /// Horizontal offset of the top card, in points. Also drives how far the cards behind it fan.
    var dx: CGFloat = 0
    /// A pointer is currently down on the deck.
    var dragging = false
    /// True once the current press has moved past the 8pt hold-cancelling threshold.
    var movedPastHoldThreshold = false
    /// Bumped on every new press; see `HomeScreen.runHoldTimer`.
    var pressToken = 0
    /// −1 / 0 / 1 — the top card is flying off-screen in this direction.
    var throwDir = 0
    /// The top card is showing its edit/delete back face. Which face is actually *drawn* at any
    /// instant is derived purely from the live rotation angle animating toward this — see
    /// `DeckFlipEffect` — so there is no second, timer-driven flag to keep in sync with it.
    var flipped = false

    /// True while a gesture or a throw owns the cards' transforms. The settle transition is
    /// disabled for exactly this window so the cards track the finger (or the throw) 1:1.
    var live: Bool { dragging || throwDir != 0 }
}

// MARK: - Card entrance (deal-in / drop-in)

/// The deck's two one-shot entrance plays. Deal-in drops every visible card in from below,
/// deepest first; drop-in drops only a freshly-added top card in from above. Both compose with
/// the card's own live transform rather than replacing it, because in the reference they animate
/// two separate nested elements — the outer wrapper (this) plays the entrance, the inner one (the
/// card's own drag/fan transform) is untouched by it.
private enum CardEntrance {
    case none
    case deal(delayMs: Double)
    case drop
}

private struct CardEntranceModifier: ViewModifier {
    let kind: CardEntrance
    @State private var arrived: Bool

    init(kind: CardEntrance) {
        self.kind = kind
        switch kind {
        case .none: _arrived = State(initialValue: true)
        default: _arrived = State(initialValue: false)
        }
    }

    func body(content: Content) -> some View {
        content
            .offset(y: arrived ? 0 : startOffset)
            .rotationEffect(.degrees(arrived ? 0 : startRotation), anchor: .center)
            .task {
                switch kind {
                case .none:
                    break
                case .deal(let delayMs):
                    if delayMs > 0 { try? await Task.sleep(for: .milliseconds(Int(delayMs))) }
                    guard !Task.isCancelled else { return }
                    withAnimation(.glide(0.62)) { arrived = true }
                case .drop:
                    withAnimation(.glide(0.56)) { arrived = true }
                }
            }
    }

    private var startOffset: CGFloat {
        switch kind {
        case .deal: return 640
        case .drop: return -580
        case .none: return 0
        }
    }

    private var startRotation: Double {
        switch kind {
        case .deal: return 6
        case .drop: return -5
        case .none: return 0
        }
    }
}

// MARK: - Card faces

/// The deck card's face — `TaskCard`'s layout minus the per-card miles readout, which the deck
/// drops because the stack peeks off-page and would clip a corner number; the earn preview lives
/// on Preflight instead.
private struct DeckCardFace<Accessory: View>: View {
    let title: String
    let bg: Color
    let muted: Bool
    /// Suppresses the background-colour transition while a gesture or throw is live, matching the
    /// card's own transform (which the caller separately gates the same way).
    let liveDrag: Bool
    /// Sits on the same line as the open affordance, to its trailing side. Empty on every card but
    /// the top one, which puts its flip control here.
    @ViewBuilder var accessory: Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // **No subtitle line.** The reference prints a free-text `meta` here — "Deadline 15
            // Aug", "Problem set 4" — and offers nothing anywhere that can write one: the add and
            // rename sheet takes a title and nothing else. A card that states a deadline the
            // member cannot set, change or clear is the Concourse search field's dead control
            // again, so the line is gone and `TaskItem` no longer carries one.
            //
            // **One spacer, above — the title block is bottom-anchored.** A second spacer below
            // it was added to centre the group once the meta line went, on the theory that a
            // bottom-weighted card reads as content jammed against an edge. It does not: measured
            // against the reference running in a browser, the top card's open affordance sits
            // exactly 24pt above the card's bottom edge — its `flex:1` spacer is the only one on
            // the card and pushes title and affordance flush to the bottom padding. Centring lifted
            // the affordance ~90pt up a 370pt card and is what "the play button is too far up"
            // reports. Measurement, not taste: the card is a fixed box with one flexible gap in it.
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(TFont.core(.bold, 38))
                    .tpType(size: 38, track: -0.045, lineHeight: 1.02)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    DeckOpenAffordance()
                    accessory
                }
                .padding(.top, 22)
            }
            .opacity(muted ? 0.55 : 1)
            .animation(.linear(duration: 0.3), value: muted)
        }
        .padding(.horizontal, 26)
        .padding(.top, 26)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, minHeight: 370, alignment: .topLeading)
        // The reference's card is absolutely positioned, so it is exactly as tall as its
        // content (370 at the minimum: a 320 content box plus its 26/24 padding, which
        // content-box sizing puts outside that minimum) and the deck area centres it. Without this the card's
        // `Spacer` stretches it to fill the whole deck, dropping the title 50pt down the page.
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(TColor.textOnAccent)
        .background(bg)
        .animation(liveDrag ? nil : .glide(0.36), value: bg)
        .clipShape(RoundedRectangle(cornerRadius: TRadius.xl, style: .continuous))
        .tpShadow(.raised)
    }
}

/// The 46×46 "open" affordance on the deck card: a translucent circle with a right chevron drawn
/// as a plain triangle, matching the reference's CSS border-triangle rather than an SF Symbol
/// (which would not sit as tightly against the circle's rim).
private struct DeckOpenAffordance: View {
    var body: some View {
        ZStack {
            Circle().fill(Color.white.opacity(0.2))
            Circle().strokeBorder(Color.white.opacity(0.4), lineWidth: 1.5)
            RightChevronTriangle()
                .fill(Color.white.opacity(0.95))
                .frame(width: 14, height: 18)
                .offset(x: 2)
        }
        // 49, not 46: the reference's circle is `width:46;height:46` with a `1.5px` border under
        // content-box sizing, so the border sits *outside* the 46 and the drawn circle measures 49
        // (confirmed against the running reference). SwiftUI's `strokeBorder` insets instead, so
        // the frame has to carry the border's own 3pt.
        .frame(width: 49, height: 49)
    }
}

private struct RightChevronTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: 0, y: 0))
            p.addLine(to: CGPoint(x: rect.width, y: rect.height / 2))
            p.addLine(to: CGPoint(x: 0, y: rect.height))
            p.closeSubpath()
        }
    }
}

/// The deck card's back — edit, delete or turn back. Only the top card ever renders this, behind
/// a 3D flip triggered by a hold or by the front face's flip button.
///
/// **Turning back is a control, not a hint.** The way out used to be a 14pt line of `textMuted`
/// text at the very bottom of the card, which does not read as a button next to the two capsules
/// above it — a card you can turn over and apparently cannot turn back is a dead end. The round
/// control in the corner, where a dismiss lives, now carries that duty and reads as what it is.
/// A second, full-width "Turn back over" capsule used to sit below Edit/Delete doing the same
/// job — it was cut, not just to trim a redundant control, but because it was also the tallest
/// row on the card: with the week's goal strip and a tier-ending notice both showing above the
/// deck, and a task title long enough to wrap twice, that extra row was what pushed Edit/Delete
/// down under the floating nav. One way out at the top is enough, and it fits.
private struct DeckCardBack: View {
    let task: TaskItem
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onTurnBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The title and the turn-back button share one row, so the two read as a header —
            // stacked, the title sat 14pt under a button floating in its own band.
            HStack(alignment: .center, spacing: 12) {
            Text(task.title)
                .font(TFont.core(.bold, 26))
                .tpType(size: 26, track: -0.035, lineHeight: 1.1)
                .foregroundStyle(TColor.textPrimary)
                // Capped at three lines — the extreme this face is designed and tested for.
                // Nothing upstream limits a subject's length, and `minHeight: 370` below only
                // has room for a title that wraps that far: an uncapped `Text` plus `fixedSize`
                // means the *card itself* grows with every extra line, and it is exactly that
                // growth — stacked under the goal strip and a tier notice, which already eat
                // into the room above the deck — that used to carry Edit/Delete down under the
                // floating nav. Three lines of this title comfortably fits inside the 370pt
                // floor on its own; the cap exists to keep a longer one from silently pushing
                // past it.
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                Button(action: onTurnBack) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(TColor.textSecondary)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(TColor.surfaceSunken))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Turn the card back over")
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Button(action: onEdit) {
                    Text("Edit")
                        .font(TFont.core(.semibold, 15))
                        .foregroundStyle(TColor.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .overlay(Capsule().strokeBorder(TColor.borderDefault, lineWidth: 1.5))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)

                Button(action: onDelete) {
                    Text("Delete")
                        .font(TFont.core(.semibold, 15))
                        .foregroundStyle(TColor.statusDiverted)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Capsule().fill(TColor.statusDivertedSoft))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
        // The card's painted box hangs 52pt off the right of the screen (see the deck's
        // `.padding(.trailing, -52)`), and the front face is designed for that. The back face is
        // controls, and a control half under the bezel is not a control — so its content is
        // inset by the overhang and lives in the visible width. The card itself does not move.
        .padding(.trailing, 52)
        .padding(.top, 26)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, minHeight: 370, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .background(TColor.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TRadius.xl, style: .continuous))
        .tpShadow(.raised)
    }
}

// MARK: - Tier-ending notice

/// Announced once, on the way in: a tier that will not carry into the next 90-day period unless
/// more hours land before it closes.
private struct HomeNoticeBanner: View {
    let title: String
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(TColor.statusDelayed)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(TFont.core(.semibold, 15))
                    .tpType(size: 15, lineHeight: 1.3)
                    .foregroundStyle(TColor.textPrimary)
                Text(message)
                    .font(TFont.core(.regular, 14))
                    .tpType(size: 14, lineHeight: 1.45)
                    .foregroundStyle(TColor.textSecondary)
            }

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Color(hex: 0x8a6531))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(TColor.statusDelayed.opacity(0.16)))
            }
            .accessibilityLabel("Dismiss")
        }
        .padding(16)
        .background(TColor.statusDelayedSoft)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 24)
        .padding(.top, 18)
    }
}

