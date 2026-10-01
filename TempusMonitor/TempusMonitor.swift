// DeviceActivity monitor extension — the only part of Tempus that runs when Tempus doesn't.
//
// It shares nothing with the app but SharedStore, so rather than trying to keep its own
// state in sync with anything, it re-derives one answer — should the shield be up right
// now? — every time iOS wakes it. That answer is `SharedStore.shouldShield`, and raising
// it is `Blocking.apply`: the identical code the app runs, compiled into this target too,
// so the process that decides while Tempus is open and the process that decides while it
// is closed can never drift apart.
//
// What wakes it is `Blocking.scheduleReshield`, armed by the app when an unlock is bought.
// The interval *starts* at the unlock's deadline, so intervalDidStart is the moment the
// shield goes back up. Nothing here keeps a schedule or a timer of its own.
//
// Target membership: this file, plus Tempus/Shared/SharedStore.swift and
// Tempus/Models/Blocking.swift. See SETUP.md.
import DeviceActivity
import Foundation

final class TempusMonitor: DeviceActivityMonitor {

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        refresh()
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        refresh()
    }

    /// Fires shortly before an interval ends — the deadline that matters here (an unlock
    /// expiring, a flight landing) is almost certainly not being watched by a running app,
    /// which is the whole reason this re-checks rather than trusting a timer somewhere else.
    override func intervalWillEndWarning(for activity: DeviceActivityName) {
        super.intervalWillEndWarning(for: activity)
        refresh()
    }

    /// This process only ever runs because Screen Time authorized it, so `authorized` is a
    /// question the app has to ask and this does not.
    private func refresh() {
        Blocking.apply(authorized: true)
    }
}
