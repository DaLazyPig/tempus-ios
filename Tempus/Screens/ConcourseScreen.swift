import SwiftUI

/// The Concourse shelf: card faces, pass headers and gift faces, bought with miles.
///
/// **The shelf is open to everyone.** It used to be gated whole — `ConcourseLocked` was the entire
/// screen without the plan — which meant a member who had flown for their miles had nothing to
/// spend them on, and the one screen in the app that is a shop read as an advertisement. Business
/// Class now buys the top of the shelf rather than the door to it: about three quarters of the
/// stock is `ShopCatalog.businessOnly`, and the rest is bought with miles like anything else. A
/// locked tile still opens, still shows its art at full size, and says what it costs to unlock —
/// looking is never the thing that is sold.
///
/// The shelf itself never changes phase to show an item or a gift: `ShopItemScreen` and
/// `GiftScreen` are overlays drawn here, keyed on `model.shopSelection`/`model.giftOpen` so a
/// fresh open always gets fresh `@State` and a stale one keeps the same identity through its own
/// 740 ms exit (see `ShopItemScreen.leave()`).
struct ConcourseScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(Backend.self) private var backend

    var body: some View {
        @Bindable var model = model
        shelf
    }

    private func close() { model.go(.home, .lift, dir: -1) }

    // MARK: - The shelf

    @State private var cat = "All"
    /// The search field's text. Filters the shelf by name and nothing else — see `ConcourseSearchBar`.
    @State private var query = ""
    @State private var shelfSeed = Double.random(in: 0..<1)
    @State private var scrollY: CGFloat = 0
    @State private var shelfCache = ShelfCache()

    /// **Gifts are un-archived.** They were pulled on 18 Sep 2026 because the flow spent real miles
    /// and told the sender "it is in their wallet now" with nothing behind it — no server row, no
    /// recipient lookup, no acceptance path. `Backend` now carries one (`public.gifts`, see
    /// `supabase/schema.sql`), so the chip is back — but only when there is an account to send from:
    /// a signed-out member sees the shelf with no Gifts chip rather than one that fails the moment
    /// it is tapped. (`showGifts` below is the other half of the same switch.)
    private var categories: [String] {
        Backend.isConfigured && backend.isLinked ? ["All", "Cards", "Headers", "Gifts"] : ["All", "Cards", "Headers"]
    }

    /// `k = cl(sc/64, 0, 1)` — how far the sticky header has collapsed.
    private var k: Double { TEase.clamp(scrollY / 64, 0, 1) }
    private var far: Bool { scrollY > 900 }

    /// Dimming while an item or gift is open — in immediately, out only once the overlay's own
    /// exit animation (`shopLeaving`) has started, so the leaving card is the only thing moving
    /// for the first beat.
    private var dimmed: Bool { (model.shopSelection != nil || model.giftOpen != nil) && !model.shopLeaving }

    private var shelf: some View {
        ZStack {
            ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        VStack(spacing: 0) {
                            ConcourseSearchBar(query: $query)
                            ConcourseCategoryRow(cat: $cat, categories: categories)
                            if model.status.founders {
                                ConcourseFreeBanner()
                            }
                            if shelfEntries.isEmpty {
                                ConcourseNoResults(query: query) { query = "" }
                            } else {
                                ConcourseGrid(shelf: shelfEntries, seed: shelfSeed)
                                    .id(cat)
                            }
                        }
                        .padding(.init(top: 6, leading: 20, bottom: 128, trailing: 20))
                    } header: {
                        ConcourseStickyHeader(k: k, far: far, onClose: close) {
                            // The reference's `scrollTo({top:0,behavior:'smooth'})`. This used to
                            // write `scrollY = 0` and re-anchor, which expanded the title where the
                            // shelf stood and left the shelf exactly where it was.
                            withAnimation(.glide(0.4)) { proxy.scrollTo("concourseTop", anchor: .top) }
                        }
                        .id("concourseTop")
                    }
                }
                // The scroll offset, read straight off the stack's own frame. Two earlier shapes
                // failed silently: a zero-height `GeometryReader` row inside the `LazyVStack`, which
                // the lazy stack never laid out, and then a preference set from this background,
                // which `onPreferenceChange` on the `ScrollView` received exactly once, as its
                // default 0, and never again — the geometry closure below re-ran on every scroll
                // frame with the right numbers (logged) while the preference never arrived. So
                // `scrollY` stayed 0 for the life of the screen and the header never collapsed into
                // its pill, on device and in the sim alike. `onChange` needs no channel: it writes
                // the state from inside the closure that has the value.
                //
                // Read in the scroll view's **own** space, not `.global`. A global read needs an
                // anchor for "where the top is", and that anchor was captured on the first frame —
                // while the `lift` was still carrying the screen in — so it sat a few points off for
                // the life of the visit: the header rested part-way to its pill at the very top of the
                // shelf and only became the title while overscrolled. In the named space the content's
                // `minY` *is* `-scrollTop`, wherever the screen happens to be.
                .background(GeometryReader { geo in
                    let y = geo.frame(in: .named("concourseSpace")).minY
                    Color.clear.onChange(of: y, initial: true) { _, y in scrollY = max(0, -y) }
                })
            }
            .coordinateSpace(name: "concourseSpace")
            .background(TColor.cloud100.ignoresSafeArea())
            // The shelf is a ground fill under a shadowed sticky header and a grid of shadowed
            // tiles. Faded ungrouped, every one of those shadows fades separately from the card
            // casting it and comes up through the middle of the dim — CLAUDE.md's opacity rule.
            // Taken only here, where the layer is actually part-way transparent.
            .compositingGroup()
            .opacity(dimmed ? 0 : 1)
            .animation(.glide(dimmed ? 0.56 : 0.42).delay(dimmed ? 0 : 0.56), value: dimmed)
            .scaleEffect(dimmed ? 0.985 : 1)
            .animation(.glide(dimmed ? 0.6 : 0.52).delay(dimmed ? 0 : 0.52), value: dimmed)
            .allowsHitTesting(!dimmed)
            }

            if model.shopSelection != nil {
                ShopItemScreen()
                    .id(model.shopSelection?.id ?? "")
                    .transition(.identity)
            }
            if model.giftOpen != nil {
                GiftScreen()
                    .id(model.giftFace ?? "")
                    .transition(.identity)
            }
        }
    }

    // MARK: - Shuffle + weave

    // `fileprivate`, not `private`: `ShelfEntry` is visible to the grid below and carries one of
    // these, and a fileprivate property may not expose a private type.
    fileprivate enum ShelfKind { case face(ShopFace), header(ShopHeader), gift(ShopGift) }

    struct ShelfEntry: Identifiable {
        fileprivate let kind: ShelfKind
        /// What the tile prints, and so the only thing the search field has to match against.
        var name: String {
            switch kind {
            case .face(let f): return f.name
            case .header(let h): return h.name
            case .gift(let g): return g.name + " gift"
            }
        }
        var id: String {
            switch kind {
            case .face(let f): return "face-\(f.id)"
            case .header(let h): return "header-\(h.id)"
            case .gift(let g): return "gift-\(g.id)"
            }
        }
    }

    /// A linear-congruential shuffle seeded once per screen visit (`shelfSeed`), so switching
    /// category tabs redraws a different subset in the *same* relative order rather than a fresh
    /// shuffle — only leaving and re-entering the Concourse draws a new seed.
    private func shuffled<T>(_ array: [T]) -> [T] {
        var a = array
        var r = shelfSeed
        for i in a.indices {
            r = r * 9301 + 49297
            let frac = (r / 233280).truncatingRemainder(dividingBy: 1)
            a.swapAt(i, min(i, Int(frac * Double(i + 1))))
        }
        return a
    }

    /// The woven shelf, memoised on the only three things it depends on.
    ///
    /// `weave()` shuffles three catalogues and interleaves 334 entries; this screen's body is
    /// re-evaluated on **every scroll frame** (the sticky header collapses as a function of
    /// `scrollY`), so calling it from `body` rebuilt the whole shelf 60 times a second and handed
    /// `ForEach` a brand-new array to diff each time. That was the Concourse's scroll stutter.
    /// The cache is a plain class, not `@State` storage or an `@Observable`, precisely so filling
    /// it invalidates nothing.
    private final class ShelfCache {
        var key = ""
        var entries: [ShelfEntry] = []
    }

    private var shelfEntries: [ShelfEntry] {
        let key = "\(cat)|\(model.status.idx)|\(shelfSeed)|\(query)|\(backend.isLinked)"
        if shelfCache.key == key { return shelfCache.entries }
        let woven = filtered(weave())
        shelfCache.key = key
        shelfCache.entries = woven
        return woven
    }

    /// The search field, applied. A plain case- and diacritic-insensitive name match: the shelf is
    /// 334 items with nothing to search but their names, so anything cleverer would be inventing a
    /// query language for a field that answers one question — "where is the one I saw?".
    private func filtered(_ entries: [ShelfEntry]) -> [ShelfEntry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return entries }
        return entries.filter { $0.name.localizedStandardContains(q) }
    }

    /// Interleaves faces/headers/gifts by proportional progress through each run, so a short run
    /// (18 gifts) spreads across the whole shelf instead of clustering at the start.
    private func weave() -> [ShelfEntry] {
        let showFaces = cat == "All" || cat == "Cards"
        let showHeaders = cat == "All" || cat == "Headers"
        let showGifts = (cat == "All" || cat == "Gifts") && Backend.isConfigured && backend.isLinked

        let faces = showFaces
            ? shuffled(ShopCatalog.faces(tier: model.status.idx)).map { ShelfEntry(kind: .face($0)) } : []
        let headers = showHeaders
            ? shuffled(ShopCatalog.headers).map { ShelfEntry(kind: .header($0)) } : []
        let gifts = showGifts
            ? shuffled(ShopCatalog.gifts).map { ShelfEntry(kind: .gift($0)) } : []

        let runs = [faces, headers, gifts].filter { !$0.isEmpty }
        guard !runs.isEmpty else { return [] }
        var at = Array(repeating: 0, count: runs.count)
        var out: [ShelfEntry] = []
        let total = runs.reduce(0) { $0 + $1.count }
        for _ in 0..<total {
            var pick = 0
            var best = Double.infinity
            for i in runs.indices where at[i] < runs[i].count {
                let p = (Double(at[i]) + 0.5) / Double(runs[i].count)
                if p < best { best = p; pick = i }
            }
            out.append(runs[pick][at[pick]])
            at[pick] += 1
        }
        return out
    }
}

// MARK: - Locked state

/// The soft lock shown to any member who isn't Business Class — no partial shelf, just the pitch.
// MARK: - Sticky collapsing header

/// Pinned at the top of the shelf: a title that starts oversized and un-boxed at 34px and
/// collapses into a small white pill at 19px over the first 64pt of scroll.
private struct ConcourseStickyHeader: View {
    let k: Double
    let far: Bool
    let onClose: () -> Void
    let onTop: () -> Void

    private func lp(_ a: Double, _ b: Double) -> Double { a + (b - a) * k }

    var body: some View {
        // The reference draws ONE flex row — title and the two buttons together — that becomes
        // the whole white, shadowed, capsule bar as `k` grows (app.jsx:4333-4341). This used to
        // put the background/shadow on the title `Text` alone, whose `.frame(maxWidth: .infinity)`
        // stretched to whatever width the HStack's layout gave it against the trailing buttons —
        // an arbitrarily-sized white stadium with no relation to the text or the buttons sitting
        // outside it. One unified pill over the whole row is what the reference actually draws.
        HStack(spacing: 12) {
            Text("The Concourse")
                .font(TFont.core(.bold, lp(34, 19)))
                .tracking(-0.05 * lp(34, 19))
                .foregroundStyle(TColor.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                if far {
                    squareButton(icon: "arrow.up", label: "Back to top", action: onTop)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
                squareButton(icon: "xmark", label: "Close", action: onClose)
            }
        }
        .padding(.leading, lp(0, 18))
        .padding(.trailing, lp(0, 10))
        .frame(height: lp(46, 52))
        .background(Color.white.opacity(0.96 * k))
        .clipShape(Capsule())
        .compositingGroup()
        // `0 (k*10)px (k*24)px -(k*14)px rgba(16,29,49,k*.42)`: blur=24k so sigma=12k, spread=
        // -14k, y=10k. spread/sigma is a constant -7/6 (k cancels), so the fold
        // (`TShadow.ShadowLayer.css`'s `alpha' = 2·alpha·Φ(spread/σ)`) collapses to one constant
        // factor on the reference's own `k*.42` alpha: 2·Φ(-7/6) ≈ 0.2434, so alpha' ≈ 0.42 ·
        // 0.2434 · k ≈ 0.1022·k — the same figure the old per-Text shadow already used, now
        // carried by the row it actually belongs to.
        .shadow(color: Color(hex: 0x101d31, opacity: 0.1022 * k), radius: 12 * k, y: 10 * k)
        // The reference wraps this row's height/background/shadow/padding in their own
        // `transition:'height 320ms '+E+',background 320ms '+E+',box-shadow 320ms '+E+
        // ',padding 320ms '+E` (app.jsx:4338) — every one of those keyed off `k`, which tracks raw
        // scroll offset and can jump by a lot in a single `ScrollView` frame (a fast flick —
        // or "back to top" from deep in the shelf). Without an
        // explicit `.animation(value: k)` here, SwiftUI applies no interpolation of its own to a
        // plain state mutation: the pill's height/background/shadow snapped straight to wherever
        // `k` had jumped to, which is what read as "a box appears" rather than the header easing
        // into its collapsed shape. `far`'s own animation already used this exact duration, so `k`
        // now rides the same one.
        .animation(.glide(0.32), value: k)
        .animation(.glide(0.32), value: far)
        // The reference's `padding: 64px 20px 10px` is measured under its own 46pt status bar, so
        // the title sits 18pt below it. This used to be `TSpace.topInset(64)`, which reads the key
        // window's safe area inside a body — the `AttributeGraph: cycle detected` trap in CLAUDE.md.
        // The cycle wedged this screen's graph: the scroll preference fired once at 0 and never
        // again, so `k` stayed 0 and the header never collapsed into its pill however far the shelf
        // was scrolled, on device and in the sim alike. The row is pinned at the safe-area top, so
        // 18 is the whole of the padding, and the panel reaches the screen edge on its own below.
        .padding(.init(top: 18, leading: 20, bottom: 10, trailing: 20))
        // `linear-gradient(180deg, var(--cloud-100) 62%, rgba(242,245,250,0))` — **opaque for the
        // first 62%**, and only then fading. Ported as a fade from zero, which left the tiles
        // showing straight through the title as they scrolled under it. The solid band is the
        // panel; the fade is only how it lets go at its own bottom edge.
        .background(
            LinearGradient(stops: [.init(color: TColor.cloud100, location: 0),
                                   .init(color: TColor.cloud100, location: 0.62),
                                   .init(color: TColor.cloud100.opacity(0), location: 1)],
                           startPoint: .top, endPoint: .bottom)
        )
        // The row is pinned at the safe-area top while the shelf scrolls on under the status bar,
        // so the panel also hangs a slab of its own colour above itself to cover that strip, as
        // the reference's 64pt padding does. The stage clips it at the screen edge.
        .background(alignment: .top) {
            TColor.cloud100.frame(height: 200).offset(y: -200)
        }
        .zIndex(8)
    }

    private func squareButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        let d = lp(44, 38)
        return Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(TColor.textPrimary)
                .frame(width: d, height: d)
                .background(Circle().fill(TColor.surfaceSunken))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - Search bar

/// The shelf is 334 items deep, so the one question this field answers is "where is the one I
/// saw?". It filters by name and does nothing else.
///
/// **The reference draws this field and wires nothing to it** — no `onClick`, no bound input
/// anywhere in `app.jsx` — and it draws a filter button beside it with no defined behaviour at
/// all. Neither is shippable: a field you can tap and type into that then ignores you is worse
/// than no field, and a button with nowhere to go is the Status ▸ Share button all over again. So
/// the field is real and the filter button is gone; the clear button a search field always needs
/// takes its place, and only while there is something to clear.
private struct ConcourseSearchBar: View {
    @Binding var query: String
    @FocusState private var focused: Bool

    var body: some View {
        ORise(i: 1) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color(hex: 0x7389aa))
                TextField("", text: $query, prompt: Text("Search the Concourse")
                    .foregroundColor(TColor.textMuted))
                    .font(TFont.core(.regular, TFont.sizeBody))
                    .foregroundStyle(TColor.textPrimary)
                    .tint(TColor.copper500)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($focused)
                if !query.isEmpty {
                    Button {
                        query = ""
                        focused = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(TColor.white)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(TColor.navy900))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
                }
            }
            .animation(.glide(0.24), value: query.isEmpty)
            .padding(.leading, 18)
            .padding(.trailing, query.isEmpty ? 18 : 11)
            .frame(height: 52)
            .background(Capsule().fill(TColor.white))
            .compositingGroup()
            // `0 4px 14px -10px rgba(16,29,49,.4)` — the search bar's own bespoke shadow rather
            // than `--shadow-card`. See Theme/Shadows.swift for why the −10 spread lands on the
            // alpha and not on the blur.
            .shadow(color: Color(hex: 0x101d31, opacity: 0.0613), radius: 7, y: 4)
        }
        .padding(.top, 18)
    }
}

// MARK: - Nothing matched

/// What a search that finds nothing says. States the position and offers the one action, which is
/// the same shape every other refusal in the app takes.
private struct ConcourseNoResults: View {
    let query: String
    let onClear: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text("Nothing on the shelf matches \u{201c}\(query)\u{201d}")
                .font(TFont.core(.semibold, 17))
                .tpType(size: 17, lineHeight: 1.35)
                .multilineTextAlignment(.center)
                .foregroundStyle(TColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            TButton("Clear the search", variant: .ghost, size: .md, action: onClear)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 64)
        .padding(.bottom, 40)
    }
}

// MARK: - Category tabs

private struct ConcourseCategoryRow: View {
    @Binding var cat: String
    let categories: [String]

    var body: some View {
        ORise(i: 2) {
            HStack(spacing: 8) {
                ForEach(categories, id: \.self) { c in
                    let on = c == cat
                    Button { cat = c } label: {
                        Text(c)
                            .font(TFont.core(.medium, 14))
                            .foregroundStyle(on ? TColor.white : TColor.textSecondary)
                            .frame(height: 38)
                            .padding(.horizontal, 17)
                            .background(Capsule().fill(on ? TColor.navy900 : TColor.white))
                    }
                    .buttonStyle(.plain)
                    .animation(.glide(0.3), value: on)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.top, 14)
    }
}

// MARK: - Founders' free banner

private struct ConcourseFreeBanner: View {
    var body: some View {
        ORise(i: 3) {
            HStack(spacing: 12) {
                Image(systemName: "gift.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(TColor.copper500)
                Text("Founders pay nothing here. Gifts still cost the miles you send.")
                    .font(TFont.core(.regular, TFont.sizeBodySm))
                    .tpType(size: TFont.sizeBodySm, lineHeight: 1.4)
                    .foregroundStyle(TColor.textSecondary)
            }
            .padding(.init(top: 14, leading: 18, bottom: 14, trailing: 18))
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(TColor.surfaceSunken))
        }
        .padding(.top, 14)
    }
}

// MARK: - The grid

private struct ConcourseGrid: View {
    @Environment(AppModel.self) private var model
    let shelf: [ConcourseScreen.ShelfEntry]
    let seed: Double

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ORise(i: 4) {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(Array(shelf.enumerated()), id: \.element.id) { i, entry in
                    ConcourseShopTile(entry: entry, index: i)
                }
            }
        }
        .padding(.top, 20)
    }
}

// MARK: - One tile

/// One shelf tile: a face/gift renders tilted with a drop shadow, a header lies flat. Tapping
/// captures the tile's current on-screen rect (already scroll-correct, since `GeometryReader`
/// reports live position) as the morph anchor for `ShopItemScreen`/`GiftScreen`.
struct ConcourseShopTile: View {
    @Environment(AppModel.self) private var model
    let entry: ConcourseScreen.ShelfEntry
    let index: Int

    /// See `RectBox` — the tile's own position changes on every scroll frame, and the only thing
    /// that ever asks for it is `open()`.
    @State private var rectBox = RectBox()

    /// Where the art sits inside the tile: a 104-tall row, 16 down. `ShopItemScreen`/`GiftScreen`
    /// morph from and back to *this* point, never the tile's own centre, which is 27pt lower —
    /// down among the name and the price, where no card has ever been drawn.
    static let artCentreY: CGFloat = 16 + 52

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Spacer(minLength: 0)
                    art
                    Spacer(minLength: 0)
                }
                .frame(height: 104)
                // A locked tile is dimmed, not hidden or blurred: the art is the reason to want
                // it, and a shelf that will not let you look at what it is selling sells nothing.
                // The chip says which shelf this is; the price line below says what happens next.
                .opacity(locked ? 0.6 : 1)
                .overlay(alignment: .topTrailing) { if locked { lockChip } }

                VStack(alignment: .leading, spacing: 4) {
                    Text(name)
                        .font(TFont.core(.semibold, 15))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(TColor.textPrimary)
                    Text(priceText)
                        .font(TFont.core(.bold, 18))
                        .tracking(-0.03 * 18)
                        .foregroundStyle(priceColor)
                }
                .padding(.top, 14)
                .padding(.horizontal, 4)
                .padding(.bottom, 4)
            }
            .padding(.init(top: 16, leading: 12, bottom: 12, trailing: 12))
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(TColor.surfaceCard))
            .tpShadow(.card)
        }
        .buttonStyle(TileButtonStyle())
        .measureRect(into: rectBox, in: .named("concourseSpace"))
        .opacity(shown ? 1 : 0)
        .offset(y: shown ? 0 : 18)
        .onAppear {
            withAnimation(.glide(0.56).delay(min(0.42, Double(index) * 0.044))) { shown = true }
        }
    }

    @State private var shown = false

    @ViewBuilder private var art: some View {
        switch entry.kind {
        case .face(let f):
            MarkupView(f.inner(for: model.cardName), background: f.ground, designSize: CGSize(width: 340, height: 214),
                      width: 140, cornerRadius: 9)
                .rotationEffect(.degrees(-7))
                // `0 12px 20px -12px rgba(16,29,49,.6)`, on the tilted card art in `ShopTile`.
                .compositingGroup()
                .shadow(color: Color(hex: 0x101d31, opacity: 0.1381), radius: 10, x: 0, y: 12)
        case .header(let h):
            MarkupView(h.inner, background: h.bg, designSize: CGSize(width: 268, height: 90),
                      width: 140, cornerRadius: 6)
                // `0 6px 16px -10px rgba(16,29,49,.5)` — the reference gives a header tile no
                // shadow at all, which is fine for `Runway` and wrong for `Titanium` or
                // `Platinum`: a pale band on a white tile has no edge and reads as a printing
                // fault rather than as an object. Flatter and closer than the faces' own
                // `0 12px 20px -12px`, because a header lies on the tile where a face is tilted
                // off it. Through `ShadowLayer.css`: sigma = 16/2, the -10 spread folds into the
                // alpha (Theme/Shadows.swift).
                .compositingGroup()
                .shadow(color: Color(hex: 0x101d31, opacity: 0.1056), radius: 8, x: 0, y: 6)
        case .gift(let g):
            MarkupView(g.inner, background: g.bg, designSize: CGSize(width: 340, height: 214),
                      width: 140, cornerRadius: 9)
                .rotationEffect(.degrees(-7))
                // `0 12px 20px -12px rgba(16,29,49,.6)`, on the tilted card art in `ShopTile`.
                .compositingGroup()
                .shadow(color: Color(hex: 0x101d31, opacity: 0.1381), radius: 10, x: 0, y: 12)
        }
    }

    private var name: String {
        switch entry.kind {
        case .face(let f): return f.name
        case .header(let h): return h.name
        case .gift(let g): return g.name + " gift"
        }
    }

    /// Founders pay nothing for faces or headers; a gift's surcharge is never waived (§2.1).
    private var isGift: Bool { if case .gift = entry.kind { return true }; return false }
    private var owned: Bool {
        switch entry.kind {
        case .face(let f): return model.ownedFaces.contains(f.id)
        case .header(let h): return model.ownedHeaders.contains(h.id)
        case .gift: return false
        }
    }
    private var price: Int {
        switch entry.kind {
        case .face(let f): return f.price
        case .header(let h): return h.price
        case .gift(let g): return g.extra
        }
    }
    private var free: Bool { model.status.founders && !isGift }

    /// Business Class stock, without the plan. Owning it already settles the question — a face
    /// bought before a plan lapsed does not become unavailable — so this asks about the purchase,
    /// not about the shelf.
    private var locked: Bool {
        guard !model.plus, !owned else { return false }
        switch entry.kind {
        case .face(let f): return ShopCatalog.businessOnly(f)
        case .header(let h): return ShopCatalog.businessOnly(h)
        case .gift: return false
        }
    }

    /// **A glyph, not a chip.** This was a full `lock + BUSINESS` pill, which is correct on a
    /// shelf where locked stock is the exception and wrong on this one, where it is roughly three
    /// tiles in four: twelve dark pills on a page turned the marker into the texture of the screen
    /// and buried the six tiles that actually have a price. The price line under each tile already
    /// reads "Business Class" in words — this only has to be the thing the eye catches while
    /// scrolling, so it is one small disc and the words stay where they were.
    private var lockChip: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(TColor.white)
            .frame(width: 22, height: 22)
            .background(Circle().fill(TColor.navy900.opacity(0.72)))
            .padding(.top, 2)
            .padding(.trailing, 2)
    }

    private var priceText: String {
        if owned { return "Owned" }
        if locked { return "Business Class" }
        if free || price == 0 { return "Free" }
        return "\(price) mi"
    }
    private var priceColor: Color {
        if owned { return TColor.statusOnTime }
        return locked ? TColor.textMuted : TColor.textPrimary
    }

    private func open() {
        let rect = rectBox.rect
        switch entry.kind {
        case .face(let f):
            model.shopSelection = AppModel.ShopSelection(kind: .face, id: f.id, rect: rect)
        case .header(let h):
            model.shopSelection = AppModel.ShopSelection(kind: .header, id: h.id, rect: rect)
        case .gift(let g):
            model.giftFace = g.id
            model.giftOpen = rect
        }
    }
}

private struct TileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? TPress.scale : 1)
            .animation(.glide(TDur.fast), value: configuration.isPressed)
    }
}
