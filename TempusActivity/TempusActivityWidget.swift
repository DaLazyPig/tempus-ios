// The flight, on the lock screen and in the Dynamic Island.
//
// This is the native counterpart to the bundle's DynamicIsland and LockScreen components.
// Those draw a fake iOS inside a browser so the mechanic can be demonstrated; here iOS
// draws them for real, from one `endsAt` deadline — so the pill, the expanded card, the
// lock-screen banner and the in-app countdown can never disagree.
//
// Deliberately minimal, everywhere: the house mark, the remaining time, and at most one
// identifying line. The compact and minimal presentations carry the house mark on the leading
// edge (it was Opal's padlock until 20 Sep 2026) and a plain clock on the trailing, nothing else. The expanded island and the
// lock-screen banner both
// carry mark + one line + countdown and nothing else — no route, no "LANDS hh:mm", no
// second caption line under a button. The lock screen is white, not navy (see the retint
// below), and both lock-screen cards are one `Link` each, so tapping the banner opens the
// same screen a Dynamic Island tap-through would.
import SwiftUI
import WidgetKit
import ActivityKit

// The extension is its own target and cannot see the app's theme, so the handful of
// tokens it needs are restated here. They are the same values as Theme/Colors.swift.
private enum A {
    static let copper = Color(red: 0xB8 / 255, green: 0x6F / 255, blue: 0x52 / 255)
    static let cloud = Color(red: 0xF2 / 255, green: 0xF5 / 255, blue: 0xFA / 255)
    static let navy900 = Color(red: 0x10 / 255, green: 0x1D / 255, blue: 0x31 / 255)
    static let statusOnTime = Color(red: 0x3F / 255, green: 0x7A / 255, blue: 0x63 / 255)

    /// Outfit, the interface face — the same type the app itself sets, so a card on the lock
    /// screen and the countdown inside the app are unmistakably the same product. The extension
    /// cannot see `TFont`, so it names the PostScript faces directly (`Tempus/Fonts/FONTS.md`);
    /// the `.ttf`s reach this bundle through `TempusActivity`'s membership exceptions in
    /// project.pbxproj, which is exactly how `TempusReport` already does it.
    ///
    /// **A missing font does not throw — it silently becomes Helvetica.** The app's
    /// `fontSelfCheck` cannot see this target, so the only check here is the eye: if the clock
    /// stops looking like the one on the flight screen, the plist or the membership is wrong.
    static func core(_ weight: String, _ size: CGFloat) -> Font { .custom("Outfit-\(weight)", size: size) }

    /// The one inset every expanded-island region sits inside, so the mark, the clock, the
    /// subject and the action pill all line up on the same two verticals. Stated once: three
    /// regions hand-padded to three different numbers is how the expanded card came to look
    /// like four things that had never met.
    static let islandPad: CGFloat = 6

    /// The compact pill's own inset, measured from the pill's edge to the *ink* — the ring on
    /// one end, the last digit on the other. See `IslandMark.leading`.
    static let compactPad: CGFloat = 4
    /// The same inset, less the right side bearing Outfit's digits carry: a 4 here measured 15.3pt
    /// of gap against the mark's 12.7, because the glyph box ends ~2.5pt past the last stroke.
    /// The number that matters is the one on screen, so this is the one that gets corrected.
    static let compactClockPad: CGFloat = 1.5
}

/// mm:ss, counting itself down so the widget stays live between pushes.
private struct Countdown: View {
    let endsAt: Date
    var size: CGFloat = 15
    /// An Outfit PostScript weight — "Regular", "SemiBold" or "Bold". A `Font.Weight` would be
    /// ignored: a custom face has no weight axis to ask for, only the file that was registered.
    var weight: String = "SemiBold"
    var color: Color = A.cloud
    /// Occupies only the width of the string being shown *now*, with the live glyphs flush
    /// inside it — so a clock in a row measures like any other view and the inset beside it is
    /// the inset you wrote. Wanted on every surface that puts the clock against an edge: the
    /// compact pill, both expanded islands and both lock-screen cards. See `body` for why
    /// a plain `Text(timerInterval:)` cannot be aligned.
    var tight: Bool = false

    var body: some View {
        // showsHours: false — the dial goes to 240 minutes (unlocks to 300), and the flight
        // screen counts those as uncapped mm:ss. Left to itself the widget switches to
        // H:MM:SS the moment an hour is left, so the two surfaces would disagree on the same
        // flight, and H:MM:SS is also the wider of the two strings.
        //
        // **No `pauseTime`.** This carried `pauseTime: endsAt` for a while, on the theory that it
        // would stop the count at zero. It did something else: with a pause date set, the system
        // draws the timer as a *static string* and only repaints it when it re-renders the
        // activity — every nine seconds or so on a phone — so the island and the lock screen sat
        // on one value and jumped. Measured in the simulator on 18 Sep 2026: frozen on 4:57 with
        // it, ticking 4:51 → 4:44 without it. The closed range already clamps the count at 0:00
        // and holds there, so nothing is lost by leaving it off. Do not put it back.
        let clock = Text(timerInterval: Date()...max(endsAt, Date().addingTimeInterval(1)),
                         countsDown: true, showsHours: false)
            .font(font)
            .monospacedDigit()
            .foregroundStyle(color)
        if tight {
            // `Text(timerInterval:)` lays itself out at the width of the *widest* string it could
            // ever show ("299:59"), not the one it is showing — so the compact pill grew to fit
            // six glyphs while displaying "9:41", and the island read as a wide bar with a small
            // clock and a gap in it. A fixed frame was the first answer and still left the gap:
            // 38pt holds "299:59", and a 50-minute flight shows five glyphs in it. So the frame
            // is the string being shown *now*: a hidden Text of the current mm:ss sizes the slot,
            // and the ticking clock is laid over it. The count only ever gets shorter from here,
            // so the slot stays tight for the whole activity; the scale factor covers the one
            // frame where a state push and the tick disagree by a glyph. The hidden Text carries
            // the same font as the clock, or the slot measures the wrong string's width.
            //
            // **Do not swap the overlay for `.leading` + `.fixedSize()`.** It reads as the tidier
            // way to pin the glyphs, and in a widget it renders *nothing at all* — measured on a
            // 17 Pro on 22 Sep 2026: the compact pill came back with the mark and an empty
            // trailing half. The slot is already tight; the digits are already flush in it.
            Text(Self.shown(endsAt))
                .font(font)
                .monospacedDigit()
                .hidden()
                .overlay(alignment: .trailing) {
                    clock.lineLimit(1).minimumScaleFactor(0.6)
                }
        } else {
            clock
        }
    }

    private var font: Font { A.core(weight, size) }

    /// What the timer reads at this render — the same m:ss the system draws for `showsHours: false`.
    private static func shown(_ endsAt: Date) -> String {
        let s = max(0, Int(endsAt.timeIntervalSinceNow.rounded()))
        return "\(s / 60):" + String(format: "%02d", s % 60)
    }
}

/// The compact island's glyph: the house mark, not a padlock. Asked for on 20 Sep 2026 — the
/// island is the one place the app is seen without its name, so it carries the mark. A flight
/// and an unlock share it; the keyline tint (copper / green) is what tells the two apart.
///
/// **Symmetric padding, and a mark that fits its own frame.** This carried `.padding(.leading, 3)`
/// for a while, to even the mark against the trailing clock's glyph side bearing. It did the
/// opposite: `WidgetCarrierMarkView` used to declare a frame the size of the mark's *path* box
/// while `stroke` inks half a line width outside it on every side, and the island clips a compact
/// region to the frame it is given — so a one-sided pad handed the left overflow room and left the
/// right overflow to be shaved. The ring is now measured by its ink (see `inkSize`) and the pad is
/// even, which is what actually centres it in the region.
private struct IslandMark: View {
    /// The compact pill's leading inset. `minimal` is a small circle and wants the mark dead
    /// centre in it (2/2); the compact pill has a rounded end on this side and a clock against
    /// the other, and the two insets have to read as one.
    ///
    /// **Measured, not eyeballed** (17 Pro, 22 Sep 2026): the system's own inset is ~8.7pt each
    /// side, so `2` here and `5` on the clock drew 10.7pt of gap on the left against 16.3pt on
    /// the right — the "move it in / less on the right" in the report. Both are `A.compactPad`
    /// now, and the gap is the same at four glyphs and at six, because `Countdown.tight` already
    /// sizes the clock's slot to the string being shown.
    var leading: CGFloat = 2

    var body: some View {
        WidgetCarrierMarkView(color: .white, height: 17)
            .padding(.leading, leading)
            .padding(.trailing, 2)
    }
}

/// The expanded island's one headline row: what the flight is for, and how long is left.
///
/// **Both halves live in `.bottom`, not in the two regions beside the camera.** Those are each
/// about a third of the island wide, and a subject put in one of them cannot be made bigger —
/// `minimumScaleFactor` simply scales it back down to the region. Asking for 22pt there drew the
/// same size as 19pt (measured, 16 Plus, 22 Sep 2026). `.bottom` is the full width, so the type
/// can be as large as it reads best at and the clock still has room beside it.
///
/// And in one `HStack` the two share a real `.firstTextBaseline`, which is the only way they
/// actually sit on a line together: stacked in separate regions they were centred *as boxes*, and
/// a box of digits has no descenders while "Organic chemistry" does, so the subject hung ~5pt low.
private struct ExpandedHeadline<Clock: View>: View {
    let text: String
    @ViewBuilder let clock: Clock

    init(_ text: String, @ViewBuilder clock: () -> Clock) {
        self.text = text
        self.clock = clock()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(text)
                .font(A.core("SemiBold", 24))
                .foregroundStyle(A.cloud)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Spacer(minLength: 8)
            clock
        }
    }
}

struct TempusActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FlightActivityAttributes.self) { context in
            lockScreen(context)
        } dynamicIsland: { context in
            DynamicIsland {
                // **The sensor row carries the two facts, and nothing decorative.** The leading
                // and trailing regions are each about a third of the expanded island, so the
                // mark, a 15pt subject *and* a 30pt clock laid across them left the subject
                // truncating after a word and the clock clipped against the cutout — the "out of
                // order and shape" in the report. The mark is gone (asked for on 22 Sep 2026 —
                // the island is already the app's, and the compact pill still carries it), and
                // the subject takes the space it leaves, opposite the clock. Only the action is
                // left for `.bottom`, the one full-width region. Every row sits on the same
                // `A.islandPad`, so the subject, the clock and the pill share two verticals.
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 12) {
                        ExpandedHeadline(context.attributes.subject) {
                            Countdown(endsAt: context.state.endsAt, size: 26, weight: "Bold",
                                      color: .white, tight: true)
                        }
                        // The only action worth a tap from here: extending is one tap and changes
                        // nothing else. Ending a flight needs a hold (900ms, 10s in business
                        // class — and business class has none of this button at all), which an
                        // island control cannot do, so that action lives behind the tap-through
                        // to the flight screen (`.widgetURL` below) rather than a second pill here.
                        if !context.attributes.businessClass {
                            Link(destination: URL(string: "tempus://extend")!) {
                                Text("+5 min · \(context.attributes.extendMiles) mi")
                                    .font(A.core("SemiBold", 14))
                                    .foregroundStyle(A.cloud)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(A.cloud.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(.horizontal, A.islandPad)
                }
            } compactLeading: {
                IslandMark(leading: A.compactPad)
            } compactTrailing: {
                // `tight` pulls the glyphs onto the slot's trailing edge (see `Countdown.tight`),
                // which is what puts them hard against the capsule's rounded end — so the clock
                // needs the pad the mark gets on the other side, or it reads as falling off.
                Countdown(endsAt: context.state.endsAt, size: 15, weight: "Regular", color: .white, tight: true)
                    .padding(.trailing, A.compactClockPad)
            } minimal: {
                IslandMark()
            }
            .widgetURL(URL(string: "tempus://flight"))
            .keylineTint(A.copper)
        }
    }

    /// The lock-screen banner: the mark, the subject as the one identifying line, and the
    /// countdown — nothing else. Tapping it opens the flight, same as the island.
    ///
    /// **Mark leading, label centred, clock hard right.** The label takes
    /// `frame(maxWidth: .infinity)` rather than sitting behind a `Spacer`, so it centres in
    /// whatever the mark and the clock leave rather than being shoved against the mark; and the
    /// clock is `tight`, which is the only thing that actually puts its glyphs on the right edge
    /// (see `Countdown.tight` — trailing alignment alone moves the box, not the digits).
    private func lockScreen(_ context: ActivityViewContext<FlightActivityAttributes>) -> some View {
        Link(destination: URL(string: "tempus://flight")!) {
            HStack(spacing: 12) {
                WidgetCarrierMarkView(color: A.navy900, height: 30)
                Text(context.attributes.subject)
                    .font(A.core("SemiBold", 17))
                    .foregroundStyle(A.navy900)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                Countdown(endsAt: context.state.endsAt, size: 34, weight: "Bold",
                          color: A.navy900, tight: true)
            }
        }
        .padding(EdgeInsets(top: 18, leading: 20, bottom: 18, trailing: 20))
        .activityBackgroundTint(.white)
        .activitySystemActionForegroundColor(A.navy900)
    }
}

/// Bought screen time, counting down to the moment the shield goes back up.
///
/// Deliberately quieter than the flight's. A flight is a commitment with stakes and two things you
/// can do about it; an unlock is a purchase already made, and the only fact it carries is how much
/// of it is left. So: an open padlock and a clock compact, one line expanded, and no buttons. There is no
/// "lock now" — ending an unlock early forfeits the miles it cost, which is not a one-tap action
/// on a lock screen. Tapping through opens Redeem, where more time can be bought.
struct TempusUnlockActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: UnlockActivityAttributes.self) { context in
            unlockLockScreen(context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Same two regions as the flight's, for the same reasons — see there. No
                // `.bottom` at all: an unlock has no action worth a tap (ending one early
                // forfeits the miles it cost), so the card is the two facts and stops.
                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedHeadline(context.attributes.name) {
                        Countdown(endsAt: context.state.until, size: 26, weight: "Bold",
                                  color: .white, tight: true)
                    }
                    .padding(.horizontal, A.islandPad)
                }
            } compactLeading: {
                IslandMark(leading: A.compactPad)
            } compactTrailing: {
                Countdown(endsAt: context.state.until, size: 15, weight: "Regular", color: .white, tight: true)
                    .padding(.trailing, A.compactClockPad)
            } minimal: {
                IslandMark()
            }
            .widgetURL(URL(string: "tempus://withdraw"))
            .keylineTint(A.statusOnTime)
        }
    }

    /// The mark (tinted the same green as the in-app "open" state), what is open, and the
    /// countdown. Tapping it opens Redeem, same as the island. Same three-part shape as the
    /// flight's card above, for the same reasons — the two are read in the same glance.
    ///
    /// **"Apps unlocked", not `attributes.name`.** A shield is one shield over the whole
    /// selection, so the card is not naming a thing that could have been unlocked on its own;
    /// `name` ("Instagram", or "Your selection") said more than the fact warrants at a glance on
    /// a locked screen. It stays in the payload and stays on the expanded island, where there is
    /// room to be specific.
    private func unlockLockScreen(_ context: ActivityViewContext<UnlockActivityAttributes>) -> some View {
        Link(destination: URL(string: "tempus://withdraw")!) {
            HStack(spacing: 12) {
                WidgetCarrierMarkView(color: A.statusOnTime, height: 30)
                Text("Apps unlocked")
                    .font(A.core("SemiBold", 17))
                    .foregroundStyle(A.navy900)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                Countdown(endsAt: context.state.until, size: 34, weight: "Bold",
                          color: A.navy900, tight: true)
            }
        }
        .padding(EdgeInsets(top: 18, leading: 20, bottom: 18, trailing: 20))
        .activityBackgroundTint(.white)
        .activitySystemActionForegroundColor(A.navy900)
    }
}

@main
struct TempusActivityBundle: WidgetBundle {
    var body: some Widget {
        TempusActivityWidget()
        TempusUnlockActivityWidget()
    }
}
