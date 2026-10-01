// What the shield's one button does: close.
//
// A ShieldAction extension may only answer .close, .defer or .none — it cannot open its
// host app. The shield used to offer "Redeem miles", record the request in the App Group
// and post a local notification whose tap opened Redeem; on device that read as a button
// that promised a jump it could not make, so it went (18 Sep 2026). The shield now states
// the position and closes, and redeeming happens in Tempus. `tempus://withdraw` still
// resolves in TempusApp for anything else that sends it.
//
// Target membership: this file, plus Tempus/Shared/SharedStore.swift. See SETUP.md.
import ManagedSettings

final class ShieldActionExtension: ShieldActionDelegate {
    override func handle(action: ShieldAction,
                         for application: ApplicationToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        completionHandler(.close)
    }

    override func handle(action: ShieldAction,
                         for webDomain: WebDomainToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        completionHandler(.close)
    }

    override func handle(action: ShieldAction,
                         for category: ActivityCategoryToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        completionHandler(.close)
    }
}
