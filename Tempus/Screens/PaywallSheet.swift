import SwiftUI

/// The Business Class ("plus") upsell. `model.paywall` is the request — `.open` while rising,
/// `.closing` while it asks to leave — and this view is the only thing that ever turns `.closing`
/// into `nil`, once its own exit animation has actually finished playing.
///
/// **This is a real payment.** The reference's `onStart` is `setPlus(true)` — a button that grants
/// the plan for nothing, because a web demo has no store. Here it is a StoreKit purchase through
/// RevenueCat: the price, the trial and the sub-copy are read from the live offering, and the plan
/// is granted by the entitlement rather than by this screen. See `Billing`.
///
/// The reference's own copy stands in until the store answers, so the screen is never blank; and
/// when there is no store at all — no API key, no offering — the button says so instead of
/// pretending. A purchase is never implied where one cannot happen.
struct PaywallSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(Billing.self) private var billing
    @State private var risen = false

    /// How far to push the sheet when it is down.
    ///
    /// **Only used for the off-screen offset, never for the sheet's height** — the same job
    /// `Controls.offY` uses `UIScreen` for, where the number just has to be "far enough". The
    /// sheet used to take its *height* from this too (`screen − 64`), which assumes the sheet's
    /// container is the whole window. It is not always: `RootView` sizes its stack from a
    /// viewport `GeometryReader`, and anything that makes that container shorter than the screen
    /// left the sheet taller than the space it had. Bottom-aligned, an oversized sheet overflows
    /// *upward*, so the close button and the top of the pass card were the parts that went — the
    /// screen "slightly cut off" reported from Linked ▸ Business Class. The sheet is laid out
    /// against its container now (see `body`) and cannot outgrow it.
    private var offscreen: CGFloat { TStage.bounds.height }

    private var closeRow: some View {
        HStack {
            Spacer(minLength: 0)
            IconButton(tone: .onDark, size: .md, label: "Close", action: requestClose) {
                Image(systemName: "xmark").font(.system(size: 20, weight: .regular))
            }
        }
        .padding(.top, 18)
        .padding(.horizontal, 18)
    }

    var body: some View {
        ZStack {
            TColor.navy900.opacity(0.4)
                .ignoresSafeArea()
                .opacity(risen ? 1 : 0)
                .animation(.glide(0.3), value: risen)
                .onTapGesture { requestClose() }

            VStack(spacing: 0) {
                closeRow
                // **The slack goes above the plans, never below them.** A `ScrollView` on its own
                // gives its content the top of the viewport and keeps the rest as empty ground —
                // which parked the plan cards a good 90pt clear of the button they are a choice
                // about, with nothing in between. `ViewThatFits` takes the distributed layout
                // whenever it fits (the `Spacer` then absorbs whatever is left between the pass
                // and the plans, where a gap reads as air around the hero) and falls back to the
                // scrolling one when it does not — a long localised price, a store error wrapping
                // to three lines, the restore button.
                ViewThatFits(in: .vertical) {
                    VStack(spacing: 0) {
                        cardAndPrice(spacer: true)
                    }
                    .padding(.horizontal, 20)

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            cardAndPrice(spacer: false)
                        }
                        .padding(.horizontal, 20)
                    }
                }
                footer
            }
            // **The sheet fills its container below a 64pt gap, rather than measuring the screen.**
            // `.padding(.top, 64)` is applied *after* the frame, so layout proposes
            // (container − 64) inward and `maxHeight: .infinity` takes exactly that — the sheet
            // is therefore always as tall as the space it actually has, on any container, and the
            // top can no longer be pushed off. The background is inside the padding, so the gap
            // stays transparent and the scrim still shows through it.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // The sheet's own ground is navy, so the copper shadow under its buy button was a
            // halo rather than a shadow — the same fix the dark onboarding screens carry. Set
            // inside the background, so the sheet's own upward shadow onto the app is unaffected.
            .tpDarkGround()
            .background(TColor.navy700)
            .clipShape(
                UnevenRoundedRectangle(topLeadingRadius: 40, bottomLeadingRadius: 0,
                                        bottomTrailingRadius: 0, topTrailingRadius: 40)
            )
            // "0 -18px 60px rgba(16,29,49,.45)" — blur halved per the project's CSS→SwiftUI shadow
            // convention, y kept negative because the shadow throws upward, away from the sheet.
            .shadow(color: TColor.navy900.opacity(0.45), radius: 30, x: 0, y: -18)
            .padding(.top, 64)
            .offset(y: risen ? 0 : offscreen)
        }
        .ignoresSafeArea()
        .onAppear { withAnimation(.glide(0.52)) { risen = true } }
        .task(id: model.paywall) {
            guard model.paywall == .closing else { return }
            withAnimation(.exit(0.42)) { risen = false }
            try? await Task.sleep(for: .milliseconds(420))
            guard !Task.isCancelled else { return }
            if model.paywall == .closing { model.paywall = nil }
        }
    }

    // MARK: - The fake pass card

    /// The two halves of the sheet's body, built once for both `ViewThatFits` candidates so the
    /// scrolling fallback cannot drift from the distributed one. `spacer` is the only difference:
    /// present, it absorbs the leftover height; absent, the content measures its own.
    @ViewBuilder
    private func cardAndPrice(spacer: Bool) -> some View {
        // The card's top edge sat 6pt under the close button, which reads as the × resting on it.
        passCard.padding(.top, 20)
        if spacer { Spacer(minLength: 8) }
        priceRow
    }

    private var passCard: some View {
        Rise(i: 0) {
            // Flattened before the notches are cut, and the seam raised above the rows. SwiftUI
            // paints siblings in source order, so a hole drawn on the seam had its lower half
            // repainted by the row block underneath it and only the upper quadrant survived —
            // the quarter circle the pass was wearing instead of a hole. `zIndex` is CSS's
            // "a positioned element wins over a static one", said in SwiftUI.
            VStack(spacing: 0) {
                passCardTop
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 24, bottomLeadingRadius: 0,
                                                       bottomTrailingRadius: 0, topTrailingRadius: 24))
                perforation.zIndex(1)
                passCardBottom
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 24,
                                                       bottomTrailingRadius: 24, topTrailingRadius: 0))
            }
            .compositingGroup()
        }
    }

    private var passCardTop: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Upgrade").tpLabelStyle().foregroundStyle(TColor.textMuted)
                Spacer(minLength: 0)
                Text("Seat 1A").tpLabelStyle().foregroundStyle(TColor.textAccent)
            }
            Text("Business Class")
                .font(TFont.core(.bold, 34))
                .tracking(-0.045 * 34)
                .foregroundStyle(TColor.textPrimary)
                .padding(.top, 14)
            // **A blurb, but never the rows in a sentence.** The old one said "Longer routes,
            // every pass kept, and the Status Club" directly above three rows reading "Routes
            // longer than 90 minutes", "The Concourse's Business stock" and "Status Club higher
            // tiers" — the same sentence twice, the second time itemised — so it was cut on
            // 21 Sep 2026 while the sheet was short of room. The sheet has room again (see
            // `cardAndPrice`), and the line is back saying the one thing the rows do not: the
            // cabin itself changes. Business class is armed at preflight, one lapse ends the
            // flight, and the emergency exit is the only way out — which is the part of the plan
            // a list of unlocked things cannot describe.
            Text("A seat up front, and a cabin that holds you to the flight.")
                .font(TFont.core(.regular, 15))
                .tpType(size: 15, lineHeight: 1.45)
                .foregroundStyle(TColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
        }
        .padding(EdgeInsets(top: 18, leading: 22, bottom: 14, trailing: 22))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TColor.surfaceCard)
    }

    /// Two holes bitten out of the seam. Punched rather than painted: `destinationOut` erases the
    /// flattened card, so the sheet shows through whatever colour it happens to be and the card's
    /// own shadow follows the bite. A hole needs no colour — the same reasoning the pass archive
    /// already records (see CLAUDE.md's divergence table).
    private var perforation: some View {
        PaywallDashedLine()
            .padding(.horizontal, 18)
            .background(TColor.surfaceCard)
            .overlay(alignment: .leading) {
                Circle().fill(.black).blendMode(.destinationOut)
                    .frame(width: 28, height: 28).offset(x: -14)
            }
            .overlay(alignment: .trailing) {
                Circle().fill(.black).blendMode(.destinationOut)
                    .frame(width: 28, height: 28).offset(x: 14)
            }
    }

    private var passCardBottom: some View {
        VStack(spacing: 0) {
            ForEach(Array(includedRows.enumerated()), id: \.offset) { i, row in
                HStack(alignment: .firstTextBaseline) {
                    Text(row)
                        .font(TFont.core(.regular, 15))
                        .foregroundStyle(TColor.textPrimary)
                    Spacer(minLength: 0)
                    Text("INCLUDED")
                        .font(TFont.data(.medium, 12))
                        .tracking(0.1 * 12)
                        .foregroundStyle(TColor.statusOnTime)
                }
                .padding(.vertical, 8)
                .overlay(alignment: .top) {
                    if i > 0 { Rectangle().fill(TColor.borderSubtle).frame(height: 1) }
                }
            }
        }
        .padding(EdgeInsets(top: 18, leading: 22, bottom: 18, trailing: 22))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TColor.surfaceCard)
    }

    /// **These three lines have to be true, and one of them stopped being true on 21 Sep 2026.**
    /// It read "The Concourse", which was right while the shelf was gated whole. The shelf is open
    /// to everyone now and the plan buys the top three quarters of the stock instead, so the line
    /// says that. A paywall that lists something the member already has is the fastest way to
    /// teach them not to read it.
    private var includedRows: [String] {
        ["Routes longer than 90 minutes",
         "The Concourse's Business stock",
         "Status Club higher tiers"]
    }

    // MARK: - Price and footer

    /// **The price, as a choice between two plans.** This was one 62pt number and one period
    /// suffix — the annual plan, take it or leave it — until 21 Sep 2026.
    ///
    /// Two cards rather than a segmented control or a row of radio buttons: a plan carries a
    /// price, a cadence, a billing line and a badge, and a selectable card is the only one of the
    /// three shapes with room for all four. Annual leads and is selected on arrival, because a
    /// default is taken more often than a badge persuades. Monthly is present, second, and
    /// deliberately quieter — it is the plan whose twelve-month cost makes the annual saving
    /// legible, which is a job it does better beside the annual card than hidden behind a toggle.
    private var priceRow: some View {
        Rise(i: 1) {
            Group {
                if billing.showsPlanChoice { PlanPicker() } else { singlePrice }
            }
        }
        .padding(.top, 16)
    }

    /// The old single-figure price, kept for the one case it is still right for: a dashboard with
    /// exactly one package configured. A picker with one option is not a choice.
    private var singlePrice: some View {
        HStack(alignment: .lastTextBaseline, spacing: 0) {
            // `tpText`, not a raw `Text(...).tracking(...)` — a live store price ends in a
            // digit as often as not, and at this size and tracking that is exactly the round
            // right edge Typography.swift documents getting clipped.
            tpText(billing.displayPrice, size: 62, track: -0.06)
                .font(TFont.core(.bold, 62))
                .monospacedDigit()
                .foregroundStyle(TColor.textOnDark)
            Text(billing.displayPeriod)
                .font(TFont.data(.medium, 16))
                .foregroundStyle(TColor.textOnDarkMuted)
        }
        .padding(.top, 4)
    }

    /// The trial, the renewal, and — the reason this moved — **why the button is grey when it is**.
    ///
    /// It used to be the last thing inside the `ScrollView`, under the price. That was fine while
    /// the price was one 62pt figure; with two plan cards there instead it fell below the fold, so
    /// a build with no store showed a dimmed buy button and kept the explanation a scroll
    /// away. This line carries `billing.error` and `billing.unavailable` as well as the renewal
    /// terms, so it belongs against the control it is about, not at the end of a scroll.
    private var subCopy: some View {
        Text(subLine)
            .font(TFont.core(.regular, 13))
            .tpType(size: 13, lineHeight: 1.45)
            .foregroundStyle(TColor.textOnDarkMuted)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
            .padding(.bottom, 4)
    }

    private var footer: some View {
        VStack(spacing: 6) {
            subCopy
            TButton(buyLabel, variant: .primary, size: .lg, fullWidth: true) {
                // The reference's primary button always closes. A purchase that succeeds and leaves
                // the member sitting on the upsell — with the only live control reading "Stay in
                // economy" — is the wrong sentence to hand someone who just bought Business Class.
                Task { if await billing.purchase(model) { requestClose() } }
            }
            .disabled(model.plus || !billing.canPurchase)
            .opacity(model.plus || billing.canPurchase ? 1 : 0.55)

            // The only live control on this sheet once the plan is held — so it must not offer to
            // keep someone in a cabin they already left. It closes either way; only the word changes.
            TButton(model.plus ? "Done" : "Stay in economy",
                    variant: .onDark, size: .md, fullWidth: true, action: requestClose)

            // Apple requires a restore path wherever a subscription is sold, and a member on a new
            // phone has no other way back to a plan they already own — but it is the least likely
            // action on this sheet, so it sits quietest and last, below both real buttons.
            // Redeem code shares the line: an offer code is the other way back into a plan that
            // was not bought on this sheet, and a second row would push the legal links off.
            if !model.plus, Billing.storeUsable {
                HStack(spacing: 8) {
                    TButton(variant: .ghost, size: .sm, fullWidth: true, disabled: billing.restoring) {
                        Task { if await billing.restore(model) { requestClose() } }
                    } content: {
                        Text(billing.restoring ? "Restoring\u{2026}" : "Restore purchase")
                            .foregroundStyle(TColor.textOnDarkMuted)
                    }
                    TButton(variant: .ghost, size: .sm, fullWidth: true) {
                        billing.redeemCode()
                    } content: {
                        Text("Redeem code").foregroundStyle(TColor.textOnDarkMuted)
                    }
                }
                .padding(.top, 2)
            }
            // Required by App Store Review 3.1.2 on every surface that sells a subscription, not
            // only on the App Store listing. Quiet, last, and never in the way of the two buttons.
            HStack(spacing: 18) {
                Link("Terms of Use", destination: Billing.termsURL)
                Link("Privacy Policy", destination: Billing.privacyURL)
            }
            .font(TFont.core(.regular, 12))
            .foregroundStyle(TColor.textOnDarkMuted)
            .padding(.top, 10)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        // 34 was the home-indicator inset exactly, which put the Terms/Privacy links *on* the
        // indicator line with nothing to spare — and nothing to spare is what turns any extra
        // line (a store error wrapping to two, a longer localised price) into content pushed off
        // the bottom. The sheet ignores the safe area so nothing reserves that room for it; 44 is
        // the inset plus a real gap. Measured: the last ink sat at 839pt of 874.
        .padding(.bottom, 44)
        .task { await billing.loadOffering() }
    }

    private var buyLabel: String {
        if model.plus { return "You are in Business Class" }
        if billing.busy { return "Contacting the App Store\u{2026}" }
        return billing.buyLabel
    }

    /// Said plainly, once, rather than by a button that looks live and does nothing.
    private var storeUnavailable: String? { model.plus ? nil : billing.unavailable }

    /// A price is an offer, and there is nothing left to offer someone who already holds the plan
    /// — quoting one under "You are in Business Class" reads as a second charge.
    private var subLine: String {
        if model.plus { return "Business class is active on this account." }
        return billing.error ?? storeUnavailable ?? billing.subCopy
    }

    // MARK: - Actions

    private func requestClose() {
        guard model.paywall == .open else { return }
        model.paywall = .closing
    }

}

/// A horizontal dashed rule that stretches to fill whatever width it is given — the perforation
/// seam between the two halves of the fake pass.
private struct PaywallDashedLine: View {
    var body: some View {
        GeometryReader { geo in
            Path { p in
                p.move(to: CGPoint(x: 0, y: 0.75))
                p.addLine(to: CGPoint(x: geo.size.width, y: 0.75))
            }
            .stroke(TColor.borderStrong, style: StrokeStyle(lineWidth: 1.5, dash: DashedLine.perforation))
        }
        .frame(height: 1.5)
    }
}

// MARK: - The two plans

/// **The plan picker, shared by the paywall and onboarding's last screen.** Both sell the same
/// subscription, so both show the same two cards; onboarding takes `compact` because it carries a
/// ticket, two buttons and two legal links on the same screen.
///
/// The shape is what the well-made subscription screens converge on, and each part is a decision:
///
/// * **Two stacked cards, not a segmented pill.** A plan carries a price, a cadence, a billing
///   line and a badge; a pill segment has room for a word. (Segmented controls and side-by-side
///   columns start paying off at three or more tiers. There are two.)
/// * **Annual first and selected on arrival.** A default is taken far more often than a badge
///   persuades, and it is the better deal for the member as well as the better retention.
/// * **Each card leads with what it bills** — $39.99 a year, $7.99 a month — and the annual
///   card's per-month equivalent is a footnote under its name. It was the other way round (the
///   $3.33 headline, the total underneath) until App Review rejected build 43 under 3.1.2(c): the
///   billed amount must be the most conspicuous price, and a calculated one subordinate to it.
/// * **The badge is `copper100`, not `copper500`.** Copper is already the primary button's colour
///   on both of these screens, and a badge in the call-to-action's own paint makes the eye unable
///   to separate "the discount" from "the thing to press". The pale end of the same ramp keeps the
///   badge in the family — warm, so it reads as the paid thing — while being unmistakably not the
///   button. It reads as a stamp on a fare, which is the right metaphor here anyway.
/// * **Selection is a fill lift plus a thin copper border**, not a heavy stroke: the lift does the
///   work and the border only confirms it, so the border and the badge are not both shouting.
/// * **Monthly is de-emphasised by weight, never greyed out.** A default that makes the
///   alternative look broken is a default nobody trusts.
struct PlanPicker: View {
    @Environment(Billing.self) private var billing
    /// Onboarding's last screen, which has a ticket above these and four more things below them.
    var compact = false

    var body: some View {
        VStack(spacing: compact ? 7 : 8) {
            card(.annual)
            card(.monthly)
        }
    }

    private var priceSize: CGFloat { compact ? 23 : 26 }
    private var pad: CGFloat { compact ? 11 : 12 }

    @ViewBuilder
    private func card(_ plan: Billing.Plan) -> some View {
        let chosen = billing.plan == plan
        let annual = plan == .annual
        Button {
            Haptics.dialTick()
            withAnimation(.glide(TDur.fast)) { billing.select(plan) }
        } label: {
            HStack(alignment: .center, spacing: 13) {
                // A filled ring, not a tick: the row is one of two, and a tick reads as "done"
                // where a selected radio reads as "this one".
                ZStack {
                    Circle().stroke(chosen ? TColor.copper500 : TColor.textOnDarkMuted.opacity(0.5),
                                    lineWidth: 1.5)
                    if chosen { Circle().fill(TColor.copper500).padding(5) }
                }
                .frame(width: 21, height: 21)

                VStack(alignment: .leading, spacing: 2) {
                    Text(annual ? "Annual" : "Monthly")
                        .font(TFont.core(.semibold, compact ? 15 : 16))
                        .foregroundStyle(TColor.textOnDark)
                    // The per-month equivalent, small and under the name — see 3.1.2(c) above.
                    Text(annual ? "\(billing.perMonth(.annual)) a month, billed yearly" : "billed every month")
                        .font(TFont.core(.regular, compact ? 12 : 13))
                        .foregroundStyle(TColor.textOnDarkMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 1) {
                    tpText(billing.price(plan), size: priceSize, track: -0.03)
                        .font(TFont.core(.bold, priceSize))
                        .monospacedDigit()
                        .foregroundStyle(TColor.textOnDark)
                    Text(annual ? "per year" : "per month")
                        .font(TFont.data(.medium, 10))
                        .tracking(TFont.trackLabel * 10)
                        .foregroundStyle(TColor.textOnDarkMuted)
                }
            }
            .padding(EdgeInsets(top: pad, leading: 15, bottom: pad, trailing: 15))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(TColor.white.opacity(chosen ? 0.12 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(chosen ? TColor.copper500 : TColor.white.opacity(0.13),
                            lineWidth: chosen ? 1.5 : 1)
            )
            .overlay(alignment: .topTrailing) { if annual { badge } }
        }
        .buttonStyle(.plain)
    }

    /// Cut into the card's top-right corner rather than set inline beside the price — a badge and
    /// a figure sharing a baseline is the one collision worth designing out. "SAVE 58%", not
    /// "−58%": a minus sign in front of a percentage reads as something being taken away.
    @ViewBuilder
    private var badge: some View {
        if let pct = billing.annualSavingPercent {
            Text("SAVE \(pct)%")
                .font(TFont.data(.medium, 10))
                .tracking(TFont.trackLabel * 10)
                .foregroundStyle(TColor.navy900)
                .padding(.horizontal, 8)
                .padding(.vertical, 3.5)
                .background(Capsule().fill(TColor.copper100))
                .offset(x: -11, y: -8)
        }
    }
}
