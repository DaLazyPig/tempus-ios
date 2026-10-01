import SwiftUI

/// The short-screen canvas — see `TStage`. On a window shorter than `TStage.designHeight` the app
/// is hosted in its own `UIHostingController` laid out `1 / scale` times larger, and UIKit scales
/// that controller's view down to the window. On anything taller it is not applied at all.
///
/// **The hosted app gets no safe area at all** (`safeAreaRegions = []`). The iPad's compatibility
/// window has real insets — 20 top, 25 bottom — and build 46 hid them from the canvas with a
/// `GeometryReader` that ignored the safe area. That held at rest and leaked mid-transition: every
/// Fly → Club `lift` on an iPad drew Status Club a status bar too low for ~60 ms and then snapped it
/// up, while its fade ran on (measured frame by frame, 29 Sep 2026). A full-bleed layer's
/// `ignoresSafeArea` is withheld for a pass whenever the stack gains a sibling — the same failure
/// `RootView`'s layer sizing documents — and a scaled canvas has no way to stop real insets
/// arriving during that pass. A host that has none cannot leak them; with them gone every `lift` was
/// smooth, cold and warm. The screens clear the status bar with their own top padding, as they did
/// on build 46, and `TSafeArea` still reports the window's insets for the few places that read them.
/// The keyboard's region goes with the rest — `KeyboardTracker` draws the one lift this app needs.
///
/// The scale is a `UIView` transform rather than a SwiftUI `scaleEffect` so the safe area can be
/// switched off at a hosting-controller boundary, which only UIKit has.
struct StageRoot<Content: View>: View {
    @Environment(AppModel.self) private var model
    @ViewBuilder var content: () -> Content

    var body: some View {
        if TStage.scale < 1 {
            StageHost(content: content)
                .ignoresSafeArea()
                // The hosted `RootView` asks for this too, but a nested host's preference never
                // reaches the window — and the status bar follows the window.
                .preferredColorScheme(model.barDark ? .dark : .light)
        } else {
            content()
        }
    }
}

private struct StageHost<Content: View>: UIViewControllerRepresentable {
    let content: () -> Content

    func makeUIViewController(context: Context) -> StageHostController<Content> {
        StageHostController(root: content())
    }

    func updateUIViewController(_ controller: StageHostController<Content>, context: Context) {
        controller.host.rootView = StageSpace(content: content())
    }
}

private final class StageHostController<Content: View>: UIViewController {
    let host: UIHostingController<StageSpace<Content>>

    init(root: Content) {
        host = UIHostingController(rootView: StageSpace(content: root))
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        host.safeAreaRegions = []
        host.view.backgroundColor = .clear
        addChild(host)
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let s = TStage.scale
        // `frame` is undefined under a transform; bounds and centre are not.
        host.view.transform = .identity
        host.view.bounds = CGRect(x: 0, y: 0, width: view.bounds.width / s, height: view.bounds.height / s)
        host.view.center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        host.view.transform = CGAffineTransform(scaleX: s, y: s)
    }

    override var childForStatusBarStyle: UIViewController? { host }
    override var childForStatusBarHidden: UIViewController? { host }
    override var childForHomeIndicatorAutoHidden: UIViewController? { host }
}

/// Stage coordinates for everything measured inside the canvas — see `TStage.space`.
private struct StageSpace<Content: View>: View {
    let content: Content

    var body: some View {
        content.coordinateSpace(name: TStage.spaceName)
    }
}

/// The router.
///
/// While a transition is running, **two layers render** — the phase being left and the phase being
/// entered — each with its own ground and its own animation. Everything else in the app is an
/// overlay stacked on top of those layers in a fixed order.
struct RootView: View {
    @Environment(AppModel.self) private var model
    /// Only ever handed to `ScreenWarm`: a screen it builds off-screen reads the same environment
    /// the app injects, and a missing one traps inside `ImageRenderer`.
    @Environment(Billing.self) private var billing
    @Environment(Identity.self) private var identity
    @Environment(Backend.self) private var backend

    var body: some View {
        GeometryReader { viewport in
            router(in: viewport)
        }
    }

    private func router(in viewport: GeometryProxy) -> some View {
        @Bindable var model = model
        let insets = viewport.safeAreaInsets
        let full = CGSize(width: viewport.size.width + insets.leading + insets.trailing,
                          height: viewport.size.height + insets.top + insets.bottom)
        let bleed = EdgeInsets(top: -insets.top, leading: -insets.leading,
                               bottom: -insets.bottom, trailing: -insets.trailing)

        return ZStack {
            // The window's own ground, so nothing shows through during a transform.
            ground.ignoresSafeArea()

            // 1–3: the phase layers.
            ZStack {
                // Identity is the phase, not the role. The layers are a `ForEach` keyed on phase
                // so that a layer can go settled → outgoing, or incoming → settled, as a change
                // of props on the *same* view. An `if trans { two } else { one }` reads the same
                // but is two structural positions: SwiftUI tore both screens down and rebuilt
                // them at every cut — the arriving screen replayed its whole entrance when the
                // transition ended, and the leaving one flashed as it was recreated.
                ForEach(layers, id: \.phase) { layer in
                    PhaseLayer(phase: layer.phase, role: layer.role, transition: model.trans,
                               ground: groundFor(layer.phase))
                        // Resolve layout before StageEffect transforms it. Negative padding
                        // places full-bleed content at the window origin while reporting the
                        // same safe-area size as every other phase to the stack. An overlay
                        // mounting/unmounting must not renegotiate this through ignoresSafeArea.
                        .frame(width: layer.phase.fullBleed ? full.width : viewport.size.width,
                               height: layer.phase.fullBleed ? full.height : viewport.size.height)
                        .padding(layer.phase.fullBleed ? bleed : EdgeInsets())
                        .zIndex(layer.z)
                        .allowsHitTesting(layer.role != .outgoing)
                        .transition(.identity)
                }
            }
            // `== .open`, not `!= nil`: the reference keys the stage's transform on `pay==='open'`
            // (app.jsx:5653), so the stage starts restoring the moment the close begins and runs its
            // 620 ms alongside the sheet's 420 ms exit. Keyed on `!= nil` it waited for the sheet to
            // be gone and *then* eased back — a screen that visibly shifted after the sheet had left.
            .modifier(StageEffect(gateUp: model.gateUp, paywall: model.paywall == .open))
            // **A screen uncovered is not a screen arrived at.** The card studio leaves by
            // `goDirect(.status)` under an opaque copy of itself, so Status Club is a *freshly
            // mounted* phase layer and every `Rise` on it duly played its 460 ms entrance, staggered
            // up to 280 ms — the last card settling around 907 ms. The overlay above it is gone at
            // ~536 ms. So the studio finished fading and handed over to a page that had not drawn
            // itself yet: ~230 ms of bare `sky100`, then the cards rising into it. That is the
            // flicker, measured frame by frame — not a colour mismatch and not an un-eased cut, but
            // an entrance playing underneath the thing that was hiding it.
            //
            // Returning from a modal is not an arrival, and the reference never replays this
            // entrance because its studio is an overlay Status Club sits under the whole time.
            // While `cardDesignOut` is set, risers mount already revealed — so the page is complete
            // the instant the overlay starts to thin, and the fade uncovers a finished screen.
            .environment(\.tpSuppressRise, model.cardDesignOut != nil)

            // 12: the docked nav.
            NavSlot(show: navVisible) {
                FloatingNav(
                    value: model.phase,
                    // Club always lifts up, Fly always lifts down.
                    onChange: { next in model.go(next, .lift, dir: next == .status ? 1 : -1) },
                    onAdd: { model.addSheet = true }
                )
            }
            .zIndex(12)
            .transition(.identity)

            // 14: the leaving card studio, which belongs to Status Club and nothing else.
            if model.cardDesignOut != nil, model.phase == .status {
                CardDesignScreen(exiting: true)
                    // The exit copy uses the same viewport and origin as its phase layer.
                    .frame(width: full.width, height: full.height)
                    .padding(bleed)
                    .allowsHitTesting(false)
                    .zIndex(14)
                    .transition(.identity)
            }

            // 18: business class stayed open.
            if model.stayOpenToast {
                StayOpenToast().zIndex(18).transition(.identity)
            }

            // 19–20: the copper card ⇄ screen morph.
            if let morph = model.morph {
                MorphRect(morph: morph) { model.morphFinished() }
                    .zIndex(20)
                    .transition(.identity)
            }

            // 22: a consent gate.
            if let gate = model.gate {
                GateScreen(gate: gate).zIndex(22).transition(.identity)
            }

            // 26: the paywall.
            if model.paywall != nil {
                PaywallSheet().zIndex(26).transition(.identity)
            }

            // 30: the circle reveal.
            if let circle = model.circle {
                CircleRevealView(reveal: circle,
                                 onCovered: { model.circleCovered() },
                                 onGone: { model.circleGone() })
                    .zIndex(30)
                    .transition(.identity)
            }

            // 40: naming a subject, or renaming one. The reference stamps this surface above
            // the gate, the paywall and the reveal, and it is a pill over a flat scrim rather
            // than a system sheet — so it stacks here like every other floating surface, and
            // draws the one scrim the reference draws instead of sitting on the system's own.
            if model.addSheet {
                AddSheet().zIndex(40).transition(.identity)
            }

            // 62: a payment awaiting confirmation.
            if model.payFlow != nil {
                PaySheet().zIndex(62).transition(.identity)
            }
        }
        // Keep the root's reported size at the safe-area proposal even while a full-screen
        // sibling is mounted. Centring safe-area screens in a larger root shifts them at rest.
        .frame(width: viewport.size.width, height: viewport.size.height)
        .background(ground)
        .preferredColorScheme(model.barDark ? .dark : .light)
        .animation(.glide(TDur.base), value: navVisible)
        .animation(.glide(TDur.base), value: model.addSheet)
        .sheet(isPresented: $model.airportSheet) { AirportSheet() }
        .onAppear { ScreenWarm.begin(model, billing, identity, backend) }
    }

    private struct Layer {
        let phase: Phase
        let role: LayerRole
        let z: Double
    }

    /// One layer when settled, two while a transition is drawing.
    private var layers: [Layer] {
        guard let t = model.trans else {
            return [Layer(phase: model.phase, role: .settled, z: 0)]
        }
        return [Layer(phase: t.from, role: .outgoing, z: Double(zIndex(t.type, .outgoing))),
                Layer(phase: model.phase, role: .incoming, z: Double(zIndex(t.type, .incoming)))]
    }

    /// The ground each phase paints. The card studio takes the colour of the face being designed.
    /// The window and both layers all read this, so an outgoing layer, an incoming one and the
    /// ground behind them can never disagree about what colour the screen is.
    private func groundFor(_ phase: Phase) -> Color {
        switch phase {
        case .carddesign: return model.cardDesignGround
        case .preflight, .pass, .flying: return TColor.navy700
        case .settings: return TColor.white
        // Status Club's body paints `sky100` so its white cards separate from the page. The
        // router's ground has to agree with the screen's own: where the two differ, the
        // difference shows for exactly as long as a transform is running — which is the whole
        // of every transition, and the class of bug that made the card studio's exit flash.
        case .status: return TColor.sky100
        default: return TColor.cloud100
        }
    }

    private var ground: Color { groundFor(model.phase) }

    /// The nav is docked on Fly and Club only, and never over a set-piece — so a reveal never
    /// shows a nav sliding away underneath it.
    private var navVisible: Bool {
        guard model.phase == .home || model.phase == .status else { return false }
        if model.morph != nil { return false }
        if let c = model.circle, c.next != .home, c.next != .status { return false }
        return true
    }

    private func zIndex(_ type: TransitionType, _ role: LayerRole) -> Int {
        switch (type, role) {
        case (.push, .incoming): return 2
        case (.push, .outgoing): return 1
        case (.zoom, .incoming): return 1
        case (.zoom, .outgoing): return 3
        case (.cover, .incoming): return 3
        case (.cover, .outgoing): return 1
        case (.lift, .incoming): return 2
        case (.lift, .outgoing): return 1
        case (.perm, .incoming): return 3
        case (.perm, .outgoing): return 1
        case (.permout, .incoming): return 1
        case (.permout, .outgoing): return 3
        case (.sink, .incoming): return 1
        case (.sink, .outgoing): return 3
        case (.uncover, .incoming): return 1
        case (.uncover, .outgoing): return 3
        default: return role == .incoming ? 1 : 3
        }
    }
}

enum LayerRole { case incoming, outgoing, settled }

/// One phase, drawn on its own ground, playing whichever half of the transition belongs to it.
private struct PhaseLayer: View {
    let phase: Phase
    let role: LayerRole
    let transition: Transition?
    /// Handed down rather than derived. This used to be a second copy of `RootView.ground`'s
    /// switch, and the two had drifted: the card studio was missing here, so its layer painted
    /// the default `cloud100` while the window behind it painted the face's own ground. The
    /// screen ignores the safe area and the layer did not, so the difference showed as a pale
    /// strip under the home indicator. One switch now, in one place.
    let ground: Color

    /// Driven 0 → 1 once per run — the entrance on appear, the exit on becoming the outgoing layer.
    /// A layer that lives through incoming → settled → outgoing plays each exactly once, but two
    /// cuts fired back to back — faster than the first one's teardown — can ask the *same* layer to
    /// play the *same* role a second time without ever leaving `layers` in between (Fly ⇄ Club
    /// mashed inside `.lift`'s 560 ms window is the easy way in). `pIn`/`pOut` would already be
    /// sitting at 1 from the first run, so setting them to 1 again is a no-op: no animation fires,
    /// and the layer just snaps straight to its resting transform instead of playing it a second
    /// time. `pInKey`/`pOutKey` record which run each progress value actually belongs to, so `anim`
    /// treats a value from a stale run as 0 (the correct start-of-run look, identical to `Anim()`)
    /// until this run's own `.task` has reset it and claimed the key.
    @State private var pIn: Double = 0
    @State private var pOut: Double = 0
    @State private var pInKey: String?
    @State private var pOutKey: String?

    var body: some View {
        ScreenFor(phase: phase)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // RootView supplies the full viewport for full-bleed phases before this clip and
            // these transforms; the layer no longer negotiates safe-area expansion itself.
            // The ground paints edge to edge even though the screen is laid out inside the safe
            // area, and it does so through the same bled shape the clip below uses — **not**
            // through `ignoresSafeArea()`. A background's safe-area extension is granted at rest
            // and silently withheld while this stack holds a second layer (the same failure the
            // full-bleed note above describes), so a ground declared that way stopped at the
            // layout rect for exactly the duration of every transition. `StageClip` bleeds the
            // *clip* past that rect, but the ground it clipped stopped 62pt short: `perm`'s dome
            // was a 201pt semicircle with its top 62pt unpainted, so it arrived as a slab with
            // shoulders, cut flat at the status-bar line. A shape reads the insets at draw time
            // and paints wherever its path goes, in every layout state.
            // **The ground always bleeds, even on a full-bleed phase.** `bleeds` exists for the
            // *clip* below, whose corner geometry has to land on the real screen edge and would
            // be pushed off it by a second bleed. A flat fill has no such geometry: over-painting
            // past the window is free, and under-painting is a pale band across the status bar.
            // Which it was — on exactly one frame. The paywall is a sibling of this whole stack
            // and it ignores the safe area; the frame it unmounts, this layer's own ignore is
            // withheld for a pass (the same "stops reaching the window the moment the stack holds
            // a second member" failure the note above describes), the layer is inset by 62pt, and
            // a ground that trusted `fullBleed` stopped 62pt short. Closing Business Class over
            // Status Club flashed white across the top because of it.
            .background(StageClip(top: 0, bottom: 0, bleeds: true).fill(background))
            // **The clip goes under the transforms, not over them.** `.offset` and `.scaleEffect`
            // move what is drawn and leave the layout frame where it was, so a `.clipShape` applied
            // *after* them clips against the layer's resting rect — a stationary full-screen window
            // the moving content slides through. The rounded top was therefore always drawn at the
            // top of the screen, over nothing, while the sheet itself rose with a hard square edge:
            // `perm` read as a slab and `drip` as a squashed slab, neither of them as a droplet.
            // Clipping first makes the radius part of the content, so the transforms carry the tip
            // with the sheet and the horizontal squash narrows it the way a CSS `border-radius`
            // under `scaleX` does.
            .clipShape(StageClip(top: anim.topRadius, bottom: 0,
                                 // A full-bleed phase already has the full viewport, so its
                                 // layout rect *is* the screen — bleeding it again would push the
                                 // tip off the top edge.
                                 bleeds: !phase.fullBleed))
            // **One fade, not one fade per leaf — and one shadow, not one per leaf.** `zoom`,
            // `sink` and `lift` all cross-fade a whole screen through `anim.opacity`, and
            // SwiftUI's `.opacity` pushes down to every leaf and fades each one separately instead
            // of compositing the subtree once the way CSS does. On a screen with anything stacked
            // inside it — a page fill under a header band, a card over its own ground — the lower
            // layer stops being hidden by the upper one and bleeds up through the middle of the
            // fade. It peaks at half-faded and is gone at both ends, which is exactly what reads
            // as a flicker rather than as a slow cut, and it is the same trap `CardDesignScreen`
            // and `OBFade` already carry a group for. `.shadow` has the same shape of problem, so
            // the group sits here, under both, and above the transforms so the shadow rides the
            // sheet. At most two layers are ever mounted, so the pass is paid twice, briefly.
            .compositingGroup()
            // `perm`'s `box-shadow: 0 -30px 90px rgba(0,0,0,.5)` — the dome darkens the screen it
            // rises over. A blurred copy of the clip behind the sheet rather than `.shadow` on the
            // group, so the layers at rest carry no filter pass at all: this exists only while a
            // `perm` is in flight, and is gone — not merely transparent — the rest of the time.
            .background {
                if anim.shadow > 0 {
                    StageClip(top: anim.topRadius, bottom: 0, bleeds: !phase.fullBleed)
                        .fill(Self.permShadow.color)
                        .blur(radius: Self.permShadow.radius)
                        .offset(y: Self.permShadow.y)
                }
            }
            .scaleEffect(anim.scale)
            .offset(x: anim.x, y: anim.y)
            .opacity(anim.opacity)
            // Re-runs on appear *and* whenever the key changes, which is what an outgoing layer
            // needs: it was already on screen as the settled layer, so it never appears again.
            .task(id: animKey) {
                guard let t = transition, role != .settled else { return }
                let dur = role == .incoming ? t.type.inDuration : t.type.outDuration
                let run = curve(t.type, role).animation(dur)
                if role == .incoming {
                    pIn = 0
                    pInKey = animKey
                    if dur > 0 { withAnimation(run) { pIn = 1 } } else { pIn = 1 }
                } else {
                    pOut = 0
                    pOutKey = animKey
                    if dur > 0 { withAnimation(run) { pOut = 1 } } else { pOut = 1 }
                }
            }
    }

    private var animKey: String {
        guard let t = transition, role != .settled else { return "settled" }
        return "\(t.key)-\(role == .incoming ? "in" : "out")"
    }

    /// Onboarding paints its own ground, so its layer is transparent.
    private var background: Color { phase == .ob ? .clear : ground }

    private static let permShadow = TShadow.ShadowLayer.css(0x000000, 0.5, blur: 90, y: -30)

    private enum Curve {
        case glide, exitCurve, scene
        func animation(_ d: Double) -> Animation {
            switch self {
            case .glide: return .glide(d)
            case .exitCurve: return .exit(d)
            case .scene: return .onboarding(d)
            }
        }
    }

    /// Exits run on the exit curve; the "perm" family runs on the onboarding scene curve.
    private func curve(_ type: TransitionType, _ role: LayerRole) -> Curve {
        switch type {
        case .perm, .permout: return .scene
        case .zoom, .sink, .uncover: return role == .outgoing ? .exitCurve : .glide
        default: return .glide
        }
    }

    private struct Anim {
        var scale: CGFloat = 1
        var x: CGFloat = 0
        var y: CGFloat = 0
        var opacity: Double = 1
        var topRadius: CGFloat = 0
        /// 1 while the `perm` sheet is in flight, so the shadow is only ever cast by the dome.
        var shadow: Double = 0
    }

    private var anim: Anim {
        guard let t = transition, role != .settled else { return Anim() }
        let key = animKey
        let p = role == .incoming
            ? (pInKey == key ? pIn : 0)
            : (pOutKey == key ? pOut : 0)
        let dir = t.dir
        var a = Anim()
        // Screen extents the percentage-based keyframes are measured against.
        let w = TStage.bounds.width
        let h = TStage.bounds.height

        switch (t.type, role) {
        case (.zoom, .incoming):
            a.opacity = p
            a.scale = 0.965 + 0.035 * p
        case (.zoom, .outgoing):
            a.opacity = 1 - p
            a.scale = 1 + 0.08 * p
        case (.sink, .outgoing):
            a.opacity = 1 - p
            a.y = 28 * p
            a.scale = 1 - 0.02 * p
        case (.lift, .incoming):
            // Opacity reaches 1 at 60% of the run, while the transform keeps going.
            a.opacity = min(1, p / 0.6)
            if dir > 0 {
                a.scale = 0.94 + 0.06 * p
                a.y = 34 * (1 - p)
            } else {
                a.scale = 1.05 - 0.05 * p
                a.y = -22 * (1 - p)
            }
        case (.lift, .outgoing):
            a.opacity = 1 - p
            if dir > 0 {
                a.scale = 1 + 0.05 * p
                a.y = -22 * p
            } else {
                a.scale = 1 - 0.06 * p
                a.y = 34 * p
            }
        case (.perm, .incoming):
            a.y = h * (1 - p)
            a.topRadius = 240 * (1 - p)
            a.shadow = 1
        case (.permout, .outgoing):
            a.y = h * p
            a.topRadius = 240 * p
            a.shadow = 1
        case (.push, .incoming):
            a.x = w * 1.03 * (1 - p) * (dir > 0 ? 1 : -1)
        case (.push, .outgoing):
            a.x = w * 0.26 * p * (dir > 0 ? -1 : 1)
        case (.cover, .incoming):
            a.y = h * 1.03 * (1 - p)
        case (.uncover, .outgoing):
            a.y = h * 1.03 * p
        default:
            break
        }
        return a
    }
}

/// The one switch. An unknown phase renders nothing, exactly as the reference does.
private struct ScreenFor: View {
    @Environment(AppModel.self) private var model
    let phase: Phase
    /// Set only by `ScreenWarm`, which builds a screen to pay for its type rather than to show it,
    /// and so has no subject to hand the three flight screens. They all read the subject optionally.
    var warming = false

    var body: some View {
        switch phase {
        case .ob: OnboardingScreen()
        case .home: HomeScreen()
        case .settings: SettingsScreen()
        case .stats: AnalyticsScreen()
        case .status: StatusScreen()
        case .concourse: ConcourseScreen()
        case .carddesign: CardDesignScreen(exiting: false)
        case .linked: LinkedScreen()
        case .passes: PassesScreen()
        case .redeem: RedeemScreen()
        // The three flight phases need a subject; without one the model routes back home.
        case .preflight: if warming || model.task != nil { PreflightScreen() }
        case .pass: if warming || model.task != nil { PassScreen() }
        case .flying: if warming || model.task != nil { FlyingScreen() }
        case .landed: LandedScreen()
        }
    }
}

/// The stage's clip, expanded past its own bounds by the window's safe-area insets.
///
/// Both clips exist for one animated corner radius each — the `perm` transition's top edge and the
/// rounding the stage takes when a gate or the paywall lifts it — but a `clipShape` clips at every
/// radius, zero included. The layers are laid out inside the safe area (Home's header is 30pt from
/// the top of *that*, not of the screen), so clipping to their bounds trimmed away every screen
/// that opts out of it: onboarding paints its own navy ground edge to edge, and was cut back to a
/// strip of window ground above and below. Bleeding by exactly the insets also puts the `perm`
/// radius on the real screen edge, where the reference draws it.
private struct StageClip: Shape {
    var top: CGFloat
    var bottom: CGFloat
    var style: RoundedCornerStyle = .circular
    /// Whether the shape reaches past its own layout rect to the window's edges. True for a layer
    /// laid out inside the safe area, which has to bleed to reach the screen edge; false where the
    /// caller has already ignored the safe area and is therefore full-screen on its own.
    ///
    /// **A flag, not the insets themselves — and the window is read in `path(in:)`, never in a
    /// caller's `body`.** `TSafeArea.insets` is a live `keyWindow.safeAreaInsets` call. Passing it
    /// in as a view value made the window's own layout an *input* to the body of the view that
    /// window is laying out, and SwiftUI answered with `AttributeGraph: cycle detected` on the
    /// first render. It breaks a cycle by wedging that part of the graph, and the symptom was not
    /// a warped clip — it was a **dead router**: `RootView`'s `ForEach(layers)` never built a row
    /// for a new phase again, so Fly/Club and every header button changed `phase` while the old
    /// screen stayed on screen for good. `path(in:)` runs at draw time, outside body's dependency
    /// tracking, which is where this read has always belonged.
    var bleeds: Bool = true

    init(top: CGFloat, bottom: CGFloat, style: RoundedCornerStyle = .circular,
         bleeds: Bool = true) {
        self.top = top
        self.bottom = bottom
        self.style = style
        self.bleeds = bleeds
    }

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(top, bottom) }
        set { (top, bottom) = (newValue.first, newValue.second) }
    }

    func path(in rect: CGRect) -> Path {
        let i = bleeds ? TSafeArea.insets : .zero
        let bled = CGRect(x: rect.minX - i.left,
                          y: rect.minY - i.top,
                          width: rect.width + i.left + i.right,
                          height: rect.height + i.top + i.bottom)
        // CSS scales adjacent radii down to fit the side they share: `240px 240px 0 0` on a
        // 390–402pt screen is two 195–201pt arcs — a full semicircular dome, which is what the
        // reference's `perm` draws — not two 240pt corners overlapping in the middle.
        let t = Swift.min(top, bled.width / 2)
        let b = Swift.min(bottom, bled.width / 2)
        return UnevenRoundedRectangle(topLeadingRadius: t,
                                      bottomLeadingRadius: b,
                                      bottomTrailingRadius: b,
                                      topTrailingRadius: t,
                                      style: style).path(in: bled)
    }
}

/// The whole stage sinks and dims behind a gate, and shrinks a little behind the paywall.
private struct StageEffect: ViewModifier {
    let gateUp: Bool
    let paywall: Bool

    func body(content: Content) -> some View {
        content
            // **The clip goes under the transforms, not over them.** `.offset` and `.scaleEffect`
            // move what is drawn and leave the layout frame where it was, so a clip applied
            // *after* them is a stationary window the shrinking stage slides through. At
            // `scaleEffect(0.94)` the content sat ~25pt inside a clip drawn at the resting rect,
            // so the 40pt corners never touched it — they only began to bite in the last frames
            // as the scale came back to 1, which is a corner pop right at the end of the close,
            // at the top of the screen. Clipping first makes the corners belong to the stage and
            // travel with it.
            //
            // **And it bleeds.** Tried at `bleeds: false` on the theory that this modifier wraps
            // the whole window — it does not. Full-bleed layers report the safe-area size through
            // negative padding, so this stack's own layout rect is still the safe-area rect, and an
            // unbled clip here cuts the top 62pt off every full-bleed screen: Status Club came
            // back wearing a pale strip above its header band, which is the exact failure the
            // note on `PhaseLayer`'s own clip describes. Bleeding also puts the 40pt corners on
            // the real screen edge, which is where the reference draws them.
            .clipShape(StageClip(top: gateUp || paywall ? 40 : 0,
                                 bottom: gateUp || paywall ? 40 : 0,
                                 style: .continuous, bleeds: true))
            .scaleEffect(gateUp ? 0.93 : (paywall ? 0.94 : 1))
            .offset(y: gateUp ? -30 : (paywall ? -6 : 0))
            .brightness(gateUp ? -0.12 : 0)
            .animation(gateUp ? .onboarding(1.25) : .glide(0.62), value: gateUp)
            .animation(.glide(0.62), value: paywall)
    }
}

extension AppModel {
    /// The ground the card studio paints — the currently-chosen face for the current tier.
    var cardDesignGround: Color {
        let idx = min(status.idx, cardVariant.count - 1)
        return CardArt.ground(tier: idx, variant: cardVariant[idx])
    }
}


// MARK: - The first-build bill

/// SwiftUI charges for a screen the **first** time it is built, and the bill is large: Swift
/// instantiates the runtime metadata for that screen's whole nested generic view type and
/// AttributeGraph builds its layout descriptors. Measured on the iPhone 16e simulator, a first
/// Preflight costs 108 ms and a first Home ~300 ms; every visit after either one costs 10–17 ms.
///
/// That first bill is the reason a screen arrives as bare ground and then lands its content all at
/// once: the router has already cut to it, and the morph's copper rect has already been taken away,
/// while the screen itself is still being built. The reference has no equivalent cost anywhere —
/// JavaScript has no generic metadata to instantiate — which is why it looks smooth and this did
/// not.
///
/// So the bill is paid up front, once, while nothing is moving. `ImageRenderer` builds and lays a
/// view out **without hosting it**, so neither `onAppear` nor `.task` runs: this warms types, it
/// does not run screens. Nothing keeps the image — the point is the metadata left behind in the
/// runtime's caches, which every later build of that type hits instead of rebuilding.
/// After the add sheet's types, `KeyboardWarm` pays UIKit's first-keyboard stall on another idle
/// beat, so opening the sheet does not freeze its scrim and pill halfway through their entrances.
@MainActor
enum ScreenWarm {
    /// Preflight leads because it is the screen a set-piece uncovers, so it is the one whose bill
    /// is most visible. Onboarding and Home are absent on purpose: whichever of them the app
    /// launched into has already been built, and paid for, by the time this runs.
    private static let order: [Phase] = [
        .preflight, .pass, .flying, .landed, .status, .passes,
        .concourse, .redeem, .stats, .settings, .carddesign, .linked
    ]

    private static var started = false

    /// Idempotent: the router calls this on every appearance, and only the first one does anything.
    static func begin(_ model: AppModel, _ billing: Billing, _ identity: Identity,
                      _ backend: Backend) {
        guard !started else { return }
        started = true
        Task { @MainActor in
            // The deck deals itself in over 2.2 s. Nothing may stutter that.
            try? await Task.sleep(for: .milliseconds(2400))
            for phase in order where phase != model.phase {
                await settled(model)
                render(phase, model, billing, identity, backend)
                // A beat between screens, so the warm-up is a series of short hitches in idle time
                // rather than one long block.
                try? await Task.sleep(for: .milliseconds(120))
            }
            // The add sheet is not a `Phase` — it is a boolean overlay — so the loop above cannot
            // reach it, and it was the one surface still paying its whole first-build bill on the
            // tap that opens it. That is the delay before a subject can be typed.
            await settled(model)
            warmAddSheet(model, billing, identity, backend)
            try? await Task.sleep(for: .milliseconds(120))
            await settled(model)
            KeyboardWarm.run()
        }
    }

    /// Waits out anything that owns the frame budget. A set-piece must never share a frame with a
    /// 130 ms build — and neither may onboarding, which is where a new member spends their first
    /// minute, nor the deck's deal-in.
    ///
    /// ponytail: a finger already dragging the deck is the case this does not cover, and it costs
    /// that one gesture a single hitch, once per launch. Track a gesture flag on the model only if
    /// that ever proves visible.
    ///
    /// **The overlays count too.** The studio's exit is not a `trans` — it is `cardDesignOut`, a copy
    /// of the studio fading over Status Club — so a warm step started 60 ms into it and froze it for
    /// 350 ms: the chrome stopped half-faded, the card stopped mid-travel, and Status Club cut in
    /// when the thread came back. That was the "appears instantly" on every early return from
    /// Customise (measured 29 Sep 2026, `-tempusFPS 1`). The studio itself, the paywall, the pay
    /// sheet and the add sheet all animate on their own clocks and get the same courtesy.
    private static func settled(_ model: AppModel) async {
        while model.trans != nil || model.morph != nil || model.circle != nil || model.gate != nil
            || model.phase == .ob || model.deal
            || model.phase == .carddesign || model.cardDesignOut != nil
            || model.paywall != nil || model.addSheet || model.payFlow != nil {
            try? await Task.sleep(for: .milliseconds(120))
        }
    }

    private static func render(_ phase: Phase, _ model: AppModel, _ billing: Billing,
                               _ identity: Identity, _ backend: Backend) {
        let size = TStage.bounds.size
        let renderer = ImageRenderer(
            content: ScreenFor(phase: phase, warming: true)
                .frame(width: size.width, height: size.height)
                .environment(model)
                // Settings reads the account; an environment object a warmed screen asks for and
                // does not get is a trap in `ImageRenderer`, not a blank render. **Every object the
                // app injects has to be injected here too, and `Backend` was not** — so warming
                // Settings, 2.4 s after any launch that settles on a screen other than onboarding,
                // trapped the process with "No Observable object of type Backend found". It is a
                // launch crash that only fires once the deck has finished dealing, which is why it
                // reads as the app closing itself rather than as a crash on open.
                .environment(billing)
                .environment(identity)
                .environment(backend)
        )
        // The smallest raster that still forces the full build — the pixels are never looked at.
        renderer.scale = 0.1
        _ = renderer.uiImage
    }

    /// Same trick as `render`, for the one surface that has no `Phase` to be looked up by.
    private static func warmAddSheet(_ model: AppModel, _ billing: Billing,
                                     _ identity: Identity, _ backend: Backend) {
        let size = TStage.bounds.size
        let renderer = ImageRenderer(
            content: AddSheet()
                .frame(width: size.width, height: size.height)
                .environment(model)
                .environment(billing)
                .environment(identity)
                .environment(backend)
        )
        renderer.scale = 0.1
        _ = renderer.uiImage
    }
}
