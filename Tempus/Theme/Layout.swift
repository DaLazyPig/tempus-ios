import SwiftUI

/// Spacing scale — `--space-1` … `--space-20`.
enum TSpace {
    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s5: CGFloat = 20
    static let s6: CGFloat = 24
    static let s8: CGFloat = 32
    static let s10: CGFloat = 40
    static let s12: CGFloat = 48
    static let s16: CGFloat = 64
    static let s20: CGFloat = 80

    /// `--gutter-screen` — the horizontal inset every screen sits inside.
    static let gutter: CGFloat = 20
    /// `--width-screen-max`. The reference draws into a 420pt-wide phone frame; on a real device
    /// the content stays capped at this width and centres on anything wider.
    static let screenMax: CGFloat = 420
    /// `--tap-min`
    static let tapMin: CGFloat = 48

    /// A reference top padding, corrected for a phone that has a status bar.
    ///
    /// The reference's screens pad 52–64 from the top of a drawing that has no island and no
    /// status bar, so that figure is *everything* between the hardware edge and the first control.
    /// Here the same number is applied inside a safe area that has already paid 62pt of it, and
    /// the two stack: the Concourse title, the shop preview's chrome and the linked-account page
    /// all sat a full status bar lower than they were drawn. Take the greater of the two rather
    /// than both, which is exactly what `OBConst.padTop` already does for the full-bleed
    /// onboarding stack — this is its counterpart for a screen laid out inside the safe area.
    ///
    /// Floored at 12 so a device with no inset at all still clears its own edge.
    static func topInset(_ reference: CGFloat) -> CGFloat {
        max(12, reference - TSafeArea.insets.top)
    }
}

enum TRadius {
    static let xs: CGFloat = 6
    static let sm: CGFloat = 10
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let pill: CGFloat = 999
}

extension View {
    /// Caps content at `--width-screen-max` and centres it, which is how the reference's phone
    /// frame behaves once the viewport is wider than the frame.
    func tpScreenWidth() -> some View {
        frame(maxWidth: TSpace.screenMax).frame(maxWidth: .infinity)
    }
}

/// The window's safe-area insets, as numbers rather than as layout.
///
/// The reference is a web page in a phone frame that has no notch and no home indicator, so its
/// screens are laid out against the viewport's own edges. Two places here need to know what those
/// edges actually cost on a phone: the stage's clip, which has to bleed past them so a full-bleed
/// ground reaches the screen edge, and onboarding, which is laid out in that full-bleed space and
/// would otherwise put its CTA under the home indicator and its back button under the island.
/// Portrait-locked and single-window, so reading the key window is enough.
enum TSafeArea {
    static var insets: UIEdgeInsets {
        UIApplication.shared.connectedScenes
            .lazy.compactMap { $0 as? UIWindowScene }
            .first?.keyWindow?.safeAreaInsets ?? .zero
    }
}
