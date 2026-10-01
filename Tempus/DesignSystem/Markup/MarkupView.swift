import SwiftUI
import CoreGraphics

// MARK: - The view

/// Draws a markup fragment authored at `designSize`, scaled to the width it is given.
///
/// The reference never re-lays-out card art: it renders at true size and applies
/// `transform: scale(w / designWidth)` with `transform-origin: 0 0`. This does the same — one
/// `Canvas`, scaled once, everything inside it in design coordinates. Nothing reflows, so a face
/// on a 140pt shelf tile and the same face on a 310pt card are the same drawing at two sizes.
struct MarkupView: View {

    private let markup: String
    private let background: String?
    private let designSize: CGSize
    private let width: CGFloat
    private let cornerRadius: CGFloat?
    private let shine: Bool
    private let materialOnly: Bool

    init(_ markup: String, background: String? = nil,
         designSize: CGSize, width: CGFloat,
         cornerRadius: CGFloat? = nil, shine: Bool = false, materialOnly: Bool = false) {
        self.markup = markup
        self.background = background
        self.designSize = designSize
        self.width = width
        self.cornerRadius = cornerRadius
        self.shine = shine
        self.materialOnly = materialOnly
    }

    private var scale: CGFloat { designSize.width > 0 ? width / designSize.width : 1 }
    private var height: CGFloat { designSize.height * scale }
    /// `radius == null ? Math.round(20 * k) : radius` — the reference's rule, kept exactly.
    private var radius: CGFloat { cornerRadius ?? (20 * scale).rounded() }

    var body: some View {
        Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: false) { context, _ in
            var ctx = context
            ctx.scaleBy(x: scale, y: scale)
            let box = CGRect(origin: .zero, size: designSize)
            if let background, !background.isEmpty {
                MarkupRenderer.paintGround(background, in: box, ctx)
            }
            MarkupRenderer.draw(materialOnly ? MarkupStore.material(markup) : MarkupStore.tree(markup),
                                in: box, style: MarkupStyle(), ctx)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: radius))
        .overlay { if shine { ShineSweep(width: width, height: height) } }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The one-shot sweep a freshly bought face plays: a 46%-wide band travelling from `-135%` to
/// `135%`, skewed `-16deg`, over `1500ms` after an `80ms` delay on `cubic-bezier(.4,0,.3,1)`,
/// running once. Opacity rides 0 → .55 (22%) → 1 (50%) → .55 (78%) → 0.
private struct ShineSweep: View {
    let width: CGFloat
    let height: CGFloat
    @State private var t: Double = 0

    var body: some View {
        let band = width * 0.46
        Rectangle()
            .fill(LinearGradient(
                stops: [
                    .init(color: .white.opacity(0), location: 0),
                    .init(color: .white.opacity(0.55), location: 0.46),
                    .init(color: .white.opacity(0), location: 1),
                ],
                startPoint: .init(x: 0.06, y: 1), endPoint: .init(x: 0.94, y: 0)   // 100deg
            ))
            .frame(width: band, height: height * 1.4)
            .transformEffect(CGAffineTransform(a: 1, b: 0, c: tan(-16 * .pi / 180), d: 1, tx: 0, ty: 0))
            .offset(x: band * (-1.35 + 2.70 * t))
            .opacity(sweepOpacity(t))
            .frame(width: width, height: height, alignment: .leading)
            .clipped()
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.timingCurve(0.4, 0, 0.3, 1, duration: 1.5).delay(0.08)) { t = 1 }
            }
    }

    private func sweepOpacity(_ t: Double) -> Double {
        switch t {
        case ..<0.22: return TEase.lerp(0, 0.55, t / 0.22)
        case ..<0.50: return TEase.lerp(0.55, 1, (t - 0.22) / 0.28)
        case ..<0.78: return TEase.lerp(1, 0.55, (t - 0.50) / 0.28)
        default: return TEase.lerp(0.55, 0, (t - 0.78) / 0.22)
        }
    }
}

// MARK: - Caches

/// Parse once, draw many. Faces are parsed on first draw and kept; `NSCache` bounds the set so a
/// long browse of all 191 does not hold all 191 trees at once.
enum MarkupStore {
    private final class Box<T> { let value: T; init(_ value: T) { self.value = value } }

    private static let trees: NSCache<NSString, Box<[MarkupNode]>> = {
        let c = NSCache<NSString, Box<[MarkupNode]>>(); c.countLimit = 96; return c
    }()
    private static let layerLists: NSCache<NSString, Box<[CSSLayer]>> = {
        let c = NSCache<NSString, Box<[CSSLayer]>>(); c.countLimit = 512; return c
    }()
    private static let images: NSCache<NSString, CGImage> = {
        let c = NSCache<NSString, CGImage>(); c.countLimit = 48; return c
    }()

    static func tree(_ markup: String) -> [MarkupNode] {
        let key = markup as NSString
        if let hit = trees.object(forKey: key) { return hit.value }
        let parsed = MarkupParser.parse(markup)
        trees.setObject(Box(parsed), forKey: key)
        return parsed
    }

    /// The material a face is printed on, without anything printed *on* it: the painted layers of
    /// a shop face's art, with every wordmark, holder name and house mark dropped.
    ///
    /// The Founders reverse is "ground and washes only — no type, no flower" (`FoundersBack`), and
    /// a built-in face gets that for free because its material is a view of its own
    /// (`FoundersMaterial`/`FoundersWash`). A bought face has no such split — it is one blob of
    /// markup — so the reference's `shopBackHTML` settles for the face's CSS `ground` alone. That
    /// works only where the ground carries the colour: `Bullion`'s ground is `#1a1508` and its gold
    /// is a gradient in the art, so its back came out near-black against a gold front. Keeping the
    /// painted layers and dropping the lettered ones gives a bought face the same reverse rule the
    /// built-ins have.
    static func material(_ markup: String) -> [MarkupNode] {
        let key = ("\u{1}material\u{1}" + markup) as NSString
        if let hit = trees.object(forKey: key) { return hit.value }
        let kept = tree(markup).filter(\.isMaterial)
        trees.setObject(Box(kept), forKey: key)
        return kept
    }

    static func layers(_ value: String) -> [CSSLayer] {
        let key = value as NSString
        if let hit = layerLists.object(forKey: key) { return hit.value }
        let parsed = CSS.layers(value)
        layerLists.setObject(Box(parsed), forKey: key)
        return parsed
    }

    static func image(_ key: String, _ make: () -> CGImage?) -> CGImage? {
        let k = key as NSString
        if let hit = images.object(forKey: k) { return hit }
        guard let made = make() else { return nil }
        images.setObject(made, forKey: k)
        return made
    }
}

// MARK: - Inherited style

struct MarkupStyle {
    var font = CSS.FontSpec()
    var color = CSSColor.black
    var tracking: Double = 0
    var indent: Double = 0
    var align: TextAlignment = .leading
    var shadows: [CSS.Shadow] = []
    var verticalCentre = false
    var verticalWriting = false
}

// MARK: - The renderer

enum MarkupRenderer {

    // MARK: Entry

    static func paintGround(_ background: String, in box: CGRect, _ ctx: GraphicsContext) {
        // A face passes its `ground` declaration (`background:#f4f5f7`); a header passes a bare
        // value. Both arrive here, so accept either.
        let value = CSS.declarations(background).first(where: { $0.0.hasPrefix("background") })?.1
            ?? background
        paint(MarkupStore.layers(value), in: box, clip: Path(box), size: nil, position: nil, ctx)
    }

    static func draw(_ nodes: [MarkupNode], in box: CGRect, style: MarkupStyle, _ ctx: GraphicsContext) {
        for node in nodes where !node.isText {
            element(node, parent: box, fixed: nil, style: style, ctx)
        }
    }

    // MARK: One element

    static func element(_ node: MarkupNode, parent: CGRect, fixed: CGRect?,
                        style inherited: MarkupStyle, _ base: GraphicsContext) {
        let css = CSS.style(node["style"])
        guard css["display"] != "none" else { return }
        var style = inherited
        apply(css, to: &style)

        // Text has to be measured before the box can be placed, because an absolutely positioned
        // element with no width or height takes both from its content.
        let isFlex = css["display"] == "flex" && !node.elements.isEmpty
        var content: (text: Text, shadow: Text?, lines: Int)?
        var measured = CGSize.zero
        var block = 0.0
        if !isFlex, node.tag != "svg", let built = inline(node.children, style: style) {
            content = built
            let available = measureWidth(css, parent: parent)
            let resolved = base.resolve(built.text)
            let glyphs = resolved.measure(in: CGSize(width: available,
                                                     height: CGFloat.greatestFiniteMagnitude))
            block = style.font.lineHeight * style.font.size * Double(built.lines)
            // In a vertical writing mode the inline axis is the *height*, so the content box the
            // layout is given has to arrive turned the same way round.
            measured = style.verticalWriting
                ? CGSize(width: block, height: glyphs.width)
                : CGSize(width: glyphs.width, height: block)
        }

        let frame = fixed ?? layout(css, parent: parent, content: content == nil ? nil : measured)
        guard frame.width.isFinite, frame.height.isFinite else { return }

        var ctx = base
        let transform = CSS.transform(css["transform"], size: frame.size)
        if !transform.isIdentity {
            ctx.translateBy(x: frame.midX, y: frame.midY)      // transform-origin: 50% 50%
            ctx.concatenate(transform)
            ctx.translateBy(x: -frame.midX, y: -frame.midY)
        }
        if let clip = css["clip-path"], let path = clipPath(clip, in: frame) { ctx.clip(to: path) }
        for shadow in CSS.shadows(dropShadows(css["filter"])) {
            ctx.addFilter(.shadow(color: shadow.color.color, radius: shadow.blur / 2,
                                  x: shadow.dx, y: shadow.dy))
        }

        let opacity = CSS.number(css["opacity"]) ?? 1
        // `mix-blend-mode` blends an element *and its subtree* against the backdrop; a layer is
        // what gives that group semantics, and it is what `opacity` needs too.
        let blend = blendMode(css["mix-blend-mode"])
        let mask = css["mask-image"] ?? css["-webkit-mask-image"]

        let body: (inout GraphicsContext) -> Void = { c in
            paintBody(node, css: css, frame: frame, style: style,
                      content: content, block: block, isFlex: isFlex, c)
        }

        if opacity < 1 || blend != .normal || mask != nil {
            ctx.opacity = opacity
            ctx.blendMode = blend
            ctx.drawLayer { layer in
                layer.opacity = 1
                layer.blendMode = .normal
                body(&layer)
                if let mask {
                    var punch = layer
                    punch.blendMode = .destinationIn
                    paint(MarkupStore.layers(mask), in: frame, clip: Path(frame),
                          size: nil, position: nil, punch)
                }
            }
        } else {
            body(&ctx)
        }
    }

    private static func paintBody(_ node: MarkupNode, css: [String: String], frame: CGRect,
                                  style: MarkupStyle,
                                  content: (text: Text, shadow: Text?, lines: Int)?,
                                  block: Double, isFlex: Bool,
                                  _ ctx: GraphicsContext) {
        if node.tag == "svg" {
            svg(node, frame: frame, ctx)
            return
        }

        let radius = CSS.length(css["border-radius"], base: min(frame.width, frame.height)) ?? 0
        let shape = radius > 0
            ? Path(roundedRect: frame, cornerRadius: min(radius, min(frame.width, frame.height) / 2))
            : Path(frame)

        for shadow in CSS.shadows(css["box-shadow"]) where !shadow.inset {
            var c = ctx
            c.addFilter(.shadow(color: shadow.color.color, radius: shadow.blur / 2,
                                x: shadow.dx, y: shadow.dy,
                                blendMode: .normal, options: .shadowOnly))
            c.fill(shape, with: .color(.black))
        }

        if let value = css["background"] ?? css["background-image"] {
            paint(MarkupStore.layers(value), in: frame, clip: shape,
                  size: css["background-size"], position: css["background-position"], ctx)
        }

        borders(css, frame: frame, radius: radius, ctx)

        for shadow in CSS.shadows(css["box-shadow"]) where shadow.inset {
            var c = ctx
            c.clip(to: shape)
            if shadow.blur > 0 { c.addFilter(.blur(radius: shadow.blur / 2)) }
            let hole = frame.insetBy(dx: shadow.spread, dy: shadow.spread)
                .offsetBy(dx: shadow.dx, dy: shadow.dy)
            var path = Path(frame.insetBy(dx: -frame.width - 40, dy: -frame.height - 40))
            path.addPath(radius > 0 ? Path(roundedRect: hole, cornerRadius: radius) : Path(hole))
            c.fill(path, with: .color(shadow.color.color), style: FillStyle(eoFill: true))
        }

        if isFlex {
            flex(node, css: css, frame: frame, style: style, ctx)
            return
        }
        if let content {
            text(content, in: frame, block: block, style: style, ctx)
        }
        for child in node.elements where child.tag != "span" || !isInline(child) {
            element(child, parent: frame, fixed: nil, style: style, ctx)
        }
    }

    /// A `<span>` with no positioning is part of its parent's text run and was already drawn there.
    private static func isInline(_ node: MarkupNode) -> Bool {
        let css = CSS.style(node["style"])
        return css["position"] == nil && css["display"] == nil
    }

    // MARK: Layout

    private static func layout(_ css: [String: String], parent: CGRect, content: CGSize?) -> CGRect {
        let pw = Double(parent.width), ph = Double(parent.height)
        var top: Double?, right: Double?, bottom: Double?, left: Double?
        if let inset = css["inset"] {
            let v = CSS.split(inset, on: " ").map { CSS.length($0, base: pw) ?? 0 }
            switch v.count {
            case 0: break
            case 1: (top, right, bottom, left) = (v[0], v[0], v[0], v[0])
            case 2: (top, right, bottom, left) = (v[0], v[1], v[0], v[1])
            case 3: (top, right, bottom, left) = (v[0], v[1], v[2], v[1])
            default: (top, right, bottom, left) = (v[0], v[1], v[2], v[3])
            }
        }
        left = CSS.length(css["left"], base: pw) ?? left
        right = CSS.length(css["right"], base: pw) ?? right
        top = CSS.length(css["top"], base: ph) ?? top
        bottom = CSS.length(css["bottom"], base: ph) ?? bottom

        var w = CSS.length(css["width"], base: pw)
        var h = CSS.length(css["height"], base: ph)
        if w == nil, let l = left, let r = right { w = pw - l - r }
        if h == nil, let t = top, let b = bottom { h = ph - t - b }
        let width = max(0, w ?? Double(content?.width ?? 0))
        let height = max(0, h ?? Double(content?.height ?? 0))

        var x = left ?? right.map { pw - $0 - width } ?? 0
        var y = top ?? bottom.map { ph - $0 - height } ?? 0
        let margin = CSS.split(css["margin"] ?? "", on: " ").map { CSS.length($0, base: pw) ?? 0 }
        if let m = margin.first { y += m; x += margin.count > 3 ? margin[3] : m }
        x += CSS.length(css["margin-left"], base: pw) ?? 0
        y += CSS.length(css["margin-top"], base: ph) ?? 0
        return CGRect(x: parent.minX + x, y: parent.minY + y, width: width, height: height)
    }

    /// The width a text run gets to lay out in, before its own box is known.
    private static func measureWidth(_ css: [String: String], parent: CGRect) -> Double {
        let pw = Double(parent.width)
        if let w = CSS.length(css["width"], base: pw) { return max(w, 1) }
        let left = CSS.length(css["left"], base: pw) ?? CSS.length(css["inset"], base: pw)
        let right = CSS.length(css["right"], base: pw) ?? CSS.length(css["inset"], base: pw)
        if let l = left, let r = right { return max(pw - l - r, 1) }
        return max(pw - (left ?? right ?? 0), 1)
    }

    private static func edges(_ value: String?, box: CGSize) -> (Double, Double, Double, Double) {
        let v = CSS.split(value ?? "", on: " ").map { CSS.length($0, base: Double(box.width)) ?? 0 }
        switch v.count {
        case 0: return (0, 0, 0, 0)
        case 1: return (v[0], v[0], v[0], v[0])
        case 2: return (v[0], v[1], v[0], v[1])
        case 3: return (v[0], v[1], v[2], v[1])
        default: return (v[0], v[1], v[2], v[3])
        }
    }

    // MARK: Flex

    /// A single-line row, which is all the corpus asks for: `flex:1` items share the free space,
    /// everything else takes its own width, and `justify-content` spends whatever is left.
    private static func flex(_ node: MarkupNode, css: [String: String], frame: CGRect,
                             style: MarkupStyle, _ ctx: GraphicsContext) {
        let pad = edges(css["padding"], box: frame.size)
        let content = CGRect(x: frame.minX + pad.3, y: frame.minY + pad.0,
                             width: max(0, frame.width - pad.1 - pad.3),
                             height: max(0, frame.height - pad.0 - pad.2))
        let gap = CSS.length(css["gap"], base: Double(content.width)) ?? 0
        let items = node.elements
        guard !items.isEmpty else { return }

        var basis: [Double] = []
        var grow: [Double] = []
        for item in items {
            let ics = CSS.style(item["style"])
            let g = ics["flex"].flatMap { CSS.number($0) } ?? 0
            grow.append(g)
            if g > 0 { basis.append(0); continue }
            if let w = CSS.length(ics["width"], base: Double(content.width)) { basis.append(w); continue }
            basis.append(intrinsicWidth(item, style: style, ctx))
        }
        let used = basis.reduce(0, +) + gap * Double(items.count - 1)
        let free = max(0, Double(content.width) - used)
        let totalGrow = grow.reduce(0, +)
        var widths = basis
        if totalGrow > 0 {
            for i in widths.indices { widths[i] += free * grow[i] / totalGrow }
        }

        var x = Double(content.minX)
        var between = gap
        if totalGrow == 0 {
            switch css["justify-content"] {
            case "center": x += free / 2
            case "flex-end", "end", "right": x += free
            case "space-between" where items.count > 1: between += free / Double(items.count - 1)
            case "space-around" where items.count > 0:
                between += free / Double(items.count)
                x += free / Double(items.count) / 2
            default: break
            }
        }

        let align = css["align-items"]
        for (i, item) in items.enumerated() {
            let ics = CSS.style(item["style"])
            let h = CSS.length(ics["height"], base: Double(content.height)) ?? Double(content.height)
            var y = Double(content.minY)
            switch align {
            case "center": y = Double(content.midY) - h / 2
            case "flex-end", "end": y = Double(content.maxY) - h
            default: break
            }
            element(item, parent: content,
                    fixed: CGRect(x: x, y: y, width: widths[i], height: h), style: style, ctx)
            x += widths[i] + between
        }
    }

    private static func intrinsicWidth(_ node: MarkupNode, style: MarkupStyle,
                                       _ ctx: GraphicsContext) -> Double {
        var s = style
        apply(CSS.style(node["style"]), to: &s)
        guard let built = inline(node.children, style: s) else { return 0 }
        let resolved = ctx.resolve(built.text)
        return Double(resolved.measure(in: CGSize(width: CGFloat.greatestFiniteMagnitude,
                                                  height: CGFloat.greatestFiniteMagnitude)).width)
    }

    // MARK: Text

    private static func inline(_ children: [MarkupNode], style: MarkupStyle)
        -> (text: Text, shadow: Text?, lines: Int)? {
        var body: Text?
        var shadowBody: Text?
        var lines = 1
        var sawText = false
        let shadowColor = style.shadows.first(where: { !$0.inset })?.color

        func walk(_ nodes: [MarkupNode], _ s: MarkupStyle) {
            for node in nodes {
                if node.isText {
                    sawText = true
                    let run = node.text.replacingOccurrences(of: "\n", with: " ")
                    body = join(body, piece(run, s, s.color))
                    if let shadowColor { shadowBody = join(shadowBody, piece(run, s, shadowColor)) }
                } else if node.tag == "br" {
                    lines += 1
                    body = join(body, Text(verbatim: "\n"))
                    if shadowColor != nil { shadowBody = join(shadowBody, Text(verbatim: "\n")) }
                } else if node.tag == "span", isInline(node) {
                    var inner = s
                    apply(CSS.style(node["style"]), to: &inner)
                    walk(node.children, inner)
                }
            }
        }
        walk(children, style)
        guard sawText, let body else { return nil }
        return (body, shadowBody, lines)
    }

    private static func join(_ a: Text?, _ b: Text) -> Text { a.map { $0 + b } ?? b }

    private static func piece(_ run: String, _ s: MarkupStyle, _ color: CSSColor) -> Text {
        var t = Text(verbatim: run).font(CSS.font(s.font)).foregroundColor(color.color)
        // CSS letter-spacing puts the gap after every glyph, including the last — that is what
        // `tracking` does and `kerning` does not, and it is why the art pairs it with text-indent.
        if s.tracking != 0 { t = t.tracking(s.tracking) }
        if s.font.italic { t = t.italic() }
        return t
    }

    private static func text(_ content: (text: Text, shadow: Text?, lines: Int),
                             in frame: CGRect, block: Double, style: MarkupStyle,
                             _ base: GraphicsContext) {
        var ctx = base
        var box = frame
        if style.verticalWriting {
            // `writing-mode: vertical-rl` — one use in the corpus. The inline axis runs down the
            // box's right edge, which is exactly a +90° turn about its top-right corner.
            ctx.translateBy(x: frame.maxX, y: frame.minY)
            ctx.rotate(by: .degrees(90))
            box = CGRect(x: 0, y: 0, width: frame.height, height: frame.width)
        }
        let resolved = ctx.resolve(content.text)
        let size = resolved.measure(in: CGSize(width: max(box.width, 1),
                                               height: CGFloat.greatestFiniteMagnitude))
        var x = Double(box.minX) + style.indent
        switch style.align {
        case .center: x = Double(box.midX) - Double(size.width) / 2 + style.indent / 2
        case .trailing: x = Double(box.maxX) - Double(size.width)
        default: break
        }
        // CSS puts the *line box* at `top` and lets a line-height under 1.2 spill symmetrically;
        // SwiftUI reports the glyph box. Centring one on the other is what keeps the two agreeing.
        let y = style.verticalCentre
            ? Double(box.midY) - Double(size.height) / 2
            : Double(box.minY) + (block - Double(size.height)) / 2
        let rect = CGRect(x: x, y: y, width: Double(size.width), height: Double(size.height))

        if let shadowText = content.shadow {
            for shadow in style.shadows where !shadow.inset {
                var c = ctx
                if shadow.blur > 0 { c.addFilter(.blur(radius: shadow.blur / 2)) }
                c.draw(c.resolve(shadowText),
                       in: rect.offsetBy(dx: shadow.dx, dy: shadow.dy))
            }
        }
        ctx.draw(resolved, in: rect)
    }

    // MARK: Style resolution

    private static func apply(_ css: [String: String], to style: inout MarkupStyle) {
        if let f = css["font"] { CSS.fontShorthand(f, into: &style.font) }
        if let w = css["font-weight"] {
            style.font.weight = Int(w) ?? (w == "bold" ? 700 : (w == "normal" ? 400 : style.font.weight))
        }
        if let s = css["font-size"], let v = CSS.length(s, base: style.font.size, em: style.font.size) {
            style.font.size = v
        }
        if css["font-style"] == "italic" || css["font-style"] == "oblique" { style.font.italic = true }
        if let c = CSS.color(css["color"]) { style.color = c }
        if let ls = css["letter-spacing"] {
            style.tracking = CSS.length(ls, base: style.font.size, em: style.font.size) ?? 0
        }
        if let ti = css["text-indent"] {
            style.indent = CSS.length(ti, base: style.font.size, em: style.font.size) ?? 0
        }
        switch css["text-align"] {
        case "center": style.align = .center
        case "right", "end": style.align = .trailing
        case "left", "start": style.align = .leading
        default: break
        }
        if let ts = css["text-shadow"] { style.shadows = CSS.shadows(ts) }
        if css["writing-mode"]?.hasPrefix("vertical") == true { style.verticalWriting = true }
        if css["display"] == "flex" {
            switch css["justify-content"] {
            case "center": style.align = .center
            case "flex-end", "end": style.align = .trailing
            default: break
            }
            if css["align-items"] == "center" { style.verticalCentre = true }
        }
    }

    private static func blendMode(_ value: String?) -> GraphicsContext.BlendMode {
        switch value {
        case "multiply": return .multiply
        case "screen": return .screen
        case "overlay": return .overlay
        case "soft-light": return .softLight
        case "hard-light": return .hardLight
        case "darken": return .darken
        case "lighten": return .lighten
        case "color-dodge": return .colorDodge
        case "color-burn": return .colorBurn
        case "difference": return .difference
        case "exclusion": return .exclusion
        case "hue": return .hue
        case "saturation": return .saturation
        case "color": return .color
        case "luminosity": return .luminosity
        default: return .normal
        }
    }

    /// `filter: drop-shadow(a b c colour)` → the shadow list. `blur()` and `backdrop-filter` have
    /// no honest equivalent on a `Canvas` backdrop and are skipped rather than guessed at.
    private static func dropShadows(_ value: String?) -> String? {
        guard let value else { return nil }
        let parts = CSS.functionList(value).filter { $0.name == "drop-shadow" }.map(\.args)
        return parts.isEmpty ? nil : parts.joined(separator: ",")
    }

    private static func clipPath(_ value: String, in frame: CGRect) -> Path? {
        guard let fn = CSS.function(value), fn.name == "polygon" else { return nil }
        let points = CSS.split(fn.args, on: ",").compactMap { pair -> CGPoint? in
            let v = CSS.split(pair, on: " ")
            guard v.count >= 2,
                  let x = CSS.length(v[0], base: Double(frame.width)),
                  let y = CSS.length(v[1], base: Double(frame.height)) else { return nil }
            return CGPoint(x: frame.minX + x, y: frame.minY + y)
        }
        guard points.count >= 3 else { return nil }
        var path = Path()
        path.move(to: points[0])
        points.dropFirst().forEach { path.addLine(to: $0) }
        path.closeSubpath()
        return path
    }

    private static func borders(_ css: [String: String], frame: CGRect, radius: Double,
                                _ ctx: GraphicsContext) {
        if let value = css["border"], let spec = borderSpec(value) {
            let inset = spec.width / 2
            let rect = frame.insetBy(dx: inset, dy: inset)
            let path = radius > 0
                ? Path(roundedRect: rect, cornerRadius: max(0, radius - inset))
                : Path(rect)
            ctx.stroke(path, with: .color(spec.color.color),
                       style: StrokeStyle(lineWidth: spec.width, dash: spec.dash))
        }
        for (side, from, to) in [
            ("border-top", CGPoint(x: frame.minX, y: frame.minY), CGPoint(x: frame.maxX, y: frame.minY)),
            ("border-bottom", CGPoint(x: frame.minX, y: frame.maxY), CGPoint(x: frame.maxX, y: frame.maxY)),
            ("border-left", CGPoint(x: frame.minX, y: frame.minY), CGPoint(x: frame.minX, y: frame.maxY)),
            ("border-right", CGPoint(x: frame.maxX, y: frame.minY), CGPoint(x: frame.maxX, y: frame.maxY)),
        ] {
            guard let value = css[side], let spec = borderSpec(value) else { continue }
            var path = Path()
            path.move(to: from)
            path.addLine(to: to)
            ctx.stroke(path, with: .color(spec.color.color),
                       style: StrokeStyle(lineWidth: spec.width, dash: spec.dash))
        }
    }

    private static func borderSpec(_ value: String)
        -> (width: Double, color: CSSColor, dash: [CGFloat])? {
        var width = 1.0
        var color: CSSColor?
        var style = "solid"
        for token in CSS.split(value, on: " ") {
            if token == "dashed" || token == "dotted" || token == "solid" { style = token; continue }
            if let c = CSS.color(token) { color = c; continue }
            if let w = CSS.length(token) { width = w }
        }
        guard let color, width > 0 else { return nil }
        // The browser's own dash rhythm for a 1px border: 3× the width on, 3× off (2× for dotted).
        let dash: [CGFloat] = style == "solid"
            ? []
            : [CGFloat(width * (style == "dotted" ? 1 : 3)), CGFloat(width * (style == "dotted" ? 2 : 3))]
        return (width, color, dash)
    }

    // MARK: Backgrounds

    /// CSS paints the *first* layer on top, so the list is walked backwards.
    static func paint(_ layers: [CSSLayer], in rect: CGRect, clip shape: Path,
                      size: String?, position: String?, _ base: GraphicsContext) {
        guard rect.width > 0, rect.height > 0 else { return }
        let sizes = CSS.split(size ?? "", on: ",")
        let positions = CSS.split(position ?? "", on: ",")
        for (i, layer) in layers.enumerated().reversed() {
            let tile = tileSize(i < sizes.count ? sizes[i] : sizes.first, in: rect)
            let origin = tileOrigin(i < positions.count ? positions[i] : positions.first, in: rect)
            switch layer {
            case .color(let c):
                base.fill(shape, with: .color(c.color))
            case .gradient(let g):
                if let tile, tile.width > 0.5, tile.height > 0.5,
                   abs(tile.width - rect.width) > 0.5 || abs(tile.height - rect.height) > 0.5 {
                    drawTiledGradient(g, tile: tile, origin: origin, rect: rect, shape: shape, base)
                } else {
                    fill(g, in: rect, clip: shape, base)
                }
            case .url(let raw):
                drawImageLayer(raw, tile: tile, origin: origin, rect: rect, shape: shape, base)
            }
        }
    }

    private static func tileSize(_ value: String?, in rect: CGRect) -> CGSize? {
        guard let value, !value.isEmpty, value != "auto", value != "cover", value != "contain" else {
            return nil
        }
        let parts = CSS.split(value, on: " ")
        guard let w = CSS.length(parts.first, base: Double(rect.width)) else { return nil }
        let h = parts.count > 1 ? (CSS.length(parts[1], base: Double(rect.height)) ?? w) : w
        return CGSize(width: w, height: h)
    }

    private static func tileOrigin(_ value: String?, in rect: CGRect) -> CGPoint {
        let parts = CSS.split(value ?? "", on: " ")
        let x = CSS.length(parts.first, base: Double(rect.width)) ?? 0
        let y = parts.count > 1 ? (CSS.length(parts[1], base: Double(rect.height)) ?? 0) : 0
        return CGPoint(x: x, y: y)
    }

    static func fill(_ gradient: CSSGradient, in rect: CGRect, clip shape: Path,
                     _ base: GraphicsContext) {
        var ctx = base
        ctx.clip(to: shape)
        switch gradient {
        case .linear(let angle, let stops, let repeating):
            let a = angle * .pi / 180
            let length = abs(Double(rect.width) * sin(a)) + abs(Double(rect.height) * cos(a))
            let resolved = CSS.resolvedStops(stops, length: length, repeating: repeating)
            guard resolved.count >= 2 else { return single(resolved, shape, ctx) }
            let mid = CGPoint(x: rect.midX, y: rect.midY)
            let dx = sin(a) * length / 2, dy = -cos(a) * length / 2
            ctx.fill(shape, with: .linearGradient(
                CSS.gradient(resolved),
                startPoint: CGPoint(x: mid.x - dx, y: mid.y - dy),
                endPoint: CGPoint(x: mid.x + dx, y: mid.y + dy)))

        case .radial(let circle, let rxs, let rys, let cxs, let cys, let stops, let repeating):
            let g = radialGeometry(circle: circle, rx: rxs, ry: rys, cx: cxs, cy: cys, in: rect)
            let resolved = CSS.resolvedStops(stops, length: g.rx, repeating: repeating)
            guard resolved.count >= 2 else { return single(resolved, shape, ctx) }
            var c = ctx
            c.translateBy(x: g.cx, y: g.cy)
            c.scaleBy(x: 1, y: g.ratio)
            let hx = max(abs(Double(rect.minX) - g.cx), abs(Double(rect.maxX) - g.cx)) + 1
            let hy = (max(abs(Double(rect.minY) - g.cy), abs(Double(rect.maxY) - g.cy)) + 1) / g.ratio
            c.fill(Path(CGRect(x: -hx, y: -hy, width: hx * 2, height: hy * 2)),
                   with: .radialGradient(CSS.gradient(resolved), center: .zero,
                                         startRadius: 0, endRadius: g.rx))

        case .conic(let from, let cxs, let cys, let stops, let repeating):
            let cx = Double(rect.minX) + (CSS.length(cxs, base: Double(rect.width)) ?? Double(rect.width) / 2)
            let cy = Double(rect.minY) + (CSS.length(cys, base: Double(rect.height)) ?? Double(rect.height) / 2)
            let resolved = CSS.resolvedStops(stops, length: 1, repeating: repeating, degrees: true)
            guard resolved.count >= 2 else { return single(resolved, shape, ctx) }
            // CSS measures from 12 o'clock; SwiftUI's angular gradient starts at 3 o'clock.
            ctx.fill(shape, with: .conicGradient(CSS.gradient(resolved),
                                                 center: CGPoint(x: cx, y: cy),
                                                 angle: .degrees(from - 90)))
        }
    }

    private static func single(_ stops: [(color: CSSColor, at: Double)], _ shape: Path,
                               _ ctx: GraphicsContext) {
        guard let only = stops.first else { return }
        ctx.fill(shape, with: .color(only.color.color))
    }

    static func radialGeometry(circle: Bool, rx: String?, ry: String?, cx: String, cy: String,
                               in rect: CGRect)
        -> (cx: Double, cy: Double, rx: Double, ratio: Double) {
        let w = Double(rect.width), h = Double(rect.height)
        let centreX = Double(rect.minX) + (CSS.length(cx, base: w) ?? w / 2)
        let centreY = Double(rect.minY) + (CSS.length(cy, base: h) ?? h / 2)
        var radiusX = CSS.length(rx, base: w)
        var radiusY = CSS.length(ry, base: h)
        if radiusX == nil || radiusY == nil {
            let fx = max(abs(centreX - Double(rect.minX)), abs(Double(rect.maxX) - centreX))
            let fy = max(abs(centreY - Double(rect.minY)), abs(Double(rect.maxY) - centreY))
            if circle {
                let r = (fx * fx + fy * fy).squareRoot()
                radiusX = r; radiusY = r
            } else {
                // farthest-corner ellipse is the farthest-side ellipse scaled by √2.
                radiusX = fx * 2.0.squareRoot(); radiusY = fy * 2.0.squareRoot()
            }
        }
        let finalX = max(radiusX ?? 1, 0.01)
        let finalY = max(radiusY ?? 1, 0.01)
        return (centreX, centreY, finalX, finalY / finalX)
    }

    // MARK: Tiles and grain

    /// A gradient repeated on a `background-size` grid. Filling it tile by tile would be thousands
    /// of gradient draws a frame for a 5px dot screen, so the whole layer is rasterised once at
    /// twice design resolution and cached.
    private static func drawTiledGradient(_ gradient: CSSGradient, tile: CGSize, origin: CGPoint,
                                          rect: CGRect, shape: Path, _ base: GraphicsContext) {
        let key = "tile|\(tile.width)x\(tile.height)|\(rect.width)x\(rect.height)|\(gradient.cacheKey)"
        guard let image = MarkupStore.image(key, {
            MarkupRaster.tiled(gradient, tile: tile, box: rect.size, scale: 2)
        }) else { return }
        var ctx = base
        ctx.clip(to: shape)
        ctx.draw(Image(decorative: image, scale: 2), in: rect.offsetBy(dx: origin.x, dy: origin.y))
    }

    /// The only `url()` the corpus uses is an inline `data:` SVG holding an `feTurbulence` grain
    /// square. It is generated once into a tile and repeated; anything else degrades to nothing.
    private static func drawImageLayer(_ raw: String, tile: CGSize?, origin: CGPoint,
                                       rect: CGRect, shape: Path, _ base: GraphicsContext) {
        guard raw.hasPrefix("data:image/svg+xml") else { return }
        let decoded = raw
            .replacingOccurrences(of: "%22", with: "\"")
            .replacingOccurrences(of: "%23", with: "#")
            .replacingOccurrences(of: "%20", with: " ")
        guard let turbulence = findTurbulence(MarkupParser.parse(decoded)) else { return }
        let frequency = CSS.number(turbulence["basefrequency"]) ?? 0.8
        let octaves = Int(CSS.number(turbulence["numoctaves"]) ?? 3)
        let side = Int(tile?.width ?? 160)
        let key = "grain|\(frequency)|\(octaves)|\(side)"
        guard let image = MarkupStore.image(key, {
            MarkupRaster.noise(frequency: frequency, octaves: octaves, side: max(8, min(side, 512)))
        }) else { return }

        var ctx = base
        ctx.clip(to: shape)
        let size = tile ?? CGSize(width: 160, height: 160)
        guard size.width > 0.5, size.height > 0.5 else { return }
        let columns = Int(ceil(rect.width / size.width))
        let rows = Int(ceil(rect.height / size.height))
        guard columns * rows <= 4096 else { return }
        let picture = Image(decorative: image, scale: 1)
        for row in 0..<max(rows, 1) {
            for column in 0..<max(columns, 1) {
                ctx.draw(picture, in: CGRect(
                    x: rect.minX + origin.x + Double(column) * size.width,
                    y: rect.minY + origin.y + Double(row) * size.height,
                    width: size.width, height: size.height))
            }
        }
    }

    private static func findTurbulence(_ nodes: [MarkupNode]) -> MarkupNode? {
        for node in nodes {
            if node.tag == "feturbulence" { return node }
            if let hit = findTurbulence(node.children) { return hit }
        }
        return nil
    }

    // MARK: SVG

    private struct SVGEnv {
        var fill: String? = "#000000"
        var stroke: String?
        var strokeWidth: Double = 1
        var fillOpacity: Double = 1
        var strokeOpacity: Double = 1
        var evenOdd = false
        var lineCap: CGLineCap = .butt
        var dash: [CGFloat] = []

        mutating func apply(_ node: MarkupNode) {
            var attrs = node.attrs
            for (k, v) in CSS.declarations(node["style"] ?? "") { attrs[k] = v }
            if let v = attrs["fill"] { fill = v }
            if let v = attrs["stroke"] { stroke = v == "none" ? nil : v }
            if let v = CSS.number(attrs["stroke-width"]) { strokeWidth = v }
            if let v = CSS.number(attrs["fill-opacity"]) { fillOpacity = v }
            if let v = CSS.number(attrs["stroke-opacity"]) { strokeOpacity = v }
            if let v = attrs["fill-rule"] { evenOdd = v == "evenodd" }
            switch attrs["stroke-linecap"] {
            case "round": lineCap = .round
            case "square": lineCap = .square
            case "butt": lineCap = .butt
            default: break
            }
            if let v = attrs["stroke-dasharray"] { dash = CSS.numbers(v).map { CGFloat($0) } }
        }
    }

    private static func svg(_ node: MarkupNode, frame: CGRect, _ base: GraphicsContext) {
        var ctx = base
        let viewBox = CSS.numbers(node["viewbox"])
        if viewBox.count == 4, viewBox[2] > 0, viewBox[3] > 0 {
            // No fragment sets preserveAspectRatio, so the default xMidYMid meet applies.
            let s = min(Double(frame.width) / viewBox[2], Double(frame.height) / viewBox[3])
            ctx.translateBy(x: Double(frame.minX) + (Double(frame.width) - viewBox[2] * s) / 2,
                            y: Double(frame.minY) + (Double(frame.height) - viewBox[3] * s) / 2)
            ctx.scaleBy(x: s, y: s)
            ctx.translateBy(x: -viewBox[0], y: -viewBox[1])
        } else {
            ctx.translateBy(x: frame.minX, y: frame.minY)
        }
        var defs: [String: MarkupNode] = [:]
        collectDefs(node, into: &defs)
        var env = SVGEnv()
        env.apply(node)
        for child in node.children { shape(child, env: env, defs: defs, ctx) }
    }

    private static func collectDefs(_ node: MarkupNode, into defs: inout [String: MarkupNode]) {
        if let id = node["id"], !id.isEmpty { defs[id] = node }
        node.children.forEach { collectDefs($0, into: &defs) }
    }

    private static func shape(_ node: MarkupNode, env inherited: SVGEnv,
                              defs: [String: MarkupNode], _ base: GraphicsContext) {
        guard !node.isText, node.tag != "defs" else { return }
        var env = inherited
        env.apply(node)
        var ctx = base
        let transform = CSS.transform(node["transform"])
        if !transform.isIdentity { ctx.concatenate(transform) }
        let opacity = CSS.number(node["opacity"]) ?? 1

        if node.tag == "g" {
            guard opacity > 0.001 else { return }
            if opacity < 1 {
                ctx.opacity *= opacity
                ctx.drawLayer { layer in
                    layer.opacity = 1
                    for child in node.children { shape(child, env: env, defs: defs, layer) }
                }
            } else {
                for child in node.children { shape(child, env: env, defs: defs, ctx) }
            }
            return
        }
        guard let path = geometry(node), opacity > 0.001 else { return }
        if opacity < 1 { ctx.opacity *= opacity }
        if let id = reference(node["filter"]), let filter = defs[id],
           let blur = CSS.number(descendant(filter, "fegaussianblur")?["stddeviation"]) {
            ctx.addFilter(.blur(radius: blur))
        }
        let bounds = path.boundingRect
        if let fill = shading(env.fill, bounds: bounds, defs: defs, opacity: env.fillOpacity) {
            ctx.fill(path, with: fill, style: FillStyle(eoFill: env.evenOdd))
        } else if let id = reference(env.fill), let pattern = defs[id], pattern.tag == "pattern" {
            tile(pattern, over: path, defs: defs, ctx)
        }
        if env.strokeWidth > 0,
           let stroke = shading(env.stroke, bounds: bounds, defs: defs, opacity: env.strokeOpacity) {
            ctx.stroke(path, with: stroke,
                       style: StrokeStyle(lineWidth: env.strokeWidth,
                                          lineCap: env.lineCap, dash: env.dash))
        }
    }

    private static func descendant(_ node: MarkupNode, _ tag: String) -> MarkupNode? {
        if node.tag == tag { return node }
        for child in node.children { if let hit = descendant(child, tag) { return hit } }
        return nil
    }

    private static func geometry(_ node: MarkupNode) -> Path? {
        func n(_ key: String) -> Double { CSS.number(node[key]) ?? 0 }
        switch node.tag {
        case "path":
            let path = SVGPath.parse(node["d"])
            return path.isEmpty ? nil : path
        case "circle":
            let r = n("r")
            guard r > 0 else { return nil }
            return Path(ellipseIn: CGRect(x: n("cx") - r, y: n("cy") - r, width: r * 2, height: r * 2))
        case "ellipse":
            let rx = n("rx"), ry = n("ry")
            guard rx > 0, ry > 0 else { return nil }
            return Path(ellipseIn: CGRect(x: n("cx") - rx, y: n("cy") - ry,
                                          width: rx * 2, height: ry * 2))
        case "rect":
            let w = n("width"), h = n("height")
            guard w > 0, h > 0 else { return nil }
            let rect = CGRect(x: n("x"), y: n("y"), width: w, height: h)
            let rx = CSS.number(node["rx"]) ?? CSS.number(node["ry"]) ?? 0
            let ry = CSS.number(node["ry"]) ?? rx
            return rx > 0 || ry > 0
                ? Path(roundedRect: rect, cornerSize: CGSize(width: rx, height: ry))
                : Path(rect)
        case "line":
            var path = Path()
            path.move(to: CGPoint(x: n("x1"), y: n("y1")))
            path.addLine(to: CGPoint(x: n("x2"), y: n("y2")))
            return path
        case "polygon":
            let v = CSS.numbers(node["points"])
            guard v.count >= 6 else { return nil }
            var path = Path()
            path.move(to: CGPoint(x: v[0], y: v[1]))
            for i in stride(from: 2, to: v.count - 1, by: 2) {
                path.addLine(to: CGPoint(x: v[i], y: v[i + 1]))
            }
            path.closeSubpath()
            return path
        default:
            return nil
        }
    }

    private static func reference(_ value: String?) -> String? {
        guard let value, let fn = CSS.function(value), fn.name == "url" else { return nil }
        let id = fn.args.trimmingCharacters(in: CharacterSet(charactersIn: " '\"#"))
        return id.isEmpty ? nil : id
    }

    private static func shading(_ raw: String?, bounds: CGRect, defs: [String: MarkupNode],
                                opacity: Double) -> GraphicsContext.Shading? {
        guard let raw, raw != "none", !raw.isEmpty else { return nil }
        if let id = reference(raw) {
            guard let def = defs[id] else { return nil }
            return gradientShading(def, bounds: bounds, opacity: opacity)
        }
        guard let c = CSS.color(raw) else { return nil }
        return .color(c.fading(opacity).color)
    }

    private static func gradientShading(_ def: MarkupNode, bounds: CGRect,
                                        opacity: Double) -> GraphicsContext.Shading? {
        let stops = def.children.filter { $0.tag == "stop" }.compactMap { s -> Gradient.Stop? in
            guard var c = CSS.color(s["stop-color"]) else { return nil }
            if let o = CSS.number(s["stop-opacity"]) { c = c.fading(o) }
            var location = CSS.number(s["offset"]) ?? 0
            if s["offset"]?.hasSuffix("%") == true { location /= 100 }
            return .init(color: c.fading(opacity).color, location: min(max(location, 0), 1))
        }
        guard stops.count >= 2 else { return stops.first.map { .color($0.color) } }
        let g = Gradient(stops: stops)
        // No definition in the corpus sets gradientUnits, so all of them are objectBoundingBox.
        func point(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: Double(bounds.minX) + x * Double(bounds.width),
                    y: Double(bounds.minY) + y * Double(bounds.height))
        }
        switch def.tag {
        case "lineargradient":
            return .linearGradient(g,
                startPoint: point(CSS.number(def["x1"]) ?? 0, CSS.number(def["y1"]) ?? 0),
                endPoint: point(CSS.number(def["x2"]) ?? 1, CSS.number(def["y2"]) ?? 0))
        case "radialgradient":
            let r = CSS.number(def["r"]) ?? 0.5
            return .radialGradient(g,
                center: point(CSS.number(def["cx"]) ?? 0.5, CSS.number(def["cy"]) ?? 0.5),
                startRadius: 0,
                endRadius: r * Double(max(bounds.width, bounds.height)))
        default:
            return nil
        }
    }

    /// `<pattern>` — one use in the whole corpus, a 5px hatch inside a diamond. Drawing the
    /// content once per tile is bounded by the shape's own bounds, so it stays cheap.
    private static func tile(_ pattern: MarkupNode, over path: Path, defs: [String: MarkupNode],
                             _ base: GraphicsContext) {
        let w = CSS.number(pattern["width"]) ?? 0
        let h = CSS.number(pattern["height"]) ?? 0
        guard w > 0.5, h > 0.5 else { return }
        var ctx = base
        ctx.clip(to: path)
        let transform = CSS.transform(pattern["patterntransform"])
        if !transform.isIdentity { ctx.concatenate(transform) }
        // The bounds have to be taken back through the pattern transform, so tile far enough to
        // cover the rotated shape.
        let bounds = path.boundingRect.insetBy(dx: -path.boundingRect.width,
                                               dy: -path.boundingRect.height)
        let columns = Int(ceil(bounds.width / w)), rows = Int(ceil(bounds.height / h))
        guard columns > 0, rows > 0, columns * rows <= 4096 else { return }
        var env = SVGEnv()
        env.fill = nil
        for row in 0..<rows {
            for column in 0..<columns {
                var cell = ctx
                cell.translateBy(x: bounds.minX + Double(column) * w, y: bounds.minY + Double(row) * h)
                for child in pattern.children { shape(child, env: env, defs: defs, cell) }
            }
        }
    }
}

private extension CSSGradient {
    /// Enough of the gradient to key a raster cache on.
    var cacheKey: String {
        switch self {
        case .linear(let a, let s, let r): return "l\(a)|\(r)|\(s.map(\.key).joined())"
        case .radial(let c, let rx, let ry, let cx, let cy, let s, let r):
            return "r\(c)\(rx ?? "")\(ry ?? "")\(cx)\(cy)|\(r)|\(s.map(\.key).joined())"
        case .conic(let f, let cx, let cy, let s, let r):
            return "c\(f)\(cx)\(cy)|\(r)|\(s.map(\.key).joined())"
        }
    }
}

private extension CSSStop {
    var key: String { "\(color.r),\(color.g),\(color.b),\(color.a):\(positions.joined(separator: " "));" }
}

// MARK: - Rasterisers

/// The two things that must never be evaluated per frame: a tiled gradient and fractal grain.
enum MarkupRaster {

    private static func context(width: Int, height: Int, scale: CGFloat) -> CGContext? {
        CGContext(data: nil,
                  width: max(1, Int(CGFloat(width) * scale)),
                  height: max(1, Int(CGFloat(height) * scale)),
                  bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    /// One tile of `gradient`, repeated across a `box`-sized image.
    static func tiled(_ gradient: CSSGradient, tile: CGSize, box: CGSize, scale: CGFloat) -> CGImage? {
        guard tile.width > 0.5, tile.height > 0.5, box.width > 0.5, box.height > 0.5,
              box.width * scale < 4096, box.height * scale < 4096,
              let cell = context(width: Int(ceil(tile.width)), height: Int(ceil(tile.height)),
                                 scale: scale) else { return nil }
        cell.scaleBy(x: scale, y: scale)
        // CG's origin is bottom-left; CSS's is top-left. Flip so the gradient reads the same way.
        cell.translateBy(x: 0, y: tile.height)
        cell.scaleBy(x: 1, y: -1)
        draw(gradient, in: cell, rect: CGRect(origin: .zero, size: tile))
        guard let tileImage = cell.makeImage(),
              let sheet = context(width: Int(ceil(box.width)), height: Int(ceil(box.height)),
                                  scale: scale) else { return nil }
        sheet.scaleBy(x: scale, y: scale)
        sheet.draw(tileImage, in: CGRect(origin: .zero, size: tile), byTiling: true)
        return sheet.makeImage()
    }

    private static func draw(_ gradient: CSSGradient, in ctx: CGContext, rect: CGRect) {
        let options: CGGradientDrawingOptions = [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        switch gradient {
        case .linear(let angle, let stops, let repeating):
            let a = angle * .pi / 180
            let length = abs(Double(rect.width) * sin(a)) + abs(Double(rect.height) * cos(a))
            guard let g = CSS.cgGradient(CSS.resolvedStops(stops, length: length, repeating: repeating))
            else { return }
            let mid = CGPoint(x: rect.midX, y: rect.midY)
            let dx = sin(a) * length / 2, dy = -cos(a) * length / 2
            ctx.drawLinearGradient(g,
                                   start: CGPoint(x: mid.x - dx, y: mid.y - dy),
                                   end: CGPoint(x: mid.x + dx, y: mid.y + dy),
                                   options: options)
        case .radial(let circle, let rx, let ry, let cx, let cy, let stops, let repeating):
            let geo = MarkupRenderer.radialGeometry(circle: circle, rx: rx, ry: ry,
                                                    cx: cx, cy: cy, in: rect)
            guard let g = CSS.cgGradient(CSS.resolvedStops(stops, length: geo.rx, repeating: repeating))
            else { return }
            ctx.saveGState()
            ctx.translateBy(x: geo.cx, y: geo.cy)
            ctx.scaleBy(x: 1, y: geo.ratio)
            ctx.drawRadialGradient(g, startCenter: .zero, startRadius: 0,
                                   endCenter: .zero, endRadius: geo.rx, options: options)
            ctx.restoreGState()
        case .conic:
            // ponytail: Core Graphics has no conic gradient and nothing in the corpus tiles one.
            // If a card ever does, the fix is wedge approximation here, not a general renderer.
            return
        }
    }

    /// `feTurbulence type="fractalNoise"` as a tile. Grain is texture, not geometry, so this is a
    /// seeded value-noise sum rather than Perlin: the lattice period is tied to the tile so the
    /// square stitches to itself, matching `stitchTiles="stitch"`.
    static func noise(frequency: Double, octaves: Int, side: Int) -> CGImage? {
        let n = max(8, side)
        var pixels = [UInt8](repeating: 0, count: n * n * 4)
        let octaveCount = max(1, min(octaves, 6))

        func hash(_ x: Int, _ y: Int, _ salt: Int) -> Double {
            var v = UInt64(bitPattern: Int64(x &* 374_761_393 &+ y &* 668_265_263 &+ salt &* 1_442_695_041))
            v = (v ^ (v >> 13)) &* 1_274_126_177
            return Double((v ^ (v >> 16)) & 0xFFFF) / 65535.0
        }

        func value(_ x: Double, _ y: Double, period: Int, salt: Int) -> Double {
            let x0 = Int(floor(x)), y0 = Int(floor(y))
            let fx = x - Double(x0), fy = y - Double(y0)
            let sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy)
            func at(_ i: Int, _ j: Int) -> Double {
                hash(((i % period) + period) % period, ((j % period) + period) % period, salt)
            }
            let top = at(x0, y0) + sx * (at(x0 + 1, y0) - at(x0, y0))
            let bottom = at(x0, y0 + 1) + sx * (at(x0 + 1, y0 + 1) - at(x0, y0 + 1))
            return top + sy * (bottom - top)
        }

        for y in 0..<n {
            for x in 0..<n {
                for channel in 0..<4 {
                    var sum = 0.0
                    var amplitude = 0.5
                    var f = frequency
                    for octave in 0..<octaveCount {
                        let period = max(1, Int((Double(n) * f).rounded()))
                        sum += amplitude * (value(Double(x) * f, Double(y) * f,
                                                  period: period, salt: channel * 31 + octave) - 0.5)
                        amplitude /= 2
                        f *= 2
                    }
                    let v = min(max(sum + 0.5, 0), 1)
                    pixels[(y * n + x) * 4 + channel] = UInt8(v * 255)
                }
            }
        }
        // Premultiply, since the bitmap is declared premultipliedLast.
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let a = Double(pixels[i + 3]) / 255
            for c in 0..<3 { pixels[i + c] = UInt8(Double(pixels[i + c]) * a) }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGImage(width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: n * 4, space: space,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false,
                       intent: .defaultIntent)
    }
}
