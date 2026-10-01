import DeviceActivity
import SwiftUI

/// The flight log — every chart the study history supports, paywalled behind Business Class.
///
/// **The flying half is real.** Hours, completion, the streak, Subjects and When you fly all
/// aggregate `AppModel.flights`, so a member who has flown three flights sees three flights. It
/// used to read `MockData`'s seeded twelve weeks, which meant a paid screen told the reader that
/// Thursday evenings were their strongest stretch on the strength of a PRNG.
///
/// **The screen-time half is measured.** Per-app usage and the projection built on it are drawn
/// by `TempusReport`, the `DeviceActivityReport` extension: iOS hands the usage to that process and
/// this screen only ever receives pixels, so the two cards embed a report view with a fixed height
/// and the figure is computed where the numbers live. The closing projection states a number and
/// stops — it does not moralise. The simulator renders no report at all, so both cards are blank
/// there; a phone with Screen Time connected fills them.
struct AnalyticsScreen: View {
    @Environment(AppModel.self) private var model

    @State private var weeks = 4
    @State private var subject: String?
    @State private var cache = DerivedCache()

    var body: some View {
        if !model.plus {
            LogLocked(onBack: { model.go(.home, .lift, dir: -1) }, onPlan: { model.paywall = .open })
        } else {
            unlocked
        }
    }

    // MARK: - Derived

    /// Six aggregations over 84 days of seeded history, computed together and memoised on the only
    /// four things that can change them.
    ///
    /// They used to be six computed properties reading `MockData` directly, which meant every one
    /// of them re-aggregated the whole history on every `body` evaluation — and several are read
    /// more than once per pass (`peakDay` and `maxDow` both want `dow`, `focus` and `maxSubject`
    /// both want `subjects`), so a single pass re-scanned the history a dozen times. This screen
    /// scrolls and animates its bars, so that pass runs at the display's refresh rate.
    ///
    /// The cache is a plain class rather than `@State`: filling it must not invalidate the view
    /// that is in the middle of reading it.
    private struct Derived {
        let totals: MockData.Totals
        let subjects: [MockData.SubjectTotal]
        let dow: [MockData.DowTotal]
        let blocks: [MockData.Block]
    }

    private final class DerivedCache {
        var key = ""
        var value: Derived?
    }

    private var derived: Derived {
        let flights = model.flights
        let key = "\(weeks)|\(subject ?? "-")|\(flights.count)"
        if cache.key == key, let value = cache.value { return value }
        let built = Derived(
            totals: MockData.Real.totals(flights, weeks: weeks),
            subjects: MockData.Real.bySubject(flights, weeks: weeks),
            dow: MockData.Real.byDow(flights, weeks: weeks, subject: subject),
            blocks: MockData.Real.byBlock(flights, weeks: weeks, subject: subject)
        )
        cache.key = key
        cache.value = built
        return built
    }

    private var totals: MockData.Totals { derived.totals }
    private var subjects: [MockData.SubjectTotal] { derived.subjects }
    private var dow: [MockData.DowTotal] { derived.dow }
    private var blocks: [MockData.Block] { derived.blocks }
    private var peakBlock: MockData.Block { blocks.max { $0.minutes < $1.minutes } ?? blocks[0] }
    private var peakDay: MockData.DowTotal { dow.max { $0.minutes < $1.minutes } ?? dow[0] }
    private var maxDow: Int { max(1, dow.map(\.minutes).max() ?? 0) }
    private var maxSubject: Int { max(1, subjects.map(\.minutes).max() ?? 0) }
    private var focus: MockData.SubjectTotal? { subject.flatMap { id in subjects.first { $0.id == id } } }

    private func fmtH(_ min: Int) -> String {
        let h = min / 60, m = min % 60
        if h > 0 { return m > 0 ? "\(h)h \(m)m" : "\(h)h" }
        return "\(m)m"
    }

    // MARK: - Unlocked body

    private var unlocked: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ORise(i: 0) { closeButton.padding(.top, 16) }
                Rise(i: 1) {
                    Text("Flight log")
                        .font(TFont.core(.bold, 40))
                        .tracking(-0.05 * 40)
                        .foregroundStyle(TColor.textPrimary)
                        .padding(.top, 18)
                }
                Rise(i: 1) { headline.padding(.top, 22) }
                Rise(i: 2) { WeekRangeTabs(weeks: $weeks).padding(.top, 22) }
                    // The extension divides by the window, not by the days that had usage, and
                    // the window is only known here.
                    .onChange(of: weeks, initial: true) { SharedStore.shared.write(reportDays: 7 * weeks) }
                // Nothing flown in the window is a fact about the window, not an error. The
                // charts would otherwise draw a row of empty bars and a peak day picked out of a
                // seven-way tie.
                if totals.flights == 0 {
                    Rise(i: 3) { emptyCard.padding(.top, 14) }
                } else {
                    Rise(i: 3) { subjectsCard.padding(.top, 14) }
                    Rise(i: 4) { whenYouFlyCard.padding(.top, 14) }
                }
                Rise(i: 5) { screenTimeCard.padding(.top, 14) }
                Rise(i: 6) { atThisRateCard.padding(.top, 14) }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 60)
        }
    }

    private var closeButton: some View {
        IconButton(tone: .sunken, size: .md, label: "Back", action: {
            model.go(.home, .lift, dir: -1)
        }) {
            Image(systemName: "xmark").font(.system(size: 20, weight: .regular))
        }
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .lastTextBaseline, spacing: 9) {
                AnalyticsPopNumber(key: "\(weeks)-\(totals.minutes)", value: Int((Double(totals.minutes) / 60).rounded()))
                Text("hours flown")
                    .font(TFont.core(.semibold, 22))
                    .foregroundStyle(TColor.textMuted)
            }
            HStack(spacing: 22) {
                Text("\(totals.completion)% completed")
                Text("\(MockData.Real.streak(model.flights)) day streak")
            }
            .font(TFont.core(.regular, 14))
            .foregroundStyle(TColor.textSecondary)
            .padding(.top, 14)
        }
    }

    private var emptyCard: some View {
        AnalyticsCard(title: "Subjects") {
            Text(model.flights.isEmpty
                 ? "No flights yet. Everything here fills in as you fly."
                 : "Nothing flown in this range. Try a longer one.")
                .font(TFont.core(.regular, 16))
                .tpType(size: 16, lineHeight: 1.5)
                .foregroundStyle(TColor.textSecondary)
                .padding(.top, 16)
        }
    }

    // MARK: - Subjects

    private var subjectsCard: some View {
        AnalyticsCard(title: "Subjects") {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(subjects) { s in
                    let on = subject == s.id
                    Button {
                        subject = on ? nil : s.id
                    } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(s.title)
                                    .font(TFont.core(.medium, 16))
                                    .foregroundStyle(TColor.textPrimary)
                                Spacer()
                                Text(fmtH(s.minutes))
                                    .font(TFont.core(.semibold, 15))
                                    .foregroundStyle(on ? TColor.textAccent : TColor.textPrimary)
                            }
                            GeometryReader { geo in
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(TColor.surfaceSunken)
                                    .overlay(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                                            .fill(on ? TColor.surfaceAccent : TColor.sky400)
                                            .frame(width: geo.size.width * CGFloat(s.minutes) / CGFloat(maxSubject))
                                            .animation(.glide(0.56), value: s.minutes)
                                    }
                            }
                            .frame(height: 6)
                        }
                    }
                    .buttonStyle(.plain)
                    .opacity(subject != nil && !on ? 0.45 : 1)
                    .animation(.glide(0.3), value: subject)
                }
            }
            .padding(.top, 20)
        }
    }

    // MARK: - When you fly

    private var whenYouFlyCard: some View {
        AnalyticsCard(title: "When you fly", note: focus?.title) {
            Text("\(peakDay.label) \(peakBlock.label.lowercased())s are your strongest stretch.")
                .font(TFont.core(.regular, 16))
                .tpType(size: 16, lineHeight: 1.5)
                .foregroundStyle(TColor.textSecondary)
                .padding(.top, 14)

            HStack(alignment: .bottom, spacing: 7) {
                ForEach(dow) { d in
                    let on = d.dow == peakDay.dow
                    VStack(spacing: 9) {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(on ? TColor.surfaceAccent : TColor.sky300)
                            .frame(height: max(3, CGFloat(d.minutes) / CGFloat(maxDow) * 72))
                            .animation(.glide(0.52), value: d.minutes)
                        Text(String(d.label.prefix(1)))
                            .font(TFont.data(.medium, 11))
                            .tracking(0.08 * 11)
                            .foregroundStyle(on ? TColor.textAccent : TColor.textMuted)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 96, alignment: .bottom)
            .padding(.top, 22)
        }
    }

    // MARK: - Screen time

    /// The window the report is asked for: the same weeks the tabs select, in whole days, on this
    /// phone only. `.daily` segments are what let the extension divide by days.
    ///
    /// Day-aligned at both ends, so the value is the same for every body this day: a filter ending
    /// at `Date()` was a new filter on every re-evaluation (a tab, any model change, the entrance
    /// settling), and each one re-asked the extension for the whole window — two cards, two
    /// windows a few microseconds apart, both blank while the answer came.
    private var reportFilter: DeviceActivityFilter {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let end = cal.date(byAdding: .day, value: 1, to: today) ?? today
        let start = cal.date(byAdding: .day, value: -7 * weeks, to: today) ?? today
        return DeviceActivityFilter(segment: .daily(during: DateInterval(start: start, end: end)),
                                    users: .all, devices: .init([.iPhone]))
    }

    /// `screenTimeAuthorized` is a live `AuthorizationCenter` read, not observed state, so a
    /// grant made from this screen changed nothing the body depends on. Bumped after the request
    /// so the cards re-read it.
    @State private var authTick = 0

    /// Five rows of 16 + 10 + 6, with 16 between — the rows the extension draws, at the height
    /// they take. A report view has no intrinsic size, so the card has to know it.
    private static let rowsHeight: CGFloat = 5 * 36 + 4 * 16
    private static let figureHeight: CGFloat = 176

    private var screenTimeCard: some View {
        AnalyticsCard(title: "Screen time") {
            if model.screenTimeAuthorized {
                DeviceActivityReport(.init(rawValue: "screenTime"), filter: reportFilter)
                    .frame(height: Self.rowsHeight)
                    .padding(.top, 20)
            } else {
                connectNote
            }
        }
    }

    /// Screen Time is not connected, so there is nothing to measure — and the card says so
    /// rather than drawing a sample. Same offer as Redeem's footer line: it asks.
    private var connectNote: some View {
        Button {
            Task {
                await model.requestScreenTimeAuthorization()
                // Same chain as Redeem's footer: a grant raises the shield now, not at the next
                // foreground.
                model.reconcileBlocking()
                authTick += 1
            }
        } label: {
            Text("CONNECT SCREEN TIME TO MEASURE THIS")
                .tpLabelStyle()
                .foregroundStyle(TColor.textAccent)
                .frame(maxWidth: .infinity)
                .padding(.top, 20)
        }
        .buttonStyle(.plain)
    }

    // MARK: - At this rate

    private var atThisRateCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("At this rate")
                .tpLabelStyle()
                .foregroundStyle(TColor.textOnDarkMuted)
            if model.screenTimeAuthorized {
                DeviceActivityReport(.init(rawValue: "projection"), filter: reportFilter)
                    .frame(height: Self.figureHeight)
                    .padding(.top, 16)
            } else {
                Text("Connect Screen Time and this card states where the minutes go.")
                    .font(TFont.core(.regular, 16))
                    .tpType(size: 16, lineHeight: 1.5)
                    .foregroundStyle(TColor.textOnDarkMuted)
                    .padding(.top, 16)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 28)
        .background(TColor.surfaceInverse, in: RoundedRectangle(cornerRadius: TRadius.xl, style: .continuous))
        .tpShadow(.raised)
    }
}

// MARK: - Locked cover

/// Free accounts see the shape of the data, never the numbers.
private struct LogLocked: View {
    let onBack: () -> Void
    let onPlan: () -> Void

    private static let barHeights: [CGFloat] = [38, 64, 49, 86, 58, 103, 72, 95, 61, 110, 80, 124]

    var body: some View {
        VStack(spacing: 0) {
            ORise(i: 0) {
                IconButton(tone: .sunken, size: .md, label: "Back", action: onBack) {
                    Image(systemName: "xmark").font(.system(size: 20, weight: .regular))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 16)
            }
            Rise(i: 1) {
                Text("Flight log")
                    .font(TFont.core(.bold, 40))
                    .tracking(-0.05 * 40)
                    .foregroundStyle(TColor.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 18)
            }

            Spacer(minLength: 0)

            Rise(i: 1) {
                HStack(alignment: .bottom, spacing: 7) {
                    ForEach(Array(Self.barHeights.enumerated()), id: \.offset) { i, h in
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(i == 11 ? TColor.copper300 : TColor.sky300)
                            .frame(height: h)
                    }
                }
                .frame(height: 118)
                .padding(.horizontal, 4)
                .opacity(0.5)
                .blur(radius: 1.5)
            }
            Rise(i: 2) {
                VStack(spacing: 0) {
                    HStack(spacing: 7) {
                        Image(systemName: "lock.fill").font(.system(size: 13)).foregroundStyle(TColor.white)
                        Text("Business Class").tpLabelStyle().foregroundStyle(TColor.white)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(TColor.surfaceAccent, in: Capsule())

                    Text("Every flight you have ever taken")
                        .font(TFont.core(.bold, 32))
                        .tracking(-0.04 * 32)
                        .tpType(size: 32, lineHeight: 1.14)
                        .foregroundStyle(TColor.textPrimary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 20)

                    Text("Twelve weeks of history, the hours behind each subject, and what your screen time adds up to over a lifetime.")
                        .font(TFont.core(.regular, 16))
                        .tpType(size: 16, lineHeight: 1.5)
                        .foregroundStyle(TColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 14)
                }
                .padding(.horizontal, 14)
                .padding(.top, 38)
            }

            Spacer(minLength: 0)

            Rise(i: 3) {
                TButton("Unlock the log", variant: .primary, size: .lg, fullWidth: true, action: onPlan)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 44)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Card shell

/// The reusable analytics card: an uppercase title, an optional accent-coloured note, whatever the
/// caller draws under it.
private struct AnalyticsCard<Content: View>: View {
    let title: String
    var note: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).tpLabelStyle().foregroundStyle(TColor.textMuted)
                Spacer()
                if let note {
                    Text(note)
                        .font(TFont.core(.medium, 13))
                        .foregroundStyle(TColor.textAccent)
                }
            }
            content()
        }
        .padding(.horizontal, 22)
        .padding(.top, 24)
        .padding(.bottom, 22)
        .background(TColor.surfaceCard, in: RoundedRectangle(cornerRadius: TRadius.xl, style: .continuous))
        .tpShadow(.card)
    }
}

// MARK: - Week range

/// Week / Month / 12 weeks — a dark-filled selected pill, same reasoning as the pass archive's
/// mode tabs: the shared `SegmentedControl`'s active segment is always light, not dark-filled.
private struct WeekRangeTabs: View {
    @Binding var weeks: Int
    private let options: [(w: Int, l: String)] = [(1, "Week"), (4, "Month"), (12, "12 weeks")]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(options, id: \.w) { o in
                let on = o.w == weeks
                Button { weeks = o.w } label: {
                    Text(o.l)
                        .font(TFont.core(.semibold, 13))
                        .foregroundStyle(on ? TColor.cloud100 : TColor.textMuted)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(on ? TColor.surfaceInverse : Color.clear, in: Capsule())
                        // A plain-style button hit-tests its label's painted pixels, and an
                        // unselected segment paints only its glyphs — so "All" and "Month"
                        // took a tap only dead on the letters. The whole capsule is the target.
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(TColor.surfaceSunken, in: Capsule())
        .animation(.glide(TDur.fast), value: weeks)
    }
}

// MARK: - Headline number

/// `tp-pop`: opacity 0→1, scale .86→1, over 420ms glide — replayed every time `key` changes
/// (a week-range switch, or a fresh landing changing the minute total).
private struct AnalyticsPopNumber: View {
    let key: String
    let value: Int
    @State private var shown = false

    var body: some View {
        tpText("\(value)", size: 76, track: -0.06)
            .font(TFont.core(.bold, 76))
            .foregroundStyle(TColor.textPrimary)
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown ? 1 : 0.86)
            .task(id: key) {
                shown = false
                try? await Task.sleep(for: .milliseconds(1))
                withAnimation(.glide(0.42)) { shown = true }
            }
    }
}
