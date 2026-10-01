import SwiftUI

/// Developer mode: the switches that let this app be walked without paying for it.
///
/// **Not in an App Store build.** Everything here hands out something the app otherwise charges
/// miles or money for — Business Class, a miles balance, a status tier — so `Dev.available` shuts
/// the whole feature off outside DEBUG. It is not merely hidden there; the entry
/// point does not render, `AppModel.devMode` is never consulted, and the pay sheet's biometric
/// bypass is unreachable. A build that reaches the store has no developer mode to find.
///
/// **It writes the ledger, never the outcome.** The status rows call `seedTier`/`addQualifyingHours`
/// — the same seams the launch arguments use — so a tier is always *earned* from qualifying hours
/// rather than assigned. That keeps every screen testing a state the app can actually reach, which
/// is the same rule `-tempusTier` follows.
enum Dev {
    /// DEBUG only. Sandbox builds (TestFlight) had it behind a passcode for a while, but App Review
    /// installs through that same sandbox, and a panel that hands out Business Class for free
    /// (Guideline 2.3.1) does not belong on any build that leaves this machine.
    static let available: Bool = {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }()

    /// Launch seams (`-tempusPhase` …) are DEBUG-only too: they seed balances and tiers.
    static let seams: Bool = {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }()

    /// How many taps on the Settings title open it. The usual seven.
    static let tapsToUnlock = 7
}

struct DevSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(Billing.self) private var billing
    @Environment(Identity.self) private var identity
    /// Needed by `serverGroup`. Injected in `RootView` and in `ScreenWarm.render` — an
    /// `@Environment` object a warmed screen asks for and does not get is a trap, not a blank.
    @Environment(Backend.self) private var backend
    let onClose: () -> Void

    @State private var screenTime: Bool?
    @State private var confirmingReset = false
    /// The thresholds live in `UserDefaults`, not in the model, so nothing invalidates this panel
    /// when one is written. Bumping a counter is the whole of what redraws the chips.
    @State private var bump = 0
    /// Raw shake events seen since this panel opened — see `shakeGroup`.
    @State private var shakes = 0
    @State private var lastShake: Date?
    /// What the last schema probe found — see `Backend.probe`. Nil until asked for.
    @State private var probe: [(String, String)]?
    @State private var probing = false

    var body: some View {
        ZStack {
            TColor.navy900.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(spacing: 0) {
                header
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        plan
                        economy
                        statusGroup
                        flight
                        guardGroup
                        shakeGroup
                        checks
                        account
                        serverGroup
                        danger
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 34)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: UIScreen.main.bounds.height * 0.86, alignment: .top)
            .background(TColor.white)
            .clipShape(
                UnevenRoundedRectangle(topLeadingRadius: 32, bottomLeadingRadius: 0,
                                        bottomTrailingRadius: 0, topTrailingRadius: 32)
            )
            .tpShadow(.overlay)
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .ignoresSafeArea()
        .task { screenTime = model.screenTimeAuthorized }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("DEVELOPER").tpLabelStyle().foregroundStyle(TColor.statusDiverted)
                Text("Off the record")
                    .font(TFont.core(.bold, 30))
                    .tracking(-0.04 * 30)
                    .foregroundStyle(TColor.textPrimary)
            }
            Spacer(minLength: 0)
            IconButton(tone: .sunken, size: .md, label: "Close", action: onClose) {
                Image(systemName: "xmark").font(.system(size: 18, weight: .regular))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 8)
    }

    // MARK: - Groups

    private var plan: some View {
        DevGroup("Plan") {
            DevToggle("Business Class", on: model.devHasPlus) {
                model.setPlus($0, source: .developer)
            }
            DevNote(planNote)
            if Billing.storeUsable {
                DevButton(billing.restoring ? "Restoring\u{2026}" : "Restore from the store") {
                    Task { await billing.restore(model) }
                }
                DevButton("Reload the offering") { Task { await billing.loadOffering() } }
            }
        }
    }

    private var planNote: String {
        var lines = ["Effective: \(model.plus ? "Business Class" : "Economy")"]
        if Billing.storeUsable {
            lines.append("RevenueCat: \(Billing.isTestStoreKey ? "TEST STORE key" : "App Store key") \u{00b7} offering \(billing.package == nil ? "none" : "loaded \(billing.displayPrice)")")
            if Billing.isTestStoreKey {
                lines.append("Swap for the appl_ key before submitting \u{2014} RevenueCat crashes a release build on a test key.")
            }
        } else if Billing.isTestStoreKey {
            lines.append("RevenueCat: test key ignored in this build type.")
        } else {
            lines.append("RevenueCat: no API key in Info.plist")
        }
        if let e = billing.error { lines.append("Last store error: \(e)") }
        return lines.joined(separator: "\n")
    }

    private var economy: some View {
        DevGroup("Miles") {
            DevNote("Balance \(model.miles) mi\(model.link == nil ? "" : " \u{00b7} pool \(model.pool) mi")")
            HStack(spacing: 8) {
                ForEach([50, 250, 1000], id: \.self) { n in
                    DevChip("+\(n)") { model.seamInstall(miles: model.miles + n) }
                }
                DevChip("0") { model.seamInstall(miles: 0) }
            }
        }
    }

    private var statusGroup: some View {
        DevGroup("Status") {
            DevNote("\(model.status.tier.name) \u{00b7} \(String(format: "%.1f", model.status.hours))h this period \u{00b7} \u{00d7}\(String(format: "%.2f", model.status.mult))")
            // Writes the hours ledger, never the tier, so the tier stays earned.
            HStack(spacing: 8) {
                ForEach(Array(Status.tiers.enumerated()), id: \.offset) { i, tier in
                    DevChip(String(tier.name.prefix(4)), on: model.status.idx == i) { model.seedTier(i) }
                }
            }
            HStack(spacing: 8) {
                DevChip("+1h") { model.addQualifyingHours(1) }
                DevChip("+10h") { model.addQualifyingHours(10) }
                DevChip("At risk") { model.seedAtRisk() }
            }
        }
    }

    private var flight: some View {
        DevGroup("Flight clock") {
            DevNote("A flight in the air runs at this multiple of real time. Never persisted \u{2014} a relaunch is back to 1\u{00d7}.")
            HStack(spacing: 8) {
                ForEach([1.0, 10.0, 60.0, 300.0], id: \.self) { x in
                    DevChip("\(Int(x))\u{00d7}", on: model.speed == x) { model.speed = x }
                }
            }
            DevToggle("Ignore the focus guard", on: model.devIgnoreFocusGuard) {
                model.devIgnoreFocusGuard = $0
            }
            DevNote("Leaving the app or picking the phone up mid-flight stops costing a chance.")
        }
    }

    /// The focus guard, with the sensor live and the two thresholds writable.
    ///
    /// The guard is the one piece of this app that cannot be judged by reading it: whether a shake
    /// trips it depends on the phone, its case and the desk it is sitting on, and the defaults came
    /// from a model rather than from any of those. So the panel shows what the accelerometer is
    /// actually reporting and lets the numbers be moved against it — put the phone down, watch it
    /// arm, pick it up, and read the peak.
    /// Why the guard is doing nothing, or nil when it is actually watching.
    ///
    /// Three separate things switch it off and none of them is a fault, so "the shake does not
    /// work" has three correct answers and the panel has to say which one applies. Without this
    /// the only way to tell a business-class cabin from a mistuned threshold is to read the source.
    private var guardIdleReason: String? {
        if Dev.available && model.devMode && model.devIgnoreFocusGuard {
            return "\u{201c}Ignore the focus guard\u{201d} is on, just above."
        }
        if !model.focusGuard.running {
            return "No flight in the air. The guard only watches between takeoff and landing \u{2014} use \u{201c}Read the sensor\u{201d} below to test it without one."
        }
        return nil
    }

    private var guardGroup: some View {
        let g = model.focusGuard
        return DevGroup("Focus guard") {
            if let why = guardIdleReason {
                DevNote("Not watching: \(why)")
            } else {
                DevNote(g.locksCabin
                        ? "Watching. Business class is zero tolerance: any pickup or leaving the app ends the flight on the spot and forfeits it \u{2014} no chances, no settle window."
                        : "Watching. \(g.chancesLeft) of \(g.chances) chances left.")
            }
            if !g.sensorAvailable {
                DevNote("No accelerometer on this device \u{2014} the simulator feeds a phone that is always still, so nothing here can be tuned. Run it on a phone.")
            }
            DevToggle("Read the sensor", on: g.tuning) { on in
                if on { g.startTuning() } else { g.stopTuning() }
            }
            if g.tuning {
                DevNote(String(format: "now %.3f g  \u{00b7}  peak %.3f g\n%@  \u{00b7}  still %d  \u{00b7}  moving %d",
                               g.lastJolt, g.peakJolt,
                               g.armedNow ? "armed \u{2014} a pickup would cost a chance" : "not armed \u{2014} put the phone down",
                               g.stillRun, g.movingRun))
                DevButton("Clear the peak") { g.stopTuning(); g.startTuning() }
            } else {
                DevNote("Turn this on, set the phone down until it arms, then pick it up. The peak is what a real pickup reads on this phone \u{2014} put \u{201c}lift\u{201d} comfortably under it.")
            }

            DevNote(String(format: "Lift: over %.2f g for 0.2s", FocusGuard.moveJolt))
            HStack(spacing: 8) {
                ForEach([0.03, 0.05, 0.08, 0.12, 0.16], id: \.self) { v in
                    DevChip(String(format: "%.2f", v), on: abs(FocusGuard.moveJolt - v) < 0.001) {
                        FocusGuard.moveJolt = v
                        bump += 1
                    }
                }
            }
            DevNote(String(format: "Still: under %.3f g for 0.5s", FocusGuard.stillJolt))
            HStack(spacing: 8) {
                ForEach([0.015, 0.025, 0.035, 0.05, 0.08], id: \.self) { v in
                    DevChip(String(format: "%.3f", v), on: abs(FocusGuard.stillJolt - v) < 0.0005) {
                        FocusGuard.stillJolt = v
                        bump += 1
                    }
                }
            }
            DevButton("Back to the defaults") {
                FocusGuard.resetThresholds()
                bump += 1
            }
        }
        .id(bump)
    }

    /// **The one question the focus guard cannot answer.** "Shaking does nothing" has two
    /// completely different causes — iOS never delivered the gesture, or it did and the guard was
    /// not watching — and the readout above cannot tell them apart, because it only ever sees the
    /// events that already got through. This counts the raw event instead.
    ///
    /// It is driven through `.onShake` itself rather than by polling `ShakeLog`, so a moving
    /// counter proves the whole delivery path end to end. There is no assert that can stand in
    /// for this: UIKit event delivery is not something a self-check can exercise.
    private var shakeGroup: some View {
        DevGroup("Shake") {
            if let last = lastShake {
                DevNote("\(shakes) since this panel opened \u{00b7} last at \(last.formatted(date: .omitted, time: .standard))\n\(ShakeLog.count) since launch.")
                DevNote("The gesture is reaching the app. Whether it costs a chance is the focus guard's business, just above.")
            } else {
                DevNote("Shake the phone now. Sharp and side to side \u{2014} iOS wants a real reversal, not a wobble.")
                DevNote("Nothing yet. If this stays at zero: Settings \u{25b8} Accessibility \u{25b8} Touch \u{25b8} Shake to Undo, and Guided Access if it is on.")
            }
        }
        .onShake {
            shakes += 1
            lastShake = Date()
        }
    }

    private var checks: some View {
        DevGroup("Identity check") {
            DevToggle("Skip \(Biometrics.name) when paying", on: model.devSkipBiometrics) {
                model.devSkipBiometrics = $0
            }
            DevNote(Biometrics.available
                ? "This device has \(Biometrics.name). The pay sheet raises the real system check."
                : "No biometry and no passcode on this device \u{2014} the real check cannot run, so leave this on.")
        }
    }

    private var account: some View {
        DevGroup("Account and Screen Time") {
            DevNote(accountNote)
            if identity.isSignedIn {
                DevButton("Sign out") { model.signOutAccount(identity) }
            }
            DevNote("Screen Time: \(screenTimeLabel)")
            DevButton("Ask for Screen Time again") {
                Task {
                    await model.requestScreenTimeAuthorization()
                    screenTime = model.screenTimeAuthorized
                }
            }
        }
    }

    /// **Which parts of `supabase/schema.sql` are actually live.** Everything the shared bank,
    /// gifts and the miles journal do goes through PostgREST, and PostgREST answers a function
    /// that was never created and one this member may not execute with the same 404 — so a
    /// feature that silently does nothing cannot tell you which it was. This asks each one
    /// directly. "NOT DEPLOYED" means run the file (or that part of it) against the project;
    /// "reachable" with a refusal after it is the healthy answer for a probe sent deliberately
    /// bad arguments.
    private var serverGroup: some View {
        DevGroup("Account server") {
            if !Backend.isConfigured {
                DevNote("No Supabase URL or anon key in Info.plist \u{2014} nothing to probe.")
            } else if !backend.isLinked {
                DevNote("Sign in first: every one of these is checked as the signed-in member.")
            } else {
                DevButton(probing ? "Checking\u{2026}" : "Check the schema") {
                    guard !probing else { return }
                    probing = true
                    Task {
                        let rows = await backend.probe()
                        probe = rows
                        probing = false
                    }
                }
                if let probe {
                    DevNote(probe.map { "\($0.0): \($0.1)" }.joined(separator: "\n"))
                }
            }
        }
    }

    private var accountNote: String {
        guard let a = identity.account else {
            return "Not signed in.\nGoogle: \(Identity.googleConfigured ? "client id present" : "no GIDClientID in Info.plist")"
        }
        return "\(a.displayName) \u{00b7} \(a.provider.label)\n\(a.email.isEmpty ? "no address" : a.email)"
    }

    private var screenTimeLabel: String {
        switch screenTime {
        case true: return "approved \u{2014} blocking is live"
        case false: return "not approved \u{2014} blocking is mocked"
        case nil: return "checking\u{2026}"
        }
    }

    private var danger: some View {
        DevGroup("Reset") {
            if confirmingReset {
                DevNote("This erases miles, passes, the hours ledger, the account and every setting, then returns to onboarding.")
                DevButton("Erase everything", destructive: true) { wipe() }
                DevButton("Never mind") { confirmingReset = false }
            } else {
                DevButton("Erase this install\u{2026}", destructive: true) { confirmingReset = true }
            }
        }
    }

    /// `AppModel.wipeInstall` is the one writer — deleting the account runs the same body.
    private func wipe() {
        model.wipeInstall(identity)
        onClose()
    }
}

// MARK: - Furniture

/// Deliberately plain. This screen is a workbench, not part of the product, and dressing it in the
/// app's own language would only make it harder to tell apart from a screen that ships.

private struct DevGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased()).tpLabelStyle().foregroundStyle(TColor.textMuted)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 18)
        .overlay(alignment: .bottom) { Rectangle().fill(TColor.borderSubtle).frame(height: 1) }
    }
}

private struct DevNote: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(TFont.data(.regular, 12))
            .tpType(size: 12, lineHeight: 1.45)
            .foregroundStyle(TColor.textMuted)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DevToggle: View {
    let label: String
    let on: Bool
    let set: (Bool) -> Void
    init(_ label: String, on: Bool, set: @escaping (Bool) -> Void) {
        self.label = label; self.on = on; self.set = set
    }
    var body: some View {
        Toggle(isOn: Binding(get: { on }, set: set)) {
            Text(label).font(TFont.core(.medium, 15)).foregroundStyle(TColor.textPrimary)
        }
        .tint(TColor.copper500)
    }
}

private struct DevChip: View {
    let label: String
    var on = false
    let action: () -> Void
    init(_ label: String, on: Bool = false, action: @escaping () -> Void) {
        self.label = label; self.on = on; self.action = action
    }
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(TFont.data(.medium, 13))
                .foregroundStyle(on ? TColor.white : TColor.textPrimary)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(Capsule().fill(on ? TColor.navy700 : TColor.cloud100))
        }
        .buttonStyle(.plain)
    }
}

private struct DevButton: View {
    let label: String
    var destructive = false
    let action: () -> Void
    init(_ label: String, destructive: Bool = false, action: @escaping () -> Void) {
        self.label = label; self.destructive = destructive; self.action = action
    }
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(TFont.core(.medium, 15))
                .foregroundStyle(destructive ? TColor.statusDiverted : TColor.textAccent)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Signing in, after onboarding

/// The same three providers onboarding offers, reachable again from Settings — because onboarding
/// runs once and a member who skipped it, or who wants to sign out, has nowhere else to go.
///
/// A plain system sheet on purpose: it is a system-level account action, and the app's own sheet
/// language belongs to things that are part of the flight.
struct SignInSheet: View {
    @Environment(Identity.self) private var identity
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""

    var body: some View {
        NavigationStack {
            Form {
                if let account = identity.account {
                    Section("Signed in") {
                        LabeledContent("Name", value: account.displayName)
                        if !account.email.isEmpty { LabeledContent("Email", value: account.email) }
                        LabeledContent("Through", value: account.provider.label)
                    }
                    Section {
                        Button("Sign out", role: .destructive) { model.signOutAccount(identity) }
                    } footer: {
                        Text("Your miles, log and passes stay on this phone either way \u{2014} signing out does not remove them.")
                    }
                } else {
                    Section {
                        Button("Continue with Apple") { Task { await model.signIn(.apple, identity: identity) } }
                        Button("Continue with Google") { Task { await model.signIn(.google, identity: identity) } }
                    }
                    Section("Or an email address") {
                        TextField("you@example.com", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Continue with email") { Task { await model.signIn(.email, identity: identity, email: email) } }
                            .disabled(email.isEmpty)
                    }
                }
                if let error = identity.error {
                    Section { Text(error).foregroundStyle(.red) }
                }
                if !Identity.syncAvailable {
                    Section {
                        Text("Signing in names the card and every pass. It does not yet back anything up \u{2014} there is no Tempus account server.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .disabled(identity.busy != nil)
        }
        .presentationDetents([.medium, .large])
    }
}
