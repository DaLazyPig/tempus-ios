import SwiftUI

/// Choosing a face. The card the member was looking at travels down into the middle while the page
/// colour fades over it, then the controls fade in. Leaving runs it backwards.
///
/// The router mounts this twice: once as the `carddesign` phase, and once with `exiting: true` drawn
/// over Status Club after the phase has already changed back underneath it. The exit copy is inert —
/// it takes no touches, plays every transition in reverse, and clears `cardDesignOut` when its
/// retreat is over so the router can drop it.
struct CardDesignScreen: View {
    @Environment(AppModel.self) private var model
    let exiting: Bool

    /// The face being browsed. `nil` until the member moves, so the saved index is the first thing
    /// drawn without needing the model inside an initialiser.
    @State private var browsing: Int?
    /// The settled flag every transition on the screen keys off. The exit copy starts settled and
    /// animates *off*.
    @State private var groundOut = false
    @State private var on: Bool
    @State private var dx: CGFloat = 0
    @State private var dragging = false

    /// One deck slot, and the finger travel that commits an advance.
    private static let step: CGFloat = 250
    private static let commit: CGFloat = 56
    /// The deck strip's own resting centre: `top: 196` plus half of its `260` height.
    private static let deckCentreY: CGFloat = 326

    init(exiting: Bool) {
        self.exiting = exiting
        _on = State(initialValue: exiting)
    }

    // MARK: - What is being chosen

    private var tier: Int { min(model.status.idx, model.cardVariant.count - 1) }
    private var saved: Int { exiting ? (model.cardDesignOut ?? 0) : model.cardVariant[tier] }
    private var set: [CardArt.Face] { CardArt.faces(tier: tier, owned: model.ownedFaces) }
    private var index: Int { CardArt.slot(browsing ?? saved, in: set) }

    /// **Nothing in the studio is gated any more.** Every tier used to issue exactly one face for
    /// free and charge Business Class for the rest of its own built-in run — so the card the
    /// membership is *about* could not be changed without the plan, and the studio's only live
    /// control read "Unlock with Business Class".
    ///
    /// The built-in faces are now free at every tier: they are the base set, they ship in the
    /// binary, and a member who has flown to a tier has already earned the right to wear it. What
    /// the plan buys is the top of the Concourse shelf (`ShopCatalog.businessOnly`) — and a shop
    /// face that reaches this deck at all is one this member already bought, which settles the
    /// question before the studio is opened.
    ///
    /// Kept as a property rather than deleted at every call site: the three places that read it
    /// are the chip, the button's label and the button's action, and one `false` is a smaller and
    /// more reversible diff than unpicking all three. `ponytail: constant on purpose.`
    private var locked: Bool { false }

    // MARK: - Colour

    private var theme0: CardArt.Theme {
        CardArt.theme(tier: tier, variant: index, owned: model.ownedFaces)
    }

    /// The ground follows the swipe rather than the release: while a card is being dragged the page
    /// colour is mixed between the face being left and the one arriving.
    private var neighbour: CardArt.Theme {
        let n = dx < 0 ? min(set.count - 1, index + 1) : max(0, index - 1)
        return CardArt.theme(tier: tier, variant: n, owned: model.ownedFaces)
    }

    private var mixT: Double { dragging ? min(1, Double(abs(dx)) / Double(Self.step)) : 0 }
    private var theme: CardArt.Theme { mixT > 0.5 ? neighbour : theme0 }
    private var liveBg: Color {
        mixT > 0 ? CardArt.mix(theme0.bg, neighbour.bg, mixT) : theme0.bg
    }

    /// The band Status Club is painting behind the card right now — the panel this screen grows
    /// out of, and the one it has to start as.
    ///
    /// **`CardArt.band(behind:)`, not `CardArt.header`.** The club stopped painting the raw header
    /// colour when `band(behind:)` was introduced; the studio's entrance did not follow, so the
    /// first frame of every Customise repainted the top of the screen from the club's band
    /// (122,144,178 on Essential) to the header it is derived from (91,118,160) — a step down, and
    /// then the whole thing lightened again as the band grew into `liveBg`.
    private var savedHeader: Color {
        CardArt.band(behind: CardArt.header(tier: tier, variant: saved, owned: model.ownedFaces))
    }

    /// Where the club's hero band ends. Measured by Status Club itself; the 500 is only the
    /// reference's own literal, for the one path that arrives with nothing measured.
    private var heroBottom: CGFloat {
        let y = model.statusHero.rect.maxY
        return y > 0 ? y : 500
    }

    // MARK: - Where the deck starts

    /// Where the card was standing on the screen we came from — the deck starts there and glides
    /// into the middle. With no source rect it is the club's own card, as the club measured it
    /// (`AppModel.statusCardBox`); the reference's 89pt drop is only the fallback for a launch
    /// that arrives with nothing measured.
    private var start: (dx: CGFloat, dy: CGFloat, scale: CGFloat, rot: Double, veil: Color?) {
        guard let from = model.cardDesignFrom else {
            let club = model.statusCardBox.rect
            return (0, club.midY > 0 ? club.midY - Self.deckCentreY : -89, 1, 0, nil)
        }
        return (from.rect.midX - UIScreen.main.bounds.width / 2,
                from.rect.midY - Self.deckCentreY,
                from.rect.width / CardArt.width,
                from.rot,
                from.bg)
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .topLeading) {
            background
            headerRow.cdTop(56, inset: 28).cdFade(on, 0)
            deck
                // The deck does not fade on the way out. It travels the 89pt back up into the
                // club card's own place over its 520 ms (the reference's exit transform) and the
                // sheet dissolves over it once it is nearly there — that is the morph. Fading it
                // mid-travel left the club's card popping in where the studio's had just vanished.
                .cdTop(196)
            pager.cdTop(478).cdFade(on, 1)
            titleBlock.cdTop(544, inset: 28).cdFade(on, 2)
            actions.cdBottom(40, inset: 28).cdFade(on, 3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // No `clipped()`: it clips to the layout bounds *before* the safe area is ignored, so the
        // ground stopped 34pt short of the bottom edge and the layer's own showed through. The
        // stage clips every layer to the screen anyway, which is all this was ever doing.
        .ignoresSafeArea()
        // Flattened before it fades. CSS `opacity` on a parent establishes a stacking context and
        // composites the subtree once; SwiftUI's pushes down to every leaf and fades each one
        // separately — so the white page fill *underneath* the header band showed through the band
        // as the pair went transparent. The band lightened by 32 levels at the halfway point and
        // came back (`0x5f` → `0x80` → `0x5a`, exactly `90 + 152·a(1-a)`), which is the pale flash
        // on every return from the studio. One group, one fade, and the reference's own behaviour.
        .compositingGroup()
        // **Stage two, on its own flag, scheduled on the animation clock — never on a sleep.**
        // Two earlier shapes of this both measured wrong. `.animation(.glide(0.22).delay(0.3),
        // value: on)` never ran at all: the sheet held full opacity and vanished on the frame
        // `cardDesignOut` was cleared. A `Task.sleep(300)` before flipping `groundOut` ran ~230 ms
        // late, because `goDirect(.status)` has just put Status Club's first build and a full
        // store encode on the main thread, and a sleep resumes only when that thread is free —
        // so the card sat parked on a bare sheet for those frames and the morph read as a hold
        // then a cut. A delayed `withAnimation` is committed in the same transaction as the
        // content fade and paced by Core Animation, so it starts at 300 ms whatever the main
        // thread is doing. No `.animation(value:)` here: it would override that transaction.
        .opacity(exiting && groundOut ? 0 : 1)
        .onAppear {
            // `on` starts already at its end value (`exiting` for the exit copy, `false` for the
            // entrance), so a bare flip on the same update pass that mounts the view gives every
            // `.animation(_:value: on)` above nothing to interpolate from — first AND second
            // observed value are identical and the whole screen snaps. The reference has the same
            // problem and the same fix, one `requestAnimationFrame` before its `setOn` (app.jsx
            // ~3558): a CSS transition only fires if the browser committed a style pass at the
            // start value first. `Task.yield()` + one frame buys that same commit here.
            if exiting {
                Task { @MainActor in
                    await Task.yield()
                    try? await Task.sleep(for: .milliseconds(16))
                    guard !Task.isCancelled else { return }
                    // Stage one: the chrome and the card's travel, over their own 300 / 520 ms.
                    withAnimation(.glide(0.3)) { on = false }
                    // Stage two, the reference's own 300 ms delay then 220 ms: the card is ~92% of
                    // the way home when the sheet starts to dissolve, so the cross-fade overlays
                    // two cards a few points apart, never a slab.
                    withAnimation(.glide(0.22).delay(0.3)) { groundOut = true }
                    // 520 to finish, plus slack: this sleep can only run late, and late is safe —
                    // the layer is fully transparent long before it is dropped.
                    try? await Task.sleep(for: .milliseconds(640))
                    guard !Task.isCancelled else { return }
                    model.cardDesignOut = nil
                }
            } else {
                Task { @MainActor in
                    await Task.yield()
                    try? await Task.sleep(for: .milliseconds(16))
                    guard !Task.isCancelled else { return }
                    on = true
                }
            }
        }
    }

    // MARK: Background

    @ViewBuilder private var background: some View {
        if let veil = start.veil {
            // Opened from a rect: the originating screen's own colour uncovers the live card ground.
            liveBg
            Rectangle()
                .fill(veil)
                .opacity(on ? 0 : 1)
                .animation(.glide(on ? 0.52 : 0.46), value: on)
        } else if exiting {
            // **The exit dissolves the screen; it does not repaint it first.**
            //
            // This is the flicker on every return from the studio, and it is a porting bug rather
            // than a timing one. The reference (app.jsx ~3590) fades a `cloud-100` sheet in over
            // the whole screen on the way out — 240 ms, no delay — and at the same time shrinks
            // the coloured band to a literal `height: 500`. Both numbers are measured inside its
            // own 390 × 844 drawing, where 500 happens to land on the bottom of Status Club's
            // header band and `cloud-100` happens to be Status Club's page ground: the overlay
            // repaints itself into a copy of the screen underneath and then fades out, which is
            // invisible. Neither number survives the trip. On a real phone the club's hero is
            // ~392 pt tall, so a 500 pt band lays ~110 pt of header colour across the pale body,
            // and the page beneath is not `cloud100`. So the screen went face colour → **white,
            // with a mis-sized band across it** → club, and that third state is the flash.
            //
            // Holding the live ground and letting the layer's own `.opacity` carry it out deletes
            // the third state instead of trying to align it: there is nothing left to match, at
            // any screen size, on any face, against any page ground the club may ever paint. The
            // entrance is untouched — it keeps the reference's sheet exactly, because uncovering
            // *into* the studio is the direction those numbers were actually written for.
            Rectangle()
                .fill(liveBg)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // **`sky100`, not `cloud100` — the ground Status Club actually paints.** The reference's
            // `cloud-100` *is* its club's page ground, so its overlay starts as a copy of the screen
            // it is covering and the uncovering is invisible. This app's club body is one step down
            // (`StatusScreen`'s own `.background(TColor.sky100)`, and `RootView.groundFor(.status)`
            // agrees), so the reference's colour repainted the lower two thirds 16 levels lighter on
            // the first frame of every Customise and dropped back as the band grew over it.
            TColor.sky100
                .opacity(on ? 0 : 1)
                .animation(.glide(0.24).delay(on ? 0.32 : 0), value: on)
            Rectangle()
                .fill(on ? liveBg : savedHeader)
                // The real screen, not an iPhone 12's. As a literal 844 this fell 30pt short on a
                // 17 Pro and 112pt short on a 16 Pro Max, and what showed through was the layer
                // behind — computed from the *saved* variant and without `ownedFaces`, so a pale
                // fallback. That strip is the white band at the bottom of every non-white face.
                // The resting height is the club's own measured hero for the same reason the full
                // height is measured: 500 is 40pt short of it here, which flashed a pale strip
                // across the band on the first frame. See `heroBottom`.
                .frame(height: on ? UIScreen.main.bounds.height : heroBottom)
                .frame(maxHeight: .infinity, alignment: .top)
                .animation(.glide(on ? 0.52 : 0.46), value: on)
                // Colour tracks the finger 1:1 while dragging, and eases on the release.
                .animation(dragging ? nil : .glide(0.42), value: index)
        }
    }

    // MARK: Header

    private var headerRow: some View {
        HStack {
            Text("CARD DESIGN")
                .font(TFont.data(.medium, 11))
                .tracking(TFont.trackLabel * 11)
                .foregroundStyle(theme.mute)
            Spacer(minLength: 0)
            Button {
                model.closeCardDesign()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(theme.btnInk)
                    .frame(width: 36, height: 36)
                    .background(theme.btn, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            .disabled(exiting)
        }
        .padding(.leading, 20)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
    }

    // MARK: Deck

    private var deck: some View {
        ZStack {
            ForEach(set) { face in
                let k = face.id
                // The exit copy draws the neighbours too. It used to draw only the chosen card,
                // so the sliver of the next face at the screen edge vanished on the exit's first
                // frame — a pop, 300 ms before anything else on the screen moved. Drawn here, the
                // neighbours fade out over their own 380 ms with the rest of the chrome.
                do {
                    let off = CGFloat(k - index) * Self.step + dx * 0.62
                    let d = min(1, abs(off) / Self.step)
                    StatusCard(tier: tier, variant: k, name: model.cardName,
                               width: UIScreen.main.bounds.width - 48, owned: model.ownedFaces)
                        .shadow(color: Color(hex: 0x09111d, opacity: 0.5 - d * 0.34),
                                radius: (38 - d * 24) / 2, x: 0, y: 26 - d * 18)
                        .scaleEffect(1 - d * 0.15)
                        .offset(x: off)
                        .opacity(k == index ? 1 : (on ? 1 - Double(d) * 0.45 : 0))
                        .zIndex(10 - Double(d * 8).rounded())
                        .animation(dragging ? nil : .glide(0.42), value: off)
                        .animation(dragging ? nil : .glide(0.38), value: on)
                        .onTapGesture { browsing = k }
                        .accessibilityLabel(face.name)
                }
            }
        }
        .frame(height: 260)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .gesture(exiting ? nil : drag)
        .rotationEffect(.degrees(on ? 0 : start.rot))
        .scaleEffect(on ? 1 : start.scale)
        .offset(x: on ? 0 : start.dx, y: on ? 0 : start.dy)
        .animation(.glide(on ? 0.56 : 0.52), value: on)
    }

    /// Past a full slot of real travel the card only gains 30% of the excess, so the deck resists
    /// rather than running away.
    private var drag: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { g in
                dragging = true
                let raw = g.translation.width
                dx = abs(raw) <= Self.step
                    ? raw
                    : (raw < 0 ? -1 : 1) * (Self.step + (abs(raw) - Self.step) * 0.3)
            }
            .onEnded { _ in
                let travel = dx
                dragging = false
                dx = 0
                let move = travel < -Self.commit ? 1 : (travel > Self.commit ? -1 : 0)
                browsing = CardArt.slot(index + move, in: set)
            }
    }

    // MARK: Pager

    private var pager: some View {
        HStack(spacing: 6) {
            ForEach(set) { face in
                Button {
                    browsing = face.id
                } label: {
                    Capsule()
                        .fill(face.id == index ? theme.accent : theme.idle)
                        .frame(width: face.id == index ? 24 : 8, height: 8)
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(face.name)
                .disabled(exiting)
            }
        }
        .animation(.glide(0.32), value: index)
        .frame(maxWidth: .infinity)
    }

    // MARK: Title

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                // The reference builds this by prepending a literal "0", which misprints from ten
                // faces up; a purchased face can take a tier there, so it is zero-padded properly.
                Text(String(format: "DESIGN %02d OF %02d", index + 1, set.count))
                    .font(TFont.data(.medium, 11))
                    .tracking(TFont.trackLabel * 11)
                    .foregroundStyle(theme.mute)

                if locked {
                    HStack(spacing: 5) {
                        Image(systemName: "lock.fill").font(.system(size: 10))
                        Text("BUSINESS CLASS")
                            .font(TFont.data(.medium, 11))
                            .tracking(0.12 * 11)
                    }
                    .foregroundStyle(theme.chipInk)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(theme.chip, in: Capsule())
                }
            }

            Text(set.indices.contains(index) ? set[index].name : "")
                .font(TFont.core(.bold, 34))
                .tracking(-0.045 * 34)
                .foregroundStyle(theme.ink)
        }
    }

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: 8) {
            Button {
                if locked { model.paywall = .open; return }
                model.closeCardDesign(saving: index)
            } label: {
                HStack(spacing: 9) {
                    if locked { Image(systemName: "lock.fill").font(.system(size: 16)) }
                    Text(locked ? "Unlock with Business Class" : "Use this design")
                        .font(TFont.core(.semibold, 16))
                }
                .foregroundStyle(theme.btnInk)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(theme.btn, in: Capsule())
                // `0 12px 28px -16px th.btn` — the button casting in its own paint, so the
                // spread folds into an opacity rather than into a tint of its own.
                .shadow(color: theme.btn.opacity(0.2531), radius: 14, x: 0, y: 12)
            }
            .buttonStyle(.plain)
            .disabled(exiting)

            Button {
                model.closeCardDesign()
            } label: {
                Text("Cancel")
                    .font(TFont.core(.medium, 15))
                    .foregroundStyle(theme.mute)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
            }
            .buttonStyle(.plain)
            .disabled(exiting)
        }
        .animation(.glide(0.42), value: index)
    }
}

// MARK: - Absolute placement on the screen

private extension View {
    func cdTop(_ y: CGFloat, inset: CGFloat = 0) -> some View {
        padding(.horizontal, inset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, y)
            .frame(maxHeight: .infinity, alignment: .top)
    }

    func cdBottom(_ y: CGFloat, inset: CGFloat = 0) -> some View {
        padding(.horizontal, inset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, y)
            .frame(maxHeight: .infinity, alignment: .bottom)
    }

    /// The four control groups reveal in sequence 60ms apart, 180ms in; leaving, they all go at once.
    func cdFade(_ on: Bool, _ k: Int) -> some View {
        opacity(on ? 1 : 0)
            .animation(.glide(on ? 0.4 : 0.3).delay(on ? 0.18 + Double(k) * 0.06 : 0), value: on)
    }
}
