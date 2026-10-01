import SwiftUI
import CoreGraphics

// MARK: - Colour

/// A parsed colour that keeps its components, because gradients, grain and `groundColor` all need
/// the numbers back and `SwiftUI.Color` will not give them up. `Color(css:)` in Theme/Colors is the
/// view-level equivalent; this is the same notation set with the arithmetic still available.
struct CSSColor: Hashable {
    var r: Double, g: Double, b: Double, a: Double

    static let clear = CSSColor(r: 0, g: 0, b: 0, a: 0)
    static let black = CSSColor(r: 0, g: 0, b: 0, a: 1)

    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
    var cg: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
    func fading(_ m: Double) -> CSSColor { CSSColor(r: r, g: g, b: b, a: a * m) }
    /// Rec.601 luma on 0…255, which is the weighting the reference's `groundIsDark` uses.
    var luma: Double { (r * 0.299 + g * 0.587 + b * 0.114) * 255 }
}

// MARK: - Scanning

enum CSS {

    /// Splits on `sep` at bracket depth zero and outside quotes, so `rgba(1,2,3)` survives a
    /// comma split and a `data:` URI survives a semicolon split.
    static func split(_ s: String, on sep: Character) -> [String] {
        var out: [String] = []
        var cur = ""
        var depth = 0
        var quote: Character?
        for ch in s {
            if let q = quote {
                cur.append(ch)
                if ch == q { quote = nil }
                continue
            }
            switch ch {
            case "'", "\"": quote = ch; cur.append(ch)
            case "(": depth += 1; cur.append(ch)
            case ")": depth = max(0, depth - 1); cur.append(ch)
            case sep where depth == 0: out.append(cur); cur = ""
            default: cur.append(ch)
            }
        }
        out.append(cur)
        return out.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    /// `"a:1;b:2"` → `[("a","1"),("b","2")]`, in source order so later wins on merge.
    static func declarations(_ s: String) -> [(String, String)] {
        split(s, on: ";").compactMap { decl in
            guard let i = decl.firstIndex(of: ":") else { return nil }
            let key = decl[decl.startIndex..<i].trimmingCharacters(in: .whitespaces).lowercased()
            let value = decl[decl.index(after: i)...].trimmingCharacters(in: .whitespaces)
            return key.isEmpty ? nil : (key, value)
        }
    }

    static func style(_ s: String?) -> [String: String] {
        guard let s else { return [:] }
        var out: [String: String] = [:]
        for (k, v) in declarations(s) { out[k] = v }
        return out
    }

    /// `"rotate(45)"` → `("rotate", "45")`. Nil when the string is not a single function call.
    static func function(_ s: String) -> (name: String, args: String)? {
        guard let open = s.firstIndex(of: "("), s.hasSuffix(")") else { return nil }
        let name = s[s.startIndex..<open].trimmingCharacters(in: .whitespaces).lowercased()
        guard !name.isEmpty else { return nil }
        return (name, String(s[s.index(after: open)..<s.index(before: s.endIndex)]))
    }

    /// Every `name(` in a value, for the support audit.
    static func functionNames(in s: String) -> [String] {
        var out: [String] = []
        var word = ""
        for ch in s {
            if ch.isLetter || ch == "-" || ch.isNumber { word.append(ch) }
            else {
                if ch == "(", !word.isEmpty, word.first!.isLetter { out.append(word.lowercased()) }
                word = ""
            }
        }
        return out
    }

    /// A run of function calls, `"rotate(4) scale(2)"` → the parts.
    static func functionList(_ s: String) -> [(name: String, args: String)] {
        var out: [(String, String)] = []
        var i = s.startIndex
        while i < s.endIndex {
            guard let open = s[i...].firstIndex(of: "(") else { break }
            let name = s[i..<open].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            var depth = 1
            var j = s.index(after: open)
            while j < s.endIndex, depth > 0 {
                if s[j] == "(" { depth += 1 } else if s[j] == ")" { depth -= 1 }
                if depth > 0 { j = s.index(after: j) }
            }
            guard j < s.endIndex else { break }
            if !name.isEmpty { out.append((name, String(s[s.index(after: open)..<j]))) }
            i = s.index(after: j)
        }
        return out
    }

    // MARK: Numbers

    /// Every number in a string, tolerant of commas, units and exponents.
    static func numbers(_ s: String?) -> [Double] {
        guard let s else { return [] }
        var out: [Double] = []
        var cur = ""
        let chars = Array(s)
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if ch.isNumber || ch == "." {
                cur.append(ch)
            } else if (ch == "-" || ch == "+") && (cur.isEmpty || cur.lowercased().hasSuffix("e")) {
                cur.append(ch)
            } else if (ch == "e" || ch == "E"), !cur.isEmpty, i + 1 < chars.count,
                      chars[i + 1].isNumber || chars[i + 1] == "-" || chars[i + 1] == "+" {
                cur.append("e")
            } else {
                if let v = Double(cur) { out.append(v) }
                cur = ""
            }
            i += 1
        }
        if let v = Double(cur) { out.append(v) }
        return out
    }

    static func number(_ s: String?) -> Double? { numbers(s).first }

    /// A CSS length resolved against `base` (for `%`) and `em` (for `em`/`rem`).
    static func length(_ s: String?, base: Double = 0, em: Double = 16) -> Double? {
        guard let s = s?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        guard let v = number(s) else { return nil }
        if s.hasSuffix("%") { return v / 100 * base }
        if s.hasSuffix("em") { return v * em }
        return v
    }

    static func color(_ s: String?) -> CSSColor? {
        guard let t = s?.trimmingCharacters(in: .whitespaces).lowercased(), !t.isEmpty else { return nil }
        if t.hasPrefix("#") {
            var hex = String(t.dropFirst())
            if hex.count == 3 || hex.count == 4 { hex = hex.map { "\($0)\($0)" }.joined() }
            guard hex.count == 6 || hex.count == 8, let v = UInt64(hex, radix: 16) else { return nil }
            let bits = hex.count == 8 ? v : (v << 8) | 0xff
            return CSSColor(
                r: Double((bits >> 24) & 0xff) / 255, g: Double((bits >> 16) & 0xff) / 255,
                b: Double((bits >> 8) & 0xff) / 255, a: Double(bits & 0xff) / 255
            )
        }
        if t.hasPrefix("rgb") {
            let n = numbers(function(t)?.args)
            guard n.count >= 3 else { return nil }
            return CSSColor(r: n[0] / 255, g: n[1] / 255, b: n[2] / 255, a: n.count > 3 ? n[3] : 1)
        }
        switch t {
        case "white": return CSSColor(r: 1, g: 1, b: 1, a: 1)
        case "black": return .black
        case "transparent", "none": return .clear
        default: return nil
        }
    }
}

// MARK: - Gradients

/// A colour stop with its positions still in source form: they only mean something once the
/// gradient line's length is known.
struct CSSStop {
    var color: CSSColor
    var positions: [String] = []
}

enum CSSGradient {
    /// `angle` is CSS degrees: clockwise from "to top".
    case linear(angle: Double, stops: [CSSStop], repeating: Bool)
    case radial(circle: Bool, rx: String?, ry: String?, cx: String, cy: String,
                stops: [CSSStop], repeating: Bool)
    case conic(from: Double, cx: String, cy: String, stops: [CSSStop], repeating: Bool)
}

/// One layer of a `background` / `background-image` list. CSS paints the first layer on top.
enum CSSLayer {
    case color(CSSColor)
    case gradient(CSSGradient)
    case url(String)
}

extension CSS {

    /// Parses a `background` / `background-image` value into its layers, topmost first.
    static func layers(_ value: String) -> [CSSLayer] {
        split(value, on: ",").compactMap { part in
            if let c = color(part) { return .color(c) }
            guard let fn = function(part) else { return nil }
            if fn.name == "url" {
                var raw = fn.args.trimmingCharacters(in: .whitespaces)
                if let q = raw.first, q == "'" || q == "\"" { raw = String(raw.dropFirst().dropLast()) }
                return .url(raw)
            }
            return gradient(fn.name, fn.args).map { .gradient($0) }
        }
    }

    static func gradient(_ name: String, _ args: String) -> CSSGradient? {
        let repeating = name.hasPrefix("repeating-")
        let kind = repeating ? String(name.dropFirst("repeating-".count)) : name
        var parts = split(args, on: ",")
        guard !parts.isEmpty else { return nil }

        // The first part is geometry only when it is not itself a stop. Testing it as a *stop*
        // rather than as a colour is what keeps `radial-gradient(rgba(…) .7px, …)` — a positioned
        // first stop, which is how every dot screen in the shop is drawn — from being read as a
        // size and swallowing the gradient whole.
        var head: String?
        if stop(parts[0]) == nil, !parts[0].isEmpty { head = parts.removeFirst() }
        let stops = parts.compactMap(stop)
        guard !stops.isEmpty else { return nil }

        switch kind {
        case "linear-gradient":
            return .linear(angle: linearAngle(head), stops: stops, repeating: repeating)
        case "radial-gradient":
            let g = radialGeometry(head)
            return .radial(circle: g.circle, rx: g.rx, ry: g.ry, cx: g.cx, cy: g.cy,
                           stops: stops, repeating: repeating)
        case "conic-gradient":
            let g = conicGeometry(head)
            return .conic(from: g.from, cx: g.cx, cy: g.cy, stops: stops, repeating: repeating)
        default:
            return nil
        }
    }

    private static func stop(_ s: String) -> CSSStop? {
        let tokens = split(s.replacingOccurrences(of: "\n", with: " "), on: " ")
        guard let first = tokens.first, let c = color(first) else { return nil }
        return CSSStop(color: c, positions: Array(tokens.dropFirst()))
    }

    private static func linearAngle(_ head: String?) -> Double {
        guard let head = head?.lowercased() else { return 180 }   // CSS default: to bottom
        if head.contains("deg") { return number(head) ?? 180 }
        // ponytail: the corpus writes every gradient as `Ndeg`, so the keyword forms only need the
        // four cardinals. A `to bottom right` would come out as `to bottom`, not as a crash.
        if head.contains("top") { return 0 }
        if head.contains("right") { return 90 }
        if head.contains("left") { return 270 }
        return 180
    }

    private static func radialGeometry(_ head: String?)
        -> (circle: Bool, rx: String?, ry: String?, cx: String, cy: String) {
        guard let head = head?.lowercased() else { return (false, nil, nil, "50%", "50%") }
        let sides = head.components(separatedBy: " at ")
        let shape = split(sides[0], on: " ")
        let circle = shape.contains("circle")
        let sizes = shape.filter { $0 != "circle" && $0 != "ellipse" && number($0) != nil }
        let at = sides.count > 1 ? split(sides[1], on: " ") : []
        return (circle,
                sizes.first, sizes.count > 1 ? sizes[1] : sizes.first,
                at.first ?? "50%", at.count > 1 ? at[1] : "50%")
    }

    private static func conicGeometry(_ head: String?) -> (from: Double, cx: String, cy: String) {
        guard let head = head?.lowercased() else { return (0, "50%", "50%") }
        let sides = head.components(separatedBy: " at ")
        let from = sides[0].contains("from") ? (number(sides[0]) ?? 0) : 0
        let at = sides.count > 1 ? split(sides[1], on: " ") : []
        return (from, at.first ?? "50%", at.count > 1 ? at[1] : "50%")
    }

    /// Resolves stop positions onto 0…1 of the gradient line, filling in the gaps the way CSS
    /// does (first 0, last 1, unpositioned runs spread evenly), splitting two-position stops into
    /// the hard band they describe, and expanding the repeating variants by hand.
    static func resolvedStops(_ stops: [CSSStop], length: Double, repeating: Bool,
                              degrees: Bool = false) -> [(color: CSSColor, at: Double)] {
        let unit = degrees ? 360.0 : max(length, 0.0001)
        var flat: [(CSSColor, Double?)] = []
        for s in stops {
            let values = s.positions.compactMap { p -> Double? in
                guard let v = number(p) else { return nil }
                if p.hasSuffix("%") { return v / 100 }
                if degrees { return v / 360 }
                return v / unit
            }
            if values.isEmpty { flat.append((s.color, nil)) }
            else { for v in values { flat.append((s.color, v)) } }
        }
        guard !flat.isEmpty else { return [] }
        if flat[0].1 == nil { flat[0].1 = 0 }
        if flat[flat.count - 1].1 == nil { flat[flat.count - 1].1 = 1 }
        var i = 0
        while i < flat.count {
            if flat[i].1 != nil { i += 1; continue }
            var j = i
            while j < flat.count, flat[j].1 == nil { j += 1 }
            let lo = flat[i - 1].1 ?? 0
            let hi = j < flat.count ? (flat[j].1 ?? 1) : 1
            let step = (hi - lo) / Double(j - i + 1)
            for k in i..<j { flat[k].1 = lo + step * Double(k - i + 1) }
            i = j
        }
        var located = flat.map { ($0.0, $0.1 ?? 0) }
        for k in 1..<max(located.count, 1) where located[k].1 < located[k - 1].1 {
            located[k].1 = located[k - 1].1
        }

        let plain = located.map { (color: $0.0, at: min(max($0.1, 0), 1)) }
        guard repeating else { return plain }

        let first = located.first?.1 ?? 0
        let period = (located.last?.1 ?? 1) - first
        guard period > 0.0005 else { return plain }
        let lo = Int(floor((0 - first) / period))
        let hi = Int(ceil((1 - first) / period))
        guard hi >= lo, hi - lo < 512 else { return plain }
        var out: [(color: CSSColor, at: Double)] = []
        for n in lo...hi {
            for (c, p) in located {
                let at = p + Double(n) * period
                if at < -0.001 || at > 1.001 { continue }
                out.append((c, min(max(at, 0), 1)))
            }
        }
        return out.isEmpty ? plain : out
    }

    /// The SwiftUI gradient for a resolved stop list.
    static func gradient(_ stops: [(color: CSSColor, at: Double)]) -> Gradient {
        Gradient(stops: stops.map { .init(color: $0.color.color, location: $0.at) })
    }

    /// The Core Graphics gradient for the same list, for the tile rasteriser.
    static func cgGradient(_ stops: [(color: CSSColor, at: Double)]) -> CGGradient? {
        guard stops.count >= 2, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGGradient(colorsSpace: space,
                          colors: stops.map(\.color.cg) as CFArray,
                          locations: stops.map { CGFloat($0.at) })
    }
}

// MARK: - Transforms, shadows, type

extension CSS {

    /// SVG `transform` and CSS `transform`. `size` resolves the percentage translations that only
    /// CSS uses; SVG passes `.zero` and never sees them.
    static func transform(_ s: String?, size: CGSize = .zero) -> CGAffineTransform {
        guard let s else { return .identity }
        var t = CGAffineTransform.identity
        for (name, args) in functionList(s) {
            let raw = split(args, on: ",").flatMap { split($0, on: " ") }
            let n = raw.compactMap { number($0) }
            func pct(_ i: Int, _ base: Double) -> Double {
                guard i < raw.count, let v = number(raw[i]) else { return 0 }
                return raw[i].hasSuffix("%") ? v / 100 * base : v
            }
            switch name {
            case "translate":
                t = t.translatedBy(x: pct(0, size.width), y: pct(1, size.height))
            case "translatex": t = t.translatedBy(x: pct(0, size.width), y: 0)
            case "translatey": t = t.translatedBy(x: 0, y: pct(0, size.height))
            case "scale":
                guard let sx = n.first else { break }
                t = t.scaledBy(x: sx, y: n.count > 1 ? n[1] : sx)
            case "scalex": t = t.scaledBy(x: n.first ?? 1, y: 1)
            case "scaley": t = t.scaledBy(x: 1, y: n.first ?? 1)
            case "rotate":
                guard let deg = n.first else { break }
                if n.count >= 3 {
                    t = t.translatedBy(x: n[1], y: n[2])
                        .rotated(by: deg * .pi / 180)
                        .translatedBy(x: -n[1], y: -n[2])
                } else {
                    t = t.rotated(by: deg * .pi / 180)
                }
            case "matrix":
                guard n.count >= 6 else { break }
                t = CGAffineTransform(a: n[0], b: n[1], c: n[2], d: n[3], tx: n[4], ty: n[5])
                    .concatenating(t)
            default: break
            }
        }
        return t
    }

    struct Shadow {
        var inset = false
        var dx: Double = 0, dy: Double = 0, blur: Double = 0, spread: Double = 0
        var color: CSSColor = .black
    }

    static func shadows(_ s: String?) -> [Shadow] {
        guard let s else { return [] }
        return split(s, on: ",").compactMap { part in
            var out = Shadow()
            var lengths: [Double] = []
            for token in split(part, on: " ") {
                if token.lowercased() == "inset" { out.inset = true; continue }
                if let c = color(token) { out.color = c; continue }
                if let v = length(token) { lengths.append(v) }
            }
            guard lengths.count >= 2 else { return nil }
            out.dx = lengths[0]; out.dy = lengths[1]
            if lengths.count > 2 { out.blur = lengths[2] }
            if lengths.count > 3 { out.spread = lengths[3] }
            return out
        }
    }

    struct FontSpec: Hashable {
        var weight = 400
        var size: Double = 13
        var lineHeight: Double = 1.2
        var family = "outfit"
        var italic = false
    }

    /// The `font:` shorthand as the corpus writes it — `500 13px/1 'Outfit',sans-serif`.
    /// Everything after the size token is the family list.
    static func fontShorthand(_ s: String, into spec: inout FontSpec) {
        let tokens = split(s, on: " ")
        var i = 0
        while i < tokens.count {
            let token = tokens[i]
            let lower = token.lowercased()
            i += 1
            if lower == "italic" || lower == "oblique" { spec.italic = true; continue }
            if lower == "normal" || lower == "small-caps" { continue }
            if let w = Int(token), (100...900).contains(w) { spec.weight = w; continue }
            if token.contains("px") || token.contains("em") || token.contains("/") {
                let halves = token.components(separatedBy: "/")
                if let size = length(halves[0]) { spec.size = size }
                if halves.count > 1, let lh = number(halves[1]) { spec.lineHeight = lh }
                break
            }
        }
        let rest = tokens[min(i, tokens.count)...].joined(separator: " ")
        if !rest.isEmpty { spec.family = family(from: rest) }
    }

    /// The first family in a font list, unquoted and folded.
    static func family(from list: String) -> String {
        let first = split(list, on: ",").first ?? list
        return first.trimmingCharacters(in: CharacterSet(charactersIn: " '\"")).lowercased()
    }

    /// Maps the corpus's six families onto the faces the app actually ships. The five display
    /// faces come from `TCardFont`, which already falls back to a system face of the same
    /// character when a file is missing.
    static func font(_ spec: FontSpec) -> Font {
        switch spec.family {
        case "outfit":
            return TFont.core(coreWeight(spec.weight), spec.size)
        case "dm mono":
            return TFont.data(spec.weight >= 500 ? .medium : .regular, spec.size)
        case "italiana": return TCardFont.founders.font(spec.size)
        case "archivo black": return TCardFont.archivo.font(spec.size)
        case "syne": return TCardFont.prestige.font(spec.size)
        case "big shoulders display": return TCardFont.essential.font(spec.size)
        case "georgia", "serif": return .system(size: spec.size, weight: uiWeight(spec.weight), design: .serif)
        case "monospace": return .system(size: spec.size, weight: uiWeight(spec.weight), design: .monospaced)
        default: return .system(size: spec.size, weight: uiWeight(spec.weight))
        }
    }

    static func coreWeight(_ w: Int) -> TFont.Core {
        switch w {
        case ..<350: return .light
        case ..<450: return .regular
        case ..<550: return .medium
        case ..<650: return .semibold
        case ..<750: return .bold
        default: return .extraBold
        }
    }

    private static func uiWeight(_ w: Int) -> Font.Weight {
        switch w {
        case ..<250: return .ultraLight
        case ..<350: return .light
        case ..<450: return .regular
        case ..<550: return .medium
        case ..<650: return .semibold
        case ..<750: return .bold
        case ..<850: return .heavy
        default: return .black
        }
    }
}
