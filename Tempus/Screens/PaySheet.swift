import SwiftUI

/// The redeem confirmation. The reference borrows the shape of a payment: the card comes down
/// from the island in a droplet, squares off as it lands, is presented, an identity check clears,
/// and only then does the miles ledger actually move, before the whole thing retracts.
///
/// **The side button is not ported, and cannot be.** iOS delivers no side-button event to any
/// third-party app: the double-press is a system gesture Apple routes to its own payment sheet,
/// and there is no API — public or entitled — to observe it, imitate it, or be told it happened.
/// So the reference's drawing of one is a picture of a control this app cannot have.
///
/// This carried a drawn stand-in for a while — a glassy 20 × 104 sliver pinned to the trailing
/// edge at the reference's `top:172`, confirmed by a double-tap. It was removed on 16 Sep 2026,
/// on the third report that the real button did nothing: a control drawn on the bezel *claims* to
/// be the hardware, and the 172 was a CSS literal measured inside a 390 × 844 drawing rather than
/// against any phone, so it did not even line up with the button it was imitating. An ordinary
/// confirm button says what it is. It is never presented as Apple Pay and carries no Apple Pay
/// mark: this moves in-app miles, not money.
///
/// **There used to be a second identity check drawn here: a small dark medallion with a ring
/// that swept closed and turned green, standing in for the reference's Dynamic Island.** It was
/// removed on 18 Sep 2026 — the system Face ID / Touch ID sheet *is* the identity check, and a
/// drawn ring repeating it a beat later read, in the user's words, like "a power button wearing a
/// badge". The 56pt slot now just holds the same confirm button, disabled and dimmed for as long
/// as the system check is in flight, rather than being swapped for anything.
///
/// **What was checked is a real `LAContext` evaluation.** The reference's check is a timer: 980 ms
/// after the double-click it turns green and the ledger moves, because a web page has no biometry.
/// Here the confirm button raises the system Face ID sheet and the miles move **only on a genuine
/// success** — a cancel retracts having spent nothing, a failure says so and hands the control
/// back. The reference's 980 ms floor paced the now-deleted ring and is not kept: with no ring to
/// read, holding the button disabled for a fixed minimum after the system sheet has already
/// resolved would only delay a sheet the user already confirmed. The 1120 ms beat *is* kept — it
/// holds the settled card and amount on screen after a successful payment, which has nothing to
/// do with the ring and still reads as the ceremony completing rather than being cut off.
///
/// **Two things the reference itself never uses are not ported.** `PaySheet`'s `'ready'` stage,
/// set 2050ms after mount, branches nowhere in the source — `Stage` below collapses it into
/// `.awaiting`. Its `useRoll`-eased rolling balance is computed and never rendered anywhere in the
/// component, so this file does not compute it either.
struct PaySheet: View {
    @Environment(AppModel.self) private var model

    private enum Stage: Equatable { case awaiting, check, paid, closing }
    @State private var stage: Stage = .awaiting
    @State private var didPay = false
    /// Why the last attempt did not go through. Cancelling sets nothing — declining is not an error.
    @State private var refusal: String?
    /// `refusal` read in the ordinary "declined" register (red) unless this is set — a shared-pot
    /// round trip that could not be reached must never look like a balance that came up short.
    @State private var refusalIsUnavailable = false

    /// The scrim's own dim.
    @State private var dimOn = false
    /// The droplet panel's settled shape — squashed and offset above the frame when `false`,
    /// square and in place when `true`. Reused for both the entrance (drip in) and the exit (drip
    /// out), since both are the same shape animated in opposite directions.
    @State private var landed = false
    /// The card + amount rising into the settled panel, 1150 ms after it starts arriving.
    @State private var contentIn = false

    @State private var revealTask: Task<Void, Never>?
    @State private var payTask: Task<Void, Never>?

    private static let panelSize = CGSize(width: 306, height: 288)
    /// `ISL_T + ISL_H + 16` — 16pt below the collapsed Dynamic Island's own resting position.
    private static let panelTop: CGFloat = 65

    var body: some View {
        ZStack {
            scrim
            if let order = model.payFlow {
                panelView(order)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, Self.panelTop)
                actionColumn
            }
        }
        .ignoresSafeArea()
        .onAppear { start() }
        .onDisappear {
            revealTask?.cancel(); revealTask = nil
            payTask?.cancel(); payTask = nil
        }
    }

    // MARK: - Scrim

    private var scrim: some View {
        // "rgba(9,16,28,x)" — the pay sheet's own bespoke dim colour, distinct from the app's usual
        // overlay-scrim token (navy-900 at .55). Ported literally; the reference names it apart.
        Color(hex: 0x09101c, opacity: 0.58)
            .opacity(dimOn ? 1 : 0)
            .allowsHitTesting(stage != .closing)
            .onTapGesture { tapScrim() }
            .animation(dimOn ? .onboarding(0.9) : .onboarding(0.76), value: dimOn)
            .ignoresSafeArea()
    }

    // MARK: - Panel

    private func panelView(_ order: Order) -> some View {
        let idx = model.status.idx
        let variant = model.cardVariant.indices.contains(idx) ? model.cardVariant[idx] : 0
        return VStack(spacing: 0) {
            VStack(spacing: 0) {
                StatusCard(tier: idx, variant: variant, name: model.cardName, width: 266,
                           owned: model.ownedFaces, flippable: true,
                           serial: model.founderSerialString, issued: model.founderIssuedString,
                           miles: model.pool)
                    .padding(.top, 18)
                Text("\(order.cost) mi")
                    .font(TFont.core(.bold, 40))
                    .tracking(-0.055 * 40)
                    .monospacedDigit()
                    .foregroundStyle(TColor.textPrimary)
                    .padding(.top, 22)
                // Only an unlock buys *minutes*. `Order.mins` is never set for a gift, a card face
                // or a pass header, so the unconditional line printed "Gift to Marcus · 0 min" —
                // a quantity, in the one place a member is deciding whether to spend.
                Text(order.kind == .unlock ? "\(order.name) \u{00b7} \(order.mins) min" : order.name)
                    .font(TFont.core(.medium, 14))
                    .foregroundStyle(TColor.textMuted)
                    .padding(.top, 9)
            }
            .padding(.horizontal, 20)
            .offset(y: contentIn ? 0 : 34)
            .animation(.onboarding(1.0), value: contentIn)
            .opacity(contentIn ? 1 : 0)
            // The reference's own `tp-payct 1000ms {OBE} 1150ms both, tp-payco 1000ms linear
            // 1150ms both` — the transform rides the onboarding curve, the opacity fades at a
            // flat linear rate over the same window. Confirmed against `app.jsx`; not a stray
            // `.linear` — do not "fix" it to `.glide`.
            .animation(.linear(duration: 1.0), value: contentIn)
            Spacer(minLength: 0)
        }
        .padding(.bottom, 20)
        .frame(width: Self.panelSize.width, height: Self.panelSize.height, alignment: .top)
        .background(TColor.surfaceCard)
        .clipShape(cornerShape)
        .tpShadow(.overlay)
        .scaleEffect(x: landed ? 1 : 0.46, y: 1, anchor: .top)
        .offset(y: landed ? 0 : -Self.panelSize.height * 1.24)
        .opacity(panelOpacity)
        .animation(landed ? .onboarding(1.25) : .onboarding(0.9), value: landed)
    }

    /// What to do, what went wrong, and the control that does it — sitting on the scrim *below*
    /// the droplet rather than inside it.
    ///
    /// The panel is a fixed 306 × 288 that the entrance animates the shape of, and it clips:
    /// content past 288pt is cut, not accommodated. The card, the amount and the subject already
    /// come to ~281pt of that, so anything put inside would render below the cut and never be
    /// seen. Growing the panel instead would change the droplet the whole entrance is built on.
    ///
    /// The prompt line keeps its height even when it has nothing to say, so a refusal appearing
    /// does not shove the button down under the reader's thumb.
    private var actionColumn: some View {
        VStack(spacing: 18) {
            Text(promptText ?? "")
                .font(TFont.core(.medium, 13))
                .foregroundStyle(refusal == nil || refusalIsUnavailable
                                 ? TColor.textOnDarkMuted : TColor.statusDiverted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 280)
                .opacity(contentIn && promptText != nil ? 1 : 0)
                // Same reference pairing as the card's own entrance above: opacity fades linear
                // while the sheet's transform (and everything else about `contentIn`) eases.
                .animation(.linear(duration: 0.5), value: contentIn)
                .animation(.glide(0.22), value: refusal)
                .animation(.glide(0.22), value: stage)
                .allowsHitTesting(false)

            // One button throughout — no more swap to a separate badge. While the system check
            // (or the shared-pot round trip in `settle`) is in flight it goes quiet: dimmed and
            // dead to touch, since the order is already on its way one way or the other. It stays
            // in that same quiet state through `.closing`, fading out with the rest of the column.
            TButton(confirmLabel, variant: .primary, size: .lg, action: present)
                .disabled(stage != .awaiting)
                .opacity(stage == .awaiting ? 1 : 0.4)
                .frame(height: 56)
                .opacity(contentIn ? 1 : 0)
                // Same pairing again — opacity linear against `contentIn`, everything else eased.
                .animation(.linear(duration: 0.5), value: contentIn)
                .animation(.glide(0.28), value: stage)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, Self.panelTop + Self.panelSize.height + 18)
        .opacity(stage == .closing ? (landed ? 1 : 0) : 1)
        .animation(landed ? .onboarding(1.25) : .onboarding(0.9), value: landed)
        // The scrim is navy at 58%: the button's shadow falls on a dark ground, not a pale one.
        .tpDarkGround()
    }

    private var cornerShape: UnevenRoundedRectangle {
        let top: CGFloat = landed ? 30 : 0
        let bottom: CGFloat = landed ? 30 : 200
        return UnevenRoundedRectangle(topLeadingRadius: top, bottomLeadingRadius: bottom,
                                       bottomTrailingRadius: bottom, topTrailingRadius: top)
    }

    /// Opaque throughout the entrance and the wait; only fades once actually retracting, tracking
    /// the same `landed` reversal the shape itself animates on.
    private var panelOpacity: Double { stage == .closing ? (landed ? 1 : 0) : 1 }

    // MARK: - The confirm control

    /// Named for whatever this phone actually has, so the button never offers Face ID to a device
    /// without it.
    private var confirmLabel: String {
        if Dev.available, model.devMode, model.devSkipBiometrics { return "Confirm" }
        return "Confirm with \(Biometrics.name)"
    }

    // MARK: - The stage machine

    private func start() {
        guard revealTask == nil else { return }
        dimOn = true
        landed = true
        revealTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1150))
            guard !Task.isCancelled else { return }
            contentIn = true
        }
    }

    /// Confirming raises the system identity check. The reference's 980 ms was a floor that gave a
    /// now-deleted ring at least that long to read as a check; with no ring left to pace, holding
    /// the button disabled for a fixed minimum after the system sheet has already answered would
    /// only delay a sheet the user already confirmed, so it is not reproduced here. Only a real
    /// success reaches `payOrder`.
    private func present() {
        guard stage == .awaiting, let order = model.payFlow else { return }
        stage = .check
        refusal = nil
        refusalIsUnavailable = false
        model.payCheck = .check
        payTask = Task { @MainActor [order] in
            let outcome = await authorise(order)
            guard !Task.isCancelled else { return }

            switch outcome {
            case .success:
                await settle(order)
            case .cancelled:
                // Declined on purpose: no message, nothing spent, straight back to the button.
                stage = .awaiting
                model.payCheck = nil
            case .failed(let why):
                refusal = why
                refusalIsUnavailable = false
                stage = .awaiting
                model.payCheck = nil
            }
        }
    }

    /// Moves the miles once identity has cleared. The personal balance alone stays the fast,
    /// synchronous path it always was — `payOrder` never awaits anything — and only a shortfall
    /// goes to the shared pot, through `payOrderShared`. The button stays quiet and disabled for
    /// however long that round trip takes: no separate spinner, just the same state held longer.
    private func settle(_ order: Order) async {
        if order.kind != .gift, order.cost <= model.miles {
            model.payOrder(order)
        } else {
            switch await model.payOrderShared(order) {
            case .ok:
                break
            case .refused:
                // Not "you can't afford it" — the miles were there when the screen was drawn and
                // someone else spent the shortfall first.
                refusal = order.kind == .gift ? (model.giftFailed ?? "Those miles have already been spent.") : "Those miles have already been spent."
                refusalIsUnavailable = false
                stage = .awaiting
                model.payCheck = nil
                return
            case .unavailable:
                // Must never read as a refusal — nothing was spent, and the ledger says so.
                refusal = order.kind == .gift ? (model.giftFailed ?? "Connect to send this gift.") : "Could not reach the shared bank. Nothing was spent — try again."
                refusalIsUnavailable = true
                stage = .awaiting
                model.payCheck = nil
                return
            }
        }
        didPay = true
        stage = .paid
        model.payCheck = .paid
        try? await Task.sleep(for: .milliseconds(1120))
        guard !Task.isCancelled else { return }
        finish()
    }

    /// Developer mode is the one way past the system sheet, and only because the Simulator has no
    /// biometry unless it has been explicitly enrolled. It is unreachable in any release build —
    /// see `Dev.available`.
    private func authorise(_ order: Order) async -> Biometrics.Outcome {
        if Dev.available, model.devMode, model.devSkipBiometrics { return .success }
        return await Biometrics.check(reason: "Confirm \(order.cost) mi for \(order.name).")
    }

    /// Only ever the exceptions now — what went wrong, or that the check is being skipped. The
    /// instruction itself moved onto the button, which is the thing that carries it out; a line
    /// telling the reader to do what the button already says is furniture.
    private var promptText: String? {
        if let refusal { return refusal }
        guard stage == .awaiting else { return nil }
        if Dev.available, model.devMode, model.devSkipBiometrics { return "Developer mode \u{00b7} check skipped" }
        return nil
    }

    /// Tapping the scrim before presenting dismisses with nothing spent — `finish()` with no hold,
    /// so the retract starts at once.
    private func tapScrim() {
        guard stage == .awaiting else { return }
        finish()
    }

    /// A payment holds the settled card on screen a beat longer than a bare dismissal before it
    /// starts retracting, so the ceremony reads as complete rather than interrupted.
    private func finish() {
        // The reference's own `finish()` clears every pending timer, not just the payment one — a
        // scrim-tap dismissal inside the first 1150ms would otherwise still fade the content in
        // while the panel is already retracting underneath it.
        revealTask?.cancel()
        payTask?.cancel()
        stage = .closing
        model.payCheck = didPay ? .out : nil
        let hold = didPay ? 720 : 0
        payTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(hold))
            guard !Task.isCancelled else { return }
            dimOn = false
            landed = false
            try? await Task.sleep(for: .milliseconds(920))
            guard !Task.isCancelled else { return }
            model.payFlow = nil
            model.payCheck = nil
        }
    }
}
