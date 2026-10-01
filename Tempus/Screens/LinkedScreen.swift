import SwiftUI

/// The linked member's shared bank — reached only from Status Club's "Manage"/"Link an account"
/// row, and only ever goes back there. Linked members hold one bank: `model.pool` already sums
/// `miles + link.miles`, so every balance figure here reads that rather than `miles` alone.
struct LinkedScreen: View {
    /// The name as a stat label wants it. Split out because the inline form had its interpolation
    /// close one character early and shipped the expression itself to the screen.
    static func firstName(_ full: String) -> String {
        full.split(separator: " ").first.map(String.init) ?? full
    }

    @Environment(AppModel.self) private var model
    @Environment(Backend.self) private var backend

    @State private var name = ""
    @State private var email = ""

    /// Set while `sendInvite` is in flight, so the button cannot be double-tapped into a second
    /// invite while the first is still on the wire.
    @State private var sending = false
    /// What the last send attempt refused for — a duplicate invite, or a transport failure.
    /// Cancelling clears nothing; there is nothing to cancel here, only to retry.
    @State private var sendError: String?
    @State private var signInSheet = false

    /// The real shared ledger, fetched from `backend.sharedLedger` once this member is actually
    /// linked through a server pair. Empty and unused for a local-only link (no pair to fetch).
    @State private var ledger: [LinkLedgerLine] = []
    @State private var ledgerLoading = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ORise(i: 0) {
                    IconButton(tone: .sunken, size: .md, label: "Back", action: back) {
                        Image(systemName: "chevron.left")
                    }
                }
                ORise(i: 1) {
                    Text("Linked account")
                        .font(TFont.core(.bold, 40))
                        .tracking(-0.045 * 40)
                        .foregroundStyle(TColor.textPrimary)
                        .padding(.top, 18)
                }
                ORise(i: 2) {
                    // **Two balances really do become one.** This used to say "from the moment
                    // you link", because for a while nothing moved across and the pot filled from
                    // the next landing on — which left two members comparing 3,000 mi against 81
                    // under a shared bank of 0. Linking now deposits each side's balance into the
                    // pot (`AppModel.mergePersonalMiles`), so the plain reading is the true one.
                    Text("One shared pot between two members. What you each hold moves in when you link, and everything either of you earns after lands there too.")
                        .font(TFont.core(.regular, TFont.sizeBody))
                        .tpType(size: TFont.sizeBody, lineHeight: 1.55)
                        .foregroundStyle(TColor.textSecondary)
                        .padding(.top, 14)
                }

                if !model.plus {
                    ORise(i: 3) { lockedCard }.padding(.top, 24)
                } else if let link = model.link, link.isIncomingRequest {
                    ORise(i: 3) { incomingRequestCard(link) }.padding(.top, 24)
                } else if let link = model.link, link.isPending {
                    ORise(i: 3) { outgoingRequestCard(link) }.padding(.top, 24)
                } else if let link = model.link {
                    ORise(i: 3) { identityCard(link) }.padding(.top, 24)
                    ORise(i: 4) { activity(link) }.padding(.top, 24)
                    ORise(i: 5) { unlinkButton(link) }.padding(.top, 26)
                } else {
                    ORise(i: 3) { chooseCard }.padding(.top, 24)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, TSpace.topInset(56))
            .padding(.bottom, 124)
        }
        // Not `.ignoresSafeArea()` here: `.linked` is not full-bleed, and the router's own
        // `PhaseLayer` already bleeds this same colour behind it through `StageClip` — an inline
        // `.ignoresSafeArea()` stops reaching the window the moment the stack holds a second
        // layer (mid-transition, always), so this fill would shrink to the content's own
        // safe-area rect right when `.status`'s ground behind it had already switched to
        // `sky100`, and the mismatch would flash at the rounded corners the lift animates.
        .background(TColor.cloud100)
        .sheet(isPresented: $signInSheet) { SignInSheet() }
        // One-shot, not a poll: confirms `pot` and catches an invite accepted from the other
        // member's device, which has no other way to reach this one. Not gated on `linkPairID`:
        // a sender still waiting has no pair id yet, and is exactly who this call is for — it
        // used to be gated, which is why an acceptance needed a relaunch to show.
        .task { await model.refreshSharedBank() }
        // ponytail: a seam confined to this file — driving the return transition needs no state
        // outside what `back()` already touches, so this skips LaunchSeams.swift entirely.
        // `-tempusLinkBack` lands here (paired with the existing `-tempusPhase linked
        // -tempusLinked`), waits a beat for the screen to settle, then leaves the way a real tap
        // on Back would, so the Linked → Club transition can be recorded without a tap the
        // Simulator cannot make.
        .task {
            guard CommandLine.arguments.contains("-tempusLinkBack") else { return }
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            back()
        }
    }

    private func back() { model.go(.status, .lift, dir: -1) }

    // MARK: - A. Not Business Class

    private var lockedCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "lock.fill").font(.system(size: 13, weight: .semibold))
                Text("Business Class").tpLabelStyle()
            }
            .foregroundStyle(TColor.textAccent)

            Text("Linking is a Business Class feature")
                .font(TFont.core(.bold, 24)).tpType(size: 24, lineHeight: 1.1)
                .foregroundStyle(TColor.textPrimary)

            Text("Share one bank with another member. What you each hold moves in when you link, and every mile either of you earns after is spendable by both.")
                .font(TFont.core(.regular, TFont.sizeBody))
                .tpType(size: TFont.sizeBody, lineHeight: TFont.lhBody)
                .foregroundStyle(TColor.textSecondary)

            TButton("Start 7 days free", variant: .primary, size: .lg, fullWidth: true) {
                model.paywall = .open
            }
            .padding(.top, 6)
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(TColor.surfaceCard))
        .tpShadow(.card)
    }

    // MARK: - B1. Pending, sent by you

    /// **Visually distinct from "linked" on purpose** — an invite sent and a bank actually open
    /// must never look the same. With a real backend behind `linkInviteID` this reached the other
    /// member the moment it was sent; with none (or the schema not yet provisioned), it is real and
    /// honest but only this device knows it was sent — either way `pool` excludes it
    /// (`AppModel.linkedMiles`), so nothing here is spendable until it is accepted.
    private func outgoingRequestCard(_ link: LinkAccount) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("WAITING").tpLabelStyle().foregroundStyle(TColor.textMuted)
            Text("Waiting for \(Self.firstName(link.name)) to accept")
                .font(TFont.core(.bold, 22)).tpType(size: 22, lineHeight: 1.15)
                .foregroundStyle(TColor.textPrimary)
            if let email = link.email, !email.isEmpty {
                Text("Sent to \(email)")
                    .font(TFont.core(.medium, TFont.sizeBodySm))
                    .foregroundStyle(TColor.textMuted)
            }
            Text("Nothing is shared until \(Self.firstName(link.name)) accepts, and nothing has moved. You can withdraw the request at any time.")
                .font(TFont.core(.regular, TFont.sizeBody))
                .tpType(size: TFont.sizeBody, lineHeight: TFont.lhBody)
                .foregroundStyle(TColor.textSecondary)
            TButton("Withdraw request", variant: .ghost, size: .md, fullWidth: true) {
                model.withdrawLinkRequest()
            }
            .padding(.top, 2)
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(TColor.surfaceCard))
        .tpShadow(.card)
    }

    // MARK: - B2. Pending, sent to you

    private func incomingRequestCard(_ link: LinkAccount) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("REQUEST").tpLabelStyle().foregroundStyle(TColor.textMuted)
            Text("\(link.name) wants to share a bank with you")
                .font(TFont.core(.bold, 22)).tpType(size: 22, lineHeight: 1.15)
                .foregroundStyle(TColor.textPrimary)
            Text("One shared bank. What you each hold moves in when you accept, and everything either of you earns after is spendable by both.")
                .font(TFont.core(.regular, TFont.sizeBody))
                .tpType(size: TFont.sizeBody, lineHeight: TFont.lhBody)
                .foregroundStyle(TColor.textSecondary)
            HStack(spacing: 10) {
                TButton("Decline", variant: .ghost, size: .md, fullWidth: true) {
                    model.declineLinkRequest()
                }
                TButton("Accept", variant: .primary, size: .md, fullWidth: true) {
                    model.acceptLinkRequest()
                }
            }
            .padding(.top, 2)
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(TColor.surfaceCard))
        .tpShadow(.card)
    }

    // MARK: - B. Linked

    private func identityCard(_ link: LinkAccount) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Text(initials(link.name))
                    .font(TFont.core(.semibold, 18))
                    .foregroundStyle(TColor.textPrimary)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(TColor.sky200))
                VStack(alignment: .leading, spacing: 4) {
                    Text(link.name).font(TFont.core(.semibold, 20)).foregroundStyle(TColor.textPrimary)
                    Text("Linked \(fmtDay(link.at))")
                        .font(TFont.core(.regular, TFont.sizeBodySm))
                        .foregroundStyle(TColor.textMuted)
                }
                Spacer(minLength: 0)
            }

            Rectangle().fill(TColor.borderSubtle).frame(height: 1).padding(.vertical, 18)

            // One figure. Linking merges both balances into the pot, so "yours" and "theirs" are
            // gone the moment the link is live — what is left is the one bank both members spend.
            stat("SHARED BANK", "\(model.pool) mi", big: true)

            if model.linkPairID != nil {
                Text("What you each held moved into the pot when you linked, and everything either of you earns lands there too. Both of you spend from it.")
                    .font(TFont.core(.regular, 13))
                    .tpType(size: 13, lineHeight: 1.45)
                    .foregroundStyle(TColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)
            }

            // `potStale` is a promise: the figure above is last-known, not confirmed, until a
            // refresh clears it — same honesty rule as Settings' "Screen time is not connected"
            // banner. `refreshSharedBank` is already kicked off once by this screen's own `.task`.
            if model.linkPairID != nil, model.potStale {
                Text("Confirming the shared bank\u{2026}")
                    .font(TFont.core(.regular, 12))
                    .foregroundStyle(TColor.textMuted)
                    .padding(.top, 10)
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(TColor.surfaceCard))
        .tpShadow(.card)
    }

    private func stat(_ label: String, _ value: String, big: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).tpLabelStyle().foregroundStyle(TColor.textMuted)
            Text(value)
                .font(TFont.core(.bold, big ? 22 : 17))
                .foregroundStyle(TColor.textPrimary)
        }
    }

    /// A real server pair reads the real shared ledger — both members wrote it, so nothing in it
    /// is a guess. Anything else (no pair yet, no backend, no account) falls back to the old local
    /// reconstruction, exactly as it always has.
    @ViewBuilder
    private func activity(_ link: LinkAccount) -> some View {
        if let pairID = model.linkPairID, Backend.isConfigured, backend.isLinked {
            sharedLedgerCard(pairID: pairID, partner: Self.firstName(link.name))
        } else {
            localActivityCard(link)
        }
    }

    private func sharedLedgerCard(pairID: String, partner: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("SHARED ACTIVITY").tpLabelStyle().foregroundStyle(TColor.textMuted)
                Spacer()
                if !ledger.isEmpty {
                    Text("\(ledger.count) ENTRIES").tpLabelStyle().foregroundStyle(TColor.textMuted)
                }
            }
            .padding(.bottom, 14)

            if ledgerLoading && ledger.isEmpty {
                Text("Loading\u{2026}")
                    .font(TFont.core(.regular, TFont.sizeBodySm))
                    .foregroundStyle(TColor.textMuted)
                    .padding(.vertical, 8)
            } else if ledger.isEmpty {
                Text("Nothing in the bank yet. Miles arrive when either of you lands.")
                    .font(TFont.core(.regular, TFont.sizeBodySm))
                    .tpType(size: TFont.sizeBodySm, lineHeight: 1.5)
                    .foregroundStyle(TColor.textMuted)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(ledger.enumerated()), id: \.element.id) { i, l in
                        ledgerRow(l, partner: partner)
                        if i < ledger.count - 1 {
                            Rectangle().fill(TColor.borderSubtle).frame(height: 1)
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(TColor.surfaceCard))
        .tpShadow(.card)
        .task(id: pairID) { await loadLedger(pairID) }
    }

    private func loadLedger(_ pairID: String) async {
        ledgerLoading = true
        ledger = (try? await backend.sharedLedger(pair: pairID, limit: 50)) ?? []
        ledgerLoading = false
    }

    /// One line of the real shared ledger. `Backend.sharedLedger` stamps `mine` from the caller's
    /// own id, so a line can say whose movement it was — which is most of the question when two
    /// people spend from one pot, and the half this screen used to leave unanswered.
    private func ledgerRow(_ l: LinkLedgerLine, partner: String) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(l.label).font(TFont.core(.medium, 15)).foregroundStyle(TColor.textPrimary)
                Text("\(l.mine ? "You" : partner) \u{00b7} \(fmtDay(parseISO(l.at)))")
                    .font(TFont.core(.regular, 13)).foregroundStyle(TColor.textMuted)
            }
            Spacer(minLength: 8)
            Text((l.amount > 0 ? "+" : "") + "\(l.amount) mi")
                .font(TFont.core(.semibold, 15))
                .foregroundStyle(l.amount > 0 ? TColor.textAccent : TColor.textPrimary)
        }
        .padding(.vertical, 12)
    }

    private func parseISO(_ s: String) -> TimeInterval {
        ISO8601DateFormatter().date(from: s)?.timeIntervalSince1970 ?? Date().timeIntervalSince1970
    }

    /// The pre-existing reconstruction from local flights and spends, for a link with no real pair
    /// behind it yet (no backend, no account, or the schema not provisioned).
    private func localActivityCard(_ link: LinkAccount) -> some View {
        let entries = feed(link)
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("SHARED ACTIVITY").tpLabelStyle().foregroundStyle(TColor.textMuted)
                Spacer()
                Text("\(entries.count) ENTRIES").tpLabelStyle().foregroundStyle(TColor.textMuted)
            }
            .padding(.bottom, 14)

            if entries.isEmpty {
                Text("Nothing in the bank yet. Miles arrive when either of you lands.")
                    .font(TFont.core(.regular, TFont.sizeBodySm))
                    .tpType(size: TFont.sizeBodySm, lineHeight: 1.5)
                    .foregroundStyle(TColor.textMuted)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.k) { i, e in
                        feedRow(e)
                        if i < entries.count - 1 {
                            Rectangle().fill(TColor.borderSubtle).frame(height: 1)
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(TColor.surfaceCard))
        .tpShadow(.card)
    }

    private func feedRow(_ e: LinkedFeedEntry) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(e.label).font(TFont.core(.medium, 15)).foregroundStyle(TColor.textPrimary)
                Text(e.meta.isEmpty ? e.who : "\(e.who) \u{2014} \(e.meta)")
                    .font(TFont.core(.regular, 13)).foregroundStyle(TColor.textMuted)
            }
            Spacer(minLength: 8)
            Text((e.n > 0 ? "+" : "") + "\(e.n) mi")
                .font(TFont.core(.semibold, 15))
                .foregroundStyle(e.n > 0 ? TColor.textAccent : TColor.textPrimary)
        }
        .padding(.vertical, 12)
    }

    /// Splits the pot and credits this member's share back before dropping the link — never a bare
    /// `link = nil`, which would leave a real pair's remaining pot stranded server-side.
    private func unlinkButton(_ link: LinkAccount) -> some View {
        TButton("Unlink \(link.name.split(separator: " ").first.map(String.init) ?? link.name)",
               variant: .ghost, size: .md, fullWidth: true) {
            Task { @MainActor in await model.unlinkAccount() }
        }
    }

    /// `mine` (your flights + spends) concatenated with `theirs` (the partner's seeded log),
    /// newest first. `link.log` is frozen at link time in the reference — nothing appends to it
    /// afterwards, including a Concourse purchase that draws from the partner's balance, which is
    /// a real gap this native port doesn't have a second ledger to fix from this screen alone.
    private func feed(_ link: LinkAccount) -> [LinkedFeedEntry] {
        let mine = model.flights.map {
            LinkedFeedEntry(k: "f\($0.id)", t: $0.t, n: $0.miles, who: you,
                            label: $0.subject, meta: "\($0.minutes) min")
        } + model.spends.map {
            LinkedFeedEntry(k: "s\($0.id)", t: $0.t, n: -$0.cost, who: you,
                            label: $0.label, meta: "\($0.mins) min unlocked")
        }
        let theirs = link.log.map {
            LinkedFeedEntry(k: "l\($0.id)", t: $0.t, n: $0.n,
                            who: link.name.split(separator: " ").first.map(String.init) ?? link.name,
                            label: $0.label, meta: $0.meta)
        }
        return (mine + theirs).sorted { $0.t > $1.t }
    }

    private var you: String { (model.member.isEmpty ? "You" : model.member).split(separator: " ").first.map(String.init) ?? "You" }

    // MARK: - C. Not yet linked

    /// Real invites need an account to deliver to — with a server configured but nobody signed
    /// in, offering the form anyway would be a control that cannot work, the same rule the
    /// Concourse search field is held to. With no server configured at all this never shows:
    /// `chooseCard` below falls straight to the honest local-only form instead, unchanged.
    @ViewBuilder
    private var chooseCard: some View {
        if Backend.isConfigured, !backend.isLinked {
            needsAccountCard
        } else {
            requestFormCard
        }
    }

    private var needsAccountCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("LINK AN ACCOUNT").tpLabelStyle().foregroundStyle(TColor.textMuted)
            Text("Sign in to link accounts")
                .font(TFont.core(.bold, 24)).tpType(size: 24, lineHeight: 1.1)
                .foregroundStyle(TColor.textPrimary)
            Text("A real request needs an account to deliver it to, so the other member has somewhere to receive it.")
                .font(TFont.core(.regular, TFont.sizeBody))
                .tpType(size: TFont.sizeBody, lineHeight: TFont.lhBody)
                .foregroundStyle(TColor.textSecondary)
            TButton("Sign in", variant: .primary, size: .lg, fullWidth: true) {
                signInSheet = true
            }
            .padding(.top, 6)
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(TColor.surfaceCard))
        .tpShadow(.card)
    }

    private var requestFormCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("WHO ARE YOU LINKING WITH").tpLabelStyle().foregroundStyle(TColor.textMuted)

            RecipientFields(name: $name, email: $email)

            TButton(sending ? "Sending\u{2026}" : "Send request", variant: .primary, size: .lg,
                    fullWidth: true, disabled: !canLink || sending) {
                dismissKeyboard()
                link(name.trimmingCharacters(in: .whitespaces), email.trimmingCharacters(in: .whitespaces))
            }
            .padding(.top, 2)

            if let sendError {
                Text(sendError)
                    .font(TFont.core(.medium, 13))
                    .foregroundStyle(TColor.statusDiverted)
            }

            Text("Sending a request costs nothing and shares nothing yet — the bank only becomes one once they accept, and either of you can unlink at any time after.")
                .font(TFont.core(.regular, 13))
                .tpType(size: 13, lineHeight: 1.5)
                .foregroundStyle(TColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(TColor.surfaceCard))
        .tpShadow(.card)
    }

    /// A name, and an address that at least has the shape of one. Not validation for its own sake —
    /// the address is how the other member is reached the day there is a server to reach them
    /// through, so a bank linked against "asdf" would be a bank linked to nobody. Shared with
    /// `GiftScreen`'s recipient step through `RecipientFields.isValid` — see the note there.
    private var canLink: Bool { RecipientFields.isValid(name: name, email: email) }

    /// Sending a request opens **a pending link with an empty bank**, and that is the honest thing
    /// for it to do.
    ///
    /// This used to link instantly, offering three fabricated members — Marcus Hale, Priya Raman,
    /// Jonah Webb — and picking any of them seeded the same 120 mi and the same three invented log
    /// entries. Two things were wrong with that: it put people who do not exist in a shipping
    /// build, and it minted miles nobody flew for, in an app whose whole economy is that miles are
    /// flown for. Making the link instant compounded it — a real name typed in still established a
    /// shared bank nobody on the other end had agreed to.
    ///
    /// **The shared bank is real now, behind a signed-in account.** `chooseCard` only shows this
    /// form when either there is no server to reach (`applyLocalLink`, unchanged from before the
    /// backend existed) or this member is signed in and can actually post an invite — a server
    /// configured but not yet provisioned (`.notProvisioned`, `supabase/schema.sql` not run against
    /// the live project) falls back to the same local, honest, device-only request rather than
    /// showing a dead control.
    private func link(_ name: String, _ email: String) {
        guard Backend.isConfigured, backend.isLinked else {
            applyLocalLink(name, email)
            return
        }
        sendError = nil
        sending = true
        Task { @MainActor in
            do {
                let invite = try await backend.sendInvite(
                    toName: name, toEmail: email,
                    fromName: model.cardName)
                model.showInvite(invite, iSent: true)
            } catch BackendError.notProvisioned {
                applyLocalLink(name, email)
            } catch BackendError.duplicateInvite {
                sendError = "You've already invited that address."
            } catch {
                sendError = Backend.describe(error)
            }
            sending = false
        }
    }

    private func applyLocalLink(_ name: String, _ email: String) {
        model.link = LinkAccount(name: name, email: email, miles: 0,
                                 at: Date().timeIntervalSince1970, log: [],
                                 pending: true, requestedByThem: false)
    }

    private func initials(_ name: String) -> String {
        name.split(separator: " ").compactMap { $0.first.map(String.init) }.joined()
    }

    private func fmtDay(_ t: TimeInterval) -> String {
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy"
        f.locale = Locale(identifier: "en_GB")
        return f.string(from: Date(timeIntervalSince1970: t))
    }
}

private struct LinkedFeedEntry {
    let k: String
    let t: TimeInterval
    let n: Int
    let who: String
    let label: String
    let meta: String
}

// MARK: - The recipient form, shared with GiftScreen

/// "Who is this for" — a name and an email, validated the same shape-check either place needs
/// it: this screen's "who are you linking with" card, and `GiftScreen`'s recipient step. Both
/// used to carry their own copy of the two `TTextField`s and their own copy of the validator;
/// factored into one piece so a change to the rule (or the chrome) cannot update one and miss
/// the other. Deliberately *not* promoted to `DesignSystem/` — `TTextField` there is genuinely
/// shared chrome, but "a name and an email, checked this way" is specific to the two places that
/// address a person by hand rather than a real account.
struct RecipientFields: View {
    @Binding var name: String
    @Binding var email: String

    var body: some View {
        VStack(spacing: 10) {
            TTextField(placeholder: "Their name", text: $name)
            TTextField(placeholder: "Their email", text: $email)
        }
    }

    /// A name, and an address that at least has the shape of one — not validation for its own
    /// sake, but the way either recipient would actually be reached the day there is a server to
    /// reach them through, so a request or a gift addressed to "asdf" would reach nobody.
    static func isValid(name: String, email: String) -> Bool {
        let n = name.trimmingCharacters(in: .whitespaces)
        let e = email.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, e.count >= 5, !e.hasPrefix("@"), !e.hasSuffix("@") else { return false }
        let parts = e.split(separator: "@")
        return parts.count == 2 && parts[1].contains(".") && !parts[1].hasSuffix(".")
    }
}

/// `TTextField` (`DesignSystem/Controls.swift`) carries its own private `@FocusState` bound
/// directly to the real `TextField` inside it — that is the leaf SwiftUI's focus system actually
/// tracks. A `.focused($x, equals:)` applied from *outside* a `TTextField`, as this screen and
/// `GiftScreen` both used to, binds to nothing real: there is no unclaimed focusable descendant
/// left for it to attach to, so setting that outer state to `nil` to close the keyboard before
/// handing off to an async call (`link`, or `GiftScreen`'s `send`) was dead code — the keyboard
/// stayed up over the pay sheet / the "Sending…" state. Resigning the first responder directly is
/// the one way to dismiss it without `TTextField` exposing a binding of its own.
func dismissKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}
