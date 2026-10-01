import FamilyControls
import SwiftUI

/// Spending is a tab, not a wall. The dial always spans **5–300 minutes** whatever the spend rate
/// is (`min = spend*5, max = spend*300, step = spend`), so cost and time always divide cleanly —
/// `mins = ceil(cost / spend)` is a safety ceiling on an already-exact multiple, not real rounding.
///
/// An unlock in progress is a banner, not a wall: the dial stays live underneath it so time can be
/// **added** (same app, `extend: true`, stacks onto the running deadline) or **moved** to another
/// app, which is not an extend — it asks first, because the miles already spent on the old unlock
/// are gone the moment the new one is confirmed.
struct RedeemScreen: View {
    @Environment(AppModel.self) private var model

    /// Which app is selected. Starts empty; `onAppear` resolves it to a shield's requested app if
    /// one is waiting, else the first blocked app — mirroring the reference's `useState(apps[0].id)`
    /// while still honouring `requestedUnlockApp`.
    @State private var app: String?
    /// The dial's price, in miles. `nil` until first read, at which point it lazily takes
    /// `spend*10` — the reference's `useState(() => SPEND*10)`. Spend cannot change while this
    /// screen is mounted (Settings and Redeem are different phases), so there is no dependent
    /// effect to port — see spec §1.7.
    @State private var costOverride: Double?
    /// The app a confirmation is pending for, because a different app is already unlocked with
    /// time still on it.
    @State private var swap: BlockableApp?
    /// Ticks every 250 ms so the banner's remaining time reads live, the same cadence the
    /// reference's `useRemaining` polls at.
    @State private var now = Date()

    private var cost: Double { costOverride ?? model.spend * 10 }
    private var costBinding: Binding<Double> {
        Binding(get: { cost }, set: { costOverride = $0 })
    }

    /// The six spendable categories, falling back to Instagram/TikTok/YouTube only if the member
    /// has emptied their blocked-apps list entirely in Settings — effectively unreachable in normal
    /// use, kept because the reference keeps it.
    private var apps: [BlockableApp] {
        let ids = model.blocked.isEmpty ? ["ig", "tt", "yt"] : model.blocked
        return ids.map { BlockableApp.named($0) ?? BlockableApp.named("ig")! }
    }

    private var picked: BlockableApp { apps.first { $0.id == app } ?? apps[0] }

    /// The apps iOS is actually shielding, or `nil` while Screen Time is not connected or nothing
    /// is chosen — in which case the six-name strip stands in, exactly as it does in Settings.
    ///
    /// A shield is raised on opaque tokens: this app cannot read a name or an icon out of one, and
    /// `Label(token)` is the only thing that can draw them. It also cannot lift the shield off one
    /// of them — an unlock opens the whole selection — so where the strip is a chooser, this is a
    /// statement of what the miles are about to open.
    private var live: FamilyActivitySelection? {
        // A selection is a selection. This used to require `screenTimeAuthorized` as well, and
        // `AuthorizationCenter` answers from a status that is not always settled the instant a
        // cold launch reaches this screen — which put the stand-in strip, and three app names the
        // member never picked, in front of someone whose real choice was sitting right there in
        // `model.selection`.
        model.hasAppsToShield ? model.selection : nil
    }

    /// Screen Time is connected and nothing is selected: there is no shield, so there is nothing
    /// an unlock could open.
    ///
    /// **The six-name strip is for one state only** — Screen Time *not* connected, under the same
    /// banner Settings shows. Reaching for it here as well meant a member who had connected Screen
    /// Time and chosen nothing was shown Instagram, TikTok and Reddit and offered a price for
    /// them; in the simulator, where `AuthorizationCenter` reports `.approved` whatever the truth
    /// is, that was every single run.
    private var nothingChosen: Bool { live == nil && model.screenTimeAuthorized }

    private var liveCount: Int {
        guard let live else { return 0 }
        return live.applicationTokens.count + live.categoryTokens.count + live.webDomainTokens.count
    }

    /// What the statement, the banner and the running unlock call this purchase.
    ///
    /// **Not "Your selection".** That is the picker's word for the thing, not the member's: what
    /// they bought is time on the apps this unlock opens, and the screen should say so. The banner
    /// below carries the name on a line of its own with no verb after it, so a plural name reads
    /// as well as a singular one — which is what let this stop being a possessive noun phrase
    /// chosen to fit "… is open".
    private static let liveName = "The apps unlocked"
    /// The one id the one unlock carries, so adding time to it extends rather than restarts.
    private static let liveID = "selection"
    private var mins: Int { Int((cost / model.spend).rounded(.up)) }
    /// `unlockAllowance`, not `pool` — a daily spend limit is as real a refusal as an empty
    /// balance, and the button must not offer time `payOrder` would decline.
    private var ok: Bool { cost <= Double(model.unlockAllowance) && !nothingChosen }

    private var unlockedLeft: Double {
        guard let u = model.unlocked else { return 0 }
        return max(0, u.until - now.timeIntervalSince1970)
    }
    private var liveMins: Int { model.unlocked != nil ? Int((unlockedLeft / 60).rounded(.up)) : 0 }

    var body: some View {
        VStack(spacing: 0) {
            header
            banner
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    priceReadout
                    appList
                }
                .padding(.bottom, 12)
                // `justify-content: center` while nothing is unlocked, `flex-start` once the
                // banner is up — the reference's own rule, and the reason the block sits in the
                // middle of the space rather than at the top of it.
                .frame(maxHeight: .infinity, alignment: model.unlocked != nil ? .top : .center)
            }
            // **No fade at the bottom.** One was added here on the theory that a list running past
            // the fold wants to say so, but the grouped card this screen actually draws is not a
            // list that trails off — the fade cut the last row in half across its middle, which is
            // exactly the sheared card it was meant to prevent. The block is centred and short
            // enough to fit; if it ever is not, it scrolls, which says "there is more" on its own.
            primaryButton
            dial
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tpScreenWidth()
        .overlay { if swap != nil { swapOverlay } }
        .task {
            // Spending against a stale pot is worse than displaying one: `unlockAllowance` would
            // refuse time the member actually has, and telling someone they lack miles they own
            // is the worst failure this feature has. So the pot is confirmed before this screen's
            // affordability checks read it, not merely before it is drawn. One GET, no-op with no
            // backend, and it shares the flush/collect work with Home's own arrival refresh.
            await model.refreshSharedBank()

            // Consumed once: a shield only *names* the app, it never changes the price, and the
            // request must not leak into a later, unrelated visit to Redeem.
            if let req = model.requestedUnlockApp {
                // A shield names an app by its iOS display name ("Instagram"); a deep link may
                // name it by id ("ig"). Both are accepted, and anything that matches neither
                // simply leaves the default selected — the request never changed the price.
                if let match = apps.first(where: {
                    $0.id.caseInsensitiveCompare(req) == .orderedSame
                        || $0.label.caseInsensitiveCompare(req) == .orderedSame
                }) { app = match.id }
                model.requestedUnlockApp = nil
            }
            while !Task.isCancelled {
                now = Date()
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        Rise(i: 0) {
            HStack(alignment: .center, spacing: 12) {
                IconButton(tone: .sunken, size: .md, label: "Close",
                           action: { model.go(.status, .permout) }) {
                    Image(systemName: "xmark").font(.system(size: 20, weight: .regular))
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 0) {
                    Text("BANKED").tpLabelStyle().foregroundStyle(TColor.textMuted)
                    HStack(spacing: 3) {
                        MilesTicker(value: model.pool)
                        Text("mi")
                    }
                    .font(TFont.core(.semibold, 17))
                    .monospacedDigit()
                    .foregroundStyle(TColor.textPrimary)
                    .padding(.top, 7)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 52)
    }

    // MARK: - In-progress banner

    private var banner: some View {
        Group {
            if let u = model.unlocked {
                HStack(spacing: 14) {
                    ZStack {
                        Circle().fill(TColor.statusOnTime)
                        Text("\(liveMins)")
                            .font(TFont.core(.bold, 17))
                            .monospacedDigit()
                            .foregroundStyle(TColor.white)
                    }
                    .frame(width: 44, height: 44)

                    VStack(alignment: .leading, spacing: 5) {
                        // The name alone, not "… is open": the disc beside it is already counting
                        // the minutes down and the line under it already says when it ends, so the
                        // verb was the only word on this banner doing no work — and it was the one
                        // word forcing the name to be singular.
                        Text(u.name)
                            .font(TFont.core(.semibold, 16))
                            .foregroundStyle(TColor.textPrimary)
                        Text("Locks again at \(hhmm(u.until))")
                            .font(TFont.core(.regular, 13))
                            .foregroundStyle(TColor.textSecondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(TColor.statusOnTimeSoft, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 22)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity
                ))
            }
        }
        .frame(maxHeight: model.unlocked != nil ? 126 : 0, alignment: .top)
        .clipped()
        .animation(.glide(0.52), value: model.unlocked != nil)
        .opacity(model.unlocked != nil ? 1 : 0)
        .animation(.glide(0.36), value: model.unlocked != nil)
    }

    // MARK: - Price readout

    private var priceReadout: some View {
        Rise(i: 2) {
            VStack(spacing: 14) {
                HStack(alignment: .lastTextBaseline, spacing: 9) {
                    tpText("\(mins)", size: model.unlocked != nil ? TFont.sizeDialValueUnlocked : TFont.sizeDialValue, track: -0.07)
                        .font(TFont.core(.bold, model.unlocked != nil ? TFont.sizeDialValueUnlocked : TFont.sizeDialValue))
                        .monospacedDigit()
                        .foregroundStyle(ok ? TColor.textPrimary : TColor.steel400)
                        .animation(.glide(0.24), value: ok)
                        .animation(.glide(0.48), value: model.unlocked != nil)
                    Text("min")
                        .font(TFont.core(.semibold, 24))
                        .foregroundStyle(TColor.textMuted)
                }
                Group {
                    if ok {
                        Text("\(fmtMi(cost)) mi \u{00b7} \(phrase)")
                            .foregroundStyle(TColor.textAccent)
                    } else if nothingChosen {
                        // Not a refusal about miles — states the position and stops.
                        Text("Nothing is blocked yet")
                            .foregroundStyle(TColor.textMuted)
                    } else if model.limitIsTheObstacle(for: Int(cost.rounded())) {
                        // Not a shortfall: the miles are there and today's limit is not. States
                        // the position and stops, like every other refusal on this screen.
                        Text("Today's spend limit is reached")
                            .foregroundStyle(TColor.statusDiverted)
                    } else {
                        Text("You need \(fmtMi(cost - Double(model.unlockAllowance))) mi more")
                            .foregroundStyle(TColor.statusDiverted)
                    }
                }
                .font(TFont.core(.medium, 15))
                .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, model.unlocked != nil ? 10 : 24)
        .animation(.glide(0.52), value: model.unlocked != nil)
        .frame(maxWidth: .infinity)
    }

    /// What this many miles opens: the whole selection when the shield is real, the picked name
    /// when it is the stand-in.
    /// What this many miles buys, as one phrase.
    ///
    /// A real shield covers the whole selection and cannot be lifted off one app of it, so with
    /// Screen Time connected this **counts** rather than names — the names are in the card
    /// directly below, drawn by iOS itself from tokens this app cannot read. Extending says so
    /// instead of repeating the count, because adding five minutes does not open anything new.
    private var phrase: String {
        let extending = model.unlocked?.id == (live != nil ? Self.liveID : picked.id)
        guard live != nil else {
            return extending ? "adds to \(picked.label)" : "unlocks \(picked.label)"
        }
        return extending ? "adds to the unlock"
                         : "unlocks \(liveCount) app\(liveCount == 1 ? "" : "s")"
    }

    // MARK: - App list

    /// The shape of iOS's own activity picker, in this app's tokens: a small-caps instruction, a
    /// grouped card, and each row's selector on the **leading** edge beside a monogram tile. The
    /// picker's chevron and per-row count have no meaning here — nothing expands, and the price
    /// never depended on which app is picked — so their place carries the one fact this screen
    /// does have: which app is open right now.
    private var appList: some View {
        Rise(i: 3) {
            VStack(alignment: .leading, spacing: 0) {
                if let live {
                    SetGroup(title: "The apps unlocked") {
                        let apps = Array(live.applicationTokens)
                        let cats = Array(live.categoryTokens)
                        let webs = Array(live.webDomainTokens)
                        ForEach(apps, id: \.self) { t in
                            LiveRow(last: cats.isEmpty && webs.isEmpty && t == apps.last) { Label(t) }
                        }
                        ForEach(cats, id: \.self) { t in
                            LiveRow(last: webs.isEmpty && t == cats.last) { Label(t) }
                        }
                        ForEach(webs, id: \.self) { t in
                            LiveRow(last: t == webs.last) { Label(t) }
                        }
                    }
                    footer(liveCount)
                } else if nothingChosen {
                    StatusBanner(tone: .info, title: "No apps are chosen") {
                        Text("Nothing is blocked, so there is nothing to unlock. Choose what costs miles in Settings.")
                    }
                    .padding(.top, 26)
                } else {
                    SetGroup(title: "Unlock") {
                        ForEach(Array(apps.enumerated()), id: \.element.id) { index, a in
                            UnlockRow(app: a,
                                      on: a.id == picked.id,
                                      open: model.unlocked?.id == a.id,
                                      last: index == apps.count - 1) { app = a.id }
                        }
                    }
                    // **The strip says what it is.** Screen Time is not connected, so these six
                    // names are standing in for a selection that cannot be made yet — and without
                    // a word saying so the screen quietly presents three apps the member never
                    // chose as the things their miles are about to open. Settings makes the same
                    // promise in a full banner; here it takes the footer's own line, because the
                    // one thing this screen has no room for is another block (the grouped card
                    // already sits a hair above the fold). Same offer as the banner's: it asks.
                    standInNote
                }
            }
        }
        .padding(.horizontal, 24)
        // `SetGroup` already pays 26 pt above its own title.
        .padding(.top, model.unlocked != nil ? 0 : 6)
        .animation(.glide(0.48), value: model.unlocked != nil)
    }

    private var standInNote: some View {
        Button {
            Task {
                await model.requestScreenTimeAuthorization()
                model.reconcileBlocking()
            }
        } label: {
            Text("CONNECT SCREEN TIME TO CHOOSE YOUR OWN")
                .tpLabelStyle()
                .foregroundStyle(TColor.textAccent)
                .frame(maxWidth: .infinity)
                .padding(.top, 16)
        }
        .buttonStyle(.plain)
    }

    private func footer(_ n: Int) -> some View {
        Text("\(n) app\(n == 1 ? "" : "s") cost miles")
            .tpLabelStyle()
            .foregroundStyle(TColor.textMuted)
            .frame(maxWidth: .infinity)
            .padding(.top, 16)
    }

    // MARK: - Primary button and dial

    private var primaryButton: some View {
        Rise(i: 4) {
            TButton(ok ? "Pay \(fmtMi(cost)) mi"
                       : nothingChosen ? "Nothing to unlock"
                       : model.limitIsTheObstacle(for: Int(cost.rounded())) ? "Limit reached" : "Not enough miles",
                    variant: .primary, size: .lg, fullWidth: true, disabled: !ok) {
                buy()
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
    }

    private var dial: some View {
        Rise(i: 5) {
            // `arcStep: 1.25, tone: .light` — the reference's own `<Dial ... arcStep={1.25}
            // tone="light"/>` for this exact screen.
            DialView(value: costBinding, min: model.spend * 5, max: model.spend * 300,
                     step: model.spend, arcStep: 1.25, tone: .light)
        }
        .padding(.top, 8)
        // The reference clears 96 here for its docked nav. This screen does not dock one —
        // `RootView.navVisible` is Fly and Club only — so 96pt of it was empty, and the space it
        // was holding is exactly what the app list above needed: the grouped card this port draws
        // instead of the reference's hairline list is taller than the list it replaces, and was
        // being sheared through its third row by the bottom of the scroll area.
        .padding(.bottom, 24)
    }

    // MARK: - Swap confirmation

    private var swapOverlay: some View {
        ZStack {
            TColor.overlayScrim.ignoresSafeArea()
                .transition(.opacity)
            if let u = model.unlocked, let swap {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(u.name) still has \(liveMins) min")
                        .font(TFont.core(.bold, 22))
                        .tracking(-0.03 * 22)
                        .foregroundStyle(TColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Swapping to \(swap.label) ends it. The miles already spent are gone.")
                        .font(TFont.core(.regular, 15))
                        .foregroundStyle(TColor.textSecondary)
                        .padding(.top, 12)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(spacing: 8) {
                        TButton("Swap to \(swap.label)", variant: .primary, size: .md, fullWidth: true) {
                            commit(target: swap, extend: false)
                            self.swap = nil
                        }
                        TButton("Keep \(u.name)", variant: .ghost, size: .md, fullWidth: true) {
                            self.swap = nil
                        }
                    }
                    .padding(.top, 20)
                }
                .padding(24)
                .background(TColor.surfaceCard, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .tpShadow(.overlay)
                .padding(.horizontal, 24)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .zIndex(30)
        .animation(.glide(0.2), value: swap)
    }

    // MARK: - Buying

    private func buy() {
        if live != nil {
            // One shield over the whole selection: nothing to swap to, so more time is always
            // more time on the same unlock.
            model.payFlow = Order(kind: .unlock, cost: Int(cost.rounded(.up)), name: Self.liveName,
                                  itemID: Self.liveID, mins: mins,
                                  extend: model.unlocked?.id == Self.liveID)
            return
        }
        if let u = model.unlocked, u.id != picked.id, liveMins > 0 {
            swap = picked
            return
        }
        commit(target: picked, extend: model.unlocked?.id == picked.id)
    }

    /// `Order.cost` is a whole number of miles — the app's ledger is integral even though a
    /// fractional spend rate (Settings offers 1.5 mi/min) makes `cost` itself a fraction. Rounding
    /// up means a display of "7.5 mi" never actually charges less than what was shown.
    private func commit(target: BlockableApp, extend: Bool) {
        model.payFlow = Order(kind: .unlock, cost: Int(cost.rounded(.up)), name: target.label,
                               itemID: target.id, mins: mins, extend: extend)
    }

    // MARK: - Formatting

    /// Mirrors JS's default number→string coercion: no trailing zero, but a real fraction (a
    /// 1.5 mi/min spend rate) still shows its `.5`.
    private func fmtMi(_ v: Double) -> String {
        v.rounded() == v ? String(Int(v)) : String(format: "%g", v)
    }

    private func hhmm(_ epoch: TimeInterval) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.locale = Locale(identifier: "en_GB")
        return f.string(from: Date(timeIntervalSince1970: epoch))
    }
}
