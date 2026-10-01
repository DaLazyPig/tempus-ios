import SwiftUI

/// A consent gate. Two set-pieces, one component, one `kind`: nothing about a locked cabin should
/// be one tap away from either direction.
///
/// The gate rises from the bottom edge with its top corners unrounding while the screen behind it
/// sinks and dims. Confirming sends it out through the top; cancelling retracts it the way it came.
struct GateScreen: View {
    @Environment(AppModel.self) private var model
    let gate: GateState

    @State private var raised = false
    /// The content's own small rise-and-fade, layered on top of the sheet's own slide. One-way:
    /// it plays once on arrival and never resets, because closing has no content animation of its
    /// own in the reference — the rows and buttons just travel with the sheet.
    @State private var contentRaised = false

    private var isExit: Bool { gate.kind == .exit }
    /// Seconds still to fly.
    private var left: Double { max(0, model.total - model.elapsed) }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)

                Text(isExit ? "Emergency exit" : "Business class")
                    .tpLabelStyle()
                    .foregroundStyle(isExit ? TColor.statusDiverted : TColor.textAccent)

                Text(isExit ? "Leave this flight?" : "Business class locks you in")
                    .font(TFont.core(.bold, 38))
                    .tracking(-0.045 * 38)
                    .foregroundStyle(TColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 16)

                if isExit, left > 0 {
                    Text("\(mmss(left)) still to fly.")
                        .font(TFont.core(.regular, TFont.sizeBody))
                        .foregroundStyle(TColor.textSecondary)
                        .padding(.top, 14)
                }

                VStack(alignment: .leading, spacing: 24) {
                    ForEach(rows, id: \.title) { row in
                        GateRow(icon: row.icon, title: row.title, detail: row.detail, warn: isExit)
                    }
                }
                .padding(.top, 36)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentRise(contentRaised)

            VStack(spacing: 8) {
                if isExit {
                    Button {
                        model.confirmGate()
                    } label: {
                        Text("Leave the flight")
                            .font(TFont.core(.semibold, TFont.sizeBody))
                            .foregroundStyle(TColor.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Capsule().fill(TColor.statusDiverted))
                    }
                    TButton("Stay on the flight", variant: .ghost, size: .md, fullWidth: true) {
                        model.cancelGate()
                    }
                } else {
                    TButton("Board in business class", variant: .primary, size: .lg, fullWidth: true) {
                        model.confirmGate()
                    }
                    TButton("Not this flight", variant: .ghost, size: .md, fullWidth: true) {
                        model.cancelGate()
                    }
                }
            }
            .contentRise(contentRaised)
        }
        .padding(.top, 52)
        .padding(.horizontal, 30)
        .padding(.bottom, 34)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TColor.cloud100)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: topRadius,
                bottomLeadingRadius: bottomRadius,
                bottomTrailingRadius: bottomRadius,
                topTrailingRadius: topRadius
            )
        )
        .offset(y: offset)
        // `0 ±30px 90px rgba(0,0,0,.5)` — radius 45 (90/2) is correct as authored, but with no
        // `.compositingGroup()` the shadow was landing on every row's text and button
        // individually instead of the sheet's own silhouette: a 90px-blur halo around each line
        // rather than one clean shadow behind the whole gate. That was the excessive shadow.
        .compositingGroup()
        // Confirming throws the shadow the other way, because the gate is leaving upward.
        .shadow(color: Color.black.opacity(0.5), radius: 45,
                y: gate.closing == .up ? 30 : -30)
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.onboarding(1.25)) { raised = true }
            withAnimation(.onboarding(1.25)) { contentRaised = true }
        }
        .onChange(of: gate.closing) { _, closing in
            guard closing != nil else { return }
            withAnimation(.onboarding(1.2)) { raised = false }
        }
    }

    /// Rising and retracting both travel a full screen height; confirming leaves through the top.
    private var offset: CGFloat {
        guard !raised else { return 0 }
        let h = TStage.bounds.height
        return gate.closing == .up ? -h : h
    }

    private var cornerRadius: CGFloat { raised ? 0 : 240 }
    /// Entering, or retracting back down, rounds the top corners (the sheet is arriving from or
    /// returning to the bottom). Confirming and leaving through the top rounds the bottom corners
    /// instead — the edge that trails as the card lifts away.
    private var isClosingUp: Bool { gate.closing == .up }
    private var topRadius: CGFloat { isClosingUp ? 0 : cornerRadius }
    private var bottomRadius: CGFloat { isClosingUp ? cornerRadius : 0 }

    private struct Row {
        let icon: String
        let title: String
        let detail: String
    }

    private var rows: [Row] {
        if isExit {
            return [
                Row(icon: "airplane", title: "You earn nothing",
                    detail: "The miles for this flight are gone."),
                Row(icon: "exclamationmark.triangle", title: "15 mi comes off",
                    detail: "A penalty, on top of the miles you did not earn."),
                Row(icon: "lock", title: "2 hours off your status",
                    detail: "Two qualifying hours are removed from this period.")
            ]
        }
        return [
            Row(icon: "lock", title: "Tempus stays open",
                detail: "Open another app and it closes straight back to your flight."),
            Row(icon: "airplane", title: "You fly all \(model.minutes) minutes",
                detail: "No landing early. No pausing."),
            Row(icon: "exclamationmark.triangle", title: "Leaving costs you",
                detail: "Hold the X for 10 seconds. You lose this flight\u{2019}s miles, 15 mi, and 2 hours of status.")
        ]
    }

    private func mmss(_ seconds: Double) -> String {
        let m = Int(seconds) / 60, s = Int(seconds) % 60
        return String(format: "%02d:%02d", m, s)
    }
}

/// One consequence, stated once and plainly.
private struct GateRow: View {
    let icon: String
    let title: String
    /// Not `body` — that name belongs to `View`.
    let detail: String
    let warn: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(warn ? TColor.statusDivertedSoft : TColor.copper100)
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(warn ? TColor.statusDiverted : TColor.textAccent)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(TFont.core(.semibold, TFont.sizeBody))
                    .tracking(-0.01 * TFont.sizeBody)
                    .foregroundStyle(TColor.textPrimary)
                Text(detail)
                    .font(TFont.core(.regular, TFont.sizeBodySm))
                    .foregroundStyle(TColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private extension View {
    /// `tp-permct` + `tp-permco` — a second, smaller rise layered on top of the sheet's own
    /// slide: the content climbs 34pt on the same onboarding curve, while its fade only opens up
    /// through the middle half of that same 1250ms window (held at 0 for the first quarter, held
    /// at 1 for the last quarter). Reference has no equivalent while closing — the two content
    /// groups just travel with the sheet, which is why `raised` never resets this.
    func contentRise(_ raised: Bool) -> some View {
        self
            .offset(y: raised ? 0 : 34)
            .animation(.onboarding(1.25), value: raised)
            .opacity(raised ? 1 : 0)
            .animation(.linear(duration: 0.625).delay(0.3125), value: raised)
    }
}
