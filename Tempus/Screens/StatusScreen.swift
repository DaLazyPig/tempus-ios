import SwiftUI

/// Status Club: the card, the ladder, and the bank behind it.
///
/// Everything on this screen comes from `model.status`, which is recomputed on every read — a tier
/// is never stored, so a period that is not re-flown takes it away again. Nothing here writes one.
///
/// The header band takes its colour from the *chosen card face*, not from the tier, which is why the
/// ink flips: a pale ground gets dark type and dark controls.
struct StatusScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(Backend.self) private var backend

    /// Arriving from the card: the header colour fills the phone and then draws back up to its own
    /// band, so the card lands rather than cuts. Taken off the model once, so a later visit to Status
    /// Club does not replay a flash that belonged to one tier-up.
    @State private var intro: Color?
    @State private var lit = false

    @State private var showFullStatement = false
    /// Which of the received gifts the Requests pager is showing. Clamped on every draw and on
    /// every change of count — a gift answered is a gift removed from under the index.
    @State private var giftPage = 0

    private var tier: Int { min(model.status.idx, model.cardVariant.count - 1) }
    private var variant: Int { model.cardVariant[tier] }
    private var header: Color {
        CardArt.header(tier: tier, variant: variant, owned: model.ownedFaces)
    }
    /// The band painted behind the card, not the card's own colour — the rule lives in `CardArt`
    /// so the self-check can put every face through it.
    ///
    /// It used to be a flat `mix(header, cloud100, 0.55)` here, which put every band at luma
    /// 168–213 and so flipped the ink below dark on all of them. (The reference paints this band
    /// the header colour raw — `background: hdr` — and flips its ink on a pale one. Neither half
    /// of that survives here: the title is white, full stop.)
    private var band: Color { CardArt.band(behind: header) }
    private var hInk: Color { .white }
    private var hMute: Color { Color(hex: 0xffffff, opacity: 0.75) }
    private var hChip: Color { Color(hex: 0xffffff, opacity: 0.2) }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    headerBand
                        // The card studio's entrance grows its band out of this one — see
                        // `AppModel.statusHero`. Nothing observes the box, so this costs a store.
                        .measureRect(into: model.statusHero, in: .global)
                    bodyStack
                }
            }
            // One step down from the plain page ground (`cloud100`, used elsewhere) to `sky100` —
            // the white cards below the header (`statusCard`, the Requests card, the statement
            // rows) sit close enough to white that `cloud100` reads as white behind them. The
            // header band paints its own opaque colour on top, so this only changes the pale
            // lower half the cards actually sit on.
            .background(TColor.sky100)

            if let intro {
                Rectangle()
                    .fill(intro)
                    .frame(height: 844)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .opacity(lit ? 0 : 1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            if intro == nil, let ground = model.statusIntro {
                intro = ground
                model.statusIntro = nil
                withAnimation(.glide(0.42)) { lit = true }
            }
            model.stampFounderIssueIfNeeded()
        }
        // One-shot on arrival, never a poll: the sender's device has no other way to tell this one
        // an invite is waiting — and this one has no other way to learn its own invite was
        // accepted, or that a gift arrived, short of a relaunch (`refreshSharedBank` reconciles a
        // pending link against the server's pair and fetches incoming gifts).
        .task { await loadIncomingInvite(); await model.refreshSharedBank() }
    }

    /// A real invite waiting on this member, mirrored into `model.link` so `requestCard` below
    /// reads it the same way it already reads a local `-tempusRequest` seam. Only asked for when
    /// there is nothing already occupying `link` — an established or already-pending link takes
    /// priority over discovering a second invite this screen has nowhere to show at once.
    private func loadIncomingInvite() async {
        guard Backend.isConfigured, backend.isLinked, model.link == nil else { return }
        guard let invite = try? await backend.openInvites().incoming.first else { return }
        model.showInvite(invite, iSent: false)
    }

    // MARK: - Header

    /// The card takes the width the gutters leave, on every phone: it is authored at 340 and
    /// `StatusCard` scales its artwork to whatever it is given, so a wider phone gets a bigger card
    /// rather than a 342 card with wider margins (which is what the old `min(342, …)` gave a Max).
    private var cardWidth: CGFloat { UIScreen.main.bounds.width - 48 }

    private var headerBand: some View {
        let st = model.status
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                circleButton("chevron.left", "Back") {
                    model.go(.home, .lift, dir: -1)
                }
                Spacer(minLength: 0)

                Button {
                    model.cardDesignFrom = nil
                    model.goDirect(.carddesign)
                } label: {
                    Text("Customise")
                        .font(TFont.core(.semibold, 14))
                        .foregroundStyle(hInk)
                        .padding(.horizontal, 18)
                        .frame(height: 44)
                        .background(hChip, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Customise card")
            }

            Rise(i: 0) {
                StatusCard(tier: st.idx, variant: variant, name: model.cardName,
                           width: cardWidth, owned: model.ownedFaces, flippable: true,
                           serial: model.founderSerialString, issued: model.founderIssuedString,
                           miles: model.pool)
                    .frame(maxWidth: .infinity)
            }
            // Outside the riser's own offset, so its entrance never leaks into the rect.
            .measureRect(into: model.statusCardBox, in: .global)
            .padding(.top, 24)

            Rise(i: 1) {
                tpText("Status Club", size: 42, track: -0.05)
                    .font(TFont.core(.bold, 42))
                    .foregroundStyle(hInk)
            }
            .padding(.top, 26)

            Rise(i: 2) {
                HStack(alignment: .top, spacing: 30) {
                    headerFact("TIER", st.tier.name)
                    headerFact("MEMBER SINCE", model.memberSince)
                    headerFact("EARN", "\u{00d7}" + mult(st.mult))
                }
            }
            .padding(.top, 20)
        }
        .padding(.top, 62)
        .padding(.horizontal, 24)
        .padding(.bottom, 30)
        .frame(maxWidth: .infinity, alignment: .leading)
        // The band's colour overhangs a screen's worth *upward*. Negative padding lets the `Color`
        // lay out taller than the band while the padded view still reports the band's own size, so
        // nothing about the layout moves — but a rubber-band pull past the top now drags the tier's
        // colour down instead of revealing the ScrollView's `cloud100` above it. Bottom over-scroll
        // and the ground behind the body cards are untouched.
        .background(band.padding(.top, -UIScreen.main.bounds.height))
    }

    private func headerFact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).tpLabelStyle().foregroundStyle(hMute)
            Text(value)
                .font(TFont.core(.semibold, 16))
                .foregroundStyle(hInk)
                .padding(.top, 8)
        }
    }

    private func circleButton(_ symbol: String, _ label: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(hInk)
                .frame(width: 44, height: 44)
                .background(hChip, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - Body

    private var bodyStack: some View {
        // **One card per kind of request, never one card holding all of them.** A bank link and a
        // gift are different questions with different answers, and stacking them inside a single
        // REQUESTS box made one tall block whose bottom half slid under the floating nav. Each
        // now sits in its own card, and the gifts card shows one gift at a time behind a pager —
        // ten people sending gifts on the same day must not turn this screen into a ten-screen
        // scroll of near-identical rows.
        let hasLink = model.link?.isIncomingRequest ?? false
        let hasGifts = !model.receivedGifts.isEmpty
        let base = (hasLink ? 1 : 0) + (hasGifts ? 1 : 0)
        return VStack(spacing: 0) {
            if hasLink, let link = model.link { Rise(i: 0) { linkRequestCard(link) } }
            if hasGifts { Rise(i: hasLink ? 1 : 0) { giftsCard }.transition(Self.gone) }
            Rise(i: base) { milesCard }
            Rise(i: base + 1) { linkedCard }
            Rise(i: base + 2) { membershipCard }
            if !model.plus { Rise(i: base + 3) { upsellCard } }
            Rise(i: base + 4) { statementCard }
        }
        .padding(.top, 10)
        .padding(.horizontal, 24)
        .padding(.bottom, 124)
        // Answering a gift removes it: the card grows a little and fades as it goes, and the cards
        // under it close up over the same beat. Keyed on the ids rather than the count so a gift
        // paged past is not mistaken for one answered. The removal used to be a bare cut — the
        // model mutates outside any animation transaction (a server round trip, for a real gift).
        .animation(.glide(0.42), value: model.receivedGifts.map(\.t))
    }

    /// How a request leaves once answered: outward, and gone.
    private static let gone = AnyTransition.scale(scale: 1.08).combined(with: .opacity)

    // MARK: Requests

    /// The one bank-link request this device can ever owe an answer to — there is one `link`, so
    /// there is never a second of these to page through.
    private func linkRequestCard(_ link: LinkAccount) -> some View {
        statusCard {
            Text("REQUEST").tpLabelStyle().foregroundStyle(TColor.textMuted)
            linkRequestRow(link).padding(.top, 14)
        }
    }

    /// **Gifts, one at a time.** `receivedGifts` is however many people have sent one, and a card
    /// per gift is a screen of them the moment the app is used the way it is meant to be. The
    /// pager keeps the card exactly one gift tall whatever the count, and says how many are behind
    /// it — which a scroll of identical rows never does as plainly as `2 / 5`.
    private var giftsCard: some View {
        let gifts = model.receivedGifts
        let page = min(max(giftPage, 0), max(gifts.count - 1, 0))
        return statusCard {
            HStack(alignment: .firstTextBaseline) {
                // The sender is the label — "FROM JONAH WEBB" — and the gift itself is the rest
                // of the card. The figure is printed on its face, so no line repeats it below.
                Text(gifts.indices.contains(page) ? "FROM " + gifts[page].from.uppercased() : "GIFT")
                    .tpLabelStyle().foregroundStyle(TColor.textMuted)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 8)
                if gifts.count > 1 { pager(page: page, count: gifts.count) }
            }
            // The label and pager just change; only the gift itself leaves with a transition.
            .animation(nil, value: gifts.count)

            if gifts.indices.contains(page) {
                // A `ZStack` so an answered gift and the next one share a slot while the first
                // leaves — in a `VStack` the leaving row would hold its height and shove the next
                // one down for the length of the transition.
                ZStack {
                    giftRequestRow(gifts[page])
                        // A new page is a different gift, not a redrawn one — without an identity
                        // the card's art cross-fades in place and two gifts read as one changing card.
                        .id(gifts[page].id)
                        .transition(.asymmetric(insertion: .opacity, removal: Self.gone))
                }
                .padding(.top, 14)
            }

            // Accepting a delivered gift is a round trip, and every way it can fail used to
            // leave the row exactly as it was — see `AppModel.acceptGift`. The claim survives
            // either way; this is the sentence saying so.
            if let failure = model.giftFailed {
                Text(failure)
                    .font(TFont.core(.regular, 13))
                    .tpType(size: 13, lineHeight: 1.45)
                    .foregroundStyle(TColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 14)
            }
        }
        // Answering the last gift shortens the list under the pager; the page has to come back
        // inside it or the card draws nothing at all.
        .onChange(of: gifts.count) { _, n in giftPage = min(giftPage, max(n - 1, 0)) }
    }

    /// `\u{2039} 2 / 5 \u{203a}` — the quietest control that can say both "there are more" and
    /// "this is which". Ends are disabled rather than wrapped: a list of five that jumps from the
    /// last to the first gives no sign it has been all the way round.
    private func pager(page: Int, count: Int) -> some View {
        HStack(spacing: 12) {
            pagerArrow("chevron.left", enabled: page > 0) { giftPage = max(page - 1, 0) }
            Text("\(page + 1) / \(count)")
                .font(TFont.data(.medium, 12))
                .tracking(0.1 * 12)
                .foregroundStyle(TColor.textMuted)
                .monospacedDigit()
            pagerArrow("chevron.right", enabled: page < count - 1) { giftPage = min(page + 1, count - 1) }
        }
    }

    private func pagerArrow(_ icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(enabled ? TColor.textAccent : TColor.textMuted.opacity(0.4))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    /// **A gift is the card, and the card goes first.** This was a 104pt tile beside a two-line
    /// block — "250 mi gift from Jonah Webb" over "On the Nebula face." — which reads as a bank
    /// transfer with a picture attached, and stacked tall enough that the Accept button underneath
    /// it landed behind the floating nav on a phone: a live button nothing could tap. The face is
    /// centred at the top at the card's width and the two answers close the row. The face's *name*
    /// went with the subtitle, and then the subtitle went too (22 Sep 2026): the figure is printed
    /// on the face and the sender is the card's label, so the line repeated both.
    private func giftRequestRow(_ gift: ReceivedGift) -> some View {
        VStack(spacing: 14) {
            if let art = ShopCatalog.gift(id: gift.face ?? "") {
                // The card's full width — the same 340 box the gift is authored on, or as much
                // of it as the phone leaves inside this card's 44pt of margins (314 on a 17 Pro,
                // 342 on a 16 Plus). Half size read as a thumbnail of the gift rather than the gift.
                let w = min(340, UIScreen.main.bounds.width - 88)
                MarkupView(art.personalized(amt: gift.amt, who: model.cardName), background: art.bg,
                           designSize: CGSize(width: 340, height: 214),
                           width: w, cornerRadius: 19 * w / 300)
                    // The shelf tile's own `0 12px 20px -12px rgba(16,29,49,.6)`.
                    .compositingGroup()
                    .shadow(color: Color(hex: 0x101d31, opacity: 0.1381), radius: 10, x: 0, y: 12)
            }
            answerRow(decline: { model.declineGift(gift.id) },
                      accept: { model.acceptGift(gift.id) })
        }
        .frame(maxWidth: .infinity)
    }

    /// A bank link has no face to draw and does need its sentence — accepting one changes what
    /// both members can spend, which a title alone does not say.
    private func linkRequestRow(_ link: LinkAccount) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(link.name) wants to share a bank")
                .font(TFont.core(.semibold, 16))
                .tpType(size: 16, lineHeight: 1.3)
                .foregroundStyle(TColor.textPrimary)
            Text("One shared bank. What you each hold moves in when you accept, and both of you spend from it.")
                .font(TFont.core(.regular, 14))
                .tpType(size: 14, lineHeight: 1.45)
                .foregroundStyle(TColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            answerRow(decline: { model.declineLinkRequest() },
                      accept: { model.acceptLinkRequest() })
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Decline on the left, Accept on the right — the destructive answer never sits where the
    /// thumb lands first.
    private func answerRow(decline: @escaping () -> Void, accept: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            TButton("Decline", variant: .ghost, size: .md, fullWidth: true, action: decline)
            TButton("Accept", variant: .primary, size: .md, fullWidth: true, action: accept)
        }
    }

    // MARK: Miles

    /// What you hold, what you have ever earned, and the one thing you do with it.
    private var milesCard: some View {
        let st = model.status
        return statusCard {
            HStack(alignment: .top, spacing: 18) {
                bigStat("MILES", model.pool.formatted(.number.locale(Locale(identifier: "en_US"))))
                bigStat("HOURS", Status.h1(st.lifetime) + " h")
                bigStat("FLIGHTS", String(model.flights.count))
            }

            if let link = model.link, !link.isPending {
                Text("Shared bank with \(link.name.split(separator: " ").first.map(String.init) ?? link.name)")
                    .font(TFont.core(.medium, 14))
                    .tpType(size: 14, lineHeight: 1.4)
                    .foregroundStyle(TColor.textSecondary)
                    .padding(.top, 14)
            }

            Button {
                // The reference's `perm`: the dome rising from the bottom edge under its own shadow.
                model.go(.redeem, .perm)
            } label: {
                Text("Redeem miles")
                    .font(TFont.core(.semibold, 17))
                    .foregroundStyle(TColor.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(TColor.copper500, in: Capsule())
                    .tpShadow(.accent)
            }
            .buttonStyle(.plain)
            .padding(.top, 22)
        }
    }

    private func bigStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).tpLabelStyle().foregroundStyle(TColor.textMuted)
            tpText(value, size: 22, track: -0.04)
                .font(TFont.core(.bold, 22))
                .monospacedDigit()
                .foregroundStyle(TColor.textPrimary)
                .padding(.top, 11)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Linked account

    /// A shared bank used to live in Settings; it belongs with the miles.
    private var linkedCard: some View {
        statusCard {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("LINKED ACCOUNT").tpLabelStyle().foregroundStyle(TColor.textMuted)
                Spacer(minLength: 0)
                Button {
                    if model.plus { model.go(.linked, .lift, dir: 1) } else { model.paywall = .open }
                } label: {
                    Text(model.plus
                         ? (model.link == nil ? "Link an account \u{203a}" : "Manage \u{203a}")
                         : "Business Class \u{203a}")
                        .font(TFont.core(.medium, 14))
                        .foregroundStyle(TColor.textAccent)
                }
                .buttonStyle(.plain)
            }

            if let link = model.link, link.isPending {
                Text(link.isIncomingRequest
                     ? "\(link.name) wants to share a bank with you"
                     : "Waiting for \(link.name.split(separator: " ").first.map(String.init) ?? link.name) to accept")
                    .font(TFont.core(.semibold, 20))
                    .tpType(size: 20, track: -0.02, lineHeight: 1.25)
                    .foregroundStyle(TColor.textPrimary)
                    .padding(.top, 14)
                Text("Nothing is shared while this is pending.")
                    .font(TFont.core(.regular, 15))
                    .tpType(size: 15, lineHeight: 1.5)
                    .foregroundStyle(TColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 9)
            } else if let link = model.link {
                Text(link.name)
                    .font(TFont.core(.semibold, 20))
                    .tpType(size: 20, track: -0.02, lineHeight: 1.25)
                    .foregroundStyle(TColor.textPrimary)
                    .padding(.top, 14)
                Text("One shared pot. What you each held moved in when you linked, and everything either of you earns lands there too.")
                    .font(TFont.core(.regular, 15))
                    .tpType(size: 15, lineHeight: 1.5)
                    .foregroundStyle(TColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 9)

                Divider().overlay(TColor.borderSubtle).padding(.top, 18)

                // One figure. Linking merges both balances into the pot, so "yours" and "theirs"
                // are gone the moment the link is live — what is left is the one bank both spend.
                smallStat("SHARED BANK", "\(model.pool) mi")
                    .padding(.top, 16)
            } else {
                Text("Share one miles pot with another member. What you each hold moves in when you link, and everything either of you earns after is spendable by both.")
                    .font(TFont.core(.regular, 15))
                    .tpType(size: 15, lineHeight: 1.5)
                    .foregroundStyle(TColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)
            }
        }
    }

    private func smallStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).tpLabelStyle().foregroundStyle(TColor.textMuted)
            Text(value)
                .font(TFont.core(.semibold, 16))
                .monospacedDigit()
                .foregroundStyle(TColor.textPrimary)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Membership

    /// One headline, one bar, three figures — the period detail reads as a sentence.
    private var membershipCard: some View {
        let st = model.status
        return statusCard {
            Text("MEMBERSHIP").tpLabelStyle().foregroundStyle(TColor.textMuted)

            Text(headline(st))
                .font(TFont.core(.semibold, 20))
                .tpType(size: 20, track: -0.02, lineHeight: 1.3)
                .foregroundStyle(TColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)

            Text(subline(st))
                .font(TFont.core(.regular, 15))
                .tpType(size: 15, lineHeight: 1.5)
                .foregroundStyle(TColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 9)

            if let goal = goal(st) {
                VStack(spacing: 0) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(TColor.sky200)
                            Capsule().fill(TColor.copper500)
                                .frame(width: max(0, geo.size.width * goal.pct))
                        }
                    }
                    .frame(height: 6)

                    HStack {
                        Text(goal.from)
                        Spacer(minLength: 12)
                        Text(goal.to)
                    }
                    .tpLabelStyle()
                    .foregroundStyle(TColor.textMuted)
                    .padding(.top, 11)
                }
                .padding(.top, 20)
            }

            Divider().overlay(TColor.borderSubtle).padding(.top, 24)

            HStack(alignment: .top, spacing: 24) {
                ForEach(facts(st), id: \.0) { fact in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(fact.0).tpLabelStyle().foregroundStyle(TColor.textMuted)
                        Text(fact.1)
                            .font(TFont.core(.semibold, 17))
                            .foregroundStyle(TColor.textPrimary)
                            .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, 20)
        }
    }

    private func headline(_ st: Status.Snapshot) -> String {
        if st.founders { return "Founders, yours for good" }
        if let next = st.next { return "\(Status.h1(st.toNext)) hours to \(next.name)" }
        return "\(st.tier.name), the top tier you can fly to"
    }

    private func subline(_ st: Status.Snapshot) -> String {
        if st.founders {
            return "Granted, not flown for. Founders does not expire with the period."
        }
        let ends = fmtDay(st.end)
        if st.idx == 0 {
            return "Fly \(Status.h1(Status.tiers[1].gate)) h before \(ends) "
                + "to start the next period on Signature."
        }
        if st.holding {
            return "\(st.tier.name) is secured for the next period, which ends \(ends)."
        }
        return "You are carrying \(st.tier.name) from last period. "
            + "Fly \(Status.h1(st.hold)) h more by \(ends) to keep it."
    }

    private func goal(_ st: Status.Snapshot) -> (pct: Double, from: String, to: String)? {
        if st.founders { return nil }
        if let next = st.next {
            return (st.pct,
                    "\(Status.h1(st.hours)) H THIS PERIOD",
                    "\(next.name.uppercased()) \(Int(next.gate)) H")
        }
        return (min(1, st.lifetime / Status.founderHours),
                "\(Status.h1(st.lifetime)) H LIFETIME",
                "FOUNDERS 10,000 H")
    }

    private func facts(_ st: Status.Snapshot) -> [(String, String)] {
        [("EARN", "\u{00d7}" + mult(st.mult)),
         ("THIS PERIOD", Status.h1(st.hours) + " h"),
         st.founders
            ? ("EDITION", "No. " + model.founderSerialString)
            : ("DAYS LEFT", "\(st.daysLeft) days")]
    }

    // MARK: Business Class

    private var upsellCard: some View {
        Button {
            model.paywall = .open
        } label: {
            statusCard {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("Business Class")
                        .font(TFont.core(.semibold, 20))
                        .tracking(-0.02 * 20)
                        .foregroundStyle(TColor.textPrimary)
                    Spacer(minLength: 0)
                    Text("7 days free \u{203a}")
                        .font(TFont.core(.medium, 14))
                        .foregroundStyle(TColor.textAccent)
                }
                // "every card face" was true while the card studio charged for all but the first
                // face of a tier and the Concourse was gated whole. Both are open now, so the card
                // says what the plan actually buys: the Business stock on the shelf, the tiers
                // above Signature, the full log, and the multiplier.
                Text("Premier and Prestige, the Concourse's Business stock, the full log, and multipliers up to \u{00d7}1.3. Economy earns \u{00d7}1.0 and tops out at Signature.")
                    .font(TFont.core(.regular, 15))
                    .tpType(size: 15, lineHeight: 1.5)
                    .foregroundStyle(TColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                    .padding(.top, 10)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: The statement

    private struct Entry: Identifiable {
        let id: String
        let t: TimeInterval
        let n: Int
        let label: String
        let meta: String
    }

    /// Every mile in and out, most recent first. A Concourse purchase surfaces here as a spend of
    /// zero unlocked minutes, because that is exactly what the record says it is. An accepted gift
    /// is the other kind of credit — see `AppModel.acceptGift`, the one place its miles arrive.
    private var ledger: [Entry] {
        let earned = model.flights.enumerated().map { i, f in
            Entry(id: "f\(i)\(f.id)", t: f.t, n: f.miles,
                  label: f.subject.isEmpty ? "Flight \(f.no)" : f.subject,
                  meta: "\(f.minutes) min \u{00b7} \(f.no)")
        }
        let spent = model.spends.enumerated().map { i, x in
            Entry(id: "s\(i)\(x.t)", t: x.t, n: -x.cost,
                  label: x.label.isEmpty ? "Screen time" : x.label,
                  meta: "\(x.mins) min unlocked")
        }
        let credited = model.credits.enumerated().map { i, c in
            Entry(id: "c\(i)\(c.t)", t: c.t, n: c.amt, label: c.label, meta: "gift")
        }
        return (earned + spent + credited).sorted { $0.t > $1.t }
    }

    private var statementCard: some View {
        let rows = ledger
        let shown = showFullStatement ? rows : Array(rows.prefix(4))
        return statusCard {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("ACTIVITY STATEMENT").tpLabelStyle().foregroundStyle(TColor.textMuted)
                Spacer(minLength: 0)
                Text("\(rows.count) ENTRIES").tpLabelStyle().foregroundStyle(TColor.textMuted)
            }

            if rows.isEmpty {
                Text("Nothing yet. Miles arrive when you land.")
                    .font(TFont.core(.regular, 15))
                    .tpType(size: 15, lineHeight: 1.5)
                    .foregroundStyle(TColor.textSecondary)
                    .padding(.top, 14)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { i, row in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(row.label)
                                    .font(TFont.core(.medium, 15))
                                    .tpType(size: 15, lineHeight: 1.25)
                                    .foregroundStyle(TColor.textPrimary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Text(row.meta)
                                    .font(TFont.core(.regular, 13))
                                    .foregroundStyle(TColor.textMuted)
                                    .padding(.top, 6)
                            }
                            Spacer(minLength: 0)
                            Text("\(row.n > 0 ? "+" : "")\(row.n) mi")
                                .font(TFont.core(.semibold, 16))
                                .monospacedDigit()
                                .foregroundStyle(row.n > 0 ? TColor.textAccent : TColor.textPrimary)
                        }
                        .padding(.top, 15)
                        .padding(.bottom, i == shown.count - 1 ? 2 : 15)
                        .overlay(alignment: .bottom) {
                            if i != shown.count - 1 {
                                Rectangle().fill(TColor.borderSubtle).frame(height: 1)
                            }
                        }
                    }
                }
                .padding(.top, 6)

                if rows.count > 4 {
                    Button {
                        showFullStatement.toggle()
                    } label: {
                        Text(showFullStatement ? "Show less" : "Show full statement")
                            .font(TFont.core(.semibold, 15))
                            .foregroundStyle(TColor.navy700)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .overlay(Capsule().strokeBorder(TColor.borderDefault, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 16)
                }
            }
        }
    }

    // MARK: - Shared card shell

    @ViewBuilder
    private func statusCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TColor.surfaceCard,
                        in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .tpShadow(.card)
            .padding(.top, 24)
    }

    // MARK: - Formatting

    /// `×1` / `×1.3` — JavaScript prints a whole multiplier without its decimal, and the copy is
    /// quoted verbatim from the reference, so the number has to be too.
    private func mult(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }

    /// `3 Sep`.
    private func fmtDay(_ t: TimeInterval) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "d MMM"
        return f.string(from: Date(timeIntervalSince1970: t))
    }
}
