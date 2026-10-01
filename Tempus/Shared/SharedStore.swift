import Foundation

/// The App Group surface the extensions share.
///
/// The monitor, the shield and the shield's action buttons run in their own processes and can see
/// nothing of `AppModel`. Everything they need — the balance, the spend rate, which apps are
/// blocked, whether an unlock is running, whether a flight is in the air — has to be mirrored here
/// by `AppModel.syncSharedStore`.
///
/// This file is compiled into every target, so it must stay dependency-free: Foundation only, no
/// SwiftUI, no app types.
public struct SharedStore {

    public static let suiteName = "group.com.crescerestudios.tempus"

    /// The name of the `ManagedSettingsStore` both the app and the monitor write. It lives here
    /// as a plain string because this file may not import ManagedSettings — but a store written
    /// under one name and read under another is silently two stores, so it may only be spelled
    /// once.
    public static let storeName = "tempus"

    public static let shared = SharedStore()

    private let defaults: UserDefaults?

    public init() {
        defaults = UserDefaults(suiteName: SharedStore.suiteName)
    }

    private enum Key {
        static let balance = "tempus.shared.balance"
        static let spendRate = "tempus.shared.spendRate"
        static let blocked = "tempus.shared.blocked"
        static let unlockedID = "tempus.shared.unlockedID"
        static let unlockedUntil = "tempus.shared.unlockedUntil"
        static let flying = "tempus.shared.flying"
        static let flightEndsAt = "tempus.shared.flightEndsAt"
        static let request = "tempus.shared.unlockRequest"
        static let selection = "tempus.shared.selection"
        static let allowance = "tempus.shared.allowance"
        static let horizon = "tempus.shared.horizon"
        static let reportDays = "tempus.shared.reportDays"
    }

    // MARK: - Written by the app

    public func write(balance: Int, spendRate: Double, blocked: [String],
                      unlockedID: String?, unlockedUntil: TimeInterval?,
                      flying: Bool, flightEndsAt: TimeInterval?,
                      selection: Data?, allowance: Int) {
        guard let d = defaults else { return }
        d.set(selection, forKey: Key.selection)
        d.set(allowance, forKey: Key.allowance)
        d.set(balance, forKey: Key.balance)
        d.set(spendRate, forKey: Key.spendRate)
        d.set(blocked, forKey: Key.blocked)
        d.set(unlockedID, forKey: Key.unlockedID)
        d.set(unlockedUntil ?? 0, forKey: Key.unlockedUntil)
        d.set(flying, forKey: Key.flying)
        d.set(flightEndsAt ?? 0, forKey: Key.flightEndsAt)
    }

    /// What the flight log's report extension needs and cannot be told any other way: a report
    /// view takes no arguments, so the projection's horizon (a Setting) and the window it was
    /// asked for (the weeks tab) cross the App Group like everything else the extensions read.
    public func write(horizon: Int) { defaults?.set(horizon, forKey: Key.horizon) }
    public func write(reportDays: Int) { defaults?.set(reportDays, forKey: Key.reportDays) }
    /// Years the projection extrapolates over; 60 until the app has written one.
    public var horizon: Int {
        let v = defaults?.integer(forKey: Key.horizon) ?? 0
        return v > 0 ? v : 60
    }
    /// Days in the window the report was last asked for; 0 until the app has written one.
    public var reportDays: Int { defaults?.integer(forKey: Key.reportDays) ?? 0 }

    // MARK: - Read by the extensions

    public var balance: Int { defaults?.integer(forKey: Key.balance) ?? 0 }

    public var spendRate: Double {
        let v = defaults?.double(forKey: Key.spendRate) ?? 1
        return v > 0 ? v : 1
    }

    public var blocked: [String] { defaults?.stringArray(forKey: Key.blocked) ?? [] }

    /// The encoded `FamilyActivitySelection` — the apps iOS actually shields. Opaque here on
    /// purpose: this file cannot import FamilyControls, and does not need to. Only the app and
    /// the monitor decode it.
    public var selectionData: Data? { defaults?.data(forKey: Key.selection) }

    public var unlockedID: String? { defaults?.string(forKey: Key.unlockedID) }

    public var unlockedUntil: Date? {
        let t = defaults?.double(forKey: Key.unlockedUntil) ?? 0
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    public var isFlying: Bool { defaults?.bool(forKey: Key.flying) ?? false }

    public var flightEndsAt: Date? {
        let t = defaults?.double(forKey: Key.flightEndsAt) ?? 0
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    /// Should the shield be up right now?
    ///
    /// One decision, in one place, because the app raises the shield while it is running and the
    /// monitor re-raises it when it is not — and the two disagreeing is a member staring at a
    /// shield the app thinks is down. A flight in the air always wins over a live unlock: miles
    /// cannot buy your way out of the air.
    public var shouldShield: Bool {
        SharedStore.shouldShield(hasSelection: selectionData != nil,
                                 isFlying: isFlying,
                                 unlockedUntil: unlockedUntil,
                                 now: Date())
    }

    /// The decision itself, with nothing read from disk, so `blockingSelfCheck` can pin the whole
    /// table. Getting this wrong costs a member time they paid miles for, or hands them time they
    /// did not — which is why it is four arguments and no state.
    public static func shouldShield(hasSelection: Bool, isFlying: Bool,
                                    unlockedUntil: Date?, now: Date) -> Bool {
        guard hasSelection else { return false }
        return isFlying || !((unlockedUntil ?? .distantPast) > now)
    }

    /// The most that can be spent on an unlock right now — the balance, and what a daily spend
    /// limit leaves of it. Equal to `balance` when no limit is set.
    public var allowance: Int { defaults?.integer(forKey: Key.allowance) ?? 0 }

    /// The smallest unlock the dial can sell: five minutes at the current rate.
    public var smallestUnlockCost: Int { Int((spendRate * 5).rounded(.up)) }

    /// What the shield can honestly offer. Redeem can refuse, so the shield must not promise time
    /// the app is about to decline — and it can refuse for two different reasons.
    public var canAffordSmallestUnlock: Bool { allowance >= smallestUnlockCost }

    /// The limit is what is in the way, rather than the balance. Different words: one is "earn
    /// more", the other is "come back tomorrow".
    public var limitReached: Bool { allowance < smallestUnlockCost && balance >= smallestUnlockCost }

    // MARK: - Written by the shield's action button

    /// The shield asks for an unlock by naming an app. It only *names* it — the price is the app's
    /// to decide.
    public func requestUnlock(appID: String) {
        defaults?.set(appID, forKey: Key.request)
    }

    public func takeUnlockRequest() -> String? {
        guard let id = defaults?.string(forKey: Key.request) else { return nil }
        defaults?.removeObject(forKey: Key.request)
        return id
    }
}
