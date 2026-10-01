import Foundation
import Observation
import RevenueCat

/// Business Class, actually sold.
///
/// The reference's paywall is `onStart = () => setPlus(true)` — a button that grants the plan for
/// nothing, because a web demo has no store. This is the same screen wired to RevenueCat, which
/// wraps StoreKit 2 and owns the receipt: the entitlement is what RevenueCat says it is, on every
/// launch and after every purchase, so the plan survives a reinstall and a new phone without this
/// app keeping a ledger it would have to defend.
///
/// **`plus` has exactly two writers now** — this class, from the entitlement, and developer mode.
/// Nothing else may set it, or the paid state and the receipt drift apart. `AppModel.setPlus`
/// enforces that: it takes a `source`, and a RevenueCat downgrade cannot take away a plan the
/// developer switch is holding on.
@MainActor
@Observable
final class Billing {

    // MARK: - The two links Apple requires

    /// Terms of Use and Privacy Policy. App Store Review 3.1.2 requires both to be reachable from
    /// any surface that sells an auto-renewing subscription, not only from the App Store listing —
    /// so the paywall and onboarding's last screen, which sells the same plan itself, both carry
    /// them.
    ///
    /// Tempus has its own Terms and Privacy Policy now — `Resources/Legal/Terms.md` and
    /// `Privacy.md`, readable in-app from Settings ▸ Legal — and these two URLs are where the same
    /// text is hosted: the public `DaLazyPig/tempus-legal` repo, served by GitHub Pages (both
    /// checked live on 18 Sep 2026). App Store Connect wants the privacy URL in the app record and a
    /// Terms link on every subscription surface, and a link that 404s is a rejection — so a change
    /// to either document goes to both the bundle and that repo.
    static let termsURL = URL(string: "https://dalazypig.github.io/tempus-legal/terms")!
    static let privacyURL = URL(string: "https://dalazypig.github.io/tempus-legal/privacy")!

    /// The entitlement identifier configured in RevenueCat, and the offering the paywall shows.
    /// Both are RevenueCat dashboard values — if the paywall says "unavailable" with a valid key,
    /// these two names are the first thing to check.
    static let entitlement = "business"

    private(set) var offering: Offering?
    private(set) var busy = false
    private(set) var restoring = false
    var error: String?

    /// Nil until the store answers. The paywall falls back to the reference's own "$39 / yr" copy
    /// while it is nil, so the screen is never blank and never wrong — it just is not yet local.
    private(set) var priceLabel: String?
    private(set) var trialLabel: String?

    private var stream: Task<Void, Never>?

    // MARK: - Configuration

    /// The public SDK key, from `RevenueCatAPIKey` in Info.plist. Public by design — it identifies
    /// the app to RevenueCat and authorises nothing on its own — but it is still read from the
    /// plist rather than compiled in, so it can differ per build without a code change.
    static var apiKey: String? {
        let key = Bundle.main.object(forInfoDictionaryKey: "RevenueCatAPIKey") as? String
        guard let key, !key.isEmpty, !key.hasPrefix("YOUR_") else { return nil }
        return key
    }

    static var isConfigured: Bool { apiKey != nil }

    /// A RevenueCat **Test Store** key. It sells products configured in the dashboard's test store
    /// rather than anything from StoreKit, so it needs no App Store Connect product to work — which
    /// is exactly what makes it easy to leave in by accident.
    ///
    /// **RevenueCat crashes a release build that configures with one**, on purpose, so that test
    /// entitlements can never leak into production. That is the right call and this guard does not
    /// second-guess it — it just declines to configure at all outside DEBUG, so the failure is the
    /// paywall saying "the store is not connected" rather than the app dying on launch. TestFlight
    /// is a release build and counts: a test key is usable in the Simulator and from Xcode, and
    /// nowhere else. Swap it for the `appl_` key before submitting.
    static var isTestStoreKey: Bool { apiKey?.hasPrefix("test_") == true }

    /// Whether this build may talk to the store at all.
    ///
    /// The condition is `#if DEBUG` and nothing else, because that is *verbatim* the SDK's own
    /// guard (`checkForSimulatedStoreAPIKeyInRelease`, `#if !DEBUG`). A TestFlight
    /// build is a release build, so configuring with a `test_` key there reaches the
    /// SDK's `fatalError` and the app dies on launch. It did, on build 3.
    static var storeUsable: Bool {
        guard isConfigured else { return false }
        #if DEBUG
        return true
        #else
        return !isTestStoreKey
        #endif
    }

    /// Configures the SDK, adopts whatever the receipt already says, and then keeps listening.
    /// Safe to call more than once; the second call is a no-op.
    func start(_ model: AppModel) {
        guard stream == nil else { return }
        guard let key = Self.apiKey, Self.storeUsable else {
            // Not an error state the member ever sees. Without a usable key there is simply no
            // store, and the paywall says so rather than offering a button that cannot work — or,
            // for a test key in a shipped build, rather than letting the SDK crash on launch.
            return
        }
        Purchases.logLevel = .warn
        Purchases.configure(withAPIKey: key)

        stream = Task {
            // The stream yields the cached CustomerInfo immediately and then every refresh, so this
            // is both "what is true at launch" and "what became true later" in one place.
            for await info in Purchases.shared.customerInfoStream {
                model.setPlus(info.entitlements[Self.entitlement]?.isActive == true, source: .store)
            }
        }
        Task { await loadOffering() }
    }

    func loadOffering() async {
        guard Purchases.isConfigured else { return }
        do {
            let offerings = try await Purchases.shared.offerings()
            offering = offerings.current
            await readPrice()
        } catch {
            // A missing offering is a dashboard problem, not something to shout at the member
            // about. The paywall keeps the reference's copy and the buy button stays disabled.
            offering = nil
        }
    }

    // MARK: - The two plans

    /// Which subscription the paywall is selling. Two, now — it sold only the annual one until
    /// 21 Sep 2026, which made the price a take-it-or-leave-it $39.99 and lost everyone who wanted
    /// to try a month first.
    enum Plan: String, CaseIterable {
        case annual, monthly
    }

    /// **Annual is the default, and that is the single highest-leverage thing on this screen.** A
    /// default is taken far more often than any badge changes a mind, and the annual plan is both
    /// the better deal for the member and the better retention for the app. The monthly plan is
    /// never hidden — it is the plan whose *annualised* cost does the anchoring work.
    var plan: Plan = .annual

    var annualPackage: Package? { offering?.annual }
    var monthlyPackage: Package? { offering?.monthly }

    /// The package the paywall sells: whichever plan is selected, then the other one, then the
    /// first thing on offer — so a differently-configured dashboard still sells something rather
    /// than nothing.
    var package: Package? {
        let chosen = plan == .annual ? annualPackage : monthlyPackage
        let other = plan == .annual ? monthlyPackage : annualPackage
        return chosen ?? other ?? offering?.availablePackages.first
    }

    /// Whether there is a genuine choice to put on screen. With only one package configured the
    /// picker would be a control with one option, which is not a choice — the sheet drops it and
    /// shows the single price the way it always did.
    var hasBothPlans: Bool { annualPackage != nil && monthlyPackage != nil }

    /// Whether the paywall draws the two-plan picker.
    ///
    /// Both plans, or **nothing purchasable at all**. The second case looks like it breaks the
    /// project's own rule against controls that do nothing, and it is the opposite: with no
    /// package there is nothing to buy, `canPurchase` is already false, the button is already
    /// disabled and already says why. Drawing the two plans there shows the offer the app is
    /// configured to make (`fallbackAnnual`/`fallbackMonthly`, the App Store Connect figures)
    /// rather than silently presenting one of them as though it were the only one.
    ///
    /// What it deliberately does **not** do is draw a picker over a *live* offering that sells
    /// only one package. That would be the real dead control: tapping Monthly would fall back to
    /// the annual package and charge a year for a month — the one failure on this screen that
    /// costs the member money. One live package, one price.
    var showsPlanChoice: Bool { hasBothPlans || package == nil }

    // MARK: What each plan costs

    /// The fallbacks, used until the store answers and in a build with no store at all. These are
    /// the figures the App Store Connect subscription group is configured with; if they ever
    /// disagree with the store, the store wins the moment `loadOffering` returns.
    static let fallbackAnnual: Decimal = 39.99
    static let fallbackMonthly: Decimal = 7.99

    private func product(_ p: Plan) -> StoreProduct? {
        (p == .annual ? annualPackage : monthlyPackage)?.storeProduct
    }

    private func amount(_ p: Plan) -> Decimal {
        product(p)?.price ?? (p == .annual ? Self.fallbackAnnual : Self.fallbackMonthly)
    }

    /// Formats in the store's own currency where there is one, and falls back to the device's
    /// locale otherwise — never a hardcoded "$", which is wrong in most of the world.
    private func money(_ value: Decimal, like p: Plan) -> String {
        if let f = product(p)?.priceFormatter, let s = f.string(from: value as NSDecimalNumber) {
            return s
        }
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = .current
        return f.string(from: value as NSDecimalNumber) ?? "\(value)"
    }

    /// The plan's own sticker price — "$39.99" or "$7.99".
    func price(_ p: Plan) -> String { money(amount(p), like: p) }

    /// **What a plan costs per month**, which is the number the annual card leads with. A yearly
    /// total is a big number that invites a flinch; the same commitment restated as "$3.33 a
    /// month" is the identical amount of money and reads as a third of the monthly plan, which is
    /// what it is. The annual total is still printed directly underneath — this frames the price,
    /// it does not hide it.
    func perMonth(_ p: Plan) -> String {
        let monthly = p == .annual ? amount(.annual) / 12 : amount(.monthly)
        return money(round2(monthly), like: p)
    }

    /// How much cheaper a year of the annual plan is than twelve months of the monthly one, as a
    /// whole percent. Precomputed and stated outright rather than left for the reader to work out:
    /// a price comparison the buyer has to do arithmetic for is one they may do wrong, or resent.
    /// Nil when the two plans cannot be compared, so the badge is simply absent rather than wrong.
    var annualSavingPercent: Int? {
        let year = amount(.annual)
        let twelve = amount(.monthly) * 12
        guard twelve > 0, year < twelve else { return nil }
        let saved = ((twelve - year) / twelve) * 100
        let pct = Int(NSDecimalNumber(decimal: saved).doubleValue.rounded())
        return pct > 0 ? pct : nil
    }

    private func round2(_ d: Decimal) -> Decimal {
        var input = d, out = Decimal()
        NSDecimalRound(&out, &input, 2, .plain)
        return out
    }

    /// An offer on the product is not an offer this Apple account may take. Clear the old promise
    /// before asking RevenueCat, and advertise a trial only when eligibility is known — unknown
    /// is not permission to sell the member a free week the receipt will charge them for.
    private func readPrice() async {
        guard let product = package?.storeProduct else { priceLabel = nil; trialLabel = nil; return }
        priceLabel = product.localizedPriceString
        trialLabel = nil
        if let intro = product.introductoryDiscount, intro.paymentMode == .freeTrial,
           await Purchases.shared.checkTrialOrIntroDiscountEligibility(product: product) == .eligible,
           product.productIdentifier == package?.storeProduct.productIdentifier {
            let n = intro.subscriptionPeriod.value
            let unit: String
            switch intro.subscriptionPeriod.unit {
            case .day: unit = n == 1 ? "day" : "days"
            case .week: unit = n == 1 ? "week" : "weeks"
            case .month: unit = n == 1 ? "month" : "months"
            case .year: unit = n == 1 ? "year" : "years"
            @unknown default: unit = "days"
            }
            trialLabel = "\(n) \(unit) free"
        }
    }

    /// A package that is not monthly is not necessarily annual. The product's unit and count
    /// name what the store will bill; the old copy is only a fallback when it supplies no period.
    private var periodCopy: (short: String, long: String) {
        guard let period = package?.storeProduct.subscriptionPeriod else {
            return package?.packageType == .monthly ? ("/mo", "a month") : ("/yr", "a year")
        }
        let unit: String
        let short: String
        switch period.unit {
        case .day: unit = "day"; short = "/day"
        case .week: unit = "week"; short = "/wk"
        case .month: unit = "month"; short = "/mo"
        case .year: unit = "year"; short = "/yr"
        @unknown default: return ("", "per billing period")
        }
        if period.value == 1 { return (short, "a \(unit)") }
        let every = "every \(period.value) \(unit)s"
        return (every, every)
    }

    /// Switches the plan and re-reads the price and the trial. Trial eligibility is **per
    /// product**, not per account, so the free week on offer for the annual plan is not
    /// necessarily on offer for the monthly one — reading it again is the difference between
    /// advertising a trial and advertising one the receipt will not honour.
    func select(_ p: Plan) {
        guard p != plan else { return }
        plan = p
        Task { await readPrice() }
    }

    /// What the price row reads. Derived from the selected plan rather than from the cached
    /// `priceLabel`, which is a snapshot of whatever was selected when the store last answered —
    /// reading it here printed the annual price on the monthly card for one frame after every tap.
    var displayPrice: String { price(plan) }
    var displayPeriod: String { periodCopy.short }

    var buyLabel: String {
        if let trial = trialLabel { return "Start \(trial)" }
        return package == nil ? "Start 7 days free" : "Upgrade for \(displayPrice)"
    }

    var subCopy: String {
        let period = package == nil
            ? (plan == .annual ? "a year" : "a month")
            : periodCopy.long
        if let trial = trialLabel { return "\(trial), then \(displayPrice) \(period). Cancel any time." }
        return "\(displayPrice) \(period). Cancel any time."
    }

    /// True when there is genuinely something to buy. The paywall's button is disabled otherwise,
    /// because a store that cannot sell must not look like one that can.
    var canPurchase: Bool { package != nil && !busy && !restoring }

    /// Why there is nothing to buy, or `nil` when there is. Both surfaces that sell Business Class
    /// — the paywall and onboarding's last screen — say this one sentence, so neither can offer
    /// what the other has already declined to.
    var unavailable: String? {
        if !Self.storeUsable { return "The store is not connected in this build." }
        if package == nil { return "Business Class is not on sale right now." }
        return nil
    }

    // MARK: - Buying

    @discardableResult
    func purchase(_ model: AppModel) async -> Bool {
        guard let package, !busy else { return false }
        busy = true
        error = nil
        defer { busy = false }
        do {
            let result = try await Purchases.shared.purchase(package: package)
            // A cancel is a decision, not a failure: no message, no state change.
            guard !result.userCancelled else { return false }
            let active = result.customerInfo.entitlements[Self.entitlement]?.isActive == true
            model.setPlus(active, source: .store)
            if !active {
                error = "That went through, but the plan is not active yet. Try Restore in a moment."
            }
            return active
        } catch {
            self.error = Self.message(error)
            return false
        }
    }

    /// Apple's own offer-code sheet — the one sanctioned way to hand out Business Class by code
    /// (Review 3.1.1 forbids an app's own license keys). Codes are minted in App Store Connect
    /// ▸ Subscriptions ▸ Offer Codes; a redeemed one arrives through `customerInfoStream`.
    func redeemCode() {
        guard Purchases.isConfigured else { return }
        Purchases.shared.presentCodeRedemptionSheet()
    }

    @discardableResult
    func restore(_ model: AppModel) async -> Bool {
        guard Purchases.isConfigured, !restoring else { return false }
        restoring = true
        error = nil
        defer { restoring = false }
        do {
            let info = try await Purchases.shared.restorePurchases()
            let active = info.entitlements[Self.entitlement]?.isActive == true
            model.setPlus(active, source: .store)
            if !active { error = "No Business Class purchase found on this Apple ID." }
            return active
        } catch {
            self.error = Self.message(error)
            return false
        }
    }

    /// RevenueCat's own message where it has one — it writes better store errors than this app
    /// could — and a plain sentence where it does not.
    private static func message(_ error: Error) -> String? {
        if let rc = error as? RevenueCat.ErrorCode {
            if rc == .purchaseCancelledError { return nil }
            return rc.localizedDescription
        }
        return error.localizedDescription
    }
}
