import Foundation

/// One node of a parsed card-art fragment. `tag` is `"#text"` for character data.
///
/// Tag and attribute names are lower-cased on the way in. That is safe for *this* corpus — no two
/// names in the 1.6 MB of shop markup collide when folded (`viewBox`, `baseFrequency`,
/// `linearGradient`, `patternTransform` are each unique lower-cased) — and it means every lookup
/// downstream is a plain lower-case key.
struct MarkupNode: Hashable {
    var tag: String
    var attrs: [String: String] = [:]
    var children: [MarkupNode] = []
    var text: String = ""

    var isText: Bool { tag == "#text" }
    subscript(_ name: String) -> String? { attrs[name] }

    /// The element children, i.e. everything that takes part in layout.
    var elements: [MarkupNode] { children.filter { !$0.isText } }

    /// Whether this node is part of the *material* a face is printed on rather than something
    /// printed on it — a painted `div`, with no lettering and no mark anywhere beneath it. See
    /// `MarkupStore.material(_:)` for what reads this and why.
    var isMaterial: Bool {
        guard tag == "div", let style = attrs["style"], style.contains("background") else { return false }
        return !carriesInk
    }

    /// Any text, any `<svg>`, or any `font` declaration, at any depth.
    private var carriesInk: Bool {
        if tag == "svg" || tag == "img" { return true }
        if isText, text.contains(where: { !$0.isWhitespace }) { return true }
        if let style = attrs["style"], style.contains("font") { return true }
        return children.contains(where: \.carriesInk)
    }
}

/// A deliberately small HTML/SVG reader. It is not a browser and must not become one: it handles
/// the shapes the shop corpus actually uses — quoted attributes (whose values may contain `<`, `>`
/// and a whole nested `data:` SVG), self-closing tags, `<br>`, and comments. There are no entities
/// anywhere in the corpus, so there is no entity table.
enum MarkupParser {

    /// The only unclosed element in the corpus. Everything else either self-closes or has a
    /// matching end tag; a stray open tag is still recovered from at end of input.
    private static let voids: Set<String> = ["br", "img", "hr", "input", "meta", "link", "source"]

    static func parse(_ markup: String) -> [MarkupNode] {
        let s = Array(markup)
        let n = s.count
        var roots: [MarkupNode] = []
        var stack: [MarkupNode] = []
        var i = 0

        func emit(_ node: MarkupNode) {
            if stack.isEmpty { roots.append(node) } else { stack[stack.count - 1].children.append(node) }
        }

        func closeTo(_ tag: String) {
            guard let at = stack.lastIndex(where: { $0.tag == tag }) else { return }
            while stack.count > at {
                let done = stack.removeLast()
                emit(done)
            }
        }

        while i < n {
            if s[i] != "<" {
                var j = i
                while j < n && s[j] != "<" { j += 1 }
                let run = String(s[i..<j])
                // ponytail: whitespace-only runs are the newlines between sibling divs. Dropping
                // them is safe here because no face relies on an inter-element space; if one ever
                // does, it will show up as two words running together, not as a crash.
                if !run.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    emit(MarkupNode(tag: "#text", text: run))
                }
                i = j
                continue
            }

            i += 1
            guard i < n else { break }

            if s[i] == "!" {                                   // comment / doctype
                while i < n && s[i] != ">" { i += 1 }
                i += 1
                continue
            }

            if s[i] == "/" {                                   // end tag
                i += 1
                var name = ""
                while i < n && s[i] != ">" { name.append(s[i]); i += 1 }
                i += 1
                closeTo(name.trimmingCharacters(in: .whitespaces).lowercased())
                continue
            }

            var name = ""
            while i < n, s[i].isLetter || s[i].isNumber || s[i] == "-" { name.append(s[i]); i += 1 }
            let tag = name.lowercased()
            var attrs: [String: String] = [:]

            while i < n {
                while i < n, s[i].isWhitespace { i += 1 }
                if i >= n || s[i] == ">" || s[i] == "/" { break }
                var key = ""
                while i < n, s[i] != "=", s[i] != ">", s[i] != "/", !s[i].isWhitespace {
                    key.append(s[i]); i += 1
                }
                var value = ""
                if i < n, s[i] == "=" {
                    i += 1
                    if i < n, s[i] == "\"" || s[i] == "'" {
                        let quote = s[i]
                        i += 1
                        while i < n, s[i] != quote { value.append(s[i]); i += 1 }
                        i += 1
                    } else {
                        while i < n, !s[i].isWhitespace, s[i] != ">" { value.append(s[i]); i += 1 }
                    }
                }
                if !key.isEmpty { attrs[key.lowercased()] = value }
            }

            var selfClosing = false
            if i < n, s[i] == "/" { selfClosing = true; i += 1 }
            if i < n, s[i] == ">" { i += 1 }

            let node = MarkupNode(tag: tag, attrs: attrs)
            if selfClosing || voids.contains(tag) {
                emit(node)
            } else {
                stack.append(node)
            }
        }

        while let done = stack.popLast() { emit(done) }
        return roots
    }
}

/// The vocabulary this renderer covers, and the walk that proves a fragment stays inside it.
/// `MarkupSelfCheck` runs this over all 191 faces and 60 headers and asserts the result is empty.
enum MarkupSupport {

    static let tags: Set<String> = [
        "#text", "div", "span", "br",
        "svg", "g", "path", "circle", "rect", "ellipse", "line", "polygon",
        "defs", "lineargradient", "radialgradient", "stop", "pattern",
        "filter", "feturbulence", "fegaussianblur",
    ]

    static let properties: Set<String> = [
        "position", "inset", "left", "top", "right", "bottom", "width", "height",
        "background", "background-image", "background-size", "background-position",
        "color", "font", "font-weight", "font-style", "font-size", "letter-spacing",
        "border-radius", "box-shadow", "text-align", "opacity", "mix-blend-mode",
        "text-indent", "margin", "margin-left", "margin-top", "text-shadow", "transform",
        "border", "border-left", "border-top", "border-right", "border-bottom",
        "flex", "display", "justify-content", "align-items", "padding", "gap",
        "-webkit-mask-image", "mask-image", "mask-composite",
        "filter", "pointer-events", "backdrop-filter", "clip-path", "writing-mode",
    ]

    static let functions: Set<String> = [
        "rgb", "rgba", "url", "polygon", "blur", "drop-shadow",
        "linear-gradient", "radial-gradient", "conic-gradient",
        "repeating-linear-gradient", "repeating-radial-gradient", "repeating-conic-gradient",
        "translate", "translatex", "translatey", "scale", "scalex", "scaley",
        "rotate", "matrix",
    ]

    /// Every construct in `nodes` this renderer does not know about, as `"<tag>"`, `"css:prop"`
    /// or `"fn:name()"`. Empty means the fragment draws with nothing silently dropped.
    static func unsupported(in nodes: [MarkupNode]) -> [String] {
        var found: Set<String> = []
        func walk(_ node: MarkupNode) {
            if !tags.contains(node.tag) { found.insert("<\(node.tag)>") }
            if let style = node["style"] {
                for (prop, value) in CSS.declarations(style) {
                    if !properties.contains(prop) { found.insert("css:\(prop)") }
                    for fn in CSS.functionNames(in: value) where !functions.contains(fn) {
                        found.insert("fn:\(fn)()")
                    }
                }
            }
            for name in ["transform", "patterntransform"] {
                guard let value = node[name] else { continue }
                for fn in CSS.functionNames(in: value) where !functions.contains(fn) {
                    found.insert("fn:\(fn)()")
                }
            }
            node.children.forEach(walk)
        }
        nodes.forEach(walk)
        return found.sorted()
    }
}
