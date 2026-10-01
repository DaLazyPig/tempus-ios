import SwiftUI

#if DEBUG
/// Asserts the things about the Concourse's card art that are easy to get subtly wrong and
/// impossible to eyeball across 191 faces: that the catalogue is all there, that every ground
/// resolves to a colour and reads the same way the reference reads it, that the path parser knows
/// every command letter the corpus actually writes, and — the one that matters most — that not one
/// face or header contains a construct this renderer would silently drop.
///
/// A failing assert traps on launch. Read the message before anything else.
func markupSelfCheck() {
    // 1. The stock is all there.
    assert(ShopCatalog.faces.count == 191, "shop.json: \(ShopCatalog.faces.count) faces, expected 191")
    assert(ShopCatalog.headers.count == 60, "shop.json: \(ShopCatalog.headers.count) headers, expected 60")
    assert(ShopCatalog.gifts.count == 18, "shop.json: \(ShopCatalog.gifts.count) gifts, expected 18")
    assert(ShopCatalog.faces(tier: 0).count + ShopCatalog.faces(tier: 1).count
           + ShopCatalog.faces(tier: 2).count + ShopCatalog.faces(tier: 3).count
           + ShopCatalog.faces(tier: 4).count == ShopCatalog.faces.count,
           "every face must sit in one of the five tiers")
    assert(ShopCatalog.face(id: "1.01") != nil && ShopCatalog.header(id: "H01") != nil
           && ShopCatalog.gift(id: "G01") != nil, "the id indexes do not resolve")

    // 2. Every ground yields a colour, and the dark/light read matches hand-checked cases.
    for face in ShopCatalog.faces {
        assert(!face.ground.isEmpty, "face \(face.id) has no ground")
        assert(ShopCatalog.groundColor(face.ground) != Color.clear, "face \(face.id) ground has no colour")
    }
    let inked: [(String, Bool)] = [
        ("background:#f4f5f7", false),                    // 1.01, the palest ground in the shop
        ("background:#18273e", true),                     // 1.03
        ("background:linear-gradient(196deg,#88a2c9 0%,#56719b 50%,#2f4468 100%)", true),   // 2.04
        ("background:linear-gradient(158deg,#7f858c 0%,#c9ced4 22%,#9aa1a8 42%,#e2e6ea 58%,#a2a8af 74%,#767c83 100%)", false), // 4.07
        ("background:rgba(0,0,0,.4)", true),              // no hex at all reads as dark
        ("", true),
    ]
    for (ground, expected) in inked {
        assert(ShopCatalog.groundIsDark(ground) == expected,
               "groundIsDark disagrees with the reference on \(ground)")
    }
    for (id, expected) in [("1.01", false), ("1.03", true), ("2.04", true), ("4.07", false)] {
        guard let face = ShopCatalog.face(id: id) else { continue }
        assert(ShopCatalog.groundIsDark(face.ground) == expected, "face \(id) inks the wrong way")
    }

    // 3. Every path command letter the corpus writes is one the parser accepts.
    var letters: Set<Character> = []
    var unsupportedNodes: Set<String> = []
    var fragments: [String] = ShopCatalog.faces.map(\.inner) + ShopCatalog.headers.map(\.inner)
    fragments += ShopCatalog.gifts.map(\.inner)

    // One walk, three questions — the corpus is 1.6 MB and this runs on every debug launch.
    for fragment in fragments {
        let tree = MarkupParser.parse(fragment)
        unsupportedNodes.formUnion(MarkupSupport.unsupported(in: tree))
        collectPathLetters(tree, into: &letters)
        // Every gradient in the corpus is authored with at least two stops, so any that resolves
        // to fewer has been mis-parsed — that is how a positioned first stop once got read as a
        // size and swallowed a whole dot screen. This is the net under that class of bug.
        for node in flatten(tree) {
            guard let style = node["style"] else { continue }
            for (property, value) in CSS.declarations(style)
            where property.hasPrefix("background") || property.hasSuffix("mask-image") {
                for layer in CSS.layers(value) {
                    guard case .gradient(let g) = layer else { continue }
                    assert(resolvedCount(g) >= 2, "gradient resolved to fewer than two stops: \(value)")
                }
            }
        }
    }
    for letter in letters {
        assert(SVGPath.accepts(letter), "SVG path command '\(letter)' is in the corpus but not in the parser")
    }
    assert(letters.contains("C") && letters.contains("M") && letters.contains("A"),
           "the command scan found nothing — it is not reading the corpus")

    // 4. Nothing in any face or header falls outside the vocabulary.
    assert(unsupportedNodes.isEmpty,
           "unsupported card-art constructs: \(unsupportedNodes.sorted().joined(separator: ", "))")

    // 5. The grounds are markup too, and the same rules apply.
    var unsupportedGrounds: Set<String> = []
    for value in ShopCatalog.faces.map(\.ground) + ShopCatalog.headers.map(\.bg)
        + ShopCatalog.gifts.map(\.bg) {
        let bare = CSS.declarations(value).first(where: { $0.0.hasPrefix("background") })?.1 ?? value
        let layers = CSS.layers(bare)
        assert(!layers.isEmpty, "a ground parsed to no layers: \(value)")
        for layer in layers {
            guard case .gradient(let g) = layer else { continue }
            assert(resolvedCount(g) >= 2, "a ground gradient resolved to fewer than two stops: \(value)")
        }
        for fn in CSS.functionNames(in: value) where !MarkupSupport.functions.contains(fn) {
            unsupportedGrounds.insert(fn)
        }
    }
    assert(unsupportedGrounds.isEmpty,
           "unsupported ground functions: \(unsupportedGrounds.sorted().joined(separator: ", "))")

    // 6. The path parser produces geometry, not an empty path, for a real `d` from the corpus.
    let tooth = "M0 -19.17C0 -12.46 8.94 0 13.76 0C8.94 0 0 12.46 0 19.17C0 12.46 -8.94 0 -13.76 0Z"
    assert(!SVGPath.parse(tooth).isEmpty, "the path parser returned nothing for a known path")
    assert(SVGPath.parse("M0 0 A5 5 0 0 1 10 0").boundingRect.width > 4, "arcs are not being drawn")
    assert(SVGPath.parse("nonsense").isEmpty, "malformed path data should draw nothing, not trap")
}

private func flatten(_ nodes: [MarkupNode]) -> [MarkupNode] {
    nodes.flatMap { [$0] + flatten($0.children) }
}

private func resolvedCount(_ gradient: CSSGradient) -> Int {
    switch gradient {
    case .linear(_, let stops, let repeating):
        return CSS.resolvedStops(stops, length: 214, repeating: repeating).count
    case .radial(_, _, _, _, _, let stops, let repeating):
        return CSS.resolvedStops(stops, length: 120, repeating: repeating).count
    case .conic(_, _, _, let stops, let repeating):
        return CSS.resolvedStops(stops, length: 1, repeating: repeating, degrees: true).count
    }
}

/// The command letters in every `d` attribute, skipping the `e` of an exponent — which is the one
/// letter in the corpus that is part of a number rather than an instruction.
private func collectPathLetters(_ nodes: [MarkupNode], into letters: inout Set<Character>) {
    for node in nodes {
        if let d = node["d"] {
            var previous: Character = " "
            for ch in d {
                if ch.isLetter, !((ch == "e" || ch == "E") && (previous.isNumber || previous == ".")) {
                    letters.insert(ch)
                }
                previous = ch
            }
        }
        collectPathLetters(node.children, into: &letters)
    }
}
#endif
