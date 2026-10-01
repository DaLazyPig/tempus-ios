import SwiftUI

/// All / Subject / Destination — top-level (not nested) so both `PassesScreen` and its private
/// mode-tabs view can share it; a `private` type nested in one would be invisible to the other.
fileprivate enum PassesFacetMode: String, CaseIterable { case all = "All", subject = "Subject", destination = "Destination" }

/// The pass archive. A pass is a document: every tile draws exactly what its `FlightRecord` froze
/// at landing — the livery, the pass header, the aircraft, the flight number — and never
/// recomputes any of it, so a route-table change can never repaint a flight already flown.
///
/// Economy keeps the last ten passes; Business Class keeps every one. Grouping, filtering and the
/// lifted full-size view are all local — nothing here writes the model except opening the paywall.
struct PassesScreen: View {
    @Environment(AppModel.self) private var model

    @State private var mode: PassesFacetMode = .all
    @State private var pick: String?
    @State private var openID: String?
    @State private var closing = false
    /// The lifted overlay's own entrance flag — reset on every dismissal so a re-open always
    /// replays its lift-in rather than snapping straight to the settled state.
    @State private var overlayShown = false

    // MARK: - Data prep

    /// Economy keeps the last ten; Business Class keeps the lot.
    private var kept: [FlightRecord] {
        model.plus ? model.flights : Array(model.flights.prefix(10))
    }

    /// Unique facet values in first-seen order (`kept` is already newest-first), capped to 8.
    private var facets: [String] {
        var seen: [String] = []
        for f in kept {
            let v = mode == .subject ? f.subject : f.to
            if !v.isEmpty, !seen.contains(v) { seen.append(v) }
        }
        return Array(seen.prefix(8))
    }

    private var shown: [FlightRecord] {
        guard let pick else { return kept }
        return kept.filter { mode == .subject ? $0.subject == pick : $0.to == pick }
    }

    private struct MonthGroup: Identifiable {
        let key: String
        var items: [FlightRecord]
        var id: String { key }
    }

    /// Adjacent-only coalescing, not a full re-group — `shown` is already newest-first, so groups
    /// fall out in chronological order for free.
    private var groups: [MonthGroup] {
        var out: [MonthGroup] = []
        for f in shown {
            let key = Self.monthKey(f.t)
            if out.indices.last.map({ out[$0].key == key }) == true {
                out[out.count - 1].items.append(f)
            } else {
                out.append(MonthGroup(key: key, items: [f]))
            }
        }
        return out
    }

    private var full: FlightRecord? {
        guard let openID else { return nil }
        return kept.first { $0.id == openID }
    }

    private static let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                                      "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    private static func monthKey(_ t: TimeInterval) -> String {
        let d = Date(timeIntervalSince1970: t)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let m = cal.component(.month, from: d) - 1
        let y = cal.component(.year, from: d)
        return "\(monthNames[m]) \(y)"
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            scrollBody
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(TColor.cloud100)
        .overlay { if let full { liftedOverlay(full) } }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text("Passes")
                    .font(TFont.core(.bold, 34))
                    .tracking(-0.045 * 34)
                    .foregroundStyle(TColor.textPrimary)
                Spacer()
                IconButton(tone: .sunken, size: .md, label: "Close", action: {
                    model.go(.home, .lift, dir: -1)
                }) {
                    Image(systemName: "xmark").font(.system(size: 20, weight: .regular))
                }
            }

            Text("\(kept.filter { !$0.diverted }.count) LANDED \u{00b7} \(kept.filter(\.diverted).count) DIVERTED")
                .tpLabelStyle()
                .foregroundStyle(TColor.textMuted)
                .padding(.top, 8)

            PassesModeTabs(mode: $mode.onChange { pick = nil })
                .padding(.top, 16)

            if mode != .all {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        if facets.isEmpty {
                            Text("NOTHING FLOWN YET")
                                .tpLabelStyle()
                                .foregroundStyle(TColor.textMuted)
                        }
                        ForEach(facets, id: \.self) { v in
                            let on = pick == v
                            Button {
                                pick = on ? nil : v
                            } label: {
                                Text(v)
                                    .font(TFont.data(.medium, 11))
                                    .tracking(0.12 * 11)
                                    .foregroundStyle(on ? TColor.white : TColor.textSecondary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(on ? TColor.surfaceInverse : TColor.surfaceSunken, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.top, 14)
                .padding(.bottom, 2)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 62)
    }

    /// Two columns that actually fill the page, and the width one tile gets.
    ///
    /// The archive used to ask for `GridItem(.adaptive(minimum: 154, maximum: 154))`, which pins
    /// a tile to 154pt whatever the page is: on a 402pt screen inside this view's 24pt gutters
    /// that laid two 154s and a 14pt gap into 354pt of space and left **32pt dead on the right**,
    /// because the grid is `.leading`-aligned. `.flexible()` is the shape the Concourse shelf
    /// already uses, and it divides the page instead of ignoring it.
    ///
    /// `PassArchiveCard` scales every measurement off `width / 268`, so it needs the number the
    /// column is actually going to be — hence the arithmetic rather than a `GeometryReader`, which
    /// collapses to zero ideal height inside this screen's `LazyVStack` and would take the
    /// section headers' pinning with it. `TStage.bounds` is the same read
    /// `Controls.offY` makes, and this app is portrait-only on iPhone.
    private static let gutter: CGFloat = 14
    private static let pageInset: CGFloat = 24
    private static let columns = [GridItem(.flexible(), spacing: gutter),
                                  GridItem(.flexible(), spacing: gutter)]
    private static var tileWidth: CGFloat {
        (TStage.bounds.width - pageInset * 2 - gutter) / 2
    }

    @ViewBuilder
    private var scrollBody: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                if kept.isEmpty {
                    emptyState
                } else {
                    ForEach(Array(groups.enumerated()), id: \.element.id) { gi, group in
                        Section {
                            LazyVGrid(columns: Self.columns, spacing: Self.gutter) {
                                ForEach(Array(group.items.enumerated()), id: \.element.id) { i, f in
                                    PassArchiveCard(record: f, width: Self.tileWidth,
                                                     index: gi * 2 + i) {
                                        openID = f.id
                                    }
                                }
                            }
                            .padding(.bottom, 26)
                        } header: {
                            Text(group.key.uppercased())
                                .tpLabelStyle()
                                .foregroundStyle(TColor.steel500)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 5)
                                .background(TColor.cloud100.opacity(0.94), in: Capsule())
                                .padding(.bottom, 12)
                        }
                    }
                }

                if !model.plus && !model.flights.isEmpty {
                    Button {
                        model.paywall = .open
                    } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("Economy keeps your last ten passes")
                                .font(TFont.core(.semibold, 15))
                                .tpType(size: 15, lineHeight: 1.35)
                                .foregroundStyle(TColor.textPrimary)
                            Text("Business Class keeps every pass you have ever torn, all the way back.")
                                .font(TFont.core(.regular, 14))
                                .tpType(size: 14, lineHeight: 1.45)
                                .foregroundStyle(TColor.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                        .background(TColor.surfaceSunken, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 120)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("No passes yet")
                .font(TFont.core(.bold, 26))
                .tracking(-0.03 * 26)
                .tpType(size: 26, lineHeight: 1.2)
                .foregroundStyle(TColor.textPrimary)
            Text("Land a flight and its pass is kept here.")
                .font(TFont.core(.regular, 15))
                .tpType(size: 15, lineHeight: 1.5)
                .foregroundStyle(TColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
        .padding(.top, 60)
    }

    // MARK: - Lifted full-size pass

    /// The whole overlay stays mounted through its own exit — `closing` drives it back down over
    /// 260ms, and only once that settles does `lower()` actually remove it. Driven by plain
    /// `@State` rather than a `.transition`, the same pattern `Rise`/`ORise` use for screen
    /// entrances: reliable regardless of whether the state write happens inside `withAnimation`.
    private func liftedOverlay(_ record: FlightRecord) -> some View {
        let visible = overlayShown && !closing
        return VStack(spacing: 22) {
            PassArchiveCard(record: record, width: 320, index: nil, onTap: lower)
                .opacity(visible ? 1 : 0)
                .offset(y: visible ? 0 : (overlayShown ? 38 : 30))
                .scaleEffect(visible ? 1 : 0.9)
                .animation(closing ? .exit(0.26) : .glide(0.52), value: visible)
            Text("TAP TO PUT IT BACK")
                .tpLabelStyle()
                .foregroundStyle(Color(hex: 0xf2f5fa, opacity: 0.6))
                .opacity(closing ? 0 : 1)
                .animation(.linear(duration: 0.18), value: closing)
        }
        .padding(.horizontal, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: 0x16273f))
        .opacity(visible ? 1 : 0)
        .animation(.glide(0.24), value: visible)
        .contentShape(Rectangle())
        .onTapGesture(perform: lower)
        .onAppear { overlayShown = true }
        .zIndex(1)
    }

    /// Guards against re-entry, then settles the pass back into the grid rather than vanishing.
    private func lower() {
        guard !closing else { return }
        closing = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(260))
            openID = nil
            closing = false
            overlayShown = false
        }
    }
}

// MARK: - Mode tabs

/// All / Subject / Destination — a dark-filled selected pill, which the shared `SegmentedControl`
/// doesn't offer (its active segment is always light). Hand-rolled to match the archive's own
/// look rather than bend a shared component away from its own spec.
private struct PassesModeTabs: View {
    @Binding var mode: PassesFacetMode

    var body: some View {
        HStack(spacing: 4) {
            ForEach(PassesFacetMode.allCases, id: \.self) { m in
                let on = m == mode
                Button { mode = m } label: {
                    Text(m.rawValue)
                        .font(TFont.core(.semibold, 12))
                        .foregroundStyle(on ? TColor.white : TColor.steel600)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
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
        .animation(.glide(TDur.fast), value: mode)
    }
}

// MARK: - The pass tile

/// The reusable boarding-pass tile: the archive grid draws it at 154pt, the lifted view at 320pt.
/// Every measurement scales off `k`, the ratio against the pass's authored width of 268pt.
private struct PassArchiveCard: View {
    let record: FlightRecord
    var width: CGFloat = 154
    /// The staggered grid entrance's index. Nil for the lifted, full-size card.
    var index: Int?
    /// Tapping the lifted card also puts it back — the reference's click bubbles to the same
    /// `lower()` the surrounding scrim uses, since the full-size tile has no handler of its own.
    var onTap: () -> Void

    private var k: CGFloat { width / 268 }
    private func S(_ n: CGFloat) -> CGFloat { (n * k * 10).rounded() / 10 }
    private var holeRadius: CGFloat { width / 268 * 11 }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                PassBand(record: record, width: width, cornerRadius: S(20))
                infoBody
                perforation
                barcode
            }
            .frame(width: width)
            .background {
                RoundedRectangle(cornerRadius: S(20), style: .continuous)
                    .fill(TColor.surfaceCard)
            }
            // Flattens the card — fill, content and the perforation's `.destinationOut` holes —
            // into one layer, so the holes cut through the card's own background instead of
            // painting an opaque disc over whatever is drawn behind the button.
            .compositingGroup()
            // A second group isolates that already-punched layer before `.shadow` reads its
            // alpha, so the shadow is cast by the notched silhouette rather than a plain
            // rounded rect, and isn't itself subtracted by the same blend mode.
            .compositingGroup()
            // Not a `TShadow` token: this card is drawn at two very different sizes (154pt in the
            // archive grid, 320pt lifted) off one shared shape, and every measurement on it —
            // this shadow included — scales by `S(_:)`, the tile's own ratio against its 268pt
            // authored width. A fixed token can't scale with the tile the way its own radius and
            // corner do.
            .shadow(color: Color(hex: 0x101d31, opacity: 0.1197), radius: S(9), x: 0, y: S(12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(record.subject) pass, \(record.from) to \(record.to)")
        .modifier(PassInModifier(delay: index.map { min(0.36, Double($0) * 0.054) }))
    }

    private var infoBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: S(6)) {
                Text(record.carrierName)
                    .font(TFont.core(.semibold, S(13)))
                    .foregroundStyle(TColor.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(record.diverted ? "DIVERTED" : "LANDED")
                    .font(TFont.data(.medium, S(9)))
                    .tracking(0.14 * S(9))
                    .foregroundStyle(record.diverted ? TColor.statusDiverted : TColor.statusOnTime)
                    .fixedSize()
            }

            HStack(alignment: .firstTextBaseline, spacing: S(6)) {
                Text(record.from)
                    .font(TFont.core(.bold, S(26)))
                    .tracking(-0.04 * S(26))
                    .foregroundStyle(TColor.textPrimary)
                Spacer(minLength: 0)
                Text("\u{2192}")
                    .font(TFont.core(.regular, S(15)))
                    .foregroundStyle(TColor.sky400)
                Spacer(minLength: 0)
                Text(record.to)
                    .font(TFont.core(.bold, S(26)))
                    .tracking(-0.04 * S(26))
                    .foregroundStyle(TColor.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, S(14))

            VStack(alignment: .leading, spacing: S(6)) {
                Text("PASSENGER")
                    .font(TFont.data(.medium, S(9)))
                    .tracking(0.14 * S(9))
                    .foregroundStyle(TColor.textMuted)
                Text(record.subject)
                    .font(TFont.core(.semibold, S(13)))
                    .tpType(size: S(13), lineHeight: 1.2)
                    .foregroundStyle(TColor.textPrimary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, S(12))
            .overlay(alignment: .top) { Rectangle().fill(TColor.borderSubtle).frame(height: 1) }
            .padding(.top, S(14))

            HStack(alignment: .top, spacing: S(6)) {
                VStack(alignment: .leading, spacing: S(6)) {
                    Text(record.no)
                        .font(TFont.data(.medium, S(9)))
                        .tracking(0.14 * S(9))
                        .foregroundStyle(TColor.textMuted)
                    Text("\(record.minutes) min")
                        .font(TFont.core(.semibold, S(12)))
                        .foregroundStyle(TColor.textPrimary)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: S(6)) {
                    Text(record.ac)
                        .font(TFont.data(.medium, S(9)))
                        .tracking(0.14 * S(9))
                        .foregroundStyle(TColor.textMuted)
                    Text("\(record.miles) mi")
                        .font(TFont.core(.semibold, S(12)))
                        .foregroundStyle(TColor.textAccent)
                }
            }
            .padding(.top, S(12))
            .padding(.bottom, S(14))
            .overlay(alignment: .top) { Rectangle().fill(TColor.borderSubtle).frame(height: 1) }
            .padding(.top, S(12))
        }
        .padding(.horizontal, S(14))
        .padding(.top, S(14))
    }

    /// The punched perforation: two holes straddling the card's edges, and a dashed seam between
    /// them. The holes are cut with `.destinationOut`, not painted in a matching colour — that
    /// way they are real transparency, subtracted from the card's own `compositingGroup` in
    /// `body`, so the card's drop shadow follows the notch instead of the hole sitting on top of
    /// the shadow as an opaque disc.
    private var perforation: some View {
        DashedLine()
            .stroke(record.diverted ? Color(hex: 0xe2b8ae) : TColor.borderStrong,
                    style: StrokeStyle(lineWidth: 1.5, dash: DashedLine.perforation))
            .frame(height: 1.5)
            .padding(.horizontal, S(14))
            .overlay(alignment: .leading) {
                Circle().fill(.black).frame(width: holeRadius * 2, height: holeRadius * 2)
                    .blendMode(.destinationOut)
                    .offset(x: -holeRadius)
            }
            .overlay(alignment: .trailing) {
                Circle().fill(.black).frame(width: holeRadius * 2, height: holeRadius * 2)
                    .blendMode(.destinationOut)
                    .offset(x: holeRadius)
            }
    }

    private var barcode: some View {
        let widths = Carriers.barcode(seed: record.no + record.id).prefix(24)
        let inner = max(0, S(38) - S(14) - S(12))
        return HStack(spacing: max(1, S(2))) {
            ForEach(Array(widths.enumerated()), id: \.offset) { _, w in
                Rectangle().fill(TColor.navy700).frame(width: max(1, S(CGFloat(w))))
            }
        }
        .frame(height: inner)
        .padding(.horizontal, S(14))
        .padding(.top, S(14))
        .padding(.bottom, S(12))
        .opacity(record.diverted ? 0.5 : 1)
    }
}

/// A thin dashed rule — SwiftUI has no CSS `border-style:dashed`, so this strokes one. Shared
/// with the Concourse's mock pass, which draws the same two rules.
struct DashedLine: Shape {
    /// Every perforation in the reference is `1.5px dashed`, and the browser draws that as a 3pt
    /// dash with a 1.5pt gap. Stated once, because five surfaces tear along the same line.
    static let perforation: [CGFloat] = [3, 1.5]

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}

/// The band a pass tile draws: whatever the record froze. A bought header, if it flew one; the
/// house livery otherwise — never recomputed from the current route table.
private struct PassBand: View {
    let record: FlightRecord
    let width: CGFloat
    let cornerRadius: CGFloat

    private var height: CGFloat { width * Carriers.bandSize.height / Carriers.bandSize.width }

    var body: some View {
        Group {
            if let hdrID = record.hdr, let header = ShopCatalog.header(id: hdrID) {
                MarkupView(header.inner, background: header.bg, designSize: Carriers.bandSize,
                           width: width, cornerRadius: 0)
            } else {
                CarrierBandView(livery: record.pat, crop: true)
            }
        }
        .frame(width: width, height: height)
        .clipShape(
            UnevenRoundedRectangle(topLeadingRadius: cornerRadius, bottomLeadingRadius: 0,
                                    bottomTrailingRadius: 0, topTrailingRadius: cornerRadius)
        )
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color(hex: 0x101d31, opacity: 0.12)).frame(height: 1)
        }
    }
}

// MARK: - Entrance and exit choreography

/// `tp-passin` (the definition `PassCard` actually uses): opacity 0→1, translateY(26px)→0,
/// scale(.94)→1, over 520ms on the glide curve, delayed by the grid's own staggered index.
private struct PassInModifier: ViewModifier {
    /// Nil plays no entrance at all — the lifted, full-size card doesn't replay one.
    let delay: Double?
    @State private var shown = false

    func body(content: Content) -> some View {
        let on = delay == nil || shown
        return content
            .opacity(on ? 1 : 0)
            .offset(y: on ? 0 : 26)
            .scaleEffect(on ? 1 : 0.94)
            // Declarative, and the delay is a sleep rather than `Animation.delay`. The obvious
            // `withAnimation(.glide(0.52).delay(d)) { shown = true }` in `onAppear` looks right
            // and leaves every card stranded at opacity 0 for good: inside a `LazyVGrid` the
            // appear callback runs as part of the container's own layout pass, and the animated
            // write is discarded with the transaction that pass belongs to. The unanimated write
            // survives it — which is what made this read as a rendering bug rather than an
            // animation one, since the archive simply came up empty.
            .animation(.glide(0.52), value: shown)
            .task {
                guard let delay else { return }
                try? await Task.sleep(for: .seconds(delay))
                shown = true
            }
    }
}

// MARK: - Binding helper

private extension Binding {
    /// A binding that runs a side effect after every write — used here to clear the facet pick
    /// whenever the archive's grouping mode changes, exactly as the reference's `setMode` does.
    func onChange(_ action: @escaping () -> Void) -> Binding<Value> {
        Binding(
            get: { wrappedValue },
            set: { newValue in
                wrappedValue = newValue
                action()
            }
        )
    }
}
