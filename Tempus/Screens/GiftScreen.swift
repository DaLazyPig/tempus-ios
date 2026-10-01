import SwiftUI

/// The Concourse's gift flow: pick an amount, wrap it in one of the 18 gift faces, address it to a
/// name and an email — a real recipient, not a pick from a roster of fabricated people. Unrelated
/// to the Founders "gift a Prestige card" invite on Status Club, which shares nothing but the word
/// — that one is free-text, one-time, and owned by `StatusScreen`.
///
/// Drawn by `ConcourseScreen` as an overlay while `model.giftOpen` is set, exactly like
/// `ShopItemScreen` — same fresh-identity-per-open, same 740 ms `leave()`.
struct GiftScreen: View {
    @Environment(AppModel.self) private var model

    @State private var step = 0
    @State private var amt: Double = 250
    @State private var name = ""
    @State private var email = ""
    @State private var on = false
    @State private var out = false
    @State private var away = false
    @State private var leaveTask: Task<Void, Never>?

    private static let fallbackGift = ShopGift(id: "navy", name: "Navy", extra: 0,
                                               bg: "#101d31", inner: "")

    var body: some View {
        if let rect = model.giftOpen {
            content(rect: rect)
        }
    }

    @ViewBuilder
    private func content(rect: CGRect) -> some View {
        let gift = ShopCatalog.gift(id: model.giftFace ?? "") ?? ShopCatalog.gifts.first ?? Self.fallbackGift
        let free = model.status.founders
        let total = Int(amt) + (free ? 0 : gift.extra)
        let short = total > model.pool
        let ok = total <= model.pool && (step < 1 || canSendRecipient)
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let markup = gift.personalized(amt: Int(amt), who: trimmedName)

        ZStack {
            GeometryReader { geo in
                let restW: CGFloat = 300
                let restH: CGFloat = restW * 214 / 340
                let restCenter = CGPoint(x: geo.size.width / 2, y: 56 + 96 + restH / 2)
                let t: Double = (on && !out) ? 1 : 0
                let cx = TEase.lerp(rect.midX, restCenter.x, t)
                // The tile's art centre, not the tile's own — see `ConcourseShopTile.artCentreY`.
                let cy = TEase.lerp(rect.minY + ConcourseShopTile.artCentreY, restCenter.y, t)
                let scale = TEase.lerp(140 / restW, 1, t)
                let rot = TEase.lerp(-7, 0, t)

                MarkupView(markup, background: gift.bg, designSize: CGSize(width: 340, height: 214),
                          width: restW, cornerRadius: 19, shine: away)
                    .frame(width: restW, height: restH)
                    .scaleEffect(scale)
                    .rotationEffect(.degrees(rot))
                    // `0 34px 60px -24px rgba(16,29,49,.65)`, on the card box — grouped so the
                    // shadow reads as one silhouette rather than a copy per mark on the art.
                    .compositingGroup()
                    .shadow(color: Color(hex: 0x101d31, opacity: 0.2754), radius: 30, y: 34)
                    .position(x: cx, y: cy)
                    .animation(t == 1 ? .glide(0.82) : .glide(0.6).delay(0.16), value: t)
            }

            VStack(spacing: 0) {
                topRow
                Spacer(minLength: 0)
                if let failure = model.giftFailed {
                    failedPanel(failure)
                } else if away {
                    sentPanel(gift: gift)
                } else {
                    wizardPanel(gift: gift, free: free, total: total, short: short, ok: ok)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TColor.cloud100)
        // The same fade `ShopItemScreen` carries, and for the same reason: `leave()` removes this
        // overlay at 740 ms while the shelf underneath is only part-way back through its own
        // undim. Without a fade of its own, an opaque `cloud100` ground cuts out in one frame onto
        // a half-faded Concourse — which reads as a jump, not a transition. `.compositingGroup()`
        // first, per CLAUDE.md: this container stacks a fill under its content.
        .compositingGroup()
        .opacity(out ? 0 : 1)
        .animation(.glide(0.26).delay(0.6), value: out)
        .onAppear {
            // A failure from a previous open must never bleed into a fresh one — `done()` clears
            // it on the way out, but a screen opened by tapping straight back into a gift face
            // (`.id(model.giftFace ?? "")`) is new state built on the same model.
            if !model.giftAwaitingConfirmation { model.giftFailed = nil }
            Task {
                await Task.yield()
                try? await Task.sleep(for: .milliseconds(16))
                withAnimation(.glide(0.82)) { on = true }
            }
        }
        .onChange(of: model.giftSent) { _, v in if v != 0 { away = true } }
        // A timeout retains its reservation; only a server receipt can announce delivery.
        .onChange(of: model.giftFailed) { _, v in if v != nil { away = false } }
    }

    // MARK: - Chrome

    // `0 4px 12px -8px rgba(16,29,49,.5)` — the reference hand-rolls this back button and the
    // miles pill with their own tighter shadow rather than the shared `IconButton`/`--shadow-card`,
    // so this row does too instead of routing through the design-system default.
    private static let topRowShadow = (color: Color(hex: 0x101d31, opacity: 0.0912), radius: CGFloat(6), y: CGFloat(4))

    private var topRow: some View {
        HStack {
            Button(action: back) {
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
        .padding(.top, 56)
        .opacity(out ? 0 : 1)
        // The reference's own `opacity 200ms {E}` — `E` is its glide curve alias (confirmed
        // against `app.jsx`), not `linear`. This row had drifted onto `.linear`;
        // `ShopItemScreen`'s identical top row carried the same drift.
        .animation(.glide(0.2), value: out)
    }

    /// The back button steps back through the wizard before it actually leaves the screen.
    private func back() {
        dismissKeyboard()
        if step > 0 {
            withAnimation(.glide(0.3)) { step -= 1 }
        } else {
            leave()
        }
    }

    private func leave() {
        out = true
        model.shopLeaving = true
        leaveTask?.cancel()
        leaveTask = Task {
            try? await Task.sleep(for: .milliseconds(740))
            guard !Task.isCancelled else { return }
            model.giftOpen = nil
            model.giftFace = nil
            model.shopLeaving = false
        }
    }

    /// The confirmation's own button — clears state directly, no exit delay of its own.
    private func done() {
        model.giftOpen = nil
        model.giftFace = nil
        model.giftSent = 0
        model.giftFailed = nil
        model.shopLeaving = false
    }

    // MARK: - The wizard panel

    @ViewBuilder
    private func wizardPanel(gift: ShopGift, free: Bool, total: Int, short: Bool, ok: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(0..<2) { i in
                    Capsule()
                        .fill(TColor.sky200)
                        .frame(height: 4)
                        .overlay(alignment: .leading) {
                            GeometryReader { geo in
                                Capsule().fill(TColor.navy900)
                                    .frame(width: i <= step ? geo.size.width : 0)
                            }
                        }
                        .animation(.glide(0.48), value: step)
                }
            }
            .padding(.bottom, 20)

            if step == 0 {
                amountStep(gift: gift, free: free, total: total)
            } else {
                recipientStep
            }

            // Below the step content, on both steps — a modal wizard's own convention (progress,
            // then step content, then the button that advances it), not the full-bleed dial
            // screens' convention of pinning the action above the dial. Moving the button above
            // the dial on step 0 only would put it in a different place than it sits on step 1's
            // form fields, which is a worse inconsistency than the one being fixed. See CLAUDE.md
            // consistency sweep §1(d).
            primaryButton(ok: ok, short: short, total: total)
                .padding(.top, 20)
        }
        .padding(24)
        .background {
            // `0 22px 50px -26px rgba(16,29,49,.65)`, on the panel's own box.
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(TColor.white)
                .shadow(color: Color(hex: 0x101d31, opacity: 0.1939), radius: 25, y: 22)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .opacity(on && !out ? 1 : 0)
        .animation((on && !out) ? .glide(0.52).delay(0.46) : .glide(0.22), value: on && !out)
        .offset(y: (on && !out) ? 0 : 24)
        .animation((on && !out) ? .glide(0.68).delay(0.42) : .glide(0.3), value: on && !out)
    }

    private func amountStep(gift: ShopGift, free: Bool, total: Int) -> some View {
        let left = max(0, model.pool - total)
        return VStack(spacing: 14) {
            // `tpText`, not a raw `Text(...).tracking(...)` — see Typography.swift for why the
            // latter clips a round digit's right edge at this tracking. Sized at
            // `sizeDialValueModal` (two-fifths of the shared dial size, see the token): this dial
            // sits inside a modal card rather than a full screen, so it was always going to be
            // smaller than the other four — the fix is that the size is now a stated ratio of the
            // shared one rather than an unrelated 44pt literal.
            tpText("\(Int(amt)) mi", size: TFont.sizeDialValueModal, track: -0.05)
                .font(TFont.core(.bold, TFont.sizeDialValueModal))
                .foregroundStyle(TColor.textPrimary)

            Group {
                if !free, gift.extra > 0 {
                    Text("\(gift.extra) MI FACE \u{00b7} \(left) MI LEFT AFTER")
                } else {
                    Text("\(left) MI LEFT AFTER")
                }
            }
            .font(TFont.data(.regular, 12)).tracking(0.16 * 12)
            .foregroundStyle(TColor.textMuted)

            // The one dial in the app that is not full-bleed — and it has to stay that way. The
            // other four are drawn straight onto a full screen; this one lives inside the
            // wizard's own 24pt-padded card (`wizardPanel`, `.padding(24)`), which clips to a
            // rounded rect. Bleeding it to the screen's own edges would mean escaping that card
            // entirely — drawing outside its shape and over the scrim behind it — which breaks
            // the modal rather than fixing an inconsistency. See CLAUDE.md consistency sweep §1(c).
            DialView(value: $amt, min: 50, max: 1000, step: 50, arcStep: 1.25, tone: .light)
                .padding(.top, 8)
        }
    }

    private var recipientStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("TO").tpLabelStyle().foregroundStyle(TColor.textMuted)
            RecipientFields(name: $name, email: $email)
        }
    }

    /// A name, and an address that at least has the shape of one — the same test `LinkedScreen`
    /// puts a partner's email through, and for the same reason: the address is how this gift would
    /// actually reach them the day there is a server to send it through. Shared via
    /// `RecipientFields.isValid` (declared alongside `LinkedScreen`) so the two forms cannot drift
    /// into two different rules for what counts as an address.
    private var canSendRecipient: Bool { RecipientFields.isValid(name: name, email: email) }

    private func primaryButton(ok: Bool, short: Bool, total: Int) -> some View {
        let label = step == 0
            ? "Next"
            : (short ? "You need \(total - model.pool) mi more" : "Send \(total) mi")
        let color = step == 0 ? TColor.navy900 : TColor.copper500
        return Button {
            guard ok else { return }
            if step == 0 {
                withAnimation(.glide(0.3)) { step = 1 }
            } else {
                dismissKeyboard()
                send()
            }
        } label: {
            Text(label)
                .font(TFont.core(.semibold, 16))
                .foregroundStyle(TColor.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Capsule().fill(color))
        }
        .buttonStyle(.plain)
        .disabled(!ok)
        .opacity(ok ? 1 : 0.42)
        .scaleEffect(ok ? 1 : 0.99)
        .animation(.glide(TDur.fast), value: ok)
    }

    private func send() {
        guard canSendRecipient else { return }
        let who = name.trimmingCharacters(in: .whitespaces)
        let whoEmail = email.trimmingCharacters(in: .whitespaces)
        let gift = ShopCatalog.gift(id: model.giftFace ?? "") ?? ShopCatalog.gifts.first ?? Self.fallbackGift
        let free = model.status.founders
        let total = Int(amt) + (free ? 0 : gift.extra)
        model.payFlow = Order(kind: .gift, cost: total, name: "Gift to \(who)",
                              who: who, whoEmail: whoEmail, amt: Int(amt), face: gift.id)
    }

    // MARK: - Sent confirmation

    private func sentPanel(gift: ShopGift) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(TColor.statusOnTime)
            Text("SENT").tpLabelStyle().foregroundStyle(TColor.textMuted)
            Text("\(Int(amt)) mi to \(name.trimmingCharacters(in: .whitespaces))")
                .font(TFont.core(.bold, 26)).tpType(size: 26, lineHeight: 1.1)
                .multilineTextAlignment(.center)
                .foregroundStyle(TColor.textPrimary)
            Text("On the \(gift.name) face. It is in their wallet now.")
                .font(TFont.core(.regular, TFont.sizeBody))
                .tpType(size: TFont.sizeBody, lineHeight: TFont.lhBody)
                .multilineTextAlignment(.center)
                .foregroundStyle(TColor.textSecondary)
            TButton("Back to the Concourse", variant: .primary, size: .lg, fullWidth: true, action: done)
                .padding(.top, 8)
        }
        .padding(24)
        .background {
            // `0 22px 50px -26px rgba(16,29,49,.65)`, on the panel's own box.
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(TColor.white)
                .shadow(color: Color(hex: 0x101d31, opacity: 0.1939), radius: 25, y: 22)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .transition(.scale(scale: 0.9).combined(with: .opacity))
        .animation(.glide(0.62).delay(0.22), value: away)
    }

    // MARK: - Send failed

    /// Distinguish a definite refusal from a transfer whose response has not arrived.
    private func failedPanel(_ reason: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(TColor.statusDiverted)
            Text(model.giftAwaitingConfirmation ? "AWAITING CONFIRMATION" : "NOT SENT")
                .tpLabelStyle().foregroundStyle(TColor.textMuted)
            Text(reason)
                .font(TFont.core(.regular, TFont.sizeBody))
                .tpType(size: TFont.sizeBody, lineHeight: TFont.lhBody)
                .multilineTextAlignment(.center)
                .foregroundStyle(TColor.textSecondary)
            TButton("Back to the Concourse", variant: .primary, size: .lg, fullWidth: true, action: done)
                .padding(.top, 8)
        }
        .padding(24)
        .background {
            // `0 22px 50px -26px rgba(16,29,49,.65)`, same box as the wizard panel and the sent one.
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(TColor.white)
                .shadow(color: Color(hex: 0x101d31, opacity: 0.1939), radius: 25, y: 22)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .transition(.scale(scale: 0.9).combined(with: .opacity))
        .animation(.glide(0.62).delay(0.22), value: model.giftFailed != nil)
    }
}
