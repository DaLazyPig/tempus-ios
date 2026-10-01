import SwiftUI

// MARK: - Preflight

/// Where a flight is chosen: how long, therefore how far, therefore what it pays.
///
/// The Business class button is not a toggle. It raises a consent gate, and confirming that gate
/// both arms the cabin and boards in one step — there is deliberately no state in which business
/// class is armed and the flight has not left.
struct PreflightScreen: View {
    @Environment(AppModel.self) private var model

    /// Economy flies the short routes: anything past ninety minutes is Business Class, so the dial
    /// stops there rather than offering a length that cannot be boarded.
    private var ceiling: Double { model.plus ? 240 : 90 }
    private var atCeiling: Bool { !model.plus && Double(model.minutes) >= ceiling }

    private var minutesValue: Binding<Double> {
        Binding(get: { Double(model.minutes) },
                set: { model.minutes = Int($0.rounded()) })
    }

    var body: some View {
        let dest = Geography.destination(forMinutes: model.minutes)

        return VStack(spacing: 0) {
            Rise(i: 0) {
                FloatingPill(label: model.task?.title ?? "") { model.closePreflight() }
            }

            VStack(spacing: 0) {
                Rise(i: 1) {
                    Text("Flight length")
                        .tpLabelStyle()
                        .foregroundStyle(TColor.textOnDarkMuted)
                }

                Rise(i: 2) {
                    // `.lastTextBaseline`, and no tracking on the unit — the same pairing Redeem
                    // and onboarding's cap dial use. Three screens showing one number over one
                    // dial should not sit their unit on three different baselines.
                    HStack(alignment: .lastTextBaseline, spacing: 9) {
                        tpText("\(model.minutes)", size: TFont.sizeDialValue, track: -0.07)
                            .font(TFont.core(.bold, TFont.sizeDialValue))
                            .monospacedDigit()
                            .foregroundStyle(TColor.cloud100)
                        Text("min")
                            .font(TFont.core(.semibold, 24))
                            .foregroundStyle(TColor.textOnDarkMuted)
                    }
                    .padding(.top, 14)
                }

                Rise(i: 3) {
                    // Keyed on the destination, so the route pops each time it changes.
                    PopIn(duration: 0.32) {
                        Text(verbatim: "\(Geography.home.city) \u{2192} \(dest.city)")
                            .font(TFont.core(.semibold, 21))
                            .tpType(size: 21, track: -0.02, lineHeight: 1.3)
                            .foregroundStyle(TColor.copper300)
                    }
                    .id(dest.code)
                    .padding(.top, 26)
                }

                if atCeiling {
                    Rise(i: 3) {
                        Button { model.paywall = .open } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "lock")
                                    .font(.system(size: 13, weight: .medium))
                                Text("Longer routes fly in Business Class")
                                    .font(TFont.core(.medium, 13))
                            }
                            .foregroundStyle(TColor.textOnDark)
                            .padding(.horizontal, 15)
                            .padding(.vertical, 9)
                            .background(TColor.glassOnDark, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 16)
                    }
                }

                Rise(i: 4) { earnPreview.padding(.top, 14) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 28)
            .multilineTextAlignment(.center)

            Rise(i: 5) {
                HStack(spacing: 10) {
                    if model.plus {
                        Button { model.openGate(.board) } label: {
                            Text("Business class")
                                .font(TFont.core(.semibold, 17))
                                .foregroundStyle(model.biz ? TColor.white : TColor.textOnDark)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                                .padding(.horizontal, 32)
                                .frame(height: 56)
                                .background {
                                    Capsule()
                                        .fill(model.biz ? TColor.surfaceAccent : TColor.glassOnDark)
                                        .overlay {
                                            Capsule().strokeBorder(
                                                model.biz ? .clear : Color(hex: 0xf2f5fa, opacity: 0.18),
                                                lineWidth: 1)
                                        }
                                }
                                .tpShadow(model.biz ? TShadow.accent : TShadow.none)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(model.biz ? [.isButton, .isSelected] : .isButton)
                    }

                    TButton("Board now", variant: .primary, size: .lg, fullWidth: !model.plus) {
                        model.board()
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                }
                .padding(.horizontal, 18)
            }

            Rise(i: 6) {
                DialView(value: minutesValue, min: 5, max: ceiling, step: 5,
                         arcStep: 1.25, tone: .dark)
                    // 8pt under the button, the same gap Redeem leaves. It was 2.
                    .padding(.top, 8)
                    .padding(.bottom, 10)
            }
        }
        // Preflight is painted on the dark ground `RootView` lays down, so every shadow inside it
        // falls on navy — including the business-class pill's copper one, which lit a halo around
        // the pill rather than dropping a shadow under it.
        .tpDarkGround()
    }

    /// The multiplier is legible at the exact moment it would have paid off — applied for Business
    /// Class, priced for everyone else.
    @ViewBuilder
    private var earnPreview: some View {
        let st = model.status
        let paid = model.plus && st.mult > 1
        let offer = !model.plus && st.offer > 1

        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(verbatim: "\(paid ? model.earned : model.baseEarn) mi")
                .font(TFont.core(.semibold, 15))
                .foregroundStyle(TColor.copper300)

            if paid {
                Text(verbatim: "\(st.tier.name) \u{00d7}\(mult(st.mult))")
            } else if offer {
                HStack(spacing: 7) {
                    Image(systemName: "lock")
                        .font(.system(size: 12, weight: .medium))
                    Text(verbatim: "\(st.tier.name) \u{00d7}\(mult(st.offer)) \u{2014} Business Class")
                }
            } else {
                Text(verbatim: "\(st.tier.name) \u{00d7}1.0")
            }
        }
        .font(TFont.core(.medium, 13))
        .tpType(size: 13, lineHeight: 1.4)
        .foregroundStyle(TColor.textOnDarkMuted)
    }
}

// MARK: - In flight

/// The flight itself: a countdown, a destination, and one way out.
///
/// The way out is the whole screen. In economy the X is a 900 ms hold that diverts on the spot; in
/// business class it is a ten-second hold that only opens a second gate. Nothing here can end a
/// flight by being tapped.
struct FlyingScreen: View {
    @Environment(AppModel.self) private var model

    /// Presentation only. The model's `elapsed` is the time; this smooths the 250 ms steps between
    /// its ticks so the readout glides instead of stuttering, and it can never run past `total`.
    @State private var clock = FlightClock()

    var body: some View {
        let dest = model.destination ?? Geography.destination(forMinutes: model.minutes)

        VStack(spacing: 0) {
            Rise(i: 0) {
                FloatingPill(label: model.task?.title ?? "",
                             holdLabel: model.biz ? "Keep holding"
                                                  : "Hold to divert \u{00b7} \(model.stakeLabel)",
                             holdSeconds: model.biz ? 10 : HoldState.base) {
                    // The one branch that matters: a locked cabin cannot end on a hold alone.
                    if model.biz { model.openGate(.exit) } else { model.divert() }
                }
            }

            VStack(spacing: 0) {
                Rise(i: 1) {
                    Text("In flight to")
                        .tpLabelStyle()
                        .foregroundStyle(TColor.textOnDarkMuted)
                }

                Rise(i: 2) {
                    Text(verbatim: dest.city)
                        .font(TFont.core(.bold, 38))
                        .tracking(-0.045 * 38)
                        .foregroundStyle(TColor.textOnDark)
                        .padding(.top, 12)
                }

                Rise(i: 3) {
                    // Deliberately its own size, not `TFont.sizeDialValue`: this is a read-only
                    // mm:ss countdown, not a quantity picker, and "12:34" is a wider string than
                    // any of the pickers ever set — squeezing it to the shared size would make it
                    // the tightest-fit readout in the app for no reason.
                    tick { remaining, _ in
                        tpText(mmss(remaining), size: 96, track: -0.07)
                            .font(TFont.core(.bold, 96))
                            .monospacedDigit()
                            .foregroundStyle(TColor.cloud100)
                    }
                    .padding(.top, 18)
                }

                Rise(i: 4) {
                    HStack(spacing: 8) {
                        PulsingDot()
                        tick { remaining, now in
                            let lands = now.addingTimeInterval(remaining / max(0.01, model.speed))
                            Text(verbatim: "Cruising \u{00b7} lands \(hhmm(lands))")
                                .tpLabelStyle()
                                .foregroundStyle(TColor.textOnDarkMuted)
                        }
                    }
                    .padding(.top, 20)
                }

                if model.biz {
                    Rise(i: 5) {
                        HStack(spacing: 9) {
                            Image(systemName: "lock")
                                .font(.system(size: 13, weight: .medium))
                            Text("Business class \u{00b7} cabin locked")
                                .tpLabelStyle()
                        }
                        // The one warm copper the palette does not carry as a token.
                        .foregroundStyle(Color(hex: 0xe0a08e))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(Color(hex: 0xb86f52, opacity: 0.22), in: Capsule())
                        .padding(.top, 22)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 28)
            .multilineTextAlignment(.center)

            Rise(i: 5) {
                // A read-only echo of the time left. It is not a control.
                tick { remaining, _ in
                    DialView(value: .constant(remaining / 60), min: 0,
                             max: Swift.max(1, (model.total / 60).rounded()), step: 0.2,
                             arcStep: 0.7, tone: .dark, interactive: false)
                }
                .opacity(0.85)
                .padding(.bottom, 24)
            }
        }
        // A lapse takes the screen: there is nothing to do in here but put the phone down.
        .overlay {
            if let why = model.focusGuard.interruption {
                SettleOverlay(why: why, guard: model.focusGuard)
                    .transition(.opacity)
            }
        }
        .animation(.glide(TDur.base), value: model.focusGuard.interruption)
        // The accelerometer decides what a *pickup* is, and that depends on the phone and the
        // desk. A shake is decided by UIKit and means one thing, so it is wired in beside it.
        .onShake { model.focusGuard.shaken() }
    }

    /// Wraps only the parts of the screen that are a function of the wall clock in the 30 fps
    /// tick — which is the rate the reference throttles its own frame loop to.
    ///
    /// A `TimelineView` re-evaluates everything it encloses on every tick, so wrapping the whole
    /// screen rebuilt the pill, the destination and the cabin badge thirty times a second to
    /// redraw two readouts. All the calls share one `FlightClock`, so they cannot disagree: it
    /// re-anchors on a change of `elapsed`, and whoever asks first that tick does the anchoring.
    private func tick<Content: View>(
        @ViewBuilder _ content: @escaping (Double, Date) -> Content
    ) -> some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { context in
            let smooth = clock.smooth(elapsed: model.elapsed, now: context.date,
                                      speed: model.speed, total: model.total)
            content(max(0, model.total - smooth), context.date)
        }
    }
}

/// What a spent chance looks like. It states what happened, what it cost, and what to do — and
/// then counts five seconds down, but only once the phone is actually lying still.
private struct SettleOverlay: View {
    let why: Interruption
    let `guard`: FocusGuard

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            Text(chancesLine)
                .tpLabelStyle()
                .foregroundStyle(TColor.statusDelayed)

            Text(why.rawValue)
                .font(TFont.title2)
                .foregroundStyle(TColor.textOnDark)
                .multilineTextAlignment(.center)
                .padding(.top, 14)

            Text("The clock hasn't stopped.")
                .font(TFont.core(.regular, 15))
                .foregroundStyle(TColor.textOnDarkMuted)
                .padding(.top, 10)

            Group {
                if let n = `guard`.countdown {
                    VStack(spacing: 8) {
                        tpText("\(n)", size: TFont.sizeReadout, track: -0.07)
                            .font(TFont.readout)
                            .monospacedDigit()
                            .foregroundStyle(TColor.cloud100)
                            .contentTransition(.numericText(countsDown: true))
                        Text("Back in the air")
                            .tpLabelStyle()
                            .foregroundStyle(TColor.textOnDarkMuted)
                    }
                } else {
                    Text("Put your phone down to carry on.")
                        .font(TFont.core(.medium, 17))
                        .foregroundStyle(TColor.copper300)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.top, 44)
            .animation(.glide(TDur.base), value: `guard`.countdown)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 32)
        // Opaque, not a scrim: the flight's own readout sits exactly where the count does, and two
        // sets of numerals through each other read as a glitch.
        .background(TColor.navy700)
        .tpDarkGround()
        .ignoresSafeArea()
        // Nothing behind this is reachable, including the hold-to-divert control.
        .contentShape(Rectangle())
        .onTapGesture {}
    }

    private var chancesLine: String {
        // A locked cabin has no chances to count — it is never diverted, only asked for the phone
        // back. Quoting "2 chances left" there would promise a way out that business class does
        // not have.
        if `guard`.locksCabin { return "The cabin is locked" }
        return switch `guard`.chancesLeft {
        case 0: "No chances left"
        case 1: "1 chance left"
        case let n: "\(n) chances left"
        }
    }
}

/// `tp-pulse`, the live dot. The only thing in the flight loop that repeats, and it lives in its
/// own view on purpose: a `repeatForever` started from the screen's own state attaches itself to
/// every other animatable change in that body — the countdown text ended up cross-fading against
/// the first value it ever showed, on a 1.1 s loop, for the whole flight.
private struct PulsingDot: View {
    @State private var dim = false

    var body: some View {
        Circle()
            .fill(TColor.statusOnTime)
            .frame(width: 7, height: 7)
            .opacity(dim ? 0.35 : 1)
            // The reference's own `tp-pulse 2.2s ease-in-out infinite` (confirmed against
            // `app.jsx`) — CSS's `ease-in-out` keyword, a different curve from the house
            // `.glide`, and the 1.1s here is half the CSS's 2.2s because `repeatForever(
            // autoreverses: true)` plays it forward and back. Not a stray `.easeInOut`.
            .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: dim)
            .onAppear { dim = true }
    }
}

/// Interpolation between the model's ticks, and nothing else. It re-anchors whenever `elapsed`
/// moves, so a corrected tick pulls the display straight back onto the wall clock rather than
/// letting this drift into being a second, disagreeing clock.
private final class FlightClock {
    private var anchorElapsed: Double = -1
    private var anchoredAt = Date.distantPast

    func smooth(elapsed: Double, now: Date, speed: Double, total: Double) -> Double {
        if elapsed != anchorElapsed {
            anchorElapsed = elapsed
            anchoredAt = now
        }
        return min(total, anchorElapsed + now.timeIntervalSince(anchoredAt) * speed)
    }
}

// MARK: - Landed

/// What a flight paid, and what it cost. One screen with four faces: a landing, a diversion, an
/// emergency exit's bill, and a tier reached.
///
/// Where the flight went is read from `landedAt` and never recomputed — landing has already moved
/// home to the destination, so recomputing it would name the city you are now sitting in.
///
/// **A landing says two things: where, and how much.** The reference also prints the route arc, the
/// flight code and the minutes flown, and the hours left to the next tier. All of that is true and
/// none of it is what the moment is for — it is already in the pass, the flight log and the Status
/// Club, and stacking five figures under a number that just went up turns an arrival into a
/// receipt. The city and the miles are the whole screen. See CLAUDE.md's divergence table.
///
/// The two states that are *not* a plain arrival keep everything they had: a diversion keeps its
/// notice, because it explains why nothing counted, and a business-class exit keeps its bill.
struct LandedScreen: View {
    @Environment(AppModel.self) private var model
    @State private var cardRect: CGRect = .zero

    private var penalty: Bool { model.penalty }

    /// What the model actually credited. Not `earned` — that is derived from the *current* status,
    /// and a landing that crosses a tier changes the status a moment after banking at the old
    /// multiplier, so `earned` would quote a number the balance never received.
    private var payout: Int { model.bankedMiles }

    var body: some View {
        if let up = model.tierUp, !model.diverted, up == Status.founderIndex {
            InvitationArrival()
        } else if let up = model.tierUp, !model.diverted {
            tierUp(up)
        } else {
            arrival
        }
    }

    // MARK: Arrival

    private var arrival: some View {
        let dest = model.landedAt ?? Geography.destination(forMinutes: model.minutes)
        let st = model.status
        let zero = payout == 0
        // A diversion never reached the destination, so its figure reads the same muted way a
        // zero payout does, whatever `policy` actually paid out for the minutes flown.
        let muted = zero || model.diverted
        let figureSize: CGFloat = penalty ? 84 : 104

        return VStack(spacing: 0) {
            VStack(spacing: 0) {
                Rise(i: 1) {
                    VStack(spacing: 10) {
                        Text(model.diverted ? "Flight" : "Landed in")
                            .tpLabelStyle()
                            .foregroundStyle(TColor.textMuted)
                        Text(verbatim: model.diverted ? "Diverted" : dest.city)
                            .font(TFont.core(.bold, 44))
                            .tracking(-0.05 * 44)
                            .foregroundStyle(TColor.textPrimary)
                    }
                    // ponytail: 20pt gap under the route strip — the spec fixed the strip's own
                    // geometry but not this gap, so it's picked to read clearly, not measured.
                    .padding(.top, model.diverted ? 0 : 20)
                }

                PopIn(duration: 0.48, delay: 0.16) {
                    VStack(spacing: 0) {
                        // `.lastTextBaseline`, not `.bottom`: at 104pt against 17pt the numeral's
                        // box is mostly descender space, so bottom-aligning drops "mi" well below
                        // the figure it belongs to. Baselines are what make the two read as one
                        // number and its unit.
                        HStack(alignment: .lastTextBaseline, spacing: 9) {
                            CountUp(to: payout, seconds: 0.95, format: { "+\($0)" })
                                .font(TFont.core(.extraBold, figureSize))
                                .tracking(-0.06 * figureSize)
                                // tpText only kerns a literal string, and CountUp owns its own —
                                // so the last-glyph clip at this tracking (Typography.swift) is
                                // covered with trailing padding instead.
                                .padding(.trailing, 0.055 * figureSize)
                                .monospacedDigit()
                                .foregroundStyle(muted ? TColor.textMuted : TColor.surfaceAccent)
                            Text("mi")
                                .font(TFont.data(.medium, 17))
                                .foregroundStyle(muted ? TColor.textMuted : TColor.textAccent)
                        }


                        // A plain landing says where and how much, and stops. A diversion and an
                        // emergency exit keep this line, because for them it is not a statistic —
                        // it is the reason the figure above it is the size it is.
                        if model.diverted || penalty {
                            Rectangle()
                                .fill(TColor.borderDefault)
                                .frame(height: 1)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 16)

                            Text(verbatim: captionBase)
                                .font(TFont.core(.regular, 14))
                                .foregroundStyle(TColor.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 13)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.top, penalty ? 24 : 34)

                if penalty {
                    Rise(i: 5) { penaltyTable.padding(.top, 20) }
                }

                if model.diverted && !penalty {
                    Rise(i: 5) {
                        HStack(alignment: .top, spacing: 11) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(TColor.statusDiverted)
                            Text(verbatim: "Diverted flights do not count towards status."
                                 + (st.next.map { " Still \(Status.h1(st.toNext)) h to \($0.name)." } ?? ""))
                                .font(TFont.core(.regular, 14))
                                .tpType(size: 14, lineHeight: 1.45)
                                .foregroundStyle(TColor.statusDiverted)
                                .multilineTextAlignment(.leading)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .background(TColor.statusDivertedSoft,
                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .padding(.top, 20)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 30)
            .padding(.top, penalty ? 96 : 0)
            .multilineTextAlignment(.center)

            Rise(i: 6) {
                VStack(spacing: 8) {
                    TButton(model.diverted ? "Board again" : "Redeem miles",
                            variant: .primary, size: .lg, fullWidth: true) {
                        // A diversion sends you back to the gate; a landing sends you to spend.
                        if model.diverted {
                            model.go(.preflight, .zoom)
                            clearOutcome(after: TransitionType.zoom.teardown)
                        } else {
                            model.go(.redeem, .perm)
                            clearOutcome(after: TransitionType.perm.teardown)
                        }
                    }
                    TButton("Back to deck", variant: .ghost, size: .md, fullWidth: true) {
                        model.go(.home, .zoom)
                        clearOutcome(after: TransitionType.zoom.teardown)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 34)
            }
        }
    }

    /// `caption`, split so the ledger row can show its multiplier tail as its own trailing
    /// element instead of string-splitting a formatted sentence back apart.
    private var captionBase: String {
        if penalty {
            return "Emergency exit at \(model.leftAt) of \(model.minutes) minutes."
        }
        if model.diverted {
            return payout == 0
                ? "You left at \(model.leftAt) of \(model.minutes) minutes. No miles earned."
                : "You left at \(model.leftAt) of \(model.minutes) minutes \u{2014} you kept \(payout) mi"
        }
        // A plain landing does not print this at all any more — see the note on `LandedScreen`.
        return "\(model.minutes) min \u{00b7} \(model.flightNo)"
    }

    private var penaltyTable: some View {
        VStack(spacing: 0) {
            ForEach(Array([("Miles from this flight", "Forfeited"),
                           ("Exit penalty", "\u{2212}15 mi"),
                           ("Status progression", "\u{2212}2 h")].enumerated()),
                    id: \.offset) { i, row in
                HStack(spacing: 14) {
                    Text(verbatim: row.0)
                        .font(TFont.core(.regular, 14))
                        .tpType(size: 14, lineHeight: 1.3)
                        .foregroundStyle(TColor.statusDiverted)
                    Spacer(minLength: 0)
                    Text(verbatim: row.1)
                        .font(TFont.core(.semibold, 14))
                        .tpType(size: 14, lineHeight: 1.3)
                        .foregroundStyle(TColor.statusDiverted)
                }
                .padding(.vertical, 11)
                .overlay(alignment: .top) {
                    if i > 0 {
                        Rectangle()
                            .fill(Color(hex: 0xa8493c, opacity: 0.18))
                            .frame(height: 1)
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 2)
        .padding(.bottom, 4)
        .frame(maxWidth: 300)
        .background(TColor.statusDivertedSoft,
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .multilineTextAlignment(.leading)
    }

    // MARK: Tier reached

    private func tierUp(_ idx: Int) -> some View {
        let tier = Status.tiers[idx]

        return VStack(spacing: 0) {
            VStack(spacing: 0) {
                Rise(i: 0) {
                    Text("Status earned")
                        .tpLabelStyle()
                        .foregroundStyle(TColor.cloud100.opacity(0.6))
                }

                Rise(i: 1) {
                    Text(verbatim: tier.name)
                        .font(TFont.core(.bold, 44))
                        .tracking(-0.05 * 44)
                        .foregroundStyle(TColor.cloud100)
                        .padding(.top, 16)
                }

                PopIn(duration: 0.62, delay: 0.12) {
                    // The reference passes no variant here, so a tier-up shows that tier's default face —
                    // which is the right one to show for a tier you have only just reached.
                    StatusCard(tier: idx, variant: 0, name: model.cardName, width: 330,
                               owned: model.ownedFaces)
                        .rotationEffect(.degrees(-2))
                        .measuredCard($cardRect)
                }
                .padding(.top, 38)

                Rise(i: 3) {
                    Text(verbatim: "Every landing now earns \u{00d7}\(mult(tier.mult)). \(tier.name) holds while you fly \(Int(tier.gate)) h in any 90 days.")
                        .font(TFont.core(.regular, 16))
                        .tpType(size: 16, lineHeight: 1.5)
                        .foregroundStyle(TColor.cloud100.opacity(0.72))
                        .frame(maxWidth: 290)
                        .padding(.top, 34)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 24)
            .multilineTextAlignment(.center)

            Rise(i: 4) { cardButtons }
        }
        .background(TColor.navy900.ignoresSafeArea())
        .tpDarkGround()
    }

    @ViewBuilder
    private var cardButtons: some View {
        VStack(spacing: 8) {
            TButton("See my card", variant: .primary, size: .lg, fullWidth: true) {
                landedShare(model)
            }
            TButton("Customise the card", variant: .onDark, size: .md, fullWidth: true) {
                landedCustomise(model, rect: cardRect)
            }
            TButton("Not now", variant: .onDark, size: .md, fullWidth: true) {
                model.go(.home, .zoom)
                clearOutcome(after: TransitionType.zoom.teardown)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 34)
    }

    /// The celebration is shown once. Clearing it after the cut, not before, keeps the outgoing
    /// layer intact while the transition is still drawing it.
    private func clearOutcome(after seconds: Double) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            model.tierUp = nil
        }
    }
}


// MARK: - The invitation

/// Founders is granted, never flown to, so it cannot arrive on the tier-earned screen. A sealed
/// invitation lands, the seal holds for a beat, and then the card is presented.
struct InvitationArrival: View {
    @Environment(AppModel.self) private var model

    @State private var open = false
    @State private var sealed = true
    @State private var lifted = false
    @State private var cardRect: CGRect = .zero

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                if open {
                    Rise(i: 0) {
                        Text("By invitation of the house")
                            .tpLabelStyle()
                            .foregroundStyle(Color(hex: 0xf3e3bf, opacity: 0.6))
                    }
                    Rise(i: 1) {
                        Text(verbatim: "FOUNDERS")
                            .font(TCardFont.founders.font(50))
                            .tracking(0.1 * 50)
                            .foregroundStyle(Color(hex: 0xf3e3bf))
                            .padding(.top, 18)
                    }
                    PopIn(duration: 0.78, delay: 0.12) {
                        StatusCard(tier: Status.founderIndex,
                                   variant: model.cardVariant[safe: Status.founderIndex] ?? 0,
                                   name: model.cardName, width: 330, owned: model.ownedFaces,
                                   serial: model.founderSerialString, issued: model.founderIssuedString)
                            .rotationEffect(.degrees(-2))
                            .measuredCard($cardRect)
                    }
                    .padding(.top, 36)
                } else {
                    envelope
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 24)
            .multilineTextAlignment(.center)

            if open {
                Rise(i: 4) {
                    VStack(spacing: 8) {
                        TButton("See my card", variant: .primary, size: .lg, fullWidth: true) {
                            landedShare(model)
                        }
                        TButton("Customise the card", variant: .onDark, size: .md, fullWidth: true) {
                            landedCustomise(model, rect: cardRect)
                        }
                        TButton("Not now", variant: .onDark, size: .md, fullWidth: true) {
                            model.go(.home, .zoom)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 34)
                }
            }
        }
        .background {
            // A single lit corner, the way a sealed letter catches light.
            RadialGradient(colors: [Color(hex: 0x3a2f1a), Color(hex: 0x0c0a06)],
                           center: UnitPoint(x: 0.5, y: -0.04),
                           startRadius: 0, endRadius: 460)
                .background(Color(hex: 0x0c0a06))
                .ignoresSafeArea()
        }
        .task {
            withAnimation(.glide(0.78)) { lifted = true }
            try? await Task.sleep(for: .milliseconds(1200))
            withAnimation(.glide(0.4)) { sealed = false }
            try? await Task.sleep(for: .milliseconds(400))
            open = true
        }
    }

    private var envelope: some View {
        VStack(spacing: 0) {
            Text("An invitation")
                .tpLabelStyle()
                .foregroundStyle(Color(hex: 0xf3e3bf, opacity: 0.6))

            ZStack {
                Color(hex: 0xece5d7)
                // The flap: a downward triangle across the top of the envelope.
                GeometryReader { geo in
                    Path { p in
                        p.move(to: .zero)
                        p.addLine(to: CGPoint(x: geo.size.width, y: 0))
                        p.addLine(to: CGPoint(x: geo.size.width / 2, y: 112))
                        p.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [Color(hex: 0xe4dcca), Color(hex: 0xd6cdb6)],
                                         startPoint: .top, endPoint: .bottom))
                }

                PopIn(duration: 0.62, delay: 0.42) {
                    Circle()
                        .fill(RadialGradient(
                            stops: [.init(color: Color(hex: 0xf0dcae), location: 0),
                                    .init(color: Color(hex: 0xa67c35), location: 0.68),
                                    .init(color: Color(hex: 0x7a5820), location: 1)],
                            center: UnitPoint(x: 0.34, y: 0.28),
                            startRadius: 0, endRadius: 46))
                        .frame(width: 66, height: 66)
                        // Plain black, not an ink token — this is the wax seal's own cast shadow
                        // on an illustrated envelope, not UI chrome, so it does not belong to any
                        // of `TShadow`'s four roles (which are all navy-tinted for that reason).
                        .shadow(color: .black.opacity(0.2063), radius: 8, y: 8)
                }
            }
            .frame(width: 300, height: 196)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            // The envelope's own cast shadow — same reasoning as the seal's above.
            .shadow(color: .black.opacity(0.3662), radius: 33, y: 34)
            .padding(.top, 28)
            // Grouped before the lift fades it: the envelope carries its own drop shadow and the
            // seal carries another, and an ungrouped fade dims each of them separately from the
            // shape casting it — the shadow pulses through the middle of the entrance.
            .compositingGroup()
            // `tp-liftin`
            .opacity(lifted ? 1 : 0)
            .scaleEffect(lifted ? 1 : 0.9)
            .offset(y: lifted ? 0 : 30)
        }
        // The label and the envelope fade together as one layer here too, for the same reason.
        .compositingGroup()
        .opacity(sealed ? 1 : 0)
    }

}

// MARK: - Shared parts

/// Both celebration screens leave the same way, so the two exits are written once.
private func landedShare(_ model: AppModel) {
    model.tierUp = nil
    model.statusIntro = TColor.navy900
    model.goDirect(.status)
}

private func landedCustomise(_ model: AppModel, rect: CGRect) {
    model.tierUp = nil
    model.cardDesignFrom = rect == .zero
        ? nil
        : AppModel.CardDesignFrom(rect: rect, bg: TColor.navy900, rot: -2)
    model.goDirect(.carddesign)
}

/// `tp-pop` — opacity and a small scale, on the glide curve, optionally delayed. Used wherever
/// something has to land rather than appear: the route, the miles circle, the card.
private struct PopIn<Content: View>: View {
    var duration: Double = 0.32
    var delay: Double = 0
    @ViewBuilder var content: () -> Content
    @State private var shown = false

    var body: some View {
        content()
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown ? 1 : 0.86)
            .onAppear { withAnimation(.glide(duration).delay(delay)) { shown = true } }
    }
}

private struct CardRectKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

private extension View {
    /// Reports the card's rect so the studio can grow out of exactly where it sat. A preference
    /// rather than a write from `onAppear`, because a closure that captured a copy of the view can
    /// reach the storage without ever invalidating what is on screen.
    func measuredCard(_ rect: Binding<CGRect>) -> some View {
        background {
            GeometryReader { geo in
                Color.clear.preference(key: CardRectKey.self, value: geo.frame(in: TStage.space))
            }
        }
        .onPreferenceChange(CardRectKey.self) { rect.wrappedValue = $0 }
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

/// `×1.1`, not `×1.100000`. Every tier multiplier is one decimal place.
private func mult(_ v: Double) -> String { String(format: "%.1f", v) }

private func mmss(_ seconds: Double) -> String {
    let total = Int(seconds.rounded(.down))
    return String(format: "%02d:%02d", total / 60, total % 60)
}

private func hhmm(_ date: Date) -> String {
    let f = DateFormatter()
    f.dateFormat = "HH:mm"
    f.locale = Locale(identifier: "en_GB")
    return f.string(from: date)
}
