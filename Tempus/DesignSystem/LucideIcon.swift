import SwiftUI

/// The four Lucide v0.469.0 glyphs the Home header uses, ported by feeding the reference's own
/// `d` strings through `SVGPath` (`DesignSystem/Markup/SVGPath.swift`) rather than a second path
/// parser. Every Lucide icon is a 24×24 viewBox, `fill: none`, 2pt stroke, round cap/join — so
/// drawing one is "parse the d string(s), scale 24→size, stroke at `2 * size/24`". Not a general
/// Lucide importer: four icons, hand-picked, because that's all Home's header needs.
enum LucideGlyph {
    case ticket, barChart3, shoppingBag, settings

    /// Each glyph's `d` path(s). `settings` is a path plus a separate circle, matched below.
    fileprivate var paths: [String] {
        switch self {
        case .ticket:
            return ["M2 9a3 3 0 0 1 0 6v2a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-2a3 3 0 0 1 0-6V7a2 2 0 0 0-2-2H4a2 2 0 0 0-2 2Z",
                    "M13 5v2", "M13 17v2", "M13 11v2"]
        case .barChart3:
            return ["M3 3v16a2 2 0 0 0 2 2h16", "M18 17V9", "M13 17V5", "M8 17v-3"]
        case .shoppingBag:
            return ["M6 2 3 6v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6l-3-4Z", "M3 6h18", "M16 10a4 4 0 0 1-8 0"]
        case .settings:
            return ["M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.1a2 2 0 0 1 1 1.72v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.39a2 2 0 0 0-.73-2.73l-.15-.08a2 2 0 0 1-1-1.74v-.5a2 2 0 0 1 1-1.74l.15-.09a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2z"]
        }
    }

    /// `settings` also draws a stroked circle — `cx 12, cy 12, r 3` — in the same 24-unit space.
    fileprivate var circle: (cx: Double, cy: Double, r: Double)? {
        self == .settings ? (12, 12, 3) : nil
    }

    /// Parsed once per glyph, not on every `body` evaluation.
    fileprivate static let cache: [LucideGlyph: [Path]] = {
        var out: [LucideGlyph: [Path]] = [:]
        for glyph in [ticket, barChart3, shoppingBag, settings] {
            var parsed = glyph.paths.map { SVGPath.parse($0) }
            if let c = glyph.circle {
                parsed.append(Path(ellipseIn: CGRect(x: c.cx - c.r, y: c.cy - c.r, width: c.r * 2, height: c.r * 2)))
            }
            out[glyph] = parsed
        }
        return out
    }()
}

#if DEBUG
/// Each of the four glyphs must parse to a non-empty, plausibly-bounded path — the net under a
/// `d` string that silently mis-scans (see `MarkupSelfCheck.swift` for the same idea against the
/// Concourse corpus). All four sit in the 24×24 viewBox with a little slack for stroke width.
func lucideSelfCheck() {
    for glyph in [LucideGlyph.ticket, .barChart3, .shoppingBag, .settings] {
        let paths = LucideGlyph.cache[glyph] ?? []
        assert(!paths.isEmpty, "\(glyph): no paths parsed")
        let bounds = paths.reduce(CGRect.null) { $0.union($1.boundingRect) }
        assert(!bounds.isEmpty, "\(glyph): parsed path has an empty bounding box")
        assert(bounds.width > 1 && bounds.height > 1, "\(glyph): parsed path is degenerate (\(bounds))")
        let pad: CGFloat = 1
        assert(bounds.minX > -pad && bounds.minY > -pad && bounds.maxX < 24 + pad && bounds.maxY < 24 + pad,
               "\(glyph): parsed path falls outside the 24×24 viewBox (\(bounds))")
    }
}
#endif

/// One glyph, stroked at the size the caller asks for. The 24-unit viewBox scales to `size`, and
/// the stroke scales with it — exactly as SVG does, so a 20pt icon draws at a 1.667pt line, not a
/// flat 2pt. Colour is the caller's; no design token lives here because this view has none of its
/// own (`TColor.steel600` is passed in by `HomeScreen`).
struct LucideIcon: View {
    var glyph: LucideGlyph
    var size: CGFloat
    var color: Color

    var body: some View {
        let scale = size / 24
        Canvas { context, _ in
            for path in LucideGlyph.cache[glyph] ?? [] {
                let scaled = path.applying(CGAffineTransform(scaleX: scale, y: scale))
                context.stroke(scaled, with: .color(color),
                                style: StrokeStyle(lineWidth: 2 * scale, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: size, height: size)
    }
}
