import SwiftUI

/// The detail sheet for a face or a header — never a gift, which goes through `GiftScreen`
/// instead. Drawn by `ConcourseScreen` as an overlay while `model.shopSelection` is set; its own
/// `.id()` there gives every fresh open a clean `@State`, and `leave()` keeps the same identity
/// alive through its own 740 ms exit before finally clearing the selection.
struct ShopItemScreen: View {
    @Environment(AppModel.self) private var model

    @State private var on = false
    @State private var out = false
    @State private var flip = false
    @State private var hadOwned: Bool?
    @State private var boughtDuringVisit = false
    @State private var fresh = false
    @State private var freshTask: Task<Void, Never>?
    @State private var leaveTask: Task<Void, Never>?

    var body: some View {
        if let sel = model.shopSelection {
            item(sel)
        }
    }

    @ViewBuilder
    private func item(_ sel: AppModel.ShopSelection) -> some View {
        let face = sel.kind == .face ? ShopCatalog.face(id: sel.id) : nil
        let head = sel.kind == .header ? ShopCatalog.header(id: sel.id) : nil
        let twoSided = face?.t == Status.founderIndex
        let owned = sel.kind == .face
            ? model.ownedFaces.contains(sel.id) : model.ownedHeaders.contains(sel.id)
        let paying = model.payFlow != nil || model.payCheck != nil
        let free = model.status.founders
        let rawPrice = face?.price ?? head?.price ?? 0
        let displayPrice = free ? 0 : rawPrice

        // Hoisted out of the hero's `GeometryReader` below: neither one reads `geo`.
        let restW: CGFloat = face != nil ? 310 : HeaderPassMock.designW
        let restH: CGFloat = face != nil ? restW * 214 / 340 : HeaderPassMock.designH
        // The point on the hero that sits on the tile. A face scales about its own centre;
        // a header is only the band across the top of a whole pass, so the pass is scaled
        // about that band's centre instead (the reference's `transform-origin:175px 49px`)
        // — anchoring on the pass centre landed the barcode on the tile and left the header
        // floating above it on the way back.
        let anchorY: CGFloat = face != nil ? restH / 2 : 49
        let anchor = UnitPoint(x: 0.5, y: anchorY / restH)
        ZStack {
            GeometryReader { geo in
                // And on the tile: its art row is 104 tall, 16 down, so the art's centre is
                // `top + 68` — not the tile's own centre, which sits below it among the name and
                // the price. Aiming at the centre landed the card 27pt low, and the cut at 740ms
                // then read as the card teleporting into place.
                let tileAnchor = CGPoint(x: sel.rect.midX, y: sel.rect.minY + ConcourseShopTile.artCentreY)
                let restAnchor = CGPoint(x: geo.size.width / 2, y: Self.chromeTop + 96 + anchorY)
                let t: Double = (on && !out) ? 1 : 0
                let ax = TEase.lerp(tileAnchor.x, restAnchor.x, t)
                let ay = TEase.lerp(tileAnchor.y, restAnchor.y, t)
                let scale = TEase.lerp(140 / restW, 1, t)
                let rot = face != nil ? TEase.lerp(-7, 0, t) : 0

                hero(face: face, head: head, twoSided: twoSided, restW: restW, restH: restH,
                     passIn: on && !out)
                    .frame(width: restW, height: restH)
                    .scaleEffect(scale, anchor: anchor)
                    .rotationEffect(.degrees(rot), anchor: anchor)
                    // `.position` centres the layout frame, so the anchor is offset back out of it.
                    .position(x: ax, y: ay + restH / 2 - anchorY)
                    .animation(t == 1 ? .glide(0.82) : .glide(0.6).delay(0.16), value: t)
                    .onTapGesture {
                        guard twoSided else { return }
                        withAnimation(.glide(TDur.scene)) { flip.toggle() }
                    }
            }

            VStack(spacing: 0) {
                topRow
                Spacer(minLength: 0)
                panel(sel: sel, face: face, head: head, twoSided: twoSided, owned: owned,
                      paying: paying, displayPrice: displayPrice)
            }
            .padding(.bottom, Self.panelBottom)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TColor.cloud100)
        // The reference fades this whole screen's own root — background included — from 1 to 0
        // over 260ms, delayed 600ms (so it is still mid-fade at the 740ms mark `leave()` removes
        // it on). Ported without this the screen sat fully opaque right up to that instant, so its
        // removal landed on a shelf that was itself only ~43% back into `ConcourseScreen`'s own
        // 560ms-delayed/420ms undim — an opaque cut onto a half-faded shelf reads as a jump.
        // `.compositingGroup()` is required here (see CLAUDE.md): without it the fill and the
        // content above it fade as separate leaves instead of one flat layer.
        .compositingGroup()
        .opacity(out ? 0 : 1)
        .animation(.glide(0.26).delay(0.6), value: out)
        .onAppear {
            evaluateFreshness(owned: owned, paying: paying)
            Task {
                await Task.yield()
                try? await Task.sleep(for: .milliseconds(16))
                withAnimation(.glide(0.82)) { on = true }
            }
        }
        .onChange(of: owned) { _, _ in evaluateFreshness(owned: owned, paying: paying) }
        .onChange(of: paying) { _, _ in evaluateFreshness(owned: owned, paying: paying) }
    }

    // MARK: - "Fresh" (just-bought) shine, once and only once per screen instance

    private func evaluateFreshness(owned: Bool, paying: Bool) {
        guard let had = hadOwned else { hadOwned = owned; return }
        if owned, !had { boughtDuringVisit = true }
        hadOwned = owned
        guard boughtDuringVisit, !paying else { return }
        freshTask?.cancel()
        freshTask = Task {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            fresh = true
        }
    }

    // MARK: - Hero

    @ViewBuilder
    private func hero(face: ShopFace?, head: ShopHeader?, twoSided: Bool,
                      restW: CGFloat, restH: CGFloat, passIn: Bool) -> some View {
        if let face {
            ZStack {
                MarkupView(face.inner(for: model.cardName), background: face.ground, designSize: CGSize(width: 340, height: 214),
                          width: restW, cornerRadius: 19, shine: fresh)
                    .opacity(flip ? 0 : 1)
                if twoSided {
                    FoundersCardBack(face: face, width: restW, member: model.cardName, miles: model.pool)
                        .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                        .opacity(flip ? 1 : 0)
                }
            }
            .rotation3DEffect(.degrees(flip ? 180 : 0), axis: (x: 0, y: 1, z: 0),
                              perspective: 1 / 1400)
            // `0 34px 60px -24px rgba(16,29,49,.65)`, on the card box — never on its artwork's
            // own leaves, which would print a soft copy of every mark on the face.
            .compositingGroup()
            .shadow(color: Color(hex: 0x101d31, opacity: 0.2754), radius: 30, y: 34)
        } else if let head {
            HeaderPassMock(header: head, width: restW, passIn: passIn)
        }
    }

    // `0 4px 12px -8px rgba(16,29,49,.5)` — the reference hand-rolls this back button and the
    // miles pill with their own tighter shadow rather than the shared `IconButton`/`--shadow-card`,
    // so this row does too instead of routing through the design-system default.
    /// The reference pads 56 from the top of a frame that has no status bar. This screen is laid
    /// out *inside* the safe area, which has already paid ~59pt of that, so the two stacked and put
    /// the chrome a full status bar too low — the same correction `TSpace.topInset` makes for the
    /// Concourse and the linked-account page.
    ///
    /// **It is a literal here, and `TSpace.topInset(56)` is not called.** That helper reads
    /// `UIApplication.shared`'s key window, and reading UIKit state from inside this screen's body
    /// is not free: the hero is positioned by a `GeometryReader` + `.position` off this number, and
    /// the window read made that geometry unstable enough that the entrance never ran at all — the
    /// card sat frozen at its shelf-tile rect and the panel never arrived. Every phone this ships to
    /// has a top inset between 47 and 62, so the correction is a constant.
    /// ponytail: a literal, because the only alternative that keeps the helper is latching the
    /// inset into `@State` on appear, which costs a frame of jump to buy nothing.
    private static let chromeTop: CGFloat = 14

    /// The reference's own `position:absolute; bottom:20px`, restored on 21 Sep 2026. The panel
    /// hung a fixed 20pt under the hero's settled bottom edge for a while, on the reasoning that a
    /// sheet floating mid-page reads as unrelated to the card above it. On a real phone the
    /// opposite is what reads badly: the hero settles high, so the panel lands in the middle of the
    /// screen with a field of empty ground under it and nothing to sit on. Pinned to the bottom it
    /// is a sheet the page stands on, which is what the reference drew.
    private static let panelBottom: CGFloat = 20

    private static let topRowShadow = (color: Color(hex: 0x101d31, opacity: 0.0912), radius: CGFloat(6), y: CGFloat(4))

    private var topRow: some View {
        HStack {
            Button(action: leave) {
                Image(systemName: "chevron.left")
                    .foregroundStyle(TColor.navy700)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(TColor.white))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")
            .compositingGroup()
            .shadow(color: Self.topRowShadow.color, radius: Self.topRowShadow.radius, y: Self.topRowShadow.y)
            Spacer()
            HStack(spacing: 4) {
                MilesTicker(value: model.pool)
                Text("MI").font(TFont.data(.medium, 11)).tracking(0.16 * 11)
            }
            .foregroundStyle(TColor.textPrimary)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(Capsule().fill(TColor.white))
            .compositingGroup()
            .shadow(color: Self.topRowShadow.color, radius: Self.topRowShadow.radius, y: Self.topRowShadow.y)
        }
        .padding(.horizontal, 20)
        .padding(.top, Self.chromeTop)
        .opacity(out ? 0 : 1)
        // The reference's own `opacity 200ms {E}` — `E` is its glide curve alias (confirmed
        // against `app.jsx`), not `linear`. This row had drifted onto `.linear`; `GiftScreen`'s
        // identical top row carried the same drift.
        .animation(.glide(0.2), value: out)
    }

    // MARK: - Detail panel

    /// Pinned to the bottom of the page — see `panelBottom` — and wearing the reference's own
    /// `0 22px 50px -26px rgba(16,29,49,.65)` again, which is the right elevation for a sheet with
    /// the page's ground above it. (It was dropped while the panel hung directly under the hero,
    /// where it stacked with the card's own shadow and read as two objects; nothing is under the
    /// card any more.) Through `ShadowLayer.css`: sigma = 50/2, the -26 spread folds into the alpha.
    @ViewBuilder
    private func panel(sel: AppModel.ShopSelection, face: ShopFace?, head: ShopHeader?,
                       twoSided: Bool, owned: Bool, paying: Bool, displayPrice: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // `500 10px/1 var(--font-data)` at `.2em`, and the value 12 below it — the panel's own
            // register, wider-tracked and a point smaller than the 11pt `LBL` elsewhere.
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(face != nil ? "CARD FACE" : "PASS HEADER")
                        .font(TFont.data(.medium, 10)).tracking(0.2 * 10)
                        .foregroundStyle(TColor.textMuted)
                    Text(face?.name ?? head?.name ?? "")
                        .font(TFont.core(.bold, 26))
                        .tpType(size: 26, track: -0.04, lineHeight: 1.08)
                        .foregroundStyle(TColor.textPrimary)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 12) {
                    Text("PRICE")
                        .font(TFont.data(.medium, 10)).tracking(0.2 * 10)
                        .foregroundStyle(TColor.textMuted)
                    Text(displayPrice == 0 ? "Free" : "\(displayPrice) mi")
                        .font(TFont.core(.bold, 26))
                        .tpType(size: 26, track: -0.04, lineHeight: 1.08)
                        .foregroundStyle(TColor.textPrimary)
                        .fixedSize()
                }
            }

            if twoSided {
                Text("TAP THE CARD TO TURN IT OVER").tpLabelStyle()
                    .foregroundStyle(TColor.textMuted)
                    .padding(.top, 14)
            }
            if head != nil {
                Text("Owned headers come up at random on your next flights.")
                    .font(TFont.core(.regular, 14))
                    .tpType(size: 14, lineHeight: 1.45)
                    .foregroundStyle(TColor.textSecondary)
                    .padding(.top, 14)
            }

            ShopActions(
                isFace: face != nil, owned: owned, price: displayPrice, pool: model.pool, paying: paying,
                locked: locked(face: face, head: head),
                onBuy: { buy(sel: sel, face: face, head: head, price: displayPrice) },
                onUse: { if let face { useCard(face) } },
                onCustomise: customise
            )
            .padding(.top, 24)
        }
        .padding(24)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(TColor.white))
        .compositingGroup()
        .shadow(color: Color(hex: 0x101d31, opacity: 0.1939), radius: 25, x: 0, y: 22)
        .padding(.horizontal, 20)
        .opacity(on && !out ? 1 : 0)
        .animation((on && !out) ? .glide(0.52).delay(0.46) : .glide(0.22), value: on && !out)
        .offset(y: (on && !out) ? 0 : 24)
        .animation((on && !out) ? .glide(0.68).delay(0.42) : .glide(0.3), value: on && !out)
    }

    // MARK: - Actions

    /// Business Class stock, without the plan. The item still opens and still shows its art at
    /// full size — what is gated is the purchase, not the looking.
    private func locked(face: ShopFace?, head: ShopHeader?) -> Bool {
        guard !model.plus else { return false }
        if let face { return ShopCatalog.businessOnly(face) }
        if let head { return ShopCatalog.businessOnly(head) }
        return false
    }

    /// `onBuy` never touches the balance itself — it only opens the same payment ritual Redeem
    /// uses; `AppModel.payOrder` is the one place miles actually move.
    ///
    /// A locked item never reaches `payOrder`: it has no price to this member yet, so the button
    /// sells the plan instead. Charging miles for something the plan is what actually unlocks
    /// would take payment twice for one thing.
    private func buy(sel: AppModel.ShopSelection, face: ShopFace?, head: ShopHeader?, price: Int) {
        guard !locked(face: face, head: head) else { model.paywall = .open; return }
        model.payFlow = Order(kind: sel.kind, cost: price, name: face?.name ?? head?.name ?? "",
                              itemID: sel.id)
    }

    /// Jumps straight out to Status Club rather than back through the shelf (§4.9).
    private func useCard(_ face: ShopFace) {
        model.cardVariant[face.t] = ShopItemScreen.combinedIndex(
            ownedFaces: model.ownedFaces, id: face.id, tier: face.t)
        model.shopSelection = nil
        model.shopLeaving = false
        model.go(.status, .lift, dir: -1)
    }

    private func customise() {
        model.shopSelection = nil
        model.shopLeaving = false
        model.go(.carddesign, .zoom)
    }

    private func leave() {
        out = true
        model.shopLeaving = true
        leaveTask?.cancel()
        leaveTask = Task {
            try? await Task.sleep(for: .milliseconds(740))
            guard !Task.isCancelled else { return }
            model.shopSelection = nil
            model.shopLeaving = false
        }
    }

    /// `cardVariant[tier]` indexes "built-ins first, then owned Concourse faces in purchase
    /// order" (`facesFor`). The built-in counts — Essential 4, Signature 3, Premier 4, Prestige 4,
    /// Founders 5 — come from `CARD_VARIANTS` (spec `04-status-cards.md` §4), which `CardArt`
    /// ports; this is the one place a Concourse purchase writes into that combined list, so the
    /// count is duplicated here rather than reached for across screens neither of us owns yet.
    static let builtInFaceCounts = [4, 3, 4, 4, 5]

    static func combinedIndex(ownedFaces: [String], id: String, tier: Int) -> Int {
        let ofTier = ownedFaces.filter { ShopCatalog.face(id: $0)?.t == tier }
        let position = ofTier.firstIndex(of: id) ?? max(0, ofTier.count - 1)
        let base = tier < builtInFaceCounts.count ? builtInFaceCounts[tier] : builtInFaceCounts[0]
        return base + position
    }
}

// MARK: - The buy / owned state machine

/// Two absolutely-stacked layers in one animated-height box, so nothing translates and a fade is
/// never racing a move — the reference's own description of `ShopActions`.
private struct ShopActions: View {
    let isFace: Bool
    let owned: Bool
    /// Already zeroed for Founders.
    let price: Int
    let pool: Int
    let paying: Bool
    /// Business Class stock, without the plan — the button sells the plan rather than the item.
    let locked: Bool
    let onBuy: () -> Void
    let onUse: () -> Void
    let onCustomise: () -> Void

    @State private var show: Bool
    @State private var showTask: Task<Void, Never>?

    init(isFace: Bool, owned: Bool, price: Int, pool: Int, paying: Bool, locked: Bool,
        onBuy: @escaping () -> Void, onUse: @escaping () -> Void, onCustomise: @escaping () -> Void) {
        self.isFace = isFace
        self.owned = owned
        self.price = price
        self.pool = pool
        self.paying = paying
        self.locked = locked
        self.onBuy = onBuy
        self.onUse = onUse
        self.onCustomise = onCustomise
        _show = State(initialValue: owned && !paying)
    }

    /// Short of miles. A locked item is not short of anything — the plan is the price — so it
    /// never wears the "you need N mi more" state, which would name a number that buys nothing.
    private var lack: Bool { !locked && price > 0 && price > pool && !owned }
    private var hOwn: CGFloat { isFace ? 112 : 52 }

    var body: some View {
        // Both layers are `position:absolute; top:0` in the reference, so neither one measures the
        // box: its height is only ever `show ? H_OWN : H_BUY`. A `ZStack` would take the taller
        // layer's height instead and then centre it inside the frame — which hangs the 112pt owned
        // layer 28pt above the box and puts the buy button through the item's name.
        Color.clear
            .frame(height: show ? hOwn : 56)
            .overlay(alignment: .top) {
                buyLayer
                    .opacity(show ? 0 : 1)
                    .animation(.linear(duration: show ? 0.24 : 0.36), value: show)
                    .allowsHitTesting(!show)
            }
            .overlay(alignment: .top) {
                ownedLayer
                    .opacity(show ? 1 : 0)
                    .animation(.linear(duration: show ? 0.42 : 0.2).delay(show ? 0.7 : 0), value: show)
                    .allowsHitTesting(show)
            }
            // `FLOAT_E = cubic-bezier(.32,.08,.24,1)` (app.jsx, declared just above `ShopActions`)
            // — a second, deliberately named reference curve, not a drifted copy of the house
            // `E`/`glide` (.22,.61,.36,1). The reference's own comment on it: "a softer entrance...
            // more travel, no front-loaded snap, so they drift up into place rather than popping
            // in" — `glide` front-loads (`y≈.61` at `x=.22`), which is exactly the snap this box's
            // height transition is written to avoid, so this is not a candidate for consolidating
            // onto `Animation.glide`. 620 ms, `FLOAT_E`, is only ever used for this one height.
            .animation(.timingCurve(0.32, 0.08, 0.24, 1, duration: 0.62), value: show)
            .onAppear { schedule() }
            .onChange(of: owned) { _, _ in schedule() }
            .onChange(of: paying) { _, _ in schedule() }
    }

    private func schedule() {
        showTask?.cancel()
        guard owned else { show = false; return }
        guard !paying else { return }
        showTask = Task {
            try? await Task.sleep(for: .milliseconds(90))
            guard !Task.isCancelled else { return }
            show = true
        }
    }

    private var buyLabel: String {
        if locked { return "Business Class" }
        if lack { return "You need \(price - pool) mi more" }
        if price == 0 { return "Take it" }
        return "Buy for \(price) mi"
    }

    private var buyLayer: some View {
        Button(action: onBuy) {
            Text(buyLabel)
                .font(TFont.core(.semibold, 17))
                .foregroundStyle(lack ? TColor.steel600 : TColor.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Capsule().fill(lack ? TColor.sky200 : TColor.navy900))
        }
        .buttonStyle(.plain)
        .disabled(owned || lack)
    }

    @ViewBuilder private var ownedLayer: some View {
        if isFace {
            VStack(spacing: 8) {
                Button(action: onUse) {
                    Text("Use this card")
                        .font(TFont.core(.semibold, 17))
                        .foregroundStyle(TColor.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Capsule().fill(TColor.navy900))
                }
                .buttonStyle(.plain)
                Button(action: onCustomise) {
                    Text("Customise")
                        .font(TFont.core(.semibold, 15))
                        .foregroundStyle(TColor.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .overlay(Capsule().stroke(TColor.borderDefault, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        } else {
            Text("In your rotation")
                .font(TFont.core(.semibold, 15))
                .foregroundStyle(TColor.statusOnTime)
                .frame(maxWidth: .infinity, alignment: .center)
                .frame(height: 52)
        }
    }
}

// MARK: - The generic Founders card back

/// `shopBackHTML`, native: the reverse of a two-sided Founders face. The call site here hardcodes
/// `serial 001` / `issued —` exactly as the reference does — this is a generic specimen preview,
/// not the member's actual issued card (that lives on the real `StatusCard`, outside this slice).
private struct FoundersCardBack: View {
    let face: ShopFace
    let width: CGFloat
    let member: String
    let miles: Int

    private static let designW: CGFloat = 340
    private static let designH: CGFloat = 214

    var body: some View {
        let dark = ShopCatalog.groundIsDark(face.ground)
        let ink = dark ? Color(hex: 0xf4eee2, opacity: 0.94) : Color(hex: 0x18181e, opacity: 0.92)
        let mute = dark ? Color(hex: 0xf4eee2, opacity: 0.6) : Color(hex: 0x18181e, opacity: 0.55)
        let rule = dark ? Color(hex: 0xf4eee2, opacity: 0.16) : Color(hex: 0x18181e, opacity: 0.14)
        let k = width / Self.designW

        ZStack(alignment: .topLeading) {
            // The face's material without its lettering — see `FoundersBack.material` in
            // CardArt.swift and `MarkupStore.material(_:)`. The ground alone is not the card:
            // most Founders faces keep their colour in the art.
            MarkupView(face.inner, background: face.ground,
                      designSize: CGSize(width: Self.designW, height: Self.designH),
                      width: Self.designW, cornerRadius: 19, materialOnly: true)
            // The same flat scrim `FoundersBack.material` takes, and for the same reason: the ink
            // triad below is chosen once from the ground, and a face's art need not agree with its
            // ground across the whole card.
            Color(dark ? .black : .white).opacity(0.38)
            LinearGradient(colors: [Color.black.opacity(0.16), .clear],
                           startPoint: .topTrailing, endPoint: .center)

            HStack(alignment: .top, spacing: 0) {
                labelValue("DATE ISSUED", "\u{2014}", mute: mute, ink: ink, trailing: false)
                Spacer(minLength: 0)
                labelValue("EDITION", "No. 001 of 100", mute: mute, ink: ink, trailing: true)
            }
            .padding(.horizontal, 26)
            .frame(width: Self.designW)
            .offset(y: 26)

            Rectangle().fill(rule).frame(width: Self.designW - 52, height: 1)
                .offset(x: 26, y: 104)

            HStack(alignment: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("MILES").font(TFont.data(.medium, 9)).tracking(0.18 * 9).foregroundStyle(mute)
                    // `tpText`: a formatted mile count ends in a digit as often as not — the same
                    // clip Typography.swift documents, just at a smaller size than the dials.
                    tpText(miles.formatted(.number.locale(Locale(identifier: "en_US"))), size: 24, track: -0.035)
                        .font(TFont.core(.bold, 24)).foregroundStyle(ink)
                }
                Spacer(minLength: 0)
                labelValue("NAME", member.isEmpty ? "Tempus member" : member,
                          mute: mute, ink: ink, trailing: true)
            }
            .padding(.horizontal, 26)
            .frame(width: Self.designW)
            .offset(y: 126)
        }
        .frame(width: Self.designW, height: Self.designH, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 19))
        .scaleEffect(k, anchor: .topLeading)
        .frame(width: width, height: Self.designH * k, alignment: .topLeading)
    }

    private func labelValue(_ label: String, _ value: String, mute: Color, ink: Color,
                            trailing: Bool) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 4) {
            Text(label).font(TFont.data(.medium, 9)).tracking(0.18 * 9).foregroundStyle(mute)
            Text(value).font(TFont.core(.semibold, 15)).foregroundStyle(ink)
        }
    }
}

// MARK: - The mock boarding pass built around a header

/// A header on its own means nothing, so the item screen wraps it in a full mock pass — the same
/// visual language as the real boarding pass tear line, reproduced here as a static specimen.
/// `FROM` reads the member's real home airport; `TO` and the membership number are hardcoded in
/// the reference (always `HND`, always `TP 1042`) and reproduced as written.
///
/// The three pieces are separate boxes, as they are in the reference: the top block and the
/// barcode block each carry their own shadow and the seam between them carries none, because the
/// seam is where the paper is meant to read as *cut*, not as raised.
struct HeaderPassMock: View {
    @Environment(AppModel.self) private var model
    let header: ShopHeader
    let width: CGFloat
    let passIn: Bool

    static let designW: CGFloat = 292
    /// Band (292 × 90/268) + body + the 24pt seam + the barcode block, at the reference's numbers.
    static let designH: CGFloat = 288

    /// The reference stages the pass body (`bodyAnim`, app.jsx:4545-4546) as a soft opacity+
    /// translateY overlap, never gated on the band actually finishing — this port goes further,
    /// as asked: a real two-stage print. The band carries no opacity/offset of its own, only the
    /// outer rigid transform (`ShopItemScreen.item(_:)`) moves it, so it never fades with the
    /// body. The body — passenger row, seam, barcode — grows out from the band's bottom edge via
    /// an animated `.mask`.
    /// **Open**: 260ms delay (the reference's own 240-260ms stagger) then a 420ms reveal — timed
    /// so the print visibly starts only once the 820ms fly has essentially landed. **Close**: no
    /// delay, 160ms — chosen to finish inside the outer close's own 160ms delay
    /// (`ShopItemScreen.item(_:)`'s `.glide(0.6).delay(0.16)`), so the body is gone before the
    /// band starts flying back to the shelf.
    ///
    /// **The mask's target height is what the "print" actually reveals, so it has to be close to
    /// the body's real height, not a "generous" one.** This shipped with a `Rectangle().frame(
    /// height: passIn ? 1000 : 0)` on the theory that the mask only clips what's already laid
    /// out, so an oversized window "costs nothing" — true for the resting frame, false for the
    /// animation: `.animation` interpolates the mask's *height*, so 0→1000 spends 81% of the
    /// 420ms open reveal growing a mask that is already past the ~190pt-tall body (nothing left
    /// to reveal) before the curve is even a fifth done — the print reads as an near-instant pop,
    /// not a growth. Close is worse: it starts from 1000, and 81% of the 160ms retract elapses
    /// before the mask edge re-enters the body at all, so the whole visible retraction happens in
    /// the curve's last sliver — a snap, which is exactly what the user reported ("practically
    /// not really working, not really smooth"). `printMaskCap` is sized to the body's actual
    /// layout height (108 passenger row + 24 seam + 58 barcode block = 190) plus enough slack for
    /// the barcode block's own drop shadow (`y: 24, radius: 20`) to clear the mask at rest — not
    /// a measured height, so still no `GeometryReader` needed, just a constant close enough to the
    /// real content that most of the curve is spent actually revealing or retracting it.
    private static let printMaskCap: CGFloat = 272
    /// **A mask clips shadows too, and a rectangle clips them into a rectangle.** The body's two
    /// blocks cast `0 24px 40px -22px` and `0 -2px 40px -18px` from inside this mask, so a plain
    /// `Rectangle` the width of the pass cut the barcode block's shadow off flat at the card's own
    /// left and right edges and again at the cap — a grey slab with three hard sides and a
    /// gradient down its middle, sitting under the pass. The mask is therefore *wider* than the
    /// pass it reveals (nothing to cut at the sides) and its bottom edge is a fade rather than a
    /// line (nothing to cut at the tail). The opaque edge still lands at 240, so the print's
    /// pacing is exactly what it was: 272 · (1 − 32/272) = 240.
    private static let printMaskFeather: CGFloat = 32
    private static let printMaskBleed: CGFloat = 90
    private static let openDelay = 0.26

    var body: some View {
        let k = width / Self.designW
        VStack(spacing: 0) {
            MarkupView(header.inner, background: header.bg,
                      designSize: CGSize(width: 268, height: 90),
                      width: Self.designW, cornerRadius: 0)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 0,
                                                  bottomTrailingRadius: 0, topTrailingRadius: 18))
                // `0 -2px 40px -18px rgba(16,29,49,.5)`
                .compositingGroup()
                .shadow(color: Color(hex: 0x101d31, opacity: 0.1841), radius: 20, y: -2)

            VStack(spacing: 0) {
                passengerRow
                PerforationSeam()
                    .frame(height: 24)
                PassBarcode()
                    .padding(.init(top: 6, leading: 18, bottom: 16, trailing: 18))
                    .background(TColor.white)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 18,
                                                      bottomTrailingRadius: 18, topTrailingRadius: 0))
                    // `0 24px 40px -22px rgba(16,29,49,.5)`
                    .compositingGroup()
                    .shadow(color: Color(hex: 0x101d31, opacity: 0.1357), radius: 20, y: 24)
            }
            .mask(alignment: .top) { printMask }
            .opacity(passIn ? 1 : 0)
            .animation(passIn ? .glide(TDur.slow).delay(Self.openDelay) : .glide(TDur.fast), value: passIn)
        }
        .frame(width: Self.designW)
        .scaleEffect(k, anchor: .top)
        .frame(width: width)
    }

    /// The print window: opaque over the pass, fading out past it, and bled well past both edges
    /// so the blocks' own shadows are never cut into a rectangle. The stops are fractions of the
    /// animating height, so the soft edge scales with the print rather than sitting at a fixed
    /// point through it.
    private var printMask: some View {
        let h = passIn ? Self.printMaskCap : 0
        let solid = h > 0 ? max(0, 1 - Self.printMaskFeather / h) : 0
        return LinearGradient(stops: [.init(color: .black, location: 0),
                                      .init(color: .black, location: solid),
                                      .init(color: .clear, location: 1)],
                              startPoint: .top, endPoint: .bottom)
            .frame(width: Self.designW + Self.printMaskBleed * 2, height: h)
    }

    /// Every line on the pass is set `line-height:1`, and SwiftUI's line box is taller than its
    /// ink — so each one is given its own type size as a height, or the block grows ~17pt and the
    /// seam lands low.
    private var passengerRow: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(model.cardName)
                    .font(TFont.core(.semibold, 15))
                    .foregroundStyle(TColor.textPrimary)
                Spacer(minLength: 0)
                Text("TP 1042")
                    .font(TFont.data(.medium, 10)).tracking(0.16 * 10)
                    .foregroundStyle(TColor.textMuted)
            }
            .frame(height: 15)
            // The rule runs just under the codes, not through their middle: the reference
            // bottom-aligns it in a `line-height:1` box, which puts it a few points above
            // the baseline. SwiftUI's text box is taller than its ink, so the rule is hung
            // off the baseline itself rather than off the box.
            HStack(alignment: .lastTextBaseline, spacing: 0) {
                endpoint("FROM", model.homeAirport.code, trailing: false)
                DashedLine()
                    .stroke(TColor.sky300, style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    .frame(height: 1)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 6)
                    .alignmentGuide(.lastTextBaseline) { $0[.bottom] + 3.5 }
                endpoint("TO", "HND", trailing: true)
            }
            .padding(.top, 18)
        }
        .padding(.init(top: 16, leading: 18, bottom: 18, trailing: 18))
        .background(TColor.white)
    }

    /// `500 9px/1 var(--font-data)` at `.18em` over a 24pt code — the pass's own register, not the
    /// 11pt `LBL` the rest of the screen uses.
    private func endpoint(_ label: String, _ code: String, trailing: Bool) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 0) {
            Text(label)
                .font(TFont.data(.medium, 9)).tracking(0.18 * 9)
                .foregroundStyle(TColor.textMuted)
                .frame(height: 9)
            Text(code)
                .font(TFont.core(.bold, 24)).tracking(-0.035 * 24)
                .foregroundStyle(TColor.textPrimary)
                .frame(height: 24)
                .padding(.top, 8)
        }
    }
}

/// The perforated seam between a pass's header and its barcode: a white band with a half-disc
/// bitten out of each edge, and the dashed tear line between them.
///
/// The bites are *subtracted* from the band rather than painted over it in the desk's colour —
/// paint would have to know what it is sitting on, and the seam is carried across a shadowed
/// morph where nothing behind it is a flat colour.
private struct PerforationSeam: View {
    var body: some View {
        NotchedBand()
            .fill(TColor.white)
            .overlay {
                DashedLine()
                    .stroke(TColor.sky300, style: StrokeStyle(lineWidth: 1, dash: [4, 5]))
                    .frame(height: 1)
                    .padding(.horizontal, 20)
            }
    }
}

private struct NotchedBand: Shape {
    func path(in rect: CGRect) -> Path {
        let r = rect.height / 2
        let bite = { (x: CGFloat) in
            Path(ellipseIn: CGRect(x: x - r, y: rect.midY - r, width: r * 2, height: r * 2))
        }
        return Path(rect).subtracting(bite(rect.minX)).subtracting(bite(rect.maxX))
    }
}

/// The mock pass's fixed 30-bar barcode: authored widths in points, 2pt apart, flush left — it is
/// a stamp of a fixed size, not a rule that stretches to whatever box it is given.
private struct PassBarcode: View {
    static let widths: [CGFloat] = [
        2, 1, 3, 1, 2, 4, 1, 2, 3, 1, 2, 1, 4, 2, 1, 3, 2, 1, 2, 3, 1, 4, 1, 2, 2, 1, 3, 1, 2, 4,
    ]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(Self.widths.enumerated()), id: \.offset) { _, w in
                Rectangle().fill(TColor.navy700).frame(width: w)
            }
        }
        .frame(height: 36)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
