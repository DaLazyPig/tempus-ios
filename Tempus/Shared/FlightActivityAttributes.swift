import Foundation
import ActivityKit

/// The flight's Live Activity payload — the Dynamic Island pill and the lock-screen banner.
/// It carries a wall-clock `endsAt` rather than a duration, so the countdown and the
/// progress bar can count themselves down with `Text(timerInterval:)` /
/// `ProgressView(timerInterval:)` while the app is suspended. Nothing here is ever pushed
/// once a second — an update replaces the whole `ContentState`, it does not tick it.
///
/// Compiled into both the app target (which starts/updates/ends the activity) and the
/// widget target (which draws it), so it must stay dependency-free: Foundation +
/// ActivityKit only, no app types.
struct FlightActivityAttributes: ActivityAttributes {
    /// Fixed for the life of the activity — what does not change between takeoff and landing.
    let subject: String
    let flightNo: String
    let originCode: String
    let destinationCode: String
    let destinationCity: String
    /// What a +5 min extension costs, shown on the extend button.
    let extendMiles: Int
    /// Business class has no extend button and a longer hold to leave; the widget reads this
    /// to choose "Exit" / "Emergency exit" over "End" / "End flight".
    let businessClass: Bool

    /// What can change while the activity is live. In practice only the deadline moves
    /// (extending the flight), so there is nothing here that needs a per-second push.
    struct ContentState: Codable, Hashable {
        let startedAt: Date
        let endsAt: Date
        /// "lose 12 mi" / "keep 12 mi" / the business-class exit bill, precomputed — the widget
        /// cannot see AppModel.Status to work this out for itself.
        let stakeLabel: String

        /// Fraction of the flight flown, read fresh at render time rather than stored, so it
        /// stays correct however long it has been since the last update.
        func progress() -> Double {
            let total = endsAt.timeIntervalSince(startedAt)
            guard total > 0 else { return 1 }
            return min(1, max(0, Date().timeIntervalSince(startedAt) / total))
        }
    }
}
