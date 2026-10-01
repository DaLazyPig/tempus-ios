import SwiftUI

/// The house mark, standalone for the TempusActivity widget extension.
///
/// TempusActivity cannot see Tempus/Models/Carriers.swift — Tempus/ is a
/// PBXFileSystemSynchronizedRootGroup and only files listed in that target's membership
/// exceptions compile into it (see project.pbxproj). This is therefore a dependency-free
/// copy of `CarrierMarkShape`/`CarrierMarkView`'s geometry, named differently because this
/// file *also* compiles into the main Tempus app target by default (the same pattern as
/// Shared/SharedStore.swift and Shared/FlightActivityAttributes.swift) and a duplicate
/// `CarrierMarkShape` there would collide with Carriers.swift's own.
///
/// Duplication of ~25 lines of path geometry is the established pattern at this target
/// boundary. Keep this in step with Carriers.swift by hand if the mark's geometry changes.
struct WidgetCarrierMarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        // STAR
        p.move(to: CGPoint(x: 0, y: -19.17))
        p.addCurve(to: CGPoint(x: 13.76, y: 0),
                   control1: CGPoint(x: 0, y: -12.46), control2: CGPoint(x: 8.94, y: 0))
        p.addCurve(to: CGPoint(x: 0, y: 19.17),
                   control1: CGPoint(x: 8.94, y: 0), control2: CGPoint(x: 0, y: 12.46))
        p.addCurve(to: CGPoint(x: -13.76, y: 0),
                   control1: CGPoint(x: 0, y: 12.46), control2: CGPoint(x: -8.94, y: 0))
        p.addCurve(to: CGPoint(x: 0, y: -19.17),
                   control1: CGPoint(x: -8.94, y: 0), control2: CGPoint(x: 0, y: -12.46))
        p.closeSubpath()
        // HOLE
        p.move(to: CGPoint(x: 0, y: -13.71))
        p.addCurve(to: CGPoint(x: 9.84, y: 0),
                   control1: CGPoint(x: 0, y: -8.91), control2: CGPoint(x: 6.4, y: 0))
        p.addCurve(to: CGPoint(x: 0, y: 13.71),
                   control1: CGPoint(x: 6.4, y: 0), control2: CGPoint(x: 0, y: 8.91))
        p.addCurve(to: CGPoint(x: -9.84, y: 0),
                   control1: CGPoint(x: 0, y: 8.91), control2: CGPoint(x: -6.4, y: 0))
        p.addCurve(to: CGPoint(x: 0, y: -13.71),
                   control1: CGPoint(x: -6.4, y: 0), control2: CGPoint(x: 0, y: -8.91))
        p.closeSubpath()
        return p.offsetBy(dx: rect.midX, dy: rect.midY)
    }
}

/// Ring + punched star, one colour, scaled from its native 29.34 × 40.18 box (cornerRadius
/// 14.67, lineWidth 1.83) to a given height. `stroke`, not `strokeBorder` — see the note on
/// Carriers.CarrierMarkView, which this mirrors.
struct WidgetCarrierMarkView: View {
    var color: Color
    var height: CGFloat = 16

    private static let nativeSize = CGSize(width: 29.34, height: 40.18)
    private static let stroke: CGFloat = 1.83

    /// The box the mark actually *inks*, which is not `nativeSize`. `stroke` centres the ring on
    /// the path (see `CarrierMarkView` for why it is not `strokeBorder`), so the ring's outer edge
    /// sits half a line width outside `nativeSize` on all four sides — 31.17 × 42.01 in total.
    ///
    /// Sizing the view off `nativeSize` therefore declared a frame narrower and shorter than the
    /// drawing, and **the Dynamic Island clips its compact regions to the frame it is handed**: the
    /// ring's right edge was being shaved off every compact and minimal presentation. It read as
    /// the leading glyph alone being cut because `IslandMark` carried a `.padding(.leading, 3)`,
    /// which bought the left overflow room and left the right overflow with none. Fixed
    /// 21 Sep 2026 by measuring the ink rather than the path; `height` now means visible height,
    /// which is what every call site already assumed it meant.
    private static let inkSize = CGSize(width: nativeSize.width + stroke,
                                        height: nativeSize.height + stroke)

    var body: some View {
        let s = height / Self.inkSize.height
        ZStack {
            RoundedRectangle(cornerRadius: 14.67, style: .circular)
                .stroke(color, lineWidth: Self.stroke)
                .frame(width: Self.nativeSize.width, height: Self.nativeSize.height)
            WidgetCarrierMarkShape()
                .fill(color, style: FillStyle(eoFill: true))
                .frame(width: Self.nativeSize.width, height: Self.nativeSize.height)
        }
        .scaleEffect(s)
        .frame(width: Self.inkSize.width * s, height: height)
    }
}
