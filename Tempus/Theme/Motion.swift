import SwiftUI

/// Durations, in seconds. The reference declares them in milliseconds; the names match.
enum TDur {
    static let instant: Double = 0.090
    static let fast: Double = 0.160
    static let base: Double = 0.240
    static let slow: Double = 0.420
    static let scene: Double = 0.700
}

/// `--press-scale` / `--hover-lift`. Hover has no touch equivalent; the lift is kept for the
/// pointer-driven surfaces (iPad trackpad) and is otherwise inert.
enum TPress {
    static let scale: CGFloat = 0.975
    static let lift: CGFloat = -1
}

extension Animation {
    /// `--ease-glide: cubic-bezier(.22,.61,.36,1)` — the house curve. Everything moves on this
    /// unless the reference names another. No springs, no bounce, anywhere.
    static func glide(_ duration: Double = TDur.base) -> Animation {
        .timingCurve(0.22, 0.61, 0.36, 1, duration: duration)
    }

    /// `--ease-in-out: cubic-bezier(.65,0,.35,1)`
    static func easeInOutTP(_ duration: Double = TDur.base) -> Animation {
        .timingCurve(0.65, 0, 0.35, 1, duration: duration)
    }

    /// `--ease-exit: cubic-bezier(.4,0,1,1)` — for things leaving that should not linger.
    static func exit(_ duration: Double = TDur.base) -> Animation {
        .timingCurve(0.4, 0, 1, 1, duration: duration)
    }

    /// The onboarding scene curve, `cubic-bezier(.87,0,.13,1)`. Only onboarding uses it.
    static func onboarding(_ duration: Double) -> Animation {
        .timingCurve(0.87, 0, 0.13, 1, duration: duration)
    }
}

/// Easing functions as plain maths, for the places that drive a value by hand off a progress
/// clock rather than by animating a property (the onboarding scenes, the deck deal, the tear).
enum TEase {
    static func clamp(_ v: Double, _ a: Double = 0, _ b: Double = 1) -> Double {
        max(a, min(b, v))
    }

    static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

    /// `eInOut` — cubic in-out.
    static func inOut(_ t: Double) -> Double {
        t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }

    /// `eOut` — cubic out.
    static func out(_ t: Double) -> Double { 1 - pow(1 - t, 3) }

    /// `eIn` — cubic in.
    static func easeIn(_ t: Double) -> Double { t * t * t }

    /// `eExpo`
    static func expo(_ t: Double) -> Double { t >= 1 ? 1 : 1 - pow(2, -9 * t) }

    /// `eSoft` — the exponential in-out the onboarding scenes run on.
    static func soft(_ t: Double) -> Double {
        if t <= 0 { return 0 }
        if t >= 1 { return 1 }
        return t < 0.5 ? pow(2, 18 * t - 10) : 1 - pow(2, -18 * t + 8)
    }

    /// Cubic-bezier evaluated for y at a given x, for curves that have to be sampled by hand.
    /// Newton-Raphson with a bisection fallback, which is what browsers do.
    static func bezier(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ x: Double) -> Double {
        func curve(_ a: Double, _ b: Double, _ t: Double) -> Double {
            let u = 1 - t
            return 3 * u * u * t * a + 3 * u * t * t * b + t * t * t
        }
        func slope(_ a: Double, _ b: Double, _ t: Double) -> Double {
            let u = 1 - t
            return 3 * u * u * a + 6 * u * t * (b - a) + 3 * t * t * (1 - b)
        }
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        var t = x
        for _ in 0..<8 {
            let d = slope(x1, x2, t)
            if abs(d) < 1e-6 { break }
            let err = curve(x1, x2, t) - x
            if abs(err) < 1e-7 { return curve(y1, y2, t) }
            t -= err / d
        }
        var lo = 0.0, hi = 1.0
        t = x
        for _ in 0..<20 {
            let v = curve(x1, x2, t)
            if abs(v - x) < 1e-7 { break }
            if v < x { lo = t } else { hi = t }
            t = (lo + hi) / 2
        }
        return curve(y1, y2, t)
    }

    /// The house glide curve, sampled.
    static func glide(_ t: Double) -> Double { bezier(0.22, 0.61, 0.36, 1, t) }
    /// The onboarding scene curve, sampled.
    static func scene(_ t: Double) -> Double { bezier(0.87, 0, 0.13, 1, t) }
}
