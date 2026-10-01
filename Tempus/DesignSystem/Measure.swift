import SwiftUI

/// A measured rect that is **read at gesture time and never rendered from**.
///
/// Several screens need to know where something sits on screen so a set-piece can start from it —
/// the deck's top card seeds the preflight morph, a Concourse tile seeds the shop card's. The
/// obvious spelling, a `GeometryReader` writing into `@State`, is a per-frame invalidation loop:
/// the measured view moves (a scroll, a drag), the state changes, the owning view's `body` runs
/// again, and it does that at the display's refresh rate to answer a question that is only ever
/// asked on a tap. Storing the rect in a plain reference type breaks the loop — nothing observes
/// it, so writing it costs a store and nothing else.
final class RectBox {
    var rect: CGRect = .zero
}

extension View {
    /// Keeps `box` current with this view's frame in `space`, without invalidating anything.
    func measureRect(into box: RectBox, in space: CoordinateSpace) -> some View {
        background(
            GeometryReader { geo in
                Color.clear
                    .onChange(of: geo.frame(in: space), initial: true) { _, new in box.rect = new }
            }
        )
    }
}
