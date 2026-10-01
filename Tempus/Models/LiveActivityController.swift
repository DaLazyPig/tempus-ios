import Foundation
import ActivityKit

/// Starts, updates and ends the flight's Live Activity.
///
/// The activity carries a **wall-clock deadline**, not a duration, so the Dynamic Island and the
/// lock-screen banner count themselves down with the app suspended or killed. This controller is
/// therefore almost silent: it fires at takeoff, once more if the flight is extended, and at
/// touchdown. It must never push a per-second update — that is what the deadline is for.
enum LiveActivityController {

    private static var current: Activity<FlightActivityAttributes>?

    /// Whether the user has left Live Activities enabled for Tempus.
    static var available: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    static func start(
        subject: String,
        flightNo: String,
        origin: String,
        destination: Destination?,
        businessClass: Bool,
        extendMiles: Int,
        startedAt: Date,
        endsAt: Date,
        stakeLabel: String
    ) {
        guard available, current == nil else { return }

        let attributes = FlightActivityAttributes(
            subject: subject,
            flightNo: flightNo,
            originCode: origin,
            destinationCode: destination?.code ?? "\u{2014}",
            destinationCity: destination?.city ?? "\u{2014}",
            extendMiles: extendMiles,
            businessClass: businessClass
        )
        let state = FlightActivityAttributes.ContentState(
            startedAt: startedAt, endsAt: endsAt, stakeLabel: stakeLabel
        )

        do {
            current = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: endsAt.addingTimeInterval(60)),
                pushType: nil
            )
        } catch {
            // A refused activity is not a failed flight. The flight is authoritative; this is a
            // convenience surface, so log and carry on rather than disturbing the departure.
            current = nil
        }
    }

    /// Only the deadline moves, and only when a flight is extended.
    static func update(startedAt: Date, endsAt: Date, stakeLabel: String) {
        guard let activity = current else { return }
        let state = FlightActivityAttributes.ContentState(
            startedAt: startedAt, endsAt: endsAt, stakeLabel: stakeLabel
        )
        Task {
            await activity.update(.init(state: state, staleDate: endsAt.addingTimeInterval(60)))
        }
    }

    static func end() {
        guard let activity = current else { return }
        current = nil
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// After a relaunch the app has no handle on an activity it started in a previous process.
    /// Reattach rather than starting a second one over the top.
    static func reattach() {
        current = Activity<FlightActivityAttributes>.activities.first
    }
}


/// Starts, updates and ends the **unlock's** Live Activity — bought screen time counting down to
/// the moment the shield goes back up.
///
/// A sibling rather than a branch of `LiveActivityController` because `Activity` is generic over
/// its attributes: one stored handle cannot hold both, and a flight and an unlock can be live at
/// the same time (a flight always beats an unlock for the shield, but both are real facts and the
/// member is entitled to see either counting down).
///
/// Same rule as the flight's: fire on start, on extend, and on end. Never once a second — the
/// deadline in the payload is what the countdown runs off.
enum UnlockActivityController {

    private static var current: Activity<UnlockActivityAttributes>?

    static func start(name: String, startedAt: Date, until: Date) {
        // An unlock that is extended or swapped arrives here again with a new deadline. Update the
        // one on screen rather than stacking a second pill on top of it — and do that
        // unconditionally, never behind the `available` gate below. That gate reads
        // `ActivityAuthorizationInfo` fresh on every call, which is right for deciding whether to
        // *start* a brand new activity but wrong for an update: an already-running activity must
        // keep tracking the real deadline even if that read flips momentarily (Low Power Mode,
        // the member toggling Live Activities off and back on mid-unlock). Gating the update too
        // was how an extend or an app swap could leave the pill counting down to the old time —
        // ticking, but toward the wrong deadline.
        if current != nil {
            update(startedAt: startedAt, until: until)
            return
        }
        guard LiveActivityController.available else { return }
        let state = UnlockActivityAttributes.ContentState(startedAt: startedAt, until: until)
        do {
            current = try Activity.request(
                attributes: UnlockActivityAttributes(name: name),
                content: .init(state: state, staleDate: until.addingTimeInterval(60)),
                pushType: nil
            )
        } catch {
            // A refused activity is not a failed unlock. The shield is authoritative; this is a
            // convenience surface.
            current = nil
        }
    }

    static func update(startedAt: Date, until: Date) {
        guard let activity = current else { return }
        let state = UnlockActivityAttributes.ContentState(startedAt: startedAt, until: until)
        Task {
            await activity.update(.init(state: state, staleDate: until.addingTimeInterval(60)))
        }
    }

    static func end() {
        guard let activity = current else { return }
        current = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    /// After a relaunch the app has no handle on an activity it started in a previous process.
    static func reattach() {
        current = Activity<UnlockActivityAttributes>.activities.first
    }
}
