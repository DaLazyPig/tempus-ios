import FamilyControls
import SwiftUI

/// The ten-screen arrival sequence: a deck of passes that tears itself apart, two explanations,
/// three choices, an account, a permission, the Status Club and the upgrade.
///
/// All ten screens are mounted at all times and every one of them is a function of a single
/// progress value. Nothing here uses the router's transitions: the eight crossings are set-pieces
/// with their own mechanisms — a camera push, two circle reveals off measured points, a button that
/// grows into the page — and several run different properties over different windows of the same
/// clock. `OBStyles` is that table; this file is the layout it is applied to.
struct OnboardingScreen: View {
    @Environment(AppModel.self) private var model
    @State private var flow = OnboardingFlow()

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let st = OBStyles(flow: flow, size: size)

            ZStack {
                OBCoverScreen(flow: flow, st: st, size: size)
                    .obLayer(st.layers[OBScreen.cover.i], size: size)
                    .tpDarkGround(OBConst.darkScreens.contains(.cover))
                OBEarnScreen(flow: flow, st: st, content: st.contents[OBScreen.earn.i])
                    .obLayer(st.layers[OBScreen.earn.i], size: size)
                OBSpendScreen(flow: flow, content: st.contents[OBScreen.spend.i])
                    .obLayer(st.layers[OBScreen.spend.i], size: size)
                    .tpDarkGround(OBConst.darkScreens.contains(.spend))
                OBGateScreen(flow: flow, content: st.contents[OBScreen.gate.i])
                    .obLayer(st.layers[OBScreen.gate.i], size: size)
                    .tpDarkGround(OBConst.darkScreens.contains(.gate))
                OBAppsScreen(flow: flow, content: st.contents[OBScreen.apps.i])
                    .obLayer(st.layers[OBScreen.apps.i], size: size)
                    .tpDarkGround(OBConst.darkScreens.contains(.apps))
                OBCapScreen(flow: flow, content: st.contents[OBScreen.cap.i])
                    .obLayer(st.layers[OBScreen.cap.i], size: size)
                    .tpDarkGround(OBConst.darkScreens.contains(.cap))
                OBHomeScreen(flow: flow, content: st.contents[OBScreen.home.i])
                    .obLayer(st.layers[OBScreen.home.i], size: size)
                    .tpDarkGround(OBConst.darkScreens.contains(.home))
                OBAccountScreen(flow: flow, content: st.contents[OBScreen.account.i])
                    .obLayer(st.layers[OBScreen.account.i], size: size)
                    .tpDarkGround(OBConst.darkScreens.contains(.account))
                OBClubScreen(flow: flow, st: st, content: st.contents[OBScreen.club.i])
                    .obLayer(st.layers[OBScreen.club.i], size: size)
                    // `club` is the one screen whose ground depends on the tier being shown.
                    .tpDarkGround(flow.tier.dark)
                OBShopScreen(flow: flow, content: st.contents[OBScreen.shop.i])
                    .obLayer(st.layers[OBScreen.shop.i], size: size)
                    .tpDarkGround(OBConst.darkScreens.contains(.shop))
                OBBusinessScreen(flow: flow, content: st.contents[OBScreen.business.i])
                    .obLayer(st.layers[OBScreen.business.i], size: size)
                    .tpDarkGround(OBConst.darkScreens.contains(.business))

                overlays(st: st, size: size)
            }
            .frame(width: size.width, height: size.height)
            .coordinateSpace(name: OBSpace.name)
            .clipped()
        }
        .ignoresSafeArea()
        .environment(\.obRun, OBRunner { to, seek in flow.run(to, model: model, seek: seek) })
        .task { await start() }
        // Screen Time's status answers `.notDetermined` for a moment after launch and can change
        // while onboarding is open — the gate asks for it, and a member can grant it from iOS
        // Settings mid-flow. Sampling it once puts the gate's copy and the picker's banner on
        // different answers, so it is observed rather than read.
        .task {
            for await status in AuthorizationCenter.shared.$authorizationStatus.values {
                flow.screenTimeOn = status == .approved
            }
        }
    }

    /// The three overlays every crossing shares: the flat wash, the pill that grows into the page,
    /// and the plane badge that rides the reveal's edge.
    @ViewBuilder
    private func overlays(st: OBStyles, size: CGSize) -> some View {
        let o = st.overlays

        Rectangle()
            .fill(o.veilColor)
            .opacity(o.veilOpacity)
            .allowsHitTesting(false)
            .zIndex(o.veilZ)

        // **A shape, not a `.frame` + `.position`.** The pill's insets run to −300, so the rect it
        // wants is half again the height of the screen — and a `.frame` that big inside the stage's
        // `ZStack` is a layout child larger than the container, which SwiftUI then places by its own
        // rules rather than by the point `.position` names. Measured: with the frame/position pair,
        // a pill the numbers put at y 666…875 (a capsule sitting on the Next button) drew at 0…208
        // — the same band reflected about the middle of the screen. So the crossing's ground arrived
        // as a slab across the status bar, uncovered the page below it, and read as a flicker.
        // A `Shape` takes its rect at draw time and cannot resize anything, so the insets land where
        // they are written whatever they are.
        OBExpandPill(left: o.expandLeft, top: o.expandTop, bottom: o.expandBottom,
                     radius: o.expandRadius)
            .fill(o.expandColor)
            .frame(width: size.width, height: size.height)
            .opacity(o.expandOpacity)
            .allowsHitTesting(false)
            .zIndex(39)

        OBPlaneBadge()
            .position(x: o.planeX, y: o.planeY)
            .opacity(o.planeOpacity)
            .allowsHitTesting(false)
            .zIndex(40)
    }

    /// `cover` is dark, the launch seams may open somewhere else entirely, and the `spend` demo
    /// clock ticks for as long as onboarding is on screen.
    private func start() async {
        let seams = model.launchSeams
        flow.cross = seams.cross
        if let step = seams.step {
            flow.i = min(max(step, 0), OBScreen.last.i)
        }
        let here = OBScreen(rawValue: flow.i) ?? .cover
        model.obDark = here == .club ? flow.tier.dark : OBConst.darkScreens.contains(here)

        if seams.advance, flow.i < OBScreen.last.i {
            // A beat for layout, so the crossings that anchor on a measured rect have one.
            try? await Task.sleep(for: .milliseconds(80))
            flow.run(flow.i + 1, model: model, seek: 0.5)
        }

        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            flow.clockSeconds = flow.clockSeconds > 0 ? flow.clockSeconds - 1 : OBConst.demoUnlockSeconds
        }
    }
}

// MARK: - Advancing

/// Advancing is the one thing every screen does, and it needs the model. Passing it down the
/// environment keeps the nine screen views free of a model dependency they otherwise have no use
/// for, and keeps the crossing driver in one place.
struct OBRunner {
    let go: (Int, Double) -> Void
    func callAsFunction(_ to: Int) { go(to, 0) }
}

private struct OBRunKey: EnvironmentKey {
    static let defaultValue = OBRunner { _, _ in }
}

extension EnvironmentValues {
    var obRun: OBRunner {
        get { self[OBRunKey.self] }
        set { self[OBRunKey.self] = newValue }
    }
}

// MARK: - `cover` — the deck of passes

/// Nine passes, stacked. Pull the top stub down and it tears; the rest follow on their own
/// staggered windows while the camera pushes into the perforation.
private struct OBCoverScreen: View {
    @Bindable var flow: OnboardingFlow
    let st: OBStyles
    let size: CGSize

    var body: some View {
        ZStack {
            Color(hex: 0x16273f)

            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    Text("Welcome to Tempus")
                        .font(TFont.core(.semibold, 31))
                        .tracking(-0.038 * 31)
                        .tpType(size: 31, lineHeight: 1.1)
                        .foregroundStyle(TColor.cloud100)
                    Text("Every hour you focus is a flight.")
                        .font(TFont.core(.regular, 15))
                        .tpType(size: 15, lineHeight: 1.5)
                        .foregroundStyle(TColor.textOnDarkMuted)
                        .padding(.top, 11)
                }
                .multilineTextAlignment(.center)
                .padding(.top, 54)
                .opacity(st.deck.copy)

                Spacer(minLength: 0)
                deck
                Spacer(minLength: 0)

                Text("Pull the stub down to start")
                    .font(TFont.core(.regular, 14))
                    .tpType(size: 14, lineHeight: 1.5)
                    .foregroundStyle(TColor.steel500)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .opacity((flow.dy > 6 ? 0 : 1) * st.deck.copy)
            }
            .padding(.top, max(54, TSafeArea.insets.top))
            .padding(.horizontal, 26)
            .padding(.bottom, OBConst.padBottom)
        }
    }

    /// The hidden sizer is a full copy of the front pass, laid out in flow: it gives the stack its
    /// height (every real pass is overlaid) and its top half is what the tear-line origin is
    /// measured from.
    private var deck: some View {
        OBDeckPass(livery: flow.deck[0], u: 0, held: 0, front: false, sizer: true, flow: flow)
            .hidden()
            .obMeasure { r in flow.setDeckRect(r, screenHeight: size.height) }
            .overlay(alignment: .top) { passes }
            .scaleEffect(st.deck.zoom, anchor: UnitPoint(x: 0.5, y: flow.tearPct / 100))
    }

    @ViewBuilder
    private var passes: some View {
        ZStack(alignment: .top) {
            ForEach(Array(flow.deck.enumerated()), id: \.offset) { k, livery in
                // At rest only the front pass exists; the rest appear the moment the deck starts
                // being spent, and each drops out once its own tear has finished.
                let u = OBConst.deckTear(k, st.deckQ)
                let d = Double(k) - st.deck.front
                if (k == 0 || st.deckQ >= 0), u < 1, d <= 3.1 {
                    let sc = pow(0.955, max(0, d))
                    OBDeckPass(livery: livery, u: u,
                               held: k == 0 ? flow.dy : 0,
                               front: k == 0, sizer: false, flow: flow)
                        .brightness(-min(0.24, 0.085 * max(0, d)))
                        .scaleEffect(k > 0 ? TEase.lerp(sc * 0.78, sc, st.deck.reveal) : sc)
                        .zIndex(Double(20 - k))
                }
            }
        }
    }
}

/// One pass. `u` is its own tear progress: the upper half flies out of the top, the stub drops out
/// of the bottom, and both fade over the last 42% of the travel.
private struct OBDeckPass: View {
    @Environment(AppModel.self) private var model
    let livery: Carriers.Livery
    let u: Double
    let held: CGFloat
    let front: Bool
    let sizer: Bool
    @Bindable var flow: OnboardingFlow

    private static let notch = Color(hex: 0x16273f)

    private var e: Double { OBConst.tearCurve(u) }
    private var topY: CGFloat { CGFloat(-940 * e) }
    private var stubY: CGFloat { CGFloat(940 * e) }
    private var op: Double { 1 - TEase.easeIn(TEase.clamp((u - 0.58) / 0.42)) }

    var body: some View {
        VStack(spacing: 0) {
            upper
            stub
        }
    }

    private var upper: some View {
        OBCoverPass(livery: livery)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color(hex: 0xcdd9e8))
                    .frame(height: 1.5)
                    .mask(OBDashes())
                    .padding(.horizontal, 24)
                    .opacity(u > 0 ? 0 : 1)
            }
            .overlay(alignment: .bottomLeading) { notchCircle.offset(x: -15, y: 15) }
            .overlay(alignment: .bottomTrailing) { notchCircle.offset(x: 15, y: 15) }
            .clipShape(UnevenRoundedRectangle(
                topLeadingRadius: 22, bottomLeadingRadius: 0,
                bottomTrailingRadius: 0, topTrailingRadius: 22, style: .continuous))
            .rotationEffect(.degrees(Double(topY) / 340))
            .offset(y: topY)
            .opacity(op)
            .obMeasure { r in
                guard sizer else { return }
                flow.setDeckTearBottom(r.maxY)
            }
    }

    private var stub: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(Carriers.barcode(seed: Carriers.iata).prefix(24).enumerated()),
                        id: \.offset) { _, w in
                    Rectangle()
                        .fill(TColor.navy700)
                        .frame(width: CGFloat(w), height: 38)
                }
            }
            .frame(height: 38)

            OBRule().padding(.top, 16)

            HStack(spacing: 9) {
                Text(flow.dy > 88 ? "RELEASE TO BEGIN" : "TEAR TO BEGIN")
                    .font(TFont.data(.medium, 11))
                    .tracking(0.16 * 11)
                OBCaret()
                    .fill(TColor.sky300)
                    .frame(width: 10, height: 7)
            }
            .foregroundStyle(flow.dy > 88 ? TColor.statusOnTime : TColor.textMuted)
            .frame(maxWidth: .infinity)
            .padding(.top, 14)
            .opacity(front || sizer ? 1 : 0)
        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity)
        .background(TColor.white)
        .overlay(alignment: .topLeading) { notchCircle.offset(x: -15, y: -15) }
        .overlay(alignment: .topTrailing) { notchCircle.offset(x: 15, y: -15) }
        .clipShape(UnevenRoundedRectangle(
            topLeadingRadius: 0, bottomLeadingRadius: 22,
            bottomTrailingRadius: 22, topTrailingRadius: 0, style: .continuous))
        .rotationEffect(.degrees(Double(held) * 0.012 + Double(stubY) / 150))
        .offset(y: held + stubY)
        .opacity(op)
        .contentShape(Rectangle())
        .gesture(front ? tear : nil)
        .accessibilityElement()
        .accessibilityHidden(!front)
        .accessibilityLabel("Tear the pass to begin")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { flow.run(OBScreen.earn.i, model: model) }
    }

    private var tear: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in flow.tearChanged(v.translation.height, at: v.time) }
            .onEnded { _ in flow.tearEnded(model: model) }
    }

    private var notchCircle: some View {
        Circle().fill(Self.notch).frame(width: 30, height: 30)
    }
}

/// The perforation. A dashed hairline drawn as a mask, so it takes the rule's colour.
private struct OBDashes: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p.strokedPath(StrokeStyle(lineWidth: rect.height, dash: [4, 4]))
    }
}

/// The downward caret after "TEAR TO BEGIN".
private struct OBCaret: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - `earn` — flying earns miles

private struct OBEarnScreen: View {
    @Environment(\.obRun) private var run
    @Bindable var flow: OnboardingFlow
    let st: OBStyles
    let content: OBContent

    var body: some View {
        ZStack {
            TColor.cloud100
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    OBBackButton(dark: false, tint: nil) { run(flow.i - 1) }
                    OBEyebrow(text: "HOW IT WORKS", color: TColor.textMuted)
                }
                .padding(.leading, 12)
                .padding(.trailing, 20)

                VStack(alignment: .leading, spacing: 0) {
                    Text("Flying earns miles")
                        .font(TFont.core(.bold, 46))
                        .tracking(-0.05 * 46)
                        .tpType(size: 46, lineHeight: 1.04)
                        .foregroundStyle(TColor.textPrimary)
                    Text("Pick a subject, set a length, and stay in your seat. Land and the miles are yours. Leave early and the flight diverts with nothing.")
                        .font(TFont.core(.regular, 18))
                        .tpType(size: 18, lineHeight: 1.55)
                        .foregroundStyle(TColor.steel600)
                        .padding(.top, 18)
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 44)
                .padding(.horizontal, 28)

                Spacer(minLength: 0)

                OBRouteArc(apexOn: st.apexOn, haloOn: st.haloOn) { p in
                    if flow.apex == nil { flow.apex = p }
                }

                HStack(spacing: 0) {
                    Text("\(OBConst.demoMinutes) MIN IN THE AIR")
                        .font(TFont.data(.medium, 12))
                        .tracking(0.14 * 12)
                        .foregroundStyle(TColor.textMuted)
                    Spacer(minLength: 0)
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text("+\(OBConst.demoEarn)").font(TFont.core(.semibold, 18))
                        Text("mi").font(TFont.data(.medium, 12))
                    }
                    .foregroundStyle(TColor.textAccent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(TColor.copper100))
                }
                .padding(.horizontal, 28)

                OBPrimaryButton(label: "Next") { run(OBScreen.spend.i) }
                    .padding(.top, 26)
                    .padding(.horizontal, 28)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.top, OBConst.padTop)
            .padding(.bottom, OBConst.padBottom)
            .obContent(content)
        }
    }
}

// MARK: - `spend` — miles buy screen time

private struct OBSpendScreen: View {
    @Environment(\.obRun) private var run
    @Bindable var flow: OnboardingFlow
    let content: OBContent

    private var mmss: String {
        String(format: "%02d:%02d", flow.clockSeconds / 60, flow.clockSeconds % 60)
    }

    var body: some View {
        ZStack {
            TColor.navy700
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    OBBackButton(dark: true, tint: nil) { run(flow.i - 1) }
                    OBEyebrow(text: "HOW IT WORKS", color: TColor.textOnDarkMuted)
                }
                .padding(.leading, 12)
                .padding(.trailing, 20)

                VStack(alignment: .leading, spacing: 0) {
                    Text("Miles buy screen time")
                        .font(TFont.core(.bold, 46))
                        .tracking(-0.05 * 46)
                        .tpType(size: 46, lineHeight: 1.04)
                        .foregroundStyle(TColor.cloud100)
                    Text("The apps you choose stay locked until you spend what you earned. Thirty minutes costs one flight.")
                        .font(TFont.core(.regular, 18))
                        .tpType(size: 18, lineHeight: 1.55)
                        .foregroundStyle(TColor.textOnDarkMuted)
                        .padding(.top, 18)
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 44)
                .padding(.horizontal, 28)

                Spacer(minLength: 0)

                card.padding(.horizontal, 28)

                OBPrimaryButton(label: "Next") { run(OBScreen.gate.i) }
                    .padding(.top, 30)
                    .padding(.horizontal, 28)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.top, OBConst.padTop)
            .padding(.bottom, OBConst.padBottom)
            .obContent(content)
        }
    }

    /// The unlock, printed as a pass stub rather than reported as a status card. The copper band
    /// is the pass header, the spend bar sits *on* the perforation so the unlock visibly tears away
    /// as it runs down, and the state is stamped in the band. A soft green chip with a dot
    /// breathing in it is how a dashboard says "live"; nothing else in Tempus says it that way,
    /// and this screen is seen once, which is the worst possible place for a forever animation.
    private var card: some View {
        VStack(spacing: 0) {
            // copper600, not the accent itself: white on copper500 is 3.9:1, which an 11 pt label
            // has no business being set at.
            HStack(spacing: 12) {
                OBAppMonogram("TT", side: 30, radius: 9)
                Text("TikTok").tpLabelStyle()
                Spacer(minLength: 0)
                Text("Open").tpLabelStyle()
            }
            .foregroundStyle(TColor.white)
            .padding(.horizontal, 20)
            .frame(height: 56)
            .frame(maxWidth: .infinity)
            // Only the top corners: the band is the card's own head, not a block laid on it, and
            // clipping the whole stack instead would cut the perforation's holes in half.
            .background(
                UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20,
                                       style: .continuous)
                    .fill(TColor.copper600)
            )

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    tpText(mmss, size: 44, track: -0.05)
                        .font(TFont.core(.bold, 44))
                        .monospacedDigit()
                        .foregroundStyle(TColor.textPrimary)
                    Spacer(minLength: 0)
                    Text("\u{2212}\(OBConst.demoSpend) mi")
                        .font(TFont.data(.medium, 13))
                        .foregroundStyle(TColor.textAccent)
                }
                // The reference sets this row `line-height:1`; a SwiftUI Text carries the font's
                // own leading instead, and eleven points of it at 44 loosens the whole stub.
                .frame(height: 44)

                Text(OBConst.demoSpendRateLine)
                    .tpLabelStyle()
                    .foregroundStyle(TColor.textMuted)
                    .padding(.top, 12)

                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(TColor.sky100)
                        Capsule().fill(TColor.copper500)
                            .frame(width: g.size.width * CGFloat(flow.clockSeconds) / CGFloat(OBConst.demoUnlockSeconds))
                    }
                }
                .frame(height: 6)
                .padding(.top, 22)
                // The bar's second exactly absorbs the tick, so it reads as continuous.
                .animation(.linear(duration: 1), value: flow.clockSeconds)
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)

            OBStubPerforation()
                .padding(.top, 16)

            HStack(alignment: .firstTextBaseline) {
                Text("Locks again at 22:34")
                    .foregroundStyle(TColor.textMuted)
                Spacer(minLength: 0)
                Text("720 mi left")
                    .foregroundStyle(TColor.textSecondary)
            }
            .font(TFont.core(.regular, 14))
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 20)
        }
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(TColor.white))
        .tpShadow(.overlay)
    }
}

/// The stub's tear line: a dashed seam with a hole punched either side of it. The holes are painted
/// in the screen's own navy because a hole is the surface behind the paper, not a mark on it —
/// the same way the boarding pass and the flight log draw theirs.
private struct OBStubPerforation: View {
    private let hole: CGFloat = 9

    var body: some View {
        GeometryReader { g in
            Path { p in
                p.move(to: CGPoint(x: 0, y: 0.75))
                p.addLine(to: CGPoint(x: g.size.width, y: 0.75))
            }
            .stroke(TColor.borderStrong, style: StrokeStyle(lineWidth: 1.5, dash: DashedLine.perforation))
        }
        .frame(height: 1.5)
        .padding(.horizontal, 20)
        .overlay(alignment: .leading) {
            Circle().fill(TColor.navy700).frame(width: hole * 2, height: hole * 2)
                .offset(x: -hole)
        }
        .overlay(alignment: .trailing) {
            Circle().fill(TColor.navy700).frame(width: hole * 2, height: hole * 2)
                .offset(x: hole)
        }
    }
}

/// TikTok's own mark, because this card names a real app and "TT" is the monogram that says we
/// could not draw one. Every other surface lets iOS draw the app — `Label(token)` in Redeem — but
/// onboarding runs before Screen Time is authorised, so there is no token to hand it yet.
///
/// The glyph is the official 24x24 note path, read by the same `SVGPath` the Concourse uses, so it
/// is a string rather than a bundled image or a hand-built `Shape`. The two hexes are TikTok's
/// brand colours, not Tempus's palette, which is why they live here and not in `TColor`: the
/// fringe is what separates their mark from a music note, and a logo redrawn in someone else's
/// colours is a modified logo.
/// The two-letter tile the reference draws for a blocked app.
///
/// This used to be TikTok's actual note glyph in TikTok's own fringe colours (#25f4ee / #fe2c55).
/// The reference draws "TT" in DM Mono on a navy tile and never renders a third-party mark
/// anywhere — and nor does the rest of this app: Redeem uses `Label(token)` precisely so that iOS
/// draws an app rather than Tempus redrawing it, and its unconnected strip falls back to a
/// monogram. Shipping a competitor's logo, in their brand colours, inside a product illustration
/// is a trademark exposure with nothing to gain, on a screen seen once.
private struct OBAppMonogram: View {
    let text: String
    var side: CGFloat = 44
    var radius: CGFloat = 14

    init(_ text: String, side: CGFloat = 44, radius: CGFloat = 14) {
        self.text = text
        self.side = side
        self.radius = radius
    }

    var body: some View {
        Text(text)
            .font(TFont.data(.medium, side * 0.34))
            .tracking(0.04 * side * 0.34)
            .foregroundStyle(TColor.cloud100)
            .frame(width: side, height: side)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(TColor.navy900))
    }
}

/// The "open" indicator: a 2.2 s breath, so a locked app's badge is visibly not this.
private struct OBPulseDot: View {
    @State private var dim = false

    var body: some View {
        Circle()
            .fill(TColor.statusOnTime)
            .frame(width: 6, height: 6)
            .opacity(dim ? 0.35 : 1)
            .onAppear {
                // Same `tp-pulse 2.2s ease-in-out infinite` as `FlightScreens.PulsingDot` — see
                // its comment. Not a stray `.easeInOut`.
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                    dim = true
                }
            }
    }
}

// MARK: - `gate` — the permission gate

/// The gate sits immediately before the picker because the picker cannot open without Screen Time
/// — the question `apps` asks is unanswerable until this one is. Both buttons advance: a refusal
/// is a legitimate way to use the app, and every flow works with blocking mocked.
///
/// **The ground is white, where the reference's is `#101d31`.** A deliberate deviation, asked for
/// on the strength of how it looks: this is the one screen in the sequence that puts a question to
/// the member rather than telling them something, and a pale ground reads as a question. It is
/// built out of the same light palette `apps` uses one screen later, so the two now share a ground
/// as well as a subject, and the sheet that carries the gate in rises white over the navy `spend`
/// screen behind it rather than navy over navy. The one cost is at the far end: `gate → apps` is a
/// zoom-through with a *white* wash, which had a navy screen to punch out of and now does not, so
/// that crossing reads as a settle rather than a camera move. Accepted — see CLAUDE.md.
private struct OBGateScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.obRun) private var run
    @Bindable var flow: OnboardingFlow
    let content: OBContent

    /// True while `requestScreenTimeAuthorization()` is awaiting iOS's consent sheet. Local to
    /// this screen rather than on `OnboardingFlow.busy` — that flag guards a *crossing* in
    /// flight, and this is guarding the request that has to finish before one is allowed to
    /// start.
    @State private var requesting = false

    var body: some View {
        ZStack {
            TColor.white
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    OBBackButton(dark: false, tint: nil) { run(flow.i - 1) }
                    OBEyebrow(text: "PERMISSIONS", color: TColor.textMuted)
                }
                .padding(.horizontal, -18)

                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: "lock")
                        .font(.system(size: 22, weight: .regular))
                        // `copper300` is a tint for dark grounds and all but disappears on white;
                        // `textAccent` is the light-ground accent every other pale screen uses.
                        .foregroundStyle(TColor.textAccent)
                        .frame(width: 52, height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(TColor.sky200, lineWidth: 1.5)
                        )
                    Text(flow.screenTimeOn ? "Tempus can lock your apps" : "Let Tempus lock your apps")
                        .font(TFont.core(.bold, 40))
                        .tracking(-0.05 * 40)
                        .tpType(size: 40, lineHeight: 1.08)
                        .foregroundStyle(TColor.textPrimary)
                    Text(flow.screenTimeOn
                         ? "Screen Time is connected. It is what makes a flight a flight."
                         : "iOS will ask for Screen Time. It is what makes a flight a flight.")
                        .font(TFont.core(.regular, 18))
                        .tpType(size: 18, lineHeight: 1.55)
                        .foregroundStyle(TColor.steel600)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxHeight: .infinity, alignment: .center)
                .padding(.top, 44)

                // Both buttons advance, as the reference's do — a refusal is a legitimate way to
                // use the app, and every flow works with blocking mocked. Allow now *waits* for
                // an answer before advancing: the crossing used to fire the instant the button was
                // tapped, while `requestScreenTimeAuthorization` was still awaiting iOS's consent
                // sheet — so the crossing played underneath that sheet and the member landed on
                // the app list having never actually answered it. The button disables itself (and
                // hides the "Not now" ghost, which is the same advance and would race it) for the
                // life of the request, and the crossing starts the instant the sheet is dismissed
                // — granted or declined, both advance the same way.
                //
                // Screen Time can already be on — a member walking onboarding a second time. There
                // is nothing left to ask then, and nothing to decline: the gate states the position
                // and the one button carries on immediately.
                OBPrimaryButton(label: flow.screenTimeOn ? "Continue" : "Allow") {
                    guard !requesting else { return }
                    guard !flow.screenTimeOn else { run(OBScreen.apps.i); return }
                    requesting = true
                    Task {
                        await model.requestScreenTimeAuthorization()
                        flow.screenTimeOn = model.screenTimeAuthorized
                        model.reconcileBlocking()
                        requesting = false
                        run(OBScreen.apps.i)
                    }
                }
                .disabled(requesting)
                if !flow.screenTimeOn {
                    OBGhostButton(label: "Not now", fill: TColor.sky100,
                                  foreground: TColor.textMuted) { run(OBScreen.apps.i) }
                        .padding(.top, 8)
                        .disabled(requesting)
                        .opacity(requesting ? 0.5 : 1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.top, OBConst.padTop)
            .padding(.horizontal, 30)
            .padding(.bottom, OBConst.padBottom)
            .obContent(content)
        }
    }
}

// MARK: - `apps` — what should cost miles

/// The same question Settings asks, in the same shape: iOS's own activity picker behind a grouped
/// card, so a member chooses real apps *and* categories rather than six names this app invented.
///
/// The picker cannot open without Screen Time, which is why `gate` comes immediately before
/// this screen rather than after the account: by the time the question is asked, the answer is in.
/// A refusal is ordinary — the six-name stand-in stays, under the same "not connected" banner
/// Settings leads with, and its Connect button asks again for anyone who changes their mind.
private struct OBAppsScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.obRun) private var run
    @Bindable var flow: OnboardingFlow
    let content: OBContent

    @State private var pickerOpen = false

    /// Six rows is what the column has room for above the counter and the Next button — which is
    /// measured once and must not move. The count line carries whatever does not fit.
    private static let maxRows = 6

    /// What iOS is actually set to shield, or `nil` while Screen Time is not connected or nothing
    /// has been chosen — exactly Redeem's rule, so the two screens never disagree about which list
    /// is the real one.
    private var live: FamilyActivitySelection? {
        let s = model.selection
        guard flow.screenTimeOn,
              !(s.applicationTokens.isEmpty && s.categoryTokens.isEmpty && s.webDomainTokens.isEmpty)
        else { return nil }
        return s
    }

    private var liveCount: Int {
        guard let live else { return 0 }
        return live.applicationTokens.count + live.categoryTokens.count + live.webDomainTokens.count
    }

    private var counterCopy: String {
        guard let live else {
            // Connected with nothing chosen is its own sentence: the stand-in count would claim
            // apps are locked that iOS has never been told about.
            if flow.screenTimeOn { return "Nothing locked yet. Choose the apps that should cost miles." }
            let n = OBConst.apps.filter { flow.picked.contains($0.key) }.count
            switch n {
            case 0: return "Nothing locked. Everything stays open."
            case 1: return "One app locked. Everything else stays open."
            default: return "\(n) apps locked. Everything else stays open."
            }
        }
        let apps = live.applicationTokens.count + live.webDomainTokens.count
        let cats = live.categoryTokens.count
        let parts = [apps > 0 ? "\(apps) app\(apps == 1 ? "" : "s")" : nil,
                     cats > 0 ? "\(cats) categor\(cats == 1 ? "y" : "ies")" : nil].compactMap { $0 }
        return "\(parts.joined(separator: " and ")) locked. Everything else stays open."
    }

    var body: some View {
        ZStack {
            TColor.white
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    OBBackButton(dark: false, tint: nil) { run(flow.i - 1) }
                    OBEyebrow(text: "CUSTOMISATION", color: TColor.textMuted)
                }
                .padding(.horizontal, -18)

                Text("What should cost miles?")
                    .font(TFont.core(.bold, 40))
                    .tracking(-0.05 * 40)
                    .tpType(size: 40, lineHeight: 1.06)
                    .foregroundStyle(TColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 44)

                if !flow.screenTimeOn { notConnected }

                // No group title: the headline above is already this section's.
                //
                // **Connected is decided by Screen Time, not by the selection.** This branched on
                // `live`, which is nil when the selection is merely *empty* — and authorized with
                // an empty selection is exactly the state every fresh install lands in one screen
                // after tapping Allow on the gate. The screen then showed six stand-in toggles,
                // hid the banner that says they are stand-ins, and offered no route to iOS's
                // picker at all, since the "Choose apps" row lives inside `liveRows`. Members
                // finished onboarding with an empty selection, so `Blocking.apply` shielded
                // nothing and no app was ever locked.
                SetGroup {
                    if flow.screenTimeOn {
                        if let live { liveRows(live) } else { emptySelectionRow }
                    } else {
                        standInRows
                    }
                }

                Spacer(minLength: 0)

                Text(counterCopy)
                    .font(TFont.core(.regular, 15))
                    .tpType(size: 15, lineHeight: 1.5)
                    .foregroundStyle(TColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)

                // The next crossing grows this button into the page, so it has to know where the
                // button ended up. Measured once — the rect must not follow its own animation.
                OBPrimaryButton(label: "Next") { run(OBScreen.cap.i) }
                    .obMeasure { r in
                        if flow.nextButtonRect == nil { flow.nextButtonRect = r }
                    }
                    .padding(.top, 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.top, OBConst.padTop)
            .padding(.horizontal, 30)
            .padding(.bottom, OBConst.padBottom)
            .obContent(content)
        }
        .familyActivityPicker(isPresented: $pickerOpen, selection: Binding(
            get: { model.selection },
            set: { model.selection = $0 }
        ))
    }

    /// The promise the whole screen is under, in the words Settings uses: nothing on this list is
    /// enforced until Screen Time is connected, and the six names below are a stand-in.
    private var notConnected: some View {
        StatusBanner(tone: .info, title: "Screen time is not connected") {
            Text("These six stand in until it is. Connect to pick your own apps and categories.")
        } action: {
            Button("Connect", action: connect)
                .font(TFont.core(.semibold, TFont.sizeBodySm))
                .foregroundStyle(TColor.textAccent)
        }
        .padding(.top, 26)
    }

    /// The real selection. Nothing here is a chooser — a shield is one shield over the whole
    /// selection — so the rows state what is locked and the last row opens iOS's picker to change
    /// it, which is exactly the row Settings taps through.
    @ViewBuilder
    private func liveRows(_ s: FamilyActivitySelection) -> some View {
        let apps = Array(s.applicationTokens)
        let cats = Array(s.categoryTokens)
        let webs = Array(s.webDomainTokens)
        let room = Self.maxRows - 1
        ForEach(Array(apps.prefix(room)), id: \.self) { t in
            LiveRow(last: false) { Label(t) }
        }
        ForEach(Array(cats.prefix(max(0, room - apps.count))), id: \.self) { t in
            LiveRow(last: false) { Label(t) }
        }
        ForEach(Array(webs.prefix(max(0, room - apps.count - cats.count))), id: \.self) { t in
            LiveRow(last: false) { Label(t) }
        }
        SetRow(label: "Choose apps",
               value: "\(liveCount) app\(liveCount == 1 ? "" : "s")",
               last: true) { pickerOpen = true }
    }

    /// Connected, but nothing chosen yet. One row, and it opens the picker — the state a member is
    /// in the moment they grant Screen Time, so it has to lead somewhere.
    private var emptySelectionRow: some View {
        SetRow(label: "Choose apps", value: "None yet", last: true) { pickerOpen = true }
    }

    /// The stand-in, in `OBConst.apps` order — which is the order `finish` reads it back in.
    @ViewBuilder
    private var standInRows: some View {
        let apps = OBConst.apps.compactMap { BlockableApp.named($0.key) }
        ForEach(Array(apps.enumerated()), id: \.element.id) { i, a in
            UnlockRow(app: a, on: flow.picked.contains(a.id), open: false,
                      last: i == apps.count - 1) {
                if flow.picked.contains(a.id) { flow.picked.remove(a.id) } else { flow.picked.insert(a.id) }
            }
        }
    }

    /// iOS asks once. A refusal is a legitimate way to use the app — every flow works with
    /// blocking mocked — so this leaves the stand-in in place and says nothing further.
    private func connect() {
        Task {
            await model.requestScreenTimeAuthorization()
            flow.screenTimeOn = model.screenTimeAuthorized
            // A grant changes nothing on the model, so nothing would otherwise raise the shield
            // over a selection restored from a previous install.
            model.reconcileBlocking()
            if flow.screenTimeOn { pickerOpen = true }
        }
    }
}

// MARK: - `cap` — cap what you spend in a day

/// The daily cap, on its own screen and set on the dial.
///
/// It was a strip of four presets riding under `spend`'s explanation, which is the one screen in
/// the sequence that asks nothing. It belongs here instead, between the two screens that are also
/// customisation, and next to the app picker because both of them are about spending.
///
/// The dial rather than a segmented strip because this is the same question Redeem asks — how many
/// miles — and Redeem asks it on this control. A dark ground because the dial is an instrument and
/// reads as one against night, and because the reveal into the airport wheel has to open on a
/// contrast: a white screen giving way to a near-white screen is a crossing nobody sees.
private struct OBCapScreen: View {
    @Environment(\.obRun) private var run
    @Bindable var flow: OnboardingFlow
    let content: OBContent

    /// The setter clamps, so the scale below Off is a run-out the marker cannot enter: dragging
    /// down past Off simply stops there, the way a dial at the bottom of its range should.
    private var capValue: Binding<Double> {
        Binding(get: { Double(flow.spendCap) },
                set: { flow.spendCap = max(0, Int($0.rounded())) })
    }

    var body: some View {
        ZStack {
            TColor.navy700
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    OBBackButton(dark: true, tint: nil) { run(flow.i - 1) }
                    OBEyebrow(text: "CUSTOMISATION", color: TColor.textOnDarkMuted)
                }
                .padding(.horizontal, -18)

                Text("Cap what you spend in a day")
                    .font(TFont.core(.bold, 40))
                    .tracking(-0.05 * 40)
                    .tpType(size: 40, lineHeight: 1.06)
                    .foregroundStyle(TColor.cloud100)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 44)

                Text("Earning is never capped. This is only what you can spend.")
                    .font(TFont.core(.regular, 17))
                    .tpType(size: 17, lineHeight: 1.5)
                    .foregroundStyle(TColor.textOnDarkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 16)

                Spacer(minLength: 0)

                readout

                // The crossing out of this screen grows from the dial's own copper marker, so it
                // has to know where the marker landed. `DialView` draws it at the apex of its
                // 390 × 122 box — x centred, y 72 down — and the box scales with the width.
                //
                // `.standard`, not `.growingArc` — device testing on 18 Sep 2026 called the
                // trailing (right) side "chopped": at Off, `growingArc`'s right window is 0° wide,
                // so the whole arm past the marker draws nothing and the strip reads as broken
                // rather than as a dial sitting at the bottom of its travel. `.standard` keeps both
                // windows at the same full cull every other dial in the app draws, so the strip
                // always runs to the edge; only the window changed here, not `DialView` itself, so
                // `dialSelfCheck`'s pin of `growingArc`'s own window function is untouched — the
                // style is simply unused now. (CLAUDE.md's "Onboarding's cap dial" row documents
                // the growing arc as deliberate; this reverses that call on the strength of a real
                // device rather than a reading of the code, and the row is stale until it is
                // updated to match.)
                DialView(value: capValue, min: 0, max: OBConst.capMax, step: OBConst.capStep,
                         arcStep: 1.25, tone: .dark, style: .standard)
                    .obMeasure { r in
                        if flow.dialApex == nil {
                            flow.dialApex = CGPoint(x: r.midX, y: r.minY + r.width * 72 / 390)
                        }
                    }
                    // Full bleed, as Redeem draws it. The strip is the crest of a circle whose
                    // centre is 540 pt below the screen, so inside a padded column you see the
                    // arc's ends curling down rather than the shallow middle that reads as a dial.
                    .padding(.horizontal, -30)
                    // 8pt under the readout, the same gap the gift's dial leaves under its own —
                    // the two screens that put a dial directly under a number with no button in
                    // between. It was 18.
                    .padding(.top, 8)

                Spacer(minLength: 0)

                // Below the dial, unlike the full-bleed Preflight/Redeem dials' button-above
                // convention — deliberately: `OBPrimaryButton` is the one control that appears,
                // in the same place, on all ten onboarding screens. Moving it above the dial here
                // only would put "Next" in a different spot on this one screen than every other,
                // which is a worse inconsistency than the one a reorder would fix. See CLAUDE.md
                // consistency sweep §1(d).
                OBPrimaryButton(label: "Next") { run(OBScreen.home.i) }
                    .padding(.top, 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.top, OBConst.padTop)
            .padding(.horizontal, 30)
            .padding(.bottom, OBConst.padBottom)
            .obContent(content)
        }
    }

    /// Redeem's own readout, one for one: the figure and its unit on the baseline beside it. Zero
    /// is not zero miles a day, it is no cap at all, so it is the one value that reads as a word.
    /// There is no caption under it — the screen's subhead already says what the number governs,
    /// and a second line rewriting itself on every tick of the drag only competes with the dial.
    private var readout: some View {
        VStack(spacing: 14) {
            HStack(alignment: .lastTextBaseline, spacing: 9) {
                if flow.spendCap > 0 {
                    tpText("\(flow.spendCap)", size: TFont.sizeDialValue, track: -0.07)
                        .font(TFont.core(.bold, TFont.sizeDialValue))
                        .monospacedDigit()
                        .foregroundStyle(TColor.cloud100)
                    Text("mi")
                        .font(TFont.core(.semibold, 24))
                        .foregroundStyle(TColor.textOnDarkMuted)
                } else {
                    tpText("Off", size: TFont.sizeDialValue, track: -0.07)
                        .font(TFont.core(.bold, TFont.sizeDialValue))
                        .foregroundStyle(TColor.cloud100)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - `home` — which airport do you fly from

private struct OBHomeScreen: View {
    @Environment(\.obRun) private var run
    @Bindable var flow: OnboardingFlow
    let content: OBContent

    var body: some View {
        ZStack {
            TColor.cloud100
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    OBBackButton(dark: false, tint: nil) { run(flow.i - 1) }
                    OBEyebrow(text: "CUSTOMISATION", color: TColor.textMuted)
                }
                .padding(.horizontal, -16)

                Text("Which airport do you fly from?")
                    .font(TFont.core(.bold, 40))
                    .tracking(-0.05 * 40)
                    .tpType(size: 40, lineHeight: 1.06)
                    .foregroundStyle(TColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 44)

                Text("Longer flights reach further destinations.")
                    .font(TFont.core(.regular, 17))
                    .tpType(size: 17, lineHeight: 1.5)
                    .foregroundStyle(TColor.steel600)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 16)

                OBWheel(flow: flow).padding(.top, 40)

                Spacer(minLength: 0)

                OBPrimaryButton(label: "Set \(OBConst.airports[flow.pickedAirportIndex].city)") {
                    run(OBScreen.account.i)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.top, OBConst.padTop)
            .padding(.horizontal, 28)
            .padding(.bottom, OBConst.padBottom)
            // `cap → home` fades this column in through `obContent`'s plain `.opacity`, and
            // `OBWheel` is a surface with content stacked on it — a sunken pill behind its rows,
            // gradients over those. Without a group each of those three leaves takes the crossing's
            // opacity separately: the pill's own fade-in blends with the page ground underneath it
            // at one rate while the rows on top of the pill blend at another, which is the exact
            // shape CLAUDE.md's opacity note describes — half-faded is the brightest the artifact
            // gets, and it is gone at both ends, so it reads as a flicker rather than a plain fade.
            // `.compositingGroup()` here flattens the column to one image *before* `obContent`'s
            // `.opacity` is applied to it, so the wheel fades as the one picture it actually is.
            .compositingGroup()
            .obContent(content)
        }
    }
}

// MARK: - `account` — the account

private struct OBAccountScreen: View {
    @Environment(\.obRun) private var run
    @Environment(Identity.self) private var identity
    @Environment(AppModel.self) private var model
    @FocusState private var typing: Bool
    @State private var email = ""
    @Bindable var flow: OnboardingFlow
    let content: OBContent

    var body: some View {
        ZStack {
            // Tapping the ground puts the keyboard away. Keyboard avoidance only moves the *focused*
            // view, and the field already clears the keyboard — so nothing shifts, and Apple and
            // Google sit underneath it with no way out but the return key or the back button.
            // This screen is the only one with a text field, so the gesture lives here, not in the
            // onboarding chrome, and the ground carries no other gesture to compete with.
            TColor.cloud100
                .contentShape(Rectangle())
                .onTapGesture { typing = false }
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    OBBackButton(dark: false, tint: nil) { typing = false; run(flow.i - 1) }
                    OBEyebrow(text: "ACCOUNT", color: TColor.textMuted)
                }
                .padding(.horizontal, -18)

                body6
                    .frame(maxHeight: .infinity, alignment: .center)
                    .padding(.top, 20)

                Text("Your study data stays on your phone.")
                    .font(TFont.core(.regular, 13))
                    .tpType(size: 13, lineHeight: 1.5)
                    .foregroundStyle(TColor.textMuted)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.top, OBConst.padTop)
            .padding(.horizontal, 30)
            .padding(.bottom, OBConst.padBottom)
            .obContent(content)
        }
    }

    /// **These three buttons sign you in.** In the reference all three merely advance — three ways of
    /// saying "next" — because a web demo has no account layer. Here Apple and Google are real
    /// authorizations and the email field is a real address, all through `Identity`.
    ///
    /// A sign-in only advances on **success** — `go` reads the `Bool` each attempt returns. A
    /// cancel (the system sheet's Cancel, backing out of Face ID, dismissing the browser) is
    /// silent and stays right here, exactly as `Identity.attempt` already treats it: not an error
    /// worth a banner, just a "no" that should not be read as a "yes". A real failure sets
    /// `identity.error` and also stays here, so the banner has something to say. An account is
    /// optional, so `skip()` is the explicit, always-visible way past this screen.
    private var body6: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Ready when you are")
                .font(TFont.core(.bold, 44))
                .tracking(-0.05 * 44)
                .tpType(size: 44, lineHeight: 1.04)
                .foregroundStyle(TColor.textPrimary)
            Text(identity.error ?? subCopy)
                .font(TFont.core(.regular, 18))
                .tpType(size: 18, lineHeight: 1.55)
                .foregroundStyle(identity.error == nil ? TColor.steel600 : TColor.statusDiverted)
                .animation(.glide(TDur.fast), value: identity.error)

            HStack(spacing: 14) {
                TextField("", text: $email, prompt: Text(verbatim: "you@example.com")
                    .foregroundStyle(TColor.sky300))
                    .font(TFont.core(.medium, 16))
                    .foregroundStyle(TColor.textPrimary)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.continue)
                    .focused($typing)
                    .onSubmit { go(.email) }
            }
            .padding(.horizontal, 20)
            .frame(height: 62)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(TColor.white)
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(typing ? TColor.textAccent : TColor.borderSubtle, lineWidth: 1.5))
            )
            .animation(.glide(TDur.fast), value: typing)
            .padding(.top, 12)

            OBPrimaryButton(label: label("Continue with email", .email),
                            background: TColor.navy700,
                            foreground: TColor.cloud100,
                            shadowColor: .clear) { go(.email) }

            HStack(spacing: 14) {
                Rectangle().fill(TColor.sky200).frame(height: 1)
                Text("OR")
                    .font(TFont.data(.medium, 11))
                    .tracking(0.16 * 11)
                    .foregroundStyle(TColor.textMuted)
                Rectangle().fill(TColor.sky200).frame(height: 1)
            }
            .padding(.vertical, 6)

            Button { go(.apple) } label: {
                HStack(spacing: 10) {
                    Text(verbatim: "\u{F8FF}").font(.system(size: 19))
                    Text(label("Continue with Apple", .apple)).font(TFont.core(.semibold, 16))
                }
                .foregroundStyle(TColor.white)
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .background(Capsule().fill(TColor.navy900))
            }
            .buttonStyle(.plain)

            Button { go(.google) } label: {
                HStack(spacing: 10) {
                    OBGoogleMark()
                    Text(label("Continue with Google", .google)).font(TFont.core(.semibold, 16))
                }
                .foregroundStyle(TColor.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .background(
                    Capsule().fill(TColor.white)
                        .overlay(Capsule().strokeBorder(TColor.sky200, lineWidth: 1.5))
                )
            }
            .buttonStyle(.plain)

            OBGhostButton(label: "Not now", fill: TColor.sky100, foreground: TColor.textMuted) { skip() }
                .padding(.top, 2)
        }
        .fixedSize(horizontal: false, vertical: true)
        .disabled(identity.busy != nil)
    }

    private var subCopy: String {
        Identity.syncAvailable
            ? "Sign in so your miles, log and passes survive a new phone."
            : "Sign in to put your own name on the card and every pass."
    }

    private func label(_ base: String, _ provider: AuthProvider) -> String {
        identity.busy == provider ? "Signing in\u{2026}" : base
    }

    /// Runs the sign-in and advances **only if it succeeded**. A cancel or a failure leaves `ok ==
    /// false` — `Identity.attempt` already tells the two apart, clearing `identity.error` for a
    /// cancel and setting it for a real failure — so this screen just has to read the result rather
    /// than assume every attempt is a "next" in disguise. An account is still optional: that is what
    /// `skip()` is for.
    private func go(_ provider: AuthProvider) {
        typing = false
        Task {
            // A verified identity can carry a save file with it. If this member already has one in
            // the cloud, they are not a new member and the rest of onboarding is the wrong screen
            // to show them — they land on their own Home with their own miles.
            switch await model.signIn(provider, identity: identity, email: email) {
            case .failed: return
            case .restored:
                model.goDirect(.home)
                model.deal = true
            case .signedIn:
                run(OBScreen.club.i)
            }
        }
    }

    /// The explicit way past this screen with no account at all.
    private func skip() {
        typing = false
        run(OBScreen.club.i)
    }
}

/// The four-quadrant Google mark. An angular gradient with doubled stops gives the hard edges a
/// conic gradient has; the quarter-turn puts the first quadrant at twelve o'clock.
private struct OBGoogleMark: View {
    var body: some View {
        Circle()
            .fill(AngularGradient(gradient: Gradient(stops: [
                .init(color: Color(hex: 0xe9564a), location: 0),
                .init(color: Color(hex: 0xe9564a), location: 0.25),
                .init(color: Color(hex: 0xf2b33d), location: 0.25),
                .init(color: Color(hex: 0xf2b33d), location: 0.5),
                .init(color: Color(hex: 0x4a8cf0), location: 0.5),
                .init(color: Color(hex: 0x4a8cf0), location: 0.75),
                .init(color: Color(hex: 0x3f9a5a), location: 0.75),
                .init(color: Color(hex: 0x3f9a5a), location: 1)
            ]), center: .center))
            .rotationEffect(.degrees(-90))
            .frame(width: 22, height: 22)
            .overlay(Circle().fill(TColor.white).frame(width: 9, height: 9))
    }
}

// MARK: - `club` — the Status Club

private struct OBClubScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.obRun) private var run
    @Bindable var flow: OnboardingFlow
    let st: OBStyles
    let content: OBContent

    private var th: OBTier { flow.tier }
    private var titleIn: Double { TEase.clamp(st.clubT * 2.6) }
    private var detailIn: Double { TEase.clamp(st.clubT * 2 - 1) }

    var body: some View {
        ZStack {
            th.bg.animation(.glide(0.52), value: th.bg)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    OBBackButton(dark: th.dark, tint: th) { run(flow.i - 1) }
                    OBEyebrow(text: "STATUS CLUB", color: th.mute)
                }
                .padding(.horizontal, -12)

                VStack(alignment: .leading, spacing: 0) {
                    Text("Status Club")
                        .font(TFont.core(.bold, 40))
                        .tracking(-0.05 * 40)
                        .tpType(size: 40, lineHeight: 1.05)
                        .foregroundStyle(th.ink)
                    Text("Every 90 days your hours in the air set your tier for the next 90. Higher tiers earn faster, and Premier and Prestige pay a one-time bonus the day you reach them. Swipe to see all five.")
                        .font(TFont.core(.regular, 16))
                        .tpType(size: 16, lineHeight: 1.5)
                        .foregroundStyle(th.mute)
                        .padding(.top, 12)
                }
                .fixedSize(horizontal: false, vertical: true)
                .animation(.glide(0.52), value: th.ink)
                .padding(.top, 30)
                .opacity(titleIn)
                .offset(y: 16 * (1 - titleIn))

                rail.padding(.top, 30)
                dots.padding(.top, 20)
                detail.padding(.top, 26)

                Spacer(minLength: 0)

                OBPrimaryButton(label: "Next",
                                background: th.btn,
                                foreground: th.btnInk,
                                shadowColor: th.btn.opacity(0.55)) { run(OBScreen.shop.i) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.top, OBConst.padTop)
            .padding(.horizontal, 24)
            .padding(.bottom, OBConst.padBottom)
            .obContent(content)
        }
    }

    /// The five cards, dealt in one after another off the crossing clock, then swipeable.
    private var rail: some View {
        ZStack(alignment: .top) {
            ForEach(Array(OBTier.all.enumerated()), id: \.offset) { k, _ in
                let lag = TEase.clamp((st.clubT - Double(k) * 0.12) / 0.5)
                let e = TEase.soft(lag)
                let off = CGFloat(k - flow.ci) * OBConst.carouselStep + flow.cdx
                let d = min(1, Double(abs(off)) / Double(OBConst.carouselStep))
                StatusCard(tier: k, variant: 0, name: model.cardName, width: 246)
                    .opacity(e * (1 - d * 0.55))
                    .scaleEffect(TEase.lerp(0.9, 1, e) * (1 - d * 0.1))
                    .rotationEffect(.degrees(TEase.lerp(7, 0, e)))
                    .offset(x: off, y: 12 + CGFloat(TEase.lerp(230, 0, e)))
                    .zIndex(Double(10 - Int((d * 8).rounded())))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 186, alignment: .top)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { v in flow.carouselChanged(v.translation.width) }
                .onEnded { _ in flow.carouselEnded(model: model) }
        )
    }

    private var dots: some View {
        HStack(spacing: 10) {
            ForEach(Array(OBTier.all.enumerated()), id: \.offset) { k, _ in
                Capsule()
                    .fill(k == flow.ci ? th.accent : th.idle)
                    .frame(width: k == flow.ci ? 24 : 8, height: 8)
                    // The dot is 8 pt tall; the target it answers to is 44.
                    .padding(.vertical, 18)
                    .contentShape(Rectangle())
                    .onTapGesture { flow.selectCard(k, model: model) }
                    .padding(.vertical, -18)
                    .accessibilityLabel(OBTier.all[k].name)
                    .accessibilityAddTraits(k == flow.ci ? [.isButton, .isSelected] : .isButton)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.glide(0.32), value: flow.ci)
        .opacity(detailIn)
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(th.name)
                    .font(TFont.core(.bold, 34))
                    .tracking(-0.045 * 34)
                    .foregroundStyle(th.ink)
                Spacer(minLength: 0)
                Text(th.chipLabel)
                    .font(TFont.core(.semibold, 12))
                    .foregroundStyle(th.chipInk)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(th.chip))
            }

            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(th.rows.enumerated()), id: \.offset) { k, row in
                    VStack(spacing: 0) {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(row.label)
                                .font(TFont.core(.regular, 15))
                                .tpType(size: 15, lineHeight: 1.3)
                                .foregroundStyle(th.mute)
                            Spacer(minLength: 0)
                            Text(row.value)
                                .font(TFont.core(.semibold, 16))
                                .foregroundStyle(row.accent ? th.accent : th.ink)
                        }
                        if k < 2 {
                            Rectangle().fill(th.rule).frame(height: 1).padding(.top, 12)
                        }
                    }
                }
            }
            .padding(.top, 18)
        }
        .animation(.glide(0.52), value: th.ink)
        .opacity(detailIn)
    }
}

// MARK: - `business` — business class

/// **The Concourse.** The tenth screen, added 21 Sep 2026 — the shop was the one surface a new
/// member could reach from the Home header without ever having been told it existed, and with the
/// shelf now open to everyone rather than gated behind Business Class, not saying so leaves miles
/// with only one thing to buy.
///
/// It is the shop's own sentence, in order: miles are earned by flying, the shelf spends them on
/// how the card and the pass *look*, nothing there is a timer or a loot box, and about three
/// quarters of the stock is Business Class. The last of those is the lead-in to the screen after
/// it, which is why this one sits between the Status Club and the upgrade rather than anywhere
/// earlier: the club is where the card is worn, so it is the only place the shelf makes sense.
///
/// The stock is real — `ShopCatalog`'s first few faces and headers, drawn by the same `MarkupView`
/// the shelf itself uses. Nothing here is a picture of the Concourse; it is the Concourse's own
/// art at tile size, so the screen cannot drift out of step with what is actually on sale.
private struct OBShopScreen: View {
    @Environment(\.obRun) private var run
    @Environment(AppModel.self) private var model
    @Bindable var flow: OnboardingFlow
    let content: OBContent

    /// Three faces and two headers, fixed rather than shuffled: this screen is seen once, and a
    /// run chosen for how it sits together beats a fresh draw that can put three near-identical
    /// pale cards in a row — which is exactly what `faces.prefix(3)` did, because the catalogue is
    /// in tier order and tier 0 opens on five variations of off-white.
    ///
    /// The three are **one free face and two Business ones**, spread across the tiers, so the row
    /// says the same thing the line under it says: the shelf is open, the best of it is not. They
    /// are chosen by position in the catalogue rather than by id, so a data edit re-picks rather
    /// than rendering a hole.
    private var faces: [ShopFace] {
        [pick(tier: 0, dearest: false), pick(tier: 2, dearest: true), pick(tier: 4, dearest: true)]
            .compactMap { $0 }
    }

    private func pick(tier: Int, dearest: Bool) -> ShopFace? {
        let set = ShopCatalog.faces(tier: tier)
        return dearest ? set.max { $0.price < $1.price } : set.min { $0.price < $1.price }
    }

    /// The two dearest headers, which are also the two most obviously *made* of something —
    /// a header is a 268 × 90 band and the plain ones read as a coloured bar at this size.
    private var headers: [ShopHeader] {
        Array(ShopCatalog.headers.sorted { ($0.price, $0.id) > ($1.price, $1.id) }.prefix(2))
    }

    var body: some View {
        ZStack {
            TColor.cloud100
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    OBBackButton(dark: false, tint: nil) { run(flow.i - 1) }
                    OBEyebrow(text: "THE CONCOURSE", color: TColor.textMuted)
                }
                .padding(.horizontal, -8)

                Text("Spend miles on how it all looks")
                    .font(TFont.core(.bold, 40))
                    .tracking(-0.05 * 40)
                    .tpType(size: 40, lineHeight: 1.06)
                    .foregroundStyle(TColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 44)

                Text("The same miles that buy screen time also buy card faces and pass headers. Nothing here is a timer or a crate — you pay, you own it, it is yours.")
                    .font(TFont.core(.regular, 17))
                    .tpType(size: 17, lineHeight: 1.5)
                    .foregroundStyle(TColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 16)

                Spacer(minLength: 0).frame(maxHeight: 54)

                shelf

                Spacer(minLength: 0)

                // The one line on this screen that is about the *next* one. Said plainly and
                // without a number attached to it: a percentage here would read as a sales pitch
                // three screens before there is anything to buy.
                Text("Most of the shelf is open to anyone. The best of it comes with Business Class.")
                    .font(TFont.core(.regular, 15))
                    .tpType(size: 15, lineHeight: 1.45)
                    .foregroundStyle(TColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)

                OBPrimaryButton(label: "Next") { run(OBScreen.business.i) }
                    .padding(.top, 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.top, OBConst.padTop)
            .padding(.horizontal, 30)
            .padding(.bottom, OBConst.padBottom)
            .obContent(content)
        }
    }

    /// A row of three tilted faces and a pair of headers under them — the shelf's own two shapes,
    /// at a glance. The faces are tilted −7° and carry the same drop shadow `ConcourseShopTile`
    /// gives its art, so the arrangement is recognisably the shelf rather than a new layout the
    /// member will never see again.
    private var shelf: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                ForEach(faces) { f in
                    MarkupView(f.inner(for: model.cardName), background: f.ground,
                               designSize: CGSize(width: 340, height: 214),
                               width: 104, cornerRadius: 8)
                        .rotationEffect(.degrees(-7))
                        .compositingGroup()
                        .shadow(color: Color(hex: 0x101d31, opacity: 0.1381), radius: 10, x: 0, y: 12)
                }
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 12) {
                ForEach(headers) { h in
                    MarkupView(h.inner, background: h.bg,
                               designSize: CGSize(width: 268, height: 90),
                               width: 140, cornerRadius: 6)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 14)
    }
}

private struct OBBusinessScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(Billing.self) private var billing
    @Environment(\.obRun) private var run
    @Bindable var flow: OnboardingFlow
    let content: OBContent

    /// Kept in step with `PaywallSheet.includedRows` by hand — the two surfaces sell the same
    /// plan and must not list different things. "The Concourse" was right until the shelf was
    /// opened to everyone on 21 Sep 2026; the plan buys the Business stock on it now.
    private static let included = ["Routes longer than 90 minutes",
                                   "The Concourse's Business stock",
                                   "Status Club higher tiers"]

    var body: some View {
        ZStack {
            TColor.navy900
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    OBBackButton(dark: true, tint: nil) { run(flow.i - 1) }
                    OBEyebrow(text: "BUSINESS CLASS", color: TColor.textOnDarkMuted)
                }
                .padding(.horizontal, -8)

                VStack(spacing: 0) {
                    ticket
                    price.padding(.top, 26)
                    // Sat flush on the primary button's top edge at 14 — and this is the line that
                    // says *why* that button is grey when it is, so it may not read as part of it.
                    Text(model.plus ? "Business class is active on this account."
                         : (billing.error ?? billing.unavailable ?? billing.subCopy))
                        .font(TFont.core(.regular, 13))
                        .tpType(size: 13, lineHeight: 1.45)
                        .foregroundStyle(TColor.textOnDarkMuted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 16)
                        .padding(.bottom, 4)
                }
                .frame(maxHeight: .infinity, alignment: .center)
                .padding(.top, 20)

                // The reference's `onStart` is `setPlus(true)` — the plan for nothing — and a
                // shipping app cannot give away its paid tier, so this button buys.
                //
                // It used to carry the intent out of onboarding and open the paywall instead,
                // which put the *same* Business Class offer on screen twice in a row: this
                // ticket, then the sheet, same three included rows, same price, same two
                // buttons. This screen already **is** the paywall's content, so it sells from
                // here, and when there is nothing to sell it says so and goes quiet — exactly
                // what the sheet would have said. Whether the store answers is not a reason to
                // show a member the same offer a second time.
                //
                // And when the plan is already held — a reinstall on the Apple ID that bought it,
                // where `Billing.start()`'s customer stream has flipped `plus` before this screen
                // is reached — it says so and finishes, the way the paywall does. Selling a second
                // time is not a second charge (StoreKit refuses), but it is a fresh sale button
                // on top of a plan the member is already in.
                OBPrimaryButton(label: model.plus ? "You are in Business Class" : billing.buyLabel,
                                shadowAlpha: 0.9) {
                    if model.plus { flow.finish(model: model); return }
                    Task { @MainActor in
                        if await billing.purchase(model) { flow.finish(model: model) }
                    }
                }
                .disabled(!model.plus && !billing.canPurchase)
                .opacity(model.plus || billing.canPurchase ? 1 : 0.55)
                OBGhostButton(label: model.plus ? "Done" : "Stay in economy",
                              height: 52, fontSize: 16,
                              fill: Color(hex: 0xf2f5fa, opacity: 0.12),
                              foreground: TColor.cloud100) {
                    flow.finish(model: model)
                }
                .padding(.top, 8)

                // This screen sells the plan itself rather than handing off to the paywall, so it
                // carries the two links App Store Review 3.1.2 requires of any surface that does.
                HStack(spacing: 18) {
                    Link("Terms of Use", destination: Billing.termsURL)
                    Link("Privacy Policy", destination: Billing.privacyURL)
                }
                .font(TFont.core(.regular, 12))
                .foregroundStyle(TColor.textOnDarkMuted)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.top, OBConst.padTop)
            .padding(.horizontal, 20)
            .padding(.bottom, OBConst.padBottom)
            .obContent(content)
        }
    }

    /// `ticketTop` and `ticketBottom` are two separate white boxes stacked with no gap, and the
    /// notch straddles the seam between them. `compositingGroup` is what lets `.destinationOut`
    /// erase a real hole rather than paint a coloured disc — but grouping does not reorder
    /// anything, and the notch rides on `ticketTop`, the *earlier* sibling, so `ticketBottom`
    /// painted its lower half straight back in and left a quarter circle. `zIndex` is the
    /// missing half: it is SwiftUI's equivalent of the reference's positioned-beats-static
    /// painting order, and it puts the top box — and so its notches — last.
    private var ticket: some View {
        VStack(spacing: 0) {
            ticketTop.zIndex(1)
            ticketBottom
        }
        .compositingGroup()
    }

    private var ticketTop: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("UPGRADE")
                    .font(TFont.data(.medium, 11))
                    .tracking(0.16 * 11)
                    .foregroundStyle(TColor.textMuted)
                Spacer(minLength: 0)
                Text("SEAT 1A")
                    .font(TFont.data(.medium, 11))
                    .tracking(0.16 * 11)
                    .foregroundStyle(TColor.textAccent)
            }
            Text("Business Class")
                .font(TFont.core(.bold, 40))
                .tracking(-0.045 * 40)
                .tpType(size: 40, lineHeight: 1.05)
                .foregroundStyle(TColor.textPrimary)
                .padding(.top, 16)
            // Three lines that said, in a sentence, exactly what the three INCLUDED rows below
            // say in a list — and cost the tallest screen in the sequence ~70pt to do it. The
            // line now says the one thing the rows cannot: the cabin itself changes. Same
            // sentence the paywall carries, for the same reason.
            Text("A seat up front, and a cabin that holds you to the flight.")
                .font(TFont.core(.regular, 16))
                .tpType(size: 16, lineHeight: 1.5)
                .foregroundStyle(TColor.steel600)
                .padding(.top, 14)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 22)
        .padding(.top, 26)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 24, bottomLeadingRadius: 0,
                                   bottomTrailingRadius: 0, topTrailingRadius: 24,
                                   style: .continuous)
                .fill(TColor.white)
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(hex: 0xcdd9e8))
                .frame(height: 1.5)
                .mask(OBDashes())
                .padding(.horizontal, 20)
        }
        .overlay(alignment: .bottomLeading) { notch.offset(x: -14, y: 14) }
        .overlay(alignment: .bottomTrailing) { notch.offset(x: 14, y: 14) }
    }

    private var ticketBottom: some View {
        VStack(spacing: 0) {
            ForEach(Array(Self.included.enumerated()), id: \.offset) { k, row in
                VStack(spacing: 0) {
                    if k > 0 {
                        OBRule().padding(.top, 14)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(row)
                            .font(TFont.core(.medium, 15))
                            .tpType(size: 15, lineHeight: 1.3)
                            .foregroundStyle(TColor.textPrimary)
                        Spacer(minLength: 0)
                        Text("INCLUDED")
                            .font(TFont.data(.medium, 12))
                            .tracking(0.1 * 12)
                            .foregroundStyle(TColor.statusOnTime)
                    }
                    .padding(.top, k > 0 ? 14 : 0)
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 24,
                                   bottomTrailingRadius: 24, topTrailingRadius: 0,
                                   style: .continuous)
                .fill(TColor.white)
        )
    }

    /// **The two plans, the same two cards the paywall draws.** This was a 62pt annual total with
    /// a `/yr` suffix and, briefly, a segmented pill under it. Three things were wrong with that:
    ///
    /// 1. The figure was set with `Text(verbatim:).tracking(-0.06 × 62)`, which reserves trailing
    ///    space after the last glyph and clips what overflows — and every price this can show ends
    ///    in a round "9", so the 9 was visibly shaved. `PlanPicker` uses `tpText` throughout.
    /// 2. The biggest number on the screen was the *annual total*, which is the number that makes
    ///    a reader flinch. The per-month equivalent is the one to lead with; the total belongs on
    ///    the line underneath, stated in full.
    /// 3. A pill segment has room for a word, not for a price, a cadence and a saving — so the
    ///    saving had to ride in the segment's own label ("Annual −58%"), in the segment's own ink.
    ///    It is a `copper100` stamp on the card's corner now: warm, so it reads as belonging to
    ///    the paid thing, and pale, so it cannot be mistaken for the copper button below it.
    ///
    /// Shared with the paywall rather than restated, so the two surfaces that sell the same plan
    /// cannot drift into selling it differently.
    private var price: some View {
        Group {
            if billing.showsPlanChoice && !model.plus {
                PlanPicker(compact: true)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    tpText(billing.displayPrice, size: 62, track: -0.06)
                        .font(TFont.core(.bold, 62))
                        .monospacedDigit()
                        .foregroundStyle(TColor.cloud100)
                    Text(verbatim: billing.displayPeriod)
                        .font(TFont.data(.medium, 16))
                        .foregroundStyle(TColor.textOnDarkMuted)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var notch: some View {
        Circle().fill(.black).frame(width: 28, height: 28).blendMode(.destinationOut)
    }
}

/// The Next button growing into the page, drawn as a path rather than as a sized-and-positioned
/// view. `left`/`top`/`bottom` are insets from the screen's own edges and go negative once the pill
/// has grown past them; a shape simply draws outside its rect, where a view that size would have
/// renegotiated the stage's layout. See the call site in `overlays(st:size:)`.
struct OBExpandPill: Shape {
    var left: CGFloat
    var top: CGFloat
    var bottom: CGFloat
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let box = CGRect(x: rect.minX + left, y: rect.minY + top,
                         width: rect.width - left * 2, height: rect.height - top - bottom)
        guard box.width > 0, box.height > 0 else { return Path() }
        // CSS `border-radius` draws circular arcs and clamps to half the shorter side, which is
        // what turns the button's 999 into a capsule and then eases it flat.
        let rounded = Path(roundedRect: box,
                           cornerRadius: min(radius, min(box.width, box.height) / 2),
                           style: .circular)
        guard !rect.contains(box) else { return rounded }
        // **Trimmed to the screen, not merely drawn past it.** The insets run to −300, so by the
        // end of the crossing the box is half again the size of the screen — and a path that far
        // outside its own bounds is not drawn: measured, the pill vanished for ten frames and then
        // came back as a fixed 190pt band across the top, which is the "flicker" on this crossing.
        // Trimming costs one boolean op a frame on a four-arc path and the result is pixel-identical
        // to the untrimmed shape, because everything removed was off-screen.
        return Path(rounded.cgPath.intersection(CGPath(rect: rect, transform: nil)))
    }
}
