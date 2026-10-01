import Foundation
import ActivityKit

/// The screen-time unlock's Live Activity payload — the Dynamic Island pill and the lock-screen
/// banner while bought minutes are running down.
///
/// Same discipline as `FlightActivityAttributes`, and for the same reason: it carries a wall-clock
/// `until` rather than a duration, so `Text(timerInterval:)` counts itself down with the app
/// suspended or killed. Nothing here is ever pushed once a second — an unlock is started once,
/// extended at most a few times, and ended once.
///
/// The widget target cannot read the App Group (the Live Activity extension deliberately carries no
/// App Group entitlement — see SETUP.md), so everything it needs to draw is in the payload.
///
/// Compiled into both the app target and the widget target, so it stays dependency-free:
/// Foundation + ActivityKit only, no app types.
struct UnlockActivityAttributes: ActivityAttributes {
    /// What the unlock opens, as the app already names it — the picked app when the shield is the
    /// six-name stand-in, "Your selection" when it is a real `FamilyActivitySelection`. The widget
    /// cannot work this out: a shield is raised on opaque tokens with no readable name.
    let name: String

    struct ContentState: Codable, Hashable {
        /// When the current unlock began. Only used to draw how much of it is spent; extending
        /// moves `until` and leaves this where it was, so the ring keeps filling rather than
        /// resetting.
        let startedAt: Date
        /// The wall-clock deadline. The shield goes back up here whichever process notices first.
        let until: Date

        /// Fraction of the unlock spent, read fresh at render time rather than stored, so it stays
        /// correct however long it has been since the last update.
        func progress() -> Double {
            let total = until.timeIntervalSince(startedAt)
            guard total > 0 else { return 1 }
            return min(1, max(0, Date().timeIntervalSince(startedAt) / total))
        }
    }
}
