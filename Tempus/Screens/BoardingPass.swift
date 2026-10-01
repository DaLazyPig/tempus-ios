import SwiftUI

/// The boarding pass, and the tear that departs it.
///
/// The pass is one document in two pieces: a header block that stays behind and a stub that is
/// pulled off. They are separate views so the stub can move under a finger while the header does
/// not, and the perforation between them is drawn on the header's bottom edge — two punch-holes in
/// the screen's own navy, so they read as holes through the paper rather than as dots on it.
///
/// Nothing here decides anything about the flight. Tearing calls `depart`; backing out goes to
/// preflight. The pass only shows what has already been chosen.
struct PassScreen: View {
    @Environment(AppModel.self) private var model

    /// Stub offset in points. 1:1 with the finger to `tearGive`, rubber-banded after it.
    @State private var dy: CGFloat = 0
    /// True only while a finger owns the stub — it suppresses the spring-back transition.
    @State private var dragging = false
    /// The perforation has given way. One-way: nothing untears.
    @State private var torn = false
    /// Guards `fire()` so a flick that satisfies both commit tests still departs once.
    @State private var fired = false
    /// The single downward bob that says the stub pulls.
    @State private var nudge: CGFloat = 0
    /// The whole-pass entrance.
    @State private var issued = false
    /// Measured, because the tear's travel is stated as a percentage of the pass's own height.
    @State private var passHeight: CGFloat = 0
    /// Landing time is live while the pass sits on screen and freezes the instant it is torn.
    @State private var frozenLands: Date?
    @State private var now = Date()

    /// Pointer travel before the paper starts to resist.
    private let tearGive: CGFloat = 72
    /// Travel that commits the tear on distance alone.
    private let tearCommit: CGFloat = 40
    /// Flick speed that commits it regardless of distance, in points per second (0.55 px/ms).
    private let tearFling: CGFloat = 550

    private var destination: Destination { Geography.destination(forMinutes: model.minutes) }
    private var subject: String { model.task?.title ?? "" }

    /// Frozen at the tear, otherwise recomputed off a clock that ticks every 15 seconds.
    private var lands: Date {
        frozenLands ?? now.addingTimeInterval(Double(model.minutes) * 60)
    }

    var body: some View {
        let dest = destination

        VStack(spacing: 0) {
            FloatingPill(label: subject, fading: torn) { model.go(.preflight, .sink) }

            pass(dest: dest)
                .frame(maxHeight: .infinity)
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
        }
        .task {
            // A frame's grace so the pass is painted at its start position before it prints.
            try? await Task.sleep(for: .milliseconds(16))
            withAnimation(.glide(0.64)) { issued = true }
        }
        .task {
            // The hint plays once, and only if the pass has been left alone.
            try? await Task.sleep(for: .milliseconds(1100))
            guard !torn, dy == 0 else { return }
            withAnimation(.glide(0.36)) { nudge = 12 }
            try? await Task.sleep(for: .milliseconds(360))
            withAnimation(.glide(0.54)) { nudge = 0 }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                now = Date()
            }
        }
    }

    // MARK: - The document

    @ViewBuilder
    private func pass(dest: Destination) -> some View {
        VStack(spacing: 0) {
            header(dest: dest).zIndex(2)
            stub(dest: dest).zIndex(1)
        }
        .background {
            GeometryReader { geo in
                Color.clear.preference(key: PassHeightKey.self, value: geo.size.height)
            }
        }
        .onPreferenceChange(PassHeightKey.self) { passHeight = $0 }
        // The tear lifts the whole document away; the stub's own fall composes on top of it.
        .opacity(torn ? 0 : 1)
        .animation(.linear(duration: 0.46).delay(0.15), value: torn)
        .offset(y: torn ? -0.72 * passHeight : 0)
        .rotationEffect(.degrees(torn ? -3 : 0), anchor: .bottom)
        .animation(.exit(0.62).delay(0.09), value: torn)
        // `tp-issue` — the pass prints out.
        .opacity(issued ? 1 : 0)
        .scaleEffect(issued ? 1 : 0.85, anchor: .bottom)
        .offset(y: issued ? 0 : 0.58 * passHeight)
    }

    private func header(dest: Destination) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            band(dest: dest)
                .frame(height: 115)
                .frame(maxWidth: .infinity)
                .clipped()

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(verbatim: Carriers.name)
                        .font(TFont.core(.semibold, 16))
                        .tracking(-0.01 * 16)
                        .foregroundStyle(TColor.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                    Text(verbatim: Carriers.iata)
                        .tpLabelStyle()
                        .foregroundStyle(TColor.textMuted)
                }

                if model.biz {
                    HStack(spacing: 8) {
                        Image(systemName: "lock")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(TColor.copper600)
                        Text("Business class")
                            .tpLabelStyle()
                            .foregroundStyle(TColor.copper600)
                    }
                    .padding(.horizontal, 13)
                    .padding(.vertical, 8)
                    .background(TColor.copper100, in: Capsule())
                    .padding(.top, 14)
                }

                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(verbatim: Geography.home.code)
                        .font(TFont.core(.bold, 34))
                        .tracking(-0.04 * 34)
                        .foregroundStyle(TColor.textPrimary)
                    Spacer(minLength: 8)
                    Text(verbatim: "\u{2192}")
                        .font(TFont.core(.regular, 20))
                        .foregroundStyle(TColor.sky400)
                    Spacer(minLength: 8)
                    Text(verbatim: dest.code)
                        .font(TFont.core(.bold, 34))
                        .tracking(-0.04 * 34)
                        .foregroundStyle(TColor.textPrimary)
                }
                .padding(.top, 22)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Subject")
                        .tpLabelStyle()
                        .foregroundStyle(TColor.textMuted)
                    Text(verbatim: subject)
                        .font(TFont.core(.semibold, 20))
                        .tpType(size: 20, lineHeight: 1.2)
                        .foregroundStyle(TColor.textPrimary)
                }
                .padding(.top, 26)

                HStack(alignment: .top, spacing: 12) {
                    field(label: model.flightNo, value: "\(model.minutes) min", align: .leading)
                    Spacer(minLength: 0)
                    field(label: currentCarrier(to: dest).ac,
                          value: hhmm(lands), align: .center)
                    Spacer(minLength: 0)
                    field(label: "Earns", value: "\(model.earned) mi",
                          align: .trailing, tint: TColor.textAccent)
                }
                .padding(.top, 22)
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
        }
        .frame(maxWidth: .infinity)
        .background(TColor.surfaceCard)
        .clipShape(
            UnevenRoundedRectangle(topLeadingRadius: 24, bottomLeadingRadius: 0,
                                   bottomTrailingRadius: 0, topTrailingRadius: 24)
        )
        .tpShadow(.overlay)
        // The perforation is drawn after the clip, so the punch-holes hang outside the card.
        .overlay(alignment: .bottom) {
            PerforationLine()
                .padding(.horizontal, 22)
                .offset(y: -1)
                .opacity(torn ? 0 : 1)
                .animation(.glide(0.24), value: torn)
        }
        .overlay(alignment: .bottomLeading) { punch.offset(x: -15, y: 15) }
        .overlay(alignment: .bottomTrailing) { punch.offset(x: 15, y: 15) }
    }

    private func stub(dest: Destination) -> some View {
        HStack(spacing: 12) {
            HStack(alignment: .center, spacing: 2) {
                ForEach(Array(Carriers.barcode(seed: model.flightNo).prefix(22).enumerated()),
                        id: \.offset) { _, w in
                    TColor.navy700.frame(width: CGFloat(w), height: 30)
                }
            }
            .frame(width: 118, height: 30, alignment: .leading)
            .clipped()

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Text(dy > tearCommit ? "Release to depart" : "Tear to depart")
                    .tpLabelStyle()
                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .regular))
            }
            .foregroundStyle(dy > tearCommit ? TColor.statusOnTime : TColor.textMuted)
            .animation(.linear(duration: 0.2), value: dy > tearCommit)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity)
        .background(TColor.surfaceCard)
        .clipShape(
            UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 24,
                                   bottomTrailingRadius: 24, topTrailingRadius: 0)
        )
        .tpShadow(.overlay)
        .opacity(torn ? 0 : 1)
        .animation(.linear(duration: 0.42), value: torn)
        // Torn, the stub keeps falling from wherever the finger left it — no keyframe restart, so
        // releasing never snaps the pass back to its start position first.
        .offset(y: torn ? dy + 520 : dy)
        .rotationEffect(.degrees(torn ? 8 : dy * 0.014), anchor: .center)
        .animation(dragging ? nil : .glide(torn ? 0.72 : 0.52),
                   value: TearPhase(dy: dy, torn: torn))
        .offset(y: nudge)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard !torn else { return }
                    dragging = true
                    let raw = max(0, value.translation.height)
                    dy = raw <= tearGive ? raw : tearGive + (raw - tearGive) * 0.38
                }
                .onEnded { value in
                    guard !torn else { return }
                    dragging = false
                    let raw = max(0, value.translation.height)
                    // Distance *or* speed: a short flick tears as surely as a long pull.
                    if raw > tearCommit || value.velocity.height > tearFling {
                        fire(dest: dest)
                    } else {
                        dy = 0
                    }
                }
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tear to depart")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { fire(dest: dest) }
    }

    // MARK: - The band

    /// A bought header takes the band for the flight it was stamped onto; everything else flies the
    /// house livery, drawn fresh from this flight's own code — never `model.operatedBy`, which is
    /// last flight's *frozen* carrier and stays set long after this pass replaces it.
    @ViewBuilder
    private func band(dest: Destination) -> some View {
        if let id = model.passHeader, let header = ShopCatalog.header(id: id) {
            MarkupView(header.inner, background: header.bg,
                       designSize: Carriers.bandSize, width: bandWidth)
        } else {
            CarrierBandView(livery: currentCarrier(to: dest).livery, crop: true)
        }
    }

    /// The pass body is the screen less its 24pt gutters. The markup renderer is sized in points
    /// rather than laid out, so it needs the number rather than the layout.
    ///
    /// **No `screenMax` clamp.** This read `min(width, TSpace.screenMax) - 48`, which is exact on
    /// anything up to a 17 Pro's 402 and wrong on everything wider: the pass itself is never
    /// capped — it is the screen less two 24pt gutters, full stop — so on a 16 Plus's 430 the
    /// card was 382 wide and a bought header was drawn at 372 and centred in it, leaving a strip
    /// of bare card down each side of the band while the house livery beside it sat flush. The
    /// clamp belongs to screens that use `tpScreenWidth()`; this one does not.
    private var bandWidth: CGFloat {
        UIScreen.main.bounds.width - 48
    }

    // MARK: - Parts

    private var punch: some View {
        Circle()
            .fill(TColor.navy700)
            .frame(width: 30, height: 30)
    }

    private func field(label: String, value: String,
                       align: HorizontalAlignment, tint: Color = TColor.textPrimary) -> some View {
        VStack(alignment: align, spacing: 8) {
            Text(verbatim: label)
                .tpLabelStyle()
                .foregroundStyle(TColor.textMuted)
            Text(verbatim: value)
                .font(TFont.core(.semibold, 18))
                .tpType(size: 18, lineHeight: 1.2)
                .foregroundStyle(tint)
        }
    }

    // MARK: - The tear

    private func fire(dest: Destination) {
        guard !fired else { return }
        fired = true
        frozenLands = Date().addingTimeInterval(Double(model.minutes) * 60)
        dragging = false
        torn = true
        let carrier = currentCarrier(to: dest)
        // The phase changes only once the paper has finished separating.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(720))
            model.depart(operatedBy: carrier)
        }
    }

    /// The pass is on screen before `depart()` freezes a carrier for it, so it asks the route
    /// directly — the same computation `fire()` makes at the tear, so what is shown never pops the
    /// moment the pass is torn.
    private func currentCarrier(to dest: Destination) -> Carriers.Operated {
        Carriers.forRoute(from: Geography.home.code, to: dest.code, seed: model.flightNo)
    }

    private func hhmm(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.locale = Locale(identifier: "en_GB")
        return f.string(from: date)
    }
}

/// Both halves of the tear animate off one value, so the stub's fall and its fade cannot desync.
private struct TearPhase: Equatable {
    var dy: CGFloat
    var torn: Bool
}

private struct PassHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// The dashed half of the perforation. The holes either side of it are drawn by the pass, in the
/// screen's own colour, because a hole is the surface behind the paper and not a mark on it.
private struct PerforationLine: View {
    var body: some View {
        GeometryReader { geo in
            Path { p in
                p.move(to: CGPoint(x: 0, y: 0.75))
                p.addLine(to: CGPoint(x: geo.size.width, y: 0.75))
            }
            // `1.5px dashed`, as the browser draws it: a 3pt dash and a 1.5pt gap.
            .stroke(TColor.borderStrong, style: StrokeStyle(lineWidth: 1.5, dash: DashedLine.perforation))
        }
        .frame(height: 1.5)
    }
}
