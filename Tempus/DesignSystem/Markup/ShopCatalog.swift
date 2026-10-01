import SwiftUI

/// One card face on the Concourse shelf. `t` is the tier the face belongs to (0…4), `ground` is a
/// CSS *declaration* (`"background:#f4f5f7"`) and `inner` is the art fragment drawn over it.
struct ShopFace: Codable, Identifiable, Hashable {
    /// The art with the member's name in place of the sample holder the catalogue is authored
    /// with — every surface that draws a face whole goes through this, never `inner` directly.
    func inner(for name: String) -> String { inner.replacingOccurrences(of: "Olivia Reyes", with: name) }

    let id: String
    let t: Int
    let name: String
    let price: Int
    let ground: String
    let inner: String
}

/// A pass header. `bg` is a bare CSS background *value*, not a declaration.
struct ShopHeader: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let price: Int
    let bg: String
    let inner: String
}

/// A gift face. `extra` is the surcharge in miles on top of the gift's own value.
struct ShopGift: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let extra: Int
    let bg: String
    let inner: String

    /// The face's markup with this gift's own figure and recipient written into it.
    ///
    /// `replaceAll(replaceAll(inner,'250 mi', amt+' mi'), 'For Marcus', who ? 'For '+first : 'A gift')`
    /// — a literal, case-sensitive substring replace, exactly as the reference does it. It lives
    /// here rather than in `GiftScreen` because the *recipient* draws this card too, on Status
    /// Club's Requests row, and drawing the catalogue's default there prints "250 mi / For Marcus"
    /// on a 400 mi gift sent to someone else entirely.
    func personalized(amt: Int, who: String?) -> String {
        var s = inner.replacingOccurrences(of: "250 mi", with: "\(amt) mi")
        let trimmed = who?.trimmingCharacters(in: .whitespaces) ?? ""
        let forWhom = trimmed.isEmpty ? "A gift"
            : "For " + (trimmed.split(separator: " ").first.map(String.init) ?? trimmed)
        s = s.replacingOccurrences(of: "For Marcus", with: forWhom)
        return s
    }
}

/// The Concourse's stock, decoded once from `shop.json` on first touch. 1.7 MB of markup, so
/// nothing here parses art — that happens per face, on first draw, in `MarkupView`.
enum ShopCatalog {

    private struct Payload: Decodable {
        var faces: [ShopFace] = []
        var headers: [ShopHeader] = []
        var gifts: [ShopGift] = []
    }

    /// `static let` is lazy and runs its initialiser exactly once, under the runtime's own lock —
    /// so this decodes off whichever thread asks first and every later reader sees the result.
    private static let stock: Payload = {
        let candidates = [
            Bundle.main.url(forResource: "shop", withExtension: "json"),
            Bundle.main.url(forResource: "shop", withExtension: "json", subdirectory: "Resources"),
        ].compactMap { $0 }
        for url in candidates {
            guard let data = try? Data(contentsOf: url),
                  let decoded = try? JSONDecoder().decode(Payload.self, from: data) else { continue }
            return decoded
        }
        return Payload()
    }()

    static var faces: [ShopFace] { stock.faces }
    static var headers: [ShopHeader] { stock.headers }
    static var gifts: [ShopGift] { stock.gifts }

    private static let faceIndex = Dictionary(faces.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    private static let headerIndex = Dictionary(headers.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    private static let giftIndex = Dictionary(gifts.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

    static func face(id: String) -> ShopFace? { faceIndex[id] }
    static func header(id: String) -> ShopHeader? { headerIndex[id] }
    static func gift(id: String) -> ShopGift? { giftIndex[id] }

    static func faces(tier: Int) -> [ShopFace] { faces.filter { $0.t == tier } }

    // MARK: - What Business Class is for

    /// **The Concourse itself is open to everyone; most of what is *on* it is not.**
    ///
    /// It used to be gated whole — `ConcourseLocked` was the entire screen without the plan — and
    /// that sold the wrong thing: a member who has flown for their miles could not spend them on
    /// anything, so the shop read as an advertisement rather than as a shop. It is a shelf now,
    /// and the plan buys the top of it.
    ///
    /// The split is by price, because in this catalogue price is how quality was authored — the
    /// 48-mile faces are the elaborate ones. It is stated as a price **ceiling** rather than as a
    /// rank, so it always lands on a whole price band: half of a band open and half locked would
    /// read as arbitrary on a shelf where two tiles plainly cost the same.
    ///
    /// At the current prices that leaves 55 of 191 faces and 14 of 60 headers open — 69 of 251,
    /// so **72.5% of the shelf is Business Class**. `shopSelfCheck` pins that share, so a price
    /// edit that quietly moves it trips on the next debug launch rather than in the App Store.
    ///
    /// Gift faces are deliberately not in this: a gift is already paid for twice over (the miles
    /// it carries plus its surcharge) and it is the one thing on the shelf a member buys *for
    /// someone else*, who may well not hold the plan.
    static let freeFaceCeiling = 28
    static let freeHeaderCeiling = 16

    static func businessOnly(_ face: ShopFace) -> Bool { face.price > freeFaceCeiling }
    static func businessOnly(_ header: ShopHeader) -> Bool { header.price > freeHeaderCeiling }

    /// Every six-digit hex in a declaration, exactly as the reference's `/#([0-9a-f]{6})/gi` reads
    /// them: three-digit shorthands do not count, and an eight-digit hex contributes its first six.
    private static func hexes(_ css: String) -> [CSSColor] {
        let chars = Array(css)
        var out: [CSSColor] = []
        var i = 0
        while i < chars.count {
            guard chars[i] == "#" else { i += 1; continue }
            let end = i + 7
            guard end <= chars.count else { break }
            let body = chars[(i + 1)..<end]
            guard body.allSatisfy({ $0.isHexDigit }) else { i += 1; continue }
            if let c = CSS.color("#" + String(body)) { out.append(c) }
            i = end
        }
        return out
    }

    /// True when the face's ground reads as dark, so ink flips to light. Port of `groundIsDark`:
    /// mean Rec.601 luma of the declaration's hexes, below 150 on 0…255. A ground with no hex at
    /// all — a bare gradient of `rgba()` — is treated as dark, which is what the reference does.
    static func groundIsDark(_ ground: String) -> Bool {
        let colors = hexes(ground)
        guard !colors.isEmpty else { return true }
        return colors.reduce(0) { $0 + $1.luma } / Double(colors.count) < 150
    }

    /// The flat colour behind a face — the component-wise mean of its ground's hexes. Port of
    /// `groundHex`, whose fallback is the navy the rest of the app is built on.
    static func groundColor(_ ground: String) -> Color {
        let colors = hexes(ground)
        guard !colors.isEmpty else { return TColor.navy700 }
        let n = Double(colors.count)
        let r = colors.reduce(0) { $0 + $1.r } / n
        let g = colors.reduce(0) { $0 + $1.g } / n
        let b = colors.reduce(0) { $0 + $1.b } / n
        return Color(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}
