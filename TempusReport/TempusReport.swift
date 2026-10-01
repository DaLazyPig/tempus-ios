// Per-app screen time, measured by iOS.
//
// This is the `DeviceActivityReport` extension the flight log's two screen-time cards draw
// through. The numbers never leave this process: iOS hands the usage data to `makeConfiguration`
// here, the view below is rendered here, and the app only ever sees pixels. That is the whole
// reason the projection is computed in this file rather than in `MockData` — the app cannot be
// told the total, so the card that quotes it has to be drawn by the process that knows it.
//
// The extension cannot see the app's theme, so the handful of tokens it needs are restated
// here, the same way `TempusActivity` does. They are the same values as Theme/Colors.swift and
// Theme/Typography.swift, and the row layout is the one `AnalyticsScreen` used to draw itself.
import DeviceActivity
import ManagedSettings
import SwiftUI

@main
struct TempusReport: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        ScreenTimeScene { ScreenTimeRows(report: $0) }
        ProjectionScene { ProjectionFigure(report: $0) }
    }
}

// MARK: - The data

struct AppRow: Identifiable {
    let id: String
    let name: String
    var seconds: TimeInterval
    let token: ApplicationToken?
}

struct Report {
    /// The five most-used apps in the window, most used first. Tempus itself is left out — time
    /// spent flying is the opposite of what this card measures.
    var apps: [AppRow]
    /// Days in the window, so a per-day figure divides by the window and not by the days that
    /// happened to have usage.
    var days: Int
    var totalSeconds: TimeInterval

    var perDayMinutes: Double { totalSeconds / 60 / Double(max(1, days)) }
    /// Counted minutes per day, extrapolated over the horizon set in Settings (60 years until one
    /// is set — the years a 19-year-old can expect to keep using a phone). Deliberately
    /// conservative — no compounding. Same arithmetic as `MockData.projection`. Read from the App
    /// Group because a report view takes no arguments; before it did, Settings' row was a dead
    /// control and the figure always said 60.
    var horizonYears: Int { SharedStore.shared.horizon }
    var daysOfLife: Double { perDayMinutes * 365.25 * Double(horizonYears) / 1440 }
    var years: Double { daysOfLife / 365.25 }
    var maxSeconds: TimeInterval { max(1, apps.map(\.seconds).max() ?? 1) }
}

/// One pass over the results, shared by both scenes.
private func summarise(_ data: DeviceActivityResults<DeviceActivityData>) async -> Report {
    let own = "com.crescerestudios.tempus"
    let cal = Calendar.current
    var rows: [String: AppRow] = [:]
    var days = Set<Date>()
    var earliest = Date.distantFuture, latest = Date.distantPast
    var total: TimeInterval = 0
    for await d in data {
        for await seg in d.activitySegments {
            days.insert(cal.startOfDay(for: seg.dateInterval.start))
            earliest = min(earliest, seg.dateInterval.start)
            latest = max(latest, seg.dateInterval.end)
            for await cat in seg.categories {
                for await app in cat.applications {
                    let name = app.application.localizedDisplayName
                    let id = app.application.bundleIdentifier ?? name ?? "app"
                    if id == own { continue }
                    let t = app.totalActivityDuration
                    if var row = rows[id] {
                        row.seconds += t
                        rows[id] = row
                    } else {
                        rows[id] = AppRow(id: id, name: name ?? id, seconds: t,
                                          token: app.application.token)
                    }
                    total += t
                }
            }
        }
    }
    // Divide by the window the app asked for (written to the App Group by the flight log), not
    // by the days that happened to have usage: Screen Time switched on yesterday must not make
    // two days of usage look like the steady state. The segment count and span are the fallback
    // for a report drawn before the app has ever written a window.
    let span = latest > earliest ? Int((latest.timeIntervalSince(earliest) / 86400).rounded()) : 0
    let window = SharedStore.shared.reportDays
    let top = rows.values.sorted { $0.seconds > $1.seconds }.prefix(5)
    return Report(apps: Array(top), days: window > 0 ? window : max(1, days.count, span),
                  totalSeconds: total)
}

struct ScreenTimeScene: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .init(rawValue: "screenTime")
    let content: (Report) -> ScreenTimeRows
    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> Report {
        await summarise(data)
    }
}

struct ProjectionScene: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .init(rawValue: "projection")
    let content: (Report) -> ProjectionFigure
    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> Report {
        await summarise(data)
    }
}

// MARK: - The views

private enum T {
    static let navy700 = Color(red: 0x23 / 255, green: 0x39 / 255, blue: 0x5b / 255)
    static let steel400 = Color(red: 0x8e / 255, green: 0xa2 / 255, blue: 0xbf / 255)
    static let sky100 = Color(red: 0xe4 / 255, green: 0xeb / 255, blue: 0xf5 / 255)
    static let cloud100 = Color(red: 0xf2 / 255, green: 0xf5 / 255, blue: 0xfa / 255)
    static let diverted = Color(red: 0xa8 / 255, green: 0x49 / 255, blue: 0x3c / 255)
    static let onDarkMuted = Color(red: 0x9f / 255, green: 0xb3 / 255, blue: 0xd1 / 255)
    static func core(_ weight: String, _ size: CGFloat) -> Font { .custom("Outfit-\(weight)", size: size) }
}

/// The body of the "Screen time" card: five rows of app, minutes a day, and a bar against the
/// most-used app. The card's chrome and title are drawn by the app around this.
struct ScreenTimeRows: View {
    let report: Report

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if report.apps.isEmpty {
                Text("Nothing measured in this window yet.")
                    .font(T.core("Regular", 14))
                    .foregroundStyle(T.steel400)
            }
            ForEach(report.apps) { a in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(a.name)
                            .font(T.core("Medium", 16))
                            .foregroundStyle(T.navy700)
                            .lineLimit(1)
                        Spacer()
                        Text("\(Int((a.seconds / 60 / Double(max(1, report.days))).rounded())) min")
                            .font(T.core("Medium", 14))
                            .foregroundStyle(T.steel400)
                    }
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(T.sky100)
                            .overlay(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(T.diverted)
                                    .frame(width: geo.size.width * a.seconds / report.maxSeconds)
                            }
                    }
                    .frame(height: 6)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// The figure and the sentence of the "At this rate" card, on the card's own dark ground.
struct ProjectionFigure: View {
    let report: Report

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .lastTextBaseline, spacing: 10) {
                Text(String(format: "%.1f", report.years))
                    .font(T.core("Bold", 76))
                    .tracking(-0.06 * 76)
                    .foregroundStyle(T.cloud100)
                Text("years")
                    .font(T.core("SemiBold", 22))
                    .foregroundStyle(T.onDarkMuted)
            }
            Text("\(Int(report.perDayMinutes.rounded())) minutes a day over the next \(report.horizonYears) years is \(Int(report.daysOfLife.rounded()).formatted(.number.locale(Locale(identifier: "en_US")))) whole days behind a screen.")
                .font(T.core("Regular", 16))
                .lineSpacing(8)
                .foregroundStyle(T.onDarkMuted)
                .padding(.top, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
