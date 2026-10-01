import FamilyControls
import SwiftUI

/// Settings furniture: every row is either a direct write (the two switches), a navigation
/// (Status Club, Home airport), or a tap into the one shared `ChoiceSheet`.
///
/// **Never let this screen imply blocking is live.** Real enforcement needs Screen Time
/// authorisation, which this build does not hold — that promise belongs to the Blocking screen,
/// not here, but nothing on this screen may contradict it either.
/// The account-deletion row's two dialogs, lifted out of `SettingsScreen.body`.
///
/// Not tidiness: the body is already at the point where the type-checker gives up, and inlining a
/// `confirmationDialog` plus an `alert` tipped it into "unable to type-check in reasonable time".
private struct DeleteAccountDialogs: ViewModifier {
    @Binding var confirming: Bool
    @Binding var error: String?
    let onDelete: () -> Void

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Delete your account?",
                                isPresented: $confirming, titleVisibility: .visible) {
                Button("Delete account", role: .destructive, action: onDelete)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This deletes your account, its cloud backup and any shared bank, and erases everything on this phone: miles, passes, the flight log and your settings. It cannot be undone.")
            }
            .alert("Could not delete the account", isPresented: shown) {
                Button("OK", role: .cancel) { error = nil }
            } message: {
                Text(error ?? "")
            }
    }

    private var shown: Binding<Bool> {
        Binding(get: { error != nil }, set: { if !$0 { error = nil } })
    }
}

struct SettingsScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(Identity.self) private var identity
    @Environment(Backend.self) private var backend

    private enum SheetKind { case length, rate, policy, apps, spend, limit, goal, horizon }

    @State private var sheet: SheetKind?
    /// Flips true to ask the open `ChoiceSheet` to play its sink — see `ChoiceSheet.dismiss`.
    /// Only the `-tempusSettingsSheet` seam sets this; a real dismissal goes through the scrim or
    /// a single-select pick instead, both internal to `ChoiceSheet` itself.
    @State private var sheetDismiss = false
    /// iOS's own app picker. It is the only way to obtain the tokens a real shield needs, and it
    /// cannot be styled — so it is presented as the system sheet it is rather than dressed up.
    @State private var pickerOpen = false
    /// What the picker edits. It is written to the model only when the picker closes, because
    /// after the first pick a change costs miles and is confirmed before anything moves.
    @State private var draft = FamilyActivitySelection()
    /// A priced change waiting on the member's yes — see `AppModel.changeSelection`.
    @State private var confirmingChange = false
    /// The sentence shown when a change could not be paid for.
    @State private var changeRefusal: String?
    /// Re-read on appear and after a request, because authorization is granted outside this
    /// process and `AuthorizationCenter` is not observable.
    @State private var authorized = false
    /// Seven taps on the title opens developer mode, and nothing marks the title as tappable —
    /// that is the point. **DEBUG only** — see `Dev.available`. On every other build
    /// `countTitleTap` returns on its first line and the taps go nowhere, silently: a hidden door
    /// that announces itself is not hidden.
    @State private var titleTaps = 0
    @State private var devOpen = false
    /// The name field — an alert with a text box.
    @State private var editingName = false
    @State private var nameEntry = ""
    @State private var signInSheet = false
    @State private var legal: LegalDoc?
    @State private var confirmingDelete = false
    @State private var deleteError: String?
    @State private var deleting = false
    /// Where the circle reveal grows from. Read at tap time, and measured *outside* the button's
    /// `ORise` — the entrance is an 18pt `.offset`, and a `GeometryReader` inside it reports the
    /// frame with that offset baked in, so an `onAppear` capture (the old spelling) put the circle's
    /// origin 18pt below the X for the life of the screen. Same rule as the deck card's morph rect.
    @State private var closeRect = RectBox()

    var body: some View {
        // The gutter is applied to the header and to the scroll *content*, never to the stack that
        // holds the ScrollView. A ScrollView clips to its bounds, so a card sized to the full
        // scroll width has its shadow sliced dead flat down both edges — `TShadow.card` is a 6pt
        // and a 12pt blur that need room to fade out in. Padding inside the clip gives them that
        // room; padding outside it only moves the guillotine. `DevSheet` already does it this way.
        // The header scrolls with the page — it is the first rows of the content, not a bar the
        // groups slide under. iOS puts identity first: the account block leads, the Business Class
        // upsell sits right under it (the same slot an Apple ID row gives an iCloud+ banner), and
        // everything else follows in subject groups — customisation (the card, the club) ahead of
        // the operational flight settings, screen time last before Developer.
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 0) {
                        ORise(i: 0) { closeButton }
                            .measureRect(into: closeRect, in: TStage.space)
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 16)
                    ORise(i: 1) {
                        Text("Settings")
                            .font(TFont.core(.bold, 40))
                            .tracking(-0.045 * 40)
                            .foregroundStyle(TColor.textPrimary)
                            .padding(.top, 18)
                            .contentShape(Rectangle())
                            .onTapGesture(perform: countTitleTap)
                    }
                    ORise(i: 2) { accountGroup }
                    ORise(i: 3) { businessClassPromo.padding(.top, 26) }
                    ORise(i: 4) { membershipGroup }
                    ORise(i: 5) { flightsGroup }
                    ORise(i: 6) { screenTimeGroup }
                    ORise(i: 6) { legalGroup }
                    ORise(i: 7) {
                        VStack(alignment: .leading, spacing: 0) {
                            if Dev.available, model.devMode { developerGroup }
                            Text("Live Activity keeps the flight on your lock screen and in the Dynamic Island.")
                                .font(TFont.core(.regular, 13))
                                .tpType(size: 13, lineHeight: 1.5)
                                .foregroundStyle(TColor.textMuted)
                                .padding(.leading, 2)
                                .padding(.top, 12)
                                .padding(.bottom, 20)
                        }
                    }
                }
                .padding(.horizontal, TSpace.gutter)
                .padding(.bottom, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(TColor.white)
        .overlay { if let sheet { sheetView(sheet) } }
        .familyActivityPicker(isPresented: $pickerOpen, selection: $draft)
        .onChange(of: pickerOpen) { _, open in
            // The hold before the picker opened was the confirmation; closing it without a change
            // costs nothing.
            guard !open, draft != model.selection else { return }
            applyDraft()
        }
        .overlay {
            if confirmingChange {
                HoldConfirmSheet(
                    title: "Change your apps",
                    figure: "\(AppModel.selectionChangeCost) mi",
                    note: "Your first pick was free. Each change after it costs \(AppModel.selectionChangeCost) miles, charged only if you save a different set.",
                    holdLabel: "Hold to choose apps",
                    cancelLabel: "Keep current apps",
                    onConfirm: { confirmingChange = false; draft = model.selection; pickerOpen = true },
                    onCancel: { confirmingChange = false }
                )
            }
        }
        .alert("Apps not changed", isPresented: Binding(
            get: { changeRefusal != nil }, set: { if !$0 { changeRefusal = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(changeRefusal ?? "") }
        .task { authorized = model.screenTimeAuthorized }
        .sheet(isPresented: $signInSheet) { SignInSheet() }
        .alert("Name on your card", isPresented: $editingName) {
            TextField("Your name", text: $nameEntry)
                .textContentType(.name)
                .textInputAutocapitalization(.words)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                model.member = String(nameEntry.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
                model.save()
            }
        } message: { Text("Printed on your Status Club card and every pass.") }
        .sheet(item: $legal) { LegalSheet(doc: $0) }
        .modifier(DeleteAccountDialogs(confirming: $confirmingDelete,
                                       error: $deleteError,
                                       onDelete: deleteAccount))
        .task {
            // `-tempusDev` asks for the sheet straight away; the seven-tap gesture cannot be
            // driven in the Simulator, which takes no synthetic taps.
            guard Dev.available, model.devSheet else { return }
            model.devSheet = false
            devOpen = true
        }
        .task {
            // `-tempusCircle` plays the close unattended, from the *measured* rect — so a leaking
            // measurement (an entrance offset baked into it) grows the circle from the wrong point
            // on the recording, the way `-tempusMorphDrag` catches the deck card's.
            guard model.launchSeams.circleReveal else { return }
            try? await Task.sleep(for: .milliseconds(2600))
            let r = closeRect.rect
            model.circleGo(from: CGPoint(x: r.midX, y: r.midY), to: .home)
        }
        .task {
            // `-tempusSettingsSheet` opens "Cost per minute", holds it, then asks it to sink back
            // out — so both halves of the droplet can be watched without a tap the Simulator
            // cannot make. Settled first (the same 2.6s beat `-tempusMorph`/`-tempusCardClose`
            // wait for). The close goes through `sheetDismiss`, not a direct `sheet = nil`: this
            // component now plays its own sink before it actually unmounts (see `ChoiceSheet.
            // shut()`), so skipping straight to `nil` would cut the close instead of showing it.
            if model.launchSeams.appsConfirm {
                try? await Task.sleep(for: .milliseconds(2600))
                confirmingChange = true
                return
            }
            guard model.launchSeams.settingsSpendSheet else { return }
            try? await Task.sleep(for: .milliseconds(2600))
            open(.spend)
            try? await Task.sleep(for: .milliseconds(1400))
            sheetDismiss = true
        }
        .overlay {
            if devOpen {
                DevSheet { withAnimation(.glide(TDur.base)) { devOpen = false } }
                    .transition(.opacity)
            }
        }
    }

    // MARK: - Developer mode

    private func countTitleTap() {
        guard Dev.available else { return }
        // Already on: the title is the way back in, no counting needed.
        if model.devMode {
            withAnimation(.glide(TDur.base)) { devOpen = true }
            return
        }
        titleTaps += 1
        guard titleTaps >= Dev.tapsToUnlock else { return }
        titleTaps = 0
        unlockDev()
    }

    private func unlockDev() {
        model.devMode = true
        Haptics.done()
        withAnimation(.glide(TDur.base)) { devOpen = true }
    }

    // Every group on this screen passes `shadow: .raised`, not `SetGroup`'s own `.card` default —
    // a settings list is nothing but stacked groups on a plain page, so `.card`'s lighter shadow
    // read as barely-there. `SetGroup`'s default stays `.card` for onboarding's app-list screen
    // and Redeem's app groups, which share the component but not this screen's density.

    private var developerGroup: some View {
        SetGroup(title: "Developer", shadow: .raised) {
            SetRow(label: "Developer mode",
                   value: model.devHasPlus ? "Business Class granted" : "On",
                   last: true) { withAnimation(.glide(TDur.base)) { devOpen = true } }
        }
    }

    // MARK: - Header

    private var closeButton: some View {
        IconButton(tone: .sunken, size: .md, label: "Back", action: {
            let r = closeRect.rect
            model.circleGo(from: CGPoint(x: r.midX, y: r.midY), to: .home)
        }) {
            Image(systemName: "xmark").font(.system(size: 20, weight: .regular))
        }
    }

    // MARK: - Business Class promo

    /// Routed through `TCard` like every other surface on the page — it used to be a raw `Button`
    /// with a hand-built HStack/VStack, manual hairlines and no background, the one control here
    /// that never got `.tpShadow`. `TCard(tone: .light, action:)` gives it the card background and
    /// `.card` shadow for free, so it now matches `SetGroup`'s card exactly rather than floating
    /// unshadowed above it.
    private var businessClassPromo: some View {
        TCard(tone: .light, action: { model.paywall = .open }) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Business Class")
                        .font(TFont.core(.semibold, 20))
                        .tracking(-0.02 * 20)
                        .foregroundStyle(TColor.textPrimary)
                    Spacer()
                    Text(model.plus ? "Active" : "Upgrade \u{203A}")
                        .font(TFont.core(.medium, 14))
                        .foregroundStyle(TColor.textAccent)
                }
                Text("Every route, the full log, all your passes.")
                    .font(TFont.core(.regular, 15))
                    .tpType(size: 15, lineHeight: 1.5)
                    .foregroundStyle(TColor.textSecondary)
                    .padding(.top, 10)
            }
        }
    }

    // MARK: - Groups

    /// Customisation: what the card and the club look like, separate from the operational flight
    /// settings below — this is who you are on the card, not how a flight runs.
    private var membershipGroup: some View {
        SetGroup(title: "Membership", shadow: .raised) {
            SetRow(label: "Name on your card",
                   value: model.cardName,
                   action: { nameEntry = model.member; editingName = true })
            SetRow(label: "Status Club", value: model.status.tier.name, last: true,
                   action: { model.go(.status, .lift, dir: 1) })
        }
    }

    private var flightsGroup: some View {
        SetGroup(title: "Flights", shadow: .raised) {
            SetRow(label: "Home airport", value: model.homeAirport.code,
                   action: { model.airportSheet = true })
            SetRow(label: "Default length", value: "\(model.defaultMinutes) min",
                   action: { open(.length) })
            SetRow(label: "Weekly study goal",
                   value: model.weeklyGoal > 0 ? "\(model.weeklyGoal) h" : "Off",
                   action: { open(.goal) })
            SetRow(label: "Earn rate", value: "\(model.rate) mi",
                   action: { open(.rate) })
            SetRow(label: "Leaving early",
                   value: model.policy == .partial ? "Partial credit" : "All or nothing",
                   last: true, action: { open(.policy) })
        }
    }

    /// Everything the selection covers — apps, whole categories, web domains. A category counts
    /// as one line here because that is how it was chosen.
    private var selectedCount: Int {
        model.selection.applicationTokens.count
            + model.selection.categoryTokens.count
            + model.selection.webDomainTokens.count
    }

    /// The promise the whole screen is under: when Screen Time is not authorized nothing in this
    /// group is enforced, and the member is told so rather than left to assume otherwise. It leads
    /// the section rather than sitting inside the card, because it is about the card rather than
    /// one row of it.
    private var notConnectedBanner: some View {
        StatusBanner(tone: .info, title: "Screen time is not connected") {
            Text("Apps are not locked yet. Connect it to choose what costs miles.")
        } action: {
            Button("Connect") {
                Task {
                    await model.requestScreenTimeAuthorization()
                    authorized = model.screenTimeAuthorized
                    // A grant changes nothing on the model, so nothing would otherwise raise the
                    // shield over a selection restored from a previous install until the next
                    // unrelated write.
                    model.reconcileBlocking()
                }
            }
            .font(TFont.core(.semibold, TFont.sizeBodySm))
            .foregroundStyle(TColor.textAccent)
        }
        .padding(.top, 26)
    }

    /// A change after the first pick costs miles, so a member who cannot cover it is told before
    /// the picker opens rather than after they have chosen.
    private func openPicker() {
        let cost = AppModel.selectionChangeCost
        if selectedCount > 0, model.pool < cost {
            changeRefusal = "Changing your apps costs \(cost) mi. You need \(cost - model.pool) mi more."
            return
        }
        // A first pick is free and goes straight to the picker; a change is confirmed first.
        guard selectedCount == 0 else { confirmingChange = true; return }
        draft = model.selection
        pickerOpen = true
    }

    private func applyDraft() {
        let next = draft
        Task {
            switch await model.changeSelection(to: next) {
            case .ok: break
            case .refused:
                changeRefusal = "Changing your apps costs \(AppModel.selectionChangeCost) mi, and the balance does not cover it."
            case .unavailable:
                changeRefusal = "The shared bank could not be reached. Nothing was charged."
            }
        }
    }

    private var screenTimeGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !authorized { notConnectedBanner }
            SetGroup(title: "Screen time", shadow: .raised) {
                SetRow(label: "Apps that cost miles",
                       value: authorized
                           ? "\(selectedCount) app\(selectedCount == 1 ? "" : "s")"
                           : "\(model.blocked.count) app\(model.blocked.count == 1 ? "" : "s")",
                       action: {
                           // Authorized, so a real selection is obtainable: take it. Otherwise
                           // fall back to the six-name list, which is a stand-in and is labelled
                           // as one by the banner directly above it.
                           if authorized { openPicker() } else { open(.apps) }
                       })
                SetRow(label: "Cost per minute", value: "\(model.spend) mi",
                       action: { open(.spend) })
                SetRow(label: "Daily spend limit",
                       value: model.spendLimit > 0 ? "\(model.spendLimit) mi" : "Off",
                       action: { open(.limit) })
                SetRow(label: "Projection horizon", value: "\(model.horizon) years",
                       last: true, action: { open(.horizon) })
            }
        }
    }

    /// Deleting the account deletes the data — all of it, on both sides. App Store Review
    /// 5.1.1(v) asks for the account and its data; the member asked for the phone as well, because
    /// an account that is gone while its miles and passes sit here is a login removed, not a
    /// deletion. So: unlink a shared bank first (so the partner keeps their half — a failure there
    /// stops everything, rather than letting the server cascade take the pot), delete the user
    /// and every row, then wipe this install back to a first launch.
    private func deleteAccount() {
        // A cloud account whose server session has lapsed (a refused refresh drops it, the local
        // sign-in stays) would sail through `Backend.deleteAccount` as "nothing to delete" and
        // then wipe the phone — a deletion announced with the rows still there. Ask for a fresh
        // sign-in first; an email-only account has nothing on the server and needs none.
        if let account = identity.account, account.provider != .email,
           Backend.isConfigured, !backend.isLinked {
            deleteError = "Sign in again first, so the account server can confirm the deletion."
            return
        }
        deleting = true
        Task { @MainActor in
            if model.link != nil {
                await model.unlinkAccount()
                if model.link != nil {
                    deleteError = "The shared bank could not be unlinked. Check the connection and try again."
                    deleting = false
                    return
                }
            }
            deleteError = await identity.deleteAccount(backend)
            deleting = false
            guard deleteError == nil else { return }
            model.wipeInstall(identity)
        }
    }

    /// App Store Review 5.1.1 and 3.1.2 want both reachable from inside the app, and a member
    /// deciding whether to sign in or subscribe wants them *before* the paywall, not only on it.
    /// The documents ship in the bundle, so they read offline and cannot 404; the hosted copies
    /// `Billing.termsURL` / `privacyURL` point at are the same text.
    private var legalGroup: some View {
        SetGroup(title: "Legal", shadow: .raised) {
            SetRow(label: "Terms of Use", action: { legal = .terms })
            SetRow(label: "Privacy Policy", last: true, action: { legal = .privacy })
        }
        .padding(.top, 26)
    }

    private var accountGroup: some View {
        SetGroup(title: "Account", shadow: .raised) {
            // Signing in and out lives here because this is where a member looks for it, and
            // because onboarding's copy is a one-time thing they cannot get back to.
            SetRow(label: "Signed in",
                   value: identity.account.map { a in
                       var v = "\(a.displayName) \u{00b7} \(a.provider.label)"
                       // The native sign-in can succeed while the server link quietly fails
                       // (`linkBackup` swallows the error), and this row read the same either
                       // way — so it names the half that did not happen.
                       if a.provider != .email, Backend.isConfigured, !backend.isLinked { v += " \u{00b7} not backed up" }
                       return v
                   } ?? "Not signed in",
                   action: { signInSheet = true })
            SetRow(label: "Notifications") {
                GlassSwitch(isOn: Binding(
                    get: { model.notifications },
                    set: { model.notifications = $0; model.save() }
                ))
            }
            SetRow(label: "Live Activity", last: identity.account == nil) {
                GlassSwitch(isOn: Binding(
                    get: { model.liveActivity },
                    set: { model.liveActivity = $0; model.save() }
                ))
            }
            // App Store Review 5.1.1(v): signing in creates an account, so deleting it has to be
            // possible from inside the app, and it has to remove the data — offering sign-out
            // instead is called out as not sufficient. Only shown when there is one to delete.
            if identity.account != nil {
                SetRow(label: deleting ? "Deleting\u{2026}" : "Delete account", last: true,
                       action: { if !deleting { confirmingDelete = true } })
            }
        }
    }

    // MARK: - The one shared sheet

    private func open(_ kind: SheetKind) {
        // No `withAnimation` here — `ChoiceSheet` now drives its own rise on mount (real `@State`,
        // not a `.transition`; see `Droplet`'s doc comment in Controls.swift for why). Mounting it
        // is the whole of "open."
        sheet = kind
    }

    @ViewBuilder
    private func sheetView(_ kind: SheetKind) -> some View {
        let c = content(for: kind)
        ChoiceSheet(title: c.title, note: c.note, options: c.options, selection: c.selection,
                    onClose: {
            // Called only once `ChoiceSheet`'s own sink has finished playing — see `shut()` there.
            // Unmounting here is instant and correctly so: the animation already happened.
            sheet = nil
            sheetDismiss = false
        }, dismiss: sheetDismiss)
    }

    private struct SheetContent {
        let title: String
        let note: String?
        let options: [ChoiceOption<String>]
        let selection: ChoiceSheet<String>.Selection
    }

    /// Every sheet's option list and where it reads and writes. Values round-trip through
    /// `String` so one generic `ChoiceSheet<String>` covers minutes, rates and names alike —
    /// each case controls both directions of that conversion, so it can never drift.
    private func content(for kind: SheetKind) -> SheetContent {
        switch kind {
        case .length:
            let lengths = model.plus ? [25, 50, 75, 90, 120, 180] : [25, 50, 75, 90]
            return SheetContent(
                title: "Default length",
                note: model.plus ? nil : "Flights over 90 minutes fly in Business Class.",
                options: lengths.map { v in
                    ChoiceOption(value: "\(v)", label: "\(v) minutes",
                                 detail: Geography.destination(forMinutes: v).city)
                },
                selection: .single(Binding(
                    get: { "\(model.defaultMinutes)" },
                    set: { model.setDefaultMinutes(Int($0) ?? model.defaultMinutes) }
                ))
            )

        case .rate:
            let rows: [(Double, String, String)] = [
                (0.25, "4 minutes a mile", "A 50 minute flight pays 13 mi"),
                (0.2, "5 minutes a mile", "A 50 minute flight pays 10 mi"),
                (0.125, "8 minutes a mile", "A 50 minute flight pays 6 mi")
            ]
            return SheetContent(
                title: "Earn rate",
                note: "One mile buys one minute of screen time, so this is the exchange rate.",
                options: rows.map { ChoiceOption(value: "\($0.0)", label: $0.1, detail: $0.2) },
                selection: .single(Binding(
                    get: { "\(model.rate)" },
                    set: { model.rate = Double($0) ?? model.rate; model.save() }
                ))
            )

        case .policy:
            let rows: [(DivertPolicy, String, String)] = [
                (.none, "All or nothing", "A diverted flight earns nothing, however far you got"),
                (.partial, "Partial credit", "You keep the miles for the minutes you flew")
            ]
            return SheetContent(
                title: "Leaving early",
                note: nil,
                options: rows.map { ChoiceOption(value: $0.0.rawValue, label: $0.1, detail: $0.2) },
                selection: .single(Binding(
                    get: { model.policy.rawValue },
                    set: { model.policy = DivertPolicy(rawValue: $0) ?? model.policy; model.save() }
                ))
            )

        case .apps:
            return SheetContent(
                title: "Apps that cost miles",
                note: nil,
                options: BlockableApp.all.map { ChoiceOption(value: $0.id, label: $0.label) },
                selection: .multi(Binding(
                    get: { Set(model.blocked) },
                    set: { model.blocked = Array($0); model.save() }
                ))
            )

        case .spend:
            let rows: [(Double, String, String)] = [
                (1.0, "1 mi a minute", "15 minutes costs 15 mi"),
                (1.5, "1.5 mi a minute", "15 minutes costs 23 mi"),
                (2.0, "2 mi a minute", "15 minutes costs 30 mi")
            ]
            return SheetContent(
                title: "Cost per minute",
                note: "Miles spent to unlock a minute of screen time.",
                options: rows.map { ChoiceOption(value: "\($0.0)", label: $0.1, detail: $0.2) },
                selection: .single(Binding(
                    get: { "\(model.spend)" },
                    set: { model.spend = Double($0) ?? model.spend; model.save() }
                ))
            )

        case .limit:
            // Offered in miles rather than minutes because the ledger moves miles: a limit in
            // minutes would mean something different at each of the three spend rates, and change
            // underneath the member the moment they touched the row above.
            // Onboarding sets this on a dial in fives, so the value arriving here is often not one
            // of the presets. Carrying it in keeps the sheet showing what is actually set.
            var caps = [0, 30, 60, 120, 240]
            if !caps.contains(model.spendLimit) { caps.append(model.spendLimit); caps.sort() }
            return SheetContent(
                title: "Daily spend limit",
                note: "The most you can spend on screen time in a day. Earning is not capped, and neither is the Concourse.",
                options: caps.map { c in
                    ChoiceOption(value: "\(c)",
                                 label: c == 0 ? "Off" : "\(c) mi a day",
                                 detail: c == 0 ? "No limit"
                                     : "About \(Int((Double(c) / model.spend).rounded())) minutes at today's rate")
                },
                selection: .single(Binding(
                    get: { "\(model.spendLimit)" },
                    set: { model.spendLimit = Int($0) ?? model.spendLimit; model.save() }
                ))
            )

        case .goal:
            // Hours, because a goal is about the flying. Miles are what the flying pays, and a
            // goal quoted in them would move the moment the earn rate or a tier multiplier did.
            var goals = [0, 3, 5, 8, 12, 20]
            if !goals.contains(model.weeklyGoal) { goals.append(model.weeklyGoal); goals.sort() }
            return SheetContent(
                title: "Weekly study goal",
                note: "Hours in the air each week. Completed flights only \u{2014} a diversion pays nothing here either. Nothing happens if you miss it.",
                options: goals.map { h in
                    ChoiceOption(value: "\(h)",
                                 label: h == 0 ? "Off" : "\(h) h a week",
                                 detail: h == 0 ? "No goal"
                                     : "About \(Int((Double(h) * 60 / 7).rounded())) minutes a day")
                },
                selection: .single(Binding(
                    get: { "\(model.weeklyGoal)" },
                    set: { model.weeklyGoal = Int($0) ?? model.weeklyGoal; model.save() }
                ))
            )

        case .horizon:
            let years = [20, 40, 60]
            return SheetContent(
                title: "Projection horizon",
                note: "How far ahead the flight log projects your screen time.",
                options: years.map { ChoiceOption(value: "\($0)", label: "Next \($0) years") },
                selection: .single(Binding(
                    get: { "\(model.horizon)" },
                    set: { model.horizon = Int($0) ?? model.horizon; model.save() }
                ))
            )
        }
    }
}

// MARK: - Legal

/// The two documents in `Resources/Legal`. Bundled markdown, not a web view: it reads offline,
/// cannot 404, and cannot load anything else.
enum LegalDoc: String, Identifiable {
    case terms = "Terms", privacy = "Privacy"
    var id: String { rawValue }
    var title: String { self == .terms ? "Terms of Use" : "Privacy Policy" }

    var text: String {
        guard let url = Bundle.main.url(forResource: rawValue, withExtension: "md",
                                        subdirectory: "Legal")
                ?? Bundle.main.url(forResource: rawValue, withExtension: "md"),
              let s = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return s
    }
}

/// Renders a bundled markdown document line by line: `#` headings as headings, everything else
/// through `AttributedString(markdown:)` so links and emphasis survive. Deliberately not a
/// markdown engine — the two documents use headings, paragraphs, bullets and links, and that is
/// the whole vocabulary this draws. The system sheet chrome, like `SignInSheet`.
struct LegalSheet: View {
    let doc: LegalDoc
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                        block
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(doc.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.large])
    }

    private var blocks: [AnyView] {
        doc.text.components(separatedBy: "\n").compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { return nil }
            if line.hasPrefix("# ") {
                return AnyView(Text(verbatim: String(line.dropFirst(2)))
                    .font(.system(size: 26, weight: .bold)).padding(.bottom, 4))
            }
            if line.hasPrefix("## ") {
                return AnyView(Text(verbatim: String(line.dropFirst(3)))
                    .font(.system(size: 18, weight: .semibold)).padding(.top, 10))
            }
            let bullet = line.hasPrefix("- ")
            let body = bullet ? String(line.dropFirst(2)) : line
            let attributed = (try? AttributedString(markdown: body)) ?? AttributedString(body)
            let text = Text(attributed).font(.system(size: 16)).lineSpacing(3)
            return AnyView(bullet
                ? AnyView(HStack(alignment: .top, spacing: 8) { Text("\u{2022}"); text })
                : AnyView(text))
        }
    }
}
