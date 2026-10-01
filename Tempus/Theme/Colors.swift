import SwiftUI

/// The palette, one-for-one with the reference build's `:root` custom properties.
/// Ramps first, then the semantic roles that are defined in terms of them. Nothing in the app
/// may write a raw hex — if a colour is missing here, add it here.
enum TColor {

    // MARK: - Ramps

    static let navy900 = Color(hex: 0x101d31)
    static let navy800 = Color(hex: 0x182a45)
    static let navy700 = Color(hex: 0x23395b)
    static let navy600 = Color(hex: 0x2f4b76)
    static let navy500 = Color(hex: 0x3d5e8f)

    static let steel700 = Color(hex: 0x465a78)
    static let steel600 = Color(hex: 0x5d7496)
    static let steel500 = Color(hex: 0x7389aa)
    static let steel400 = Color(hex: 0x8ea2bf)

    static let sky500 = Color(hex: 0x7d99c3)
    static let sky400 = Color(hex: 0x96aed1)
    static let sky300 = Color(hex: 0xb3c5de)
    static let sky200 = Color(hex: 0xd0dbeb)
    static let sky100 = Color(hex: 0xe4ebf5)

    static let cloud100 = Color(hex: 0xf2f5fa)
    static let cloud050 = Color(hex: 0xf8fafd)
    static let white = Color(hex: 0xffffff)

    static let copper700 = Color(hex: 0x8f5340)
    static let copper600 = Color(hex: 0xa35f49)
    static let copper500 = Color(hex: 0xb86f52)
    static let copper400 = Color(hex: 0xcb8a71)
    static let copper300 = Color(hex: 0xe0af9c)
    static let copper100 = Color(hex: 0xf5e6df)

    // MARK: - Flight status

    static let statusOnTime = Color(hex: 0x3f7a63)
    static let statusOnTimeSoft = Color(hex: 0xe2efe9)
    static let statusDelayed = Color(hex: 0xb8894a)
    static let statusDelayedSoft = Color(hex: 0xf7ecdb)
    static let statusDiverted = Color(hex: 0xa8493c)
    static let statusDivertedSoft = Color(hex: 0xf7e3e0)

    // MARK: - Surfaces

    static let surfacePage = cloud100
    static let surfaceCard = white
    static let surfaceSunken = sky100
    static let surfaceInverse = navy700
    static let surfaceInverseRaised = navy600
    static let surfaceAccent = copper500
    static let surfaceAccentSoft = copper100

    // MARK: - Text

    static let textPrimary = navy700
    static let textSecondary = steel600
    static let textMuted = steel400
    static let textOnDark = cloud100
    static let textOnDarkMuted = Color(hex: 0x9fb3d1)
    static let textOnAccent = white
    static let textAccent = copper600
    static let textLink = copper600
    static let textLinkHover = copper700

    // MARK: - Borders and overlays

    static let borderSubtle = Color(hex: 0xe2e9f3)
    static let borderDefault = sky200
    static let borderStrong = sky400
    static let borderInverse = Color(hex: 0x33507c)
    static let focusRing = copper500

    static let overlayScrim = Color(hex: 0x101d31, opacity: 0.55)
    static let glassOnDark = Color(hex: 0xf2f5fa, opacity: 0.14)
    static let glassOnLight = Color(hex: 0x23395b, opacity: 0.06)
}

extension Color {
    /// `Color(hex: 0x23395b)` — the form every token above is written in.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: opacity
        )
    }

    /// Parses the colour notations the reference markup uses: `#rgb`, `#rrggbb`, `#rrggbbaa`,
    /// `rgb(r,g,b)`, `rgba(r,g,b,a)` and the handful of named colours that appear in the card art.
    /// Returns nil rather than guessing, so a caller can fall back deliberately.
    init?(css: String) {
        let s = css.trimmingCharacters(in: .whitespaces).lowercased()
        if s.hasPrefix("#") {
            var hex = String(s.dropFirst())
            if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
            if hex.count == 4 { hex = hex.map { "\($0)\($0)" }.joined() }
            guard let v = UInt64(hex, radix: 16) else { return nil }
            switch hex.count {
            case 6:
                self.init(hex: UInt32(v))
            case 8:
                self.init(hex: UInt32(v >> 8), opacity: Double(v & 0xff) / 255)
            default:
                return nil
            }
            return
        }
        if s.hasPrefix("rgb") {
            let body = s.drop { $0 != "(" }.dropFirst().prefix { $0 != ")" }
            let parts = body.split(whereSeparator: { $0 == "," || $0 == "/" || $0 == " " })
                .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard parts.count >= 3 else { return nil }
            self.init(
                .sRGB,
                red: parts[0] / 255, green: parts[1] / 255, blue: parts[2] / 255,
                opacity: parts.count > 3 ? parts[3] : 1
            )
            return
        }
        switch s {
        case "white": self.init(hex: 0xffffff)
        case "black": self.init(hex: 0x000000)
        case "transparent", "none": self.init(hex: 0x000000, opacity: 0)
        default: return nil
        }
    }
}
