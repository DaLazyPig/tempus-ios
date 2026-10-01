import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

/// Where blocking actually happens.
///
/// Until this existed nothing in Tempus ever raised a shield. `TempusMonitor` set one, but a
/// DeviceActivity monitor only runs when iOS wakes it at an interval boundary, and no interval was
/// ever scheduled — so the extension sat there correct and unreachable, and no app was ever
/// blocked. Two things fix that, and both live here:
///
///  1. **The app writes the shield itself**, every time the state behind it changes. A
///     `ManagedSettingsStore` write is durable — it outlives the process — so while Tempus is the
///     thing that decides, it does not have to be running for the decision to hold.
///  2. **The app schedules the one wake-up it cannot do itself.** An unlock expires at a wall-clock
///     deadline that will almost certainly pass with Tempus closed, and nothing else would put the
///     shield back. So an unlock also arms a DeviceActivity interval that *starts* at that
///     deadline; `TempusMonitor.intervalDidStart` then re-derives the same answer this file does.
///
/// The interval starts at the deadline rather than ending there because DeviceActivity intervals
/// have a fifteen-minute minimum and the dial sells unlocks from five. Only the start instant
/// matters, and its length is ours to pick.
enum Blocking {

    /// Both processes name the same store through `SharedStore.storeName`. A store written under
    /// one name and read under another is silently two stores.
    private static var store: ManagedSettingsStore {
        ManagedSettingsStore(named: .init(SharedStore.storeName))
    }

    private static let activity = DeviceActivityName("tempus.unlock")

    /// Raise or lower the shield to match what `SharedStore` now says.
    ///
    /// `shouldShield` is deliberately read back out of the shared store rather than passed in, so
    /// the app and the monitor are answering from the identical bytes.
    ///
    /// A live unlock lifts the shield off the whole selection, not off one app — which is why
    /// Redeem *lists* the selection when it is real (one `Label(token)` a row) and only offers a
    /// choice when it is showing the stand-in. The price never depended on which app, either way.
    static func apply(authorized: Bool) {
        let s = SharedStore.shared
        guard authorized, let data = s.selectionData,
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else {
            clear()
            return
        }

        if s.shouldShield {
            store.shield.applications = selection.applicationTokens.isEmpty
                ? nil : selection.applicationTokens
            store.shield.applicationCategories = selection.categoryTokens.isEmpty
                ? nil : .specific(selection.categoryTokens)
            store.shield.webDomains = selection.webDomainTokens.isEmpty
                ? nil : selection.webDomainTokens
        } else {
            lower()
        }
    }

    /// Everything down, the selection kept. Used while an unlock is running.
    private static func lower() {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomains = nil
    }

    /// Everything down and the schedule torn up — Screen Time is off, or nothing is selected.
    /// Leaving a shield standing here would block apps the app no longer claims to be blocking.
    static func clear() {
        lower()
        DeviceActivityCenter().stopMonitoring([activity])
    }

    /// Arm the wake-up that puts the shield back when `until` passes.
    ///
    /// Called with `nil` when no unlock is running, which tears the schedule down — otherwise a
    /// stale interval would wake the monitor for an unlock that has already been spent.
    static func scheduleReshield(at until: Date?, authorized: Bool) {
        let center = DeviceActivityCenter()
        center.stopMonitoring([activity])
        guard authorized, let until, until > Date() else { return }

        let cal = Calendar.current
        let fields: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        let schedule = DeviceActivitySchedule(
            intervalStart: cal.dateComponents(fields, from: until),
            // ponytail: half an hour is arbitrary — only the start instant is read. Long enough to
            // clear the fifteen-minute minimum with room to spare, short enough not to sit around.
            intervalEnd: cal.dateComponents(fields, from: until.addingTimeInterval(30 * 60)),
            repeats: false)
        try? center.startMonitoring(activity, during: schedule)
    }
}
