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
///
/// In stage points — see `TStage` — which are the window's own on any phone at least
/// `TStage.designHeight` tall.
enum TSafeArea {
    static var insets: UIEdgeInsets {
        let i = UIApplication.shared.connectedScenes
            .lazy.compactMap { $0 as? UIWindowScene }
            .first?.keyWindow?.safeAreaInsets ?? .zero
        let s = TStage.scale
        return UIEdgeInsets(top: i.top / s, left: i.left / s, bottom: i.bottom / s, right: i.right / s)
    }
}

/// **The short-screen stage.** Every screen here was drawn against a 17 Pro and a 16 Plus, and on a
/// 667pt window — an iPhone SE, and *every iPad*, which runs this iPhone-only app in a 375 × 667
/// compatibility window — about ten of them ran off the bottom: onboarding's Next buttons, the
/// Business Class legal links, the flight's dial. App Review rejected build 43 for it (Guideline 4,
/// on an iPad Air). Rather than a second layout for each, `StageRoot` lays the whole app out on a
/// canvas `designHeight` tall and scales it down to the window, so a short phone shows the same
/// screen, smaller.
///
/// **On a phone at least `designHeight` tall `scale` is exactly 1 and nothing changes** — no
/// wrapper, `.global` coordinates, the window's own insets. Everything below is identity there.
///
/// Inside the canvas, UIKit's numbers are window points and SwiftUI's are stage points, so the
/// three ways this app reads the window go through here: `bounds` for `UIScreen.main.bounds`,
/// `TSafeArea.insets` (already divided), and `space` for what used to be `.global`.
enum TStage {
    /// The standard iPhone height (390 × 844). At 812 onboarding's Status Club screen, which has no
    /// flexible space in its column, put its Next button on the last tier row; 844 clears it.
    static let designHeight: CGFloat = 844
    static let spaceName = "tempus.stage"

    /// Portrait-only, so the window never changes height for the life of the process.
    static let scale: CGFloat = min(1, UIScreen.main.bounds.height / designHeight)

    static var bounds: CGRect {
        let b = UIScreen.main.bounds
        return CGRect(x: 0, y: 0, width: b.width / scale, height: b.height / scale)
    }

    /// Window coordinates in stage points. `.global` inside a scaled canvas is the *scaled* window,
    /// so a rect measured there and drawn inside the canvas would land short by the scale.
    static var space: CoordinateSpace { scale < 1 ? .named(spaceName) : .global }

    /// A keyboard or other UIKit frame, from window points to stage points.
    static func points(_ window: CGFloat) -> CGFloat { window / scale }
}
