import SwiftUI
import CoreGraphics

/// SVG path `d` data → `Path`. Every command letter is covered, including the ones the shop
/// corpus does not currently use, because a new card is a data change and must not need a code
/// change. Malformed input stops the walk and returns what was read so far — never a trap.
enum SVGPath {

    static let supportedCommands: Set<Character> = Set("MmLlHhVvCcSsQqTtAaZz")

    static func accepts(_ command: Character) -> Bool { supportedCommands.contains(command) }

    static func parse(_ d: String?) -> Path {
        var path = Path()
        guard let d, !d.isEmpty else { return path }
        var scan = Scan(Array(d))
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        var lastCubic: CGPoint?
        var lastQuad: CGPoint?
        var command: Character?

        func point(_ x: Double, _ y: Double, relative: Bool) -> CGPoint {
            relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
        }

        while true {
            scan.skipSeparators()
            guard !scan.isAtEnd else { break }
            if scan.peekIsLetter {
                command = scan.takeLetter()
            }
            guard let raw = command, accepts(raw) else { break }
            let relative = raw.isLowercase
            let c = Character(raw.uppercased())

            switch c {
            case "M":
                guard let x = scan.number(), let y = scan.number() else { return path }
                current = point(x, y, relative: relative)
                subpathStart = current
                path.move(to: current)
                command = relative ? "l" : "L"
                lastCubic = nil; lastQuad = nil
            case "L":
                guard let x = scan.number(), let y = scan.number() else { return path }
                current = point(x, y, relative: relative)
                path.addLine(to: current)
                lastCubic = nil; lastQuad = nil
            case "H":
                guard let x = scan.number() else { return path }
                current = CGPoint(x: relative ? current.x + x : x, y: current.y)
                path.addLine(to: current)
                lastCubic = nil; lastQuad = nil
            case "V":
                guard let y = scan.number() else { return path }
                current = CGPoint(x: current.x, y: relative ? current.y + y : y)
                path.addLine(to: current)
                lastCubic = nil; lastQuad = nil
            case "C":
                guard let a = scan.number(), let b = scan.number(),
                      let e = scan.number(), let f = scan.number(),
                      let g = scan.number(), let h = scan.number() else { return path }
                let c1 = point(a, b, relative: relative)
                let c2 = point(e, f, relative: relative)
                current = point(g, h, relative: relative)
                path.addCurve(to: current, control1: c1, control2: c2)
                lastCubic = c2; lastQuad = nil
            case "S":
                guard let e = scan.number(), let f = scan.number(),
                      let g = scan.number(), let h = scan.number() else { return path }
                let c1 = lastCubic.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                let c2 = point(e, f, relative: relative)
                current = point(g, h, relative: relative)
                path.addCurve(to: current, control1: c1, control2: c2)
                lastCubic = c2; lastQuad = nil
            case "Q":
                guard let a = scan.number(), let b = scan.number(),
                      let e = scan.number(), let f = scan.number() else { return path }
                let ctrl = point(a, b, relative: relative)
                current = point(e, f, relative: relative)
                path.addQuadCurve(to: current, control: ctrl)
                lastQuad = ctrl; lastCubic = nil
            case "T":
                guard let e = scan.number(), let f = scan.number() else { return path }
                let ctrl = lastQuad.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                current = point(e, f, relative: relative)
                path.addQuadCurve(to: current, control: ctrl)
                lastQuad = ctrl; lastCubic = nil
            case "A":
                guard let rx = scan.number(), let ry = scan.number(), let rot = scan.number(),
                      let large = scan.number(), let sweep = scan.number(),
                      let x = scan.number(), let y = scan.number() else { return path }
                let end = point(x, y, relative: relative)
                addArc(&path, from: current, to: end, rx: rx, ry: ry,
                       rotation: rot, largeArc: large != 0, sweep: sweep != 0)
                current = end
                lastCubic = nil; lastQuad = nil
            case "Z":
                path.closeSubpath()
                current = subpathStart
                command = nil
                lastCubic = nil; lastQuad = nil
            default:
                return path
            }
        }
        return path
    }

    /// Endpoint → centre parameterisation, then cubic segments of at most 90°. Exact enough that
    /// the difference is invisible at card scale, and it keeps the arc in the same subpath so a
    /// following `Z` still closes the shape it belongs to.
    private static func addArc(_ path: inout Path, from p0: CGPoint, to p1: CGPoint,
                               rx: Double, ry: Double, rotation: Double,
                               largeArc: Bool, sweep: Bool) {
        var rx = abs(rx), ry = abs(ry)
        guard rx > 0, ry > 0 else { path.addLine(to: p1); return }
        let phi = rotation * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)
        let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
        let x1 = cosPhi * dx + sinPhi * dy
        let y1 = -sinPhi * dx + cosPhi * dy
        let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if lambda > 1 { let k = lambda.squareRoot(); rx *= k; ry *= k }
        let num = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
        let den = rx * rx * y1 * y1 + ry * ry * x1 * x1
        let factor = den == 0 ? 0 : max(0, num / den).squareRoot() * (largeArc == sweep ? -1 : 1)
        let cx1 = factor * rx * y1 / ry
        let cy1 = -factor * ry * x1 / rx
        let cx = cosPhi * cx1 - sinPhi * cy1 + (p0.x + p1.x) / 2
        let cy = sinPhi * cx1 + cosPhi * cy1 + (p0.y + p1.y) / 2

        func angle(_ ux: Double, _ uy: Double, _ vx: Double, _ vy: Double) -> Double {
            let dot = ux * vx + uy * vy
            let len = (ux * ux + uy * uy).squareRoot() * (vx * vx + vy * vy).squareRoot()
            guard len > 0 else { return 0 }
            let a = acos(min(max(dot / len, -1), 1))
            return (ux * vy - uy * vx) < 0 ? -a : a
        }
        let theta = angle(1, 0, (x1 - cx1) / rx, (y1 - cy1) / ry)
        var delta = angle((x1 - cx1) / rx, (y1 - cy1) / ry, (-x1 - cx1) / rx, (-y1 - cy1) / ry)
        if !sweep, delta > 0 { delta -= 2 * .pi }
        if sweep, delta < 0 { delta += 2 * .pi }

        let steps = max(1, Int(ceil(abs(delta) / (.pi / 2))))
        let step = delta / Double(steps)
        let alpha = 4.0 / 3.0 * tan(step / 4)
        var t = theta
        for _ in 0..<steps {
            let cosT = cos(t), sinT = sin(t)
            let cosE = cos(t + step), sinE = sin(t + step)
            func map(_ ex: Double, _ ey: Double) -> CGPoint {
                CGPoint(x: cx + cosPhi * rx * ex - sinPhi * ry * ey,
                        y: cy + sinPhi * rx * ex + cosPhi * ry * ey)
            }
            let c1 = map(cosT - alpha * sinT, sinT + alpha * cosT)
            let c2 = map(cosE + alpha * sinE, sinE - alpha * cosE)
            path.addCurve(to: map(cosE, sinE), control1: c1, control2: c2)
            t += step
        }
    }

    /// A number scanner that tolerates the ways `d` data is written: commas, no separator at all,
    /// leading dots, and exponents.
    private struct Scan {
        let chars: [Character]
        var index = 0
        init(_ chars: [Character]) { self.chars = chars }

        var isAtEnd: Bool { index >= chars.count }
        var peekIsLetter: Bool { index < chars.count && chars[index].isLetter }

        mutating func skipSeparators() {
            while index < chars.count, chars[index] == "," || chars[index].isWhitespace { index += 1 }
        }

        mutating func takeLetter() -> Character {
            defer { index += 1 }
            return chars[index]
        }

        mutating func number() -> Double? {
            skipSeparators()
            var out = ""
            if index < chars.count, chars[index] == "-" || chars[index] == "+" {
                out.append(chars[index]); index += 1
            }
            while index < chars.count, chars[index].isNumber { out.append(chars[index]); index += 1 }
            if index < chars.count, chars[index] == "." {
                out.append("."); index += 1
                while index < chars.count, chars[index].isNumber { out.append(chars[index]); index += 1 }
            }
            if index < chars.count, chars[index] == "e" || chars[index] == "E" {
                var lookahead = index + 1
                var suffix = "e"
                if lookahead < chars.count, chars[lookahead] == "-" || chars[lookahead] == "+" {
                    suffix.append(chars[lookahead]); lookahead += 1
                }
                if lookahead < chars.count, chars[lookahead].isNumber {
                    while lookahead < chars.count, chars[lookahead].isNumber {
                        suffix.append(chars[lookahead]); lookahead += 1
                    }
                    out += suffix
                    index = lookahead
                }
            }
            return Double(out)
        }
    }
}
