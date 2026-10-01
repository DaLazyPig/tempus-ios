import SwiftUI
import UIKit
import UserNotifications

@main
struct TempusApp: App {
    @State private var model = AppModel(stored: AppModel.load())
    /// The store and the account layer. Both are single instances for the app's life, injected the
    /// same way the model is, because both hold a session — RevenueCat's customer-info stream and
    /// the signed-in account — that must not restart when a screen redraws.
    @State private var billing = Billing()
    @State private var identity = Identity()
    /// The cloud copy of the save file. Does nothing at all until a member signs in with Apple or
    /// Google, and nothing ever in a build with no Supabase project in Info.plist.
    @State private var backend = Backend()
    @Environment(\.scenePhase) private var scenePhase
    /// Whether the scene has actually been away — backgrounded — since it was last refreshed.
    /// Starts `true` so a cold launch's first activation is treated as a return.
    @State private var wasAway = true

    /// Set before the scene ever appears, so a notification tapped while Tempus was not yet
    /// running still reaches `NotificationRouter` rather than being handled by no one.
    init() {
        UNUserNotificationCenter.current().delegate = NotificationRouter.shared
    }

    var body: some Scene {
        WindowGroup {
            // `StageRoot` hosts the app in its own controller on a short window (an iPad, an SE —
            // see `TStage`), so everything the screens read has to be inside the closure.
            StageRoot {
                RootView()
                    .environment(model)
                    .environment(billing)
                    .environment(identity)
                    .environment(backend)
                    .tint(TColor.copper500)
            }
                .environment(model)
                .onOpenURL(perform: handle)
                .task {
                    #if DEBUG
                    runSelfChecks()
                    FPSProbe.shared.startIfRequested()
                    #endif
                    model.stampFounderIssueIfNeeded()
                    // Adopts whatever the receipt already says before any screen asks, so a paid
                    // member never sees the paywall's upsell state on a cold launch.
                    billing.start(model)
                    // The card, and every pass, carry the signed-in name rather than the canned one.
                    model.adoptAccountName(identity.account)
                    // `save()` pushes through this, so it has to be hung on the model before any
                    // screen can write. A member who signed in on a previous launch is already
                    // linked — the session came back from the Keychain — so this is also what
                    // resumes backing up without asking them to sign in again.
                    model.backend = backend
                    await askForNotificationsIfEarned()
                }
                .onChange(of: model.hasAppsToShield) { _, any in
                    // Picking the first app is the moment a shield becomes possible, so it is
                    // also the moment its one route back into the app is worth asking for.
                    guard any else { return }
                    Task { await askForNotificationsIfEarned() }
                }
                .onChange(of: identity.account) { _, account in
                    model.adoptAccountName(account)
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else {
                        // `saveNow`, not `save`: ordinary saves coalesce onto the next runloop
                        // turn, and a process on its way to the background may not get one.
                        //
                        // **`.background` only — never `.inactive`.** Both edges of this
                        // closure used to fire on an active → inactive → active round trip, and
                        // the Face ID sheet the pay sheet raises *is* one: `LAContext` resigns
                        // the scene while the system prompt is up. So confirming a payment paid
                        // for a full synchronous encode (`Stored`, then the App Group mirror,
                        // then a `ManagedSettings` write and a `DeviceActivity` schedule) on the
                        // way in, and `refreshOnForeground`'s reconcile on the way out — tens of
                        // milliseconds of main thread on the two frames the prompt animates, which
                        // is the stutter reported after a confirmed payment. It is a regression:
                        // this branch tested `scenePhase` rather than `was` until 20 Sep 2026 and
                        // so never once ran. A notification banner and the control centre raise
                        // `.inactive` the same way.
                        //
                        // Nothing is lost by waiting: `.background` is the real departure, it
                        // fires before suspension, and `saveNow()` is synchronous.
                        if phase == .background {
                            model.saveNow()
                            // Leaving mid-flight costs a chance — again `.background`, since
                            // nobody has gone anywhere for a banner.
                            model.focusGuard.leftApp()
                            wasAway = true
                        }
                        return
                    }
                    // A prompt or a banner changes nothing outside this process, so coming back
                    // from one needs no refresh. The first activation of a launch counts as
                    // returning — that is how a shield's unlock request is picked up on a cold
                    // start.
                    guard wasAway else { return }
                    wasAway = false
                    model.refreshOnForeground()
                    // The shield may have asked for an unlock while we were away. It only names
                    // an app — it does not set a price.
                    if let app = SharedStore.shared.takeUnlockRequest() {
                        model.requestUnlock(app: app)
                    }
                }
        }
    }

    /// `tempus://withdraw` — and `tempus://withdraw?app=ig`, which names an app without changing
    /// what it costs.
    /// The shield's "Redeem miles" can only reach Tempus through a local notification — a
    /// `ShieldAction` extension has no API to open its host app (see `ShieldActionExtension`) —
    /// and that notification never displays without this authorization.
    ///
    /// **Asked in context, not on first launch.** The only thing this permission is for is a
    /// shield, and a shield cannot exist until Screen Time is granted *and* the member has
    /// actually picked apps to block — so asking someone who has just opened the app for the
    /// first time is asking before anything can explain it, and a system prompt over the cover
    /// screen is the worst first impression the app can make.
    ///
    /// Both halves of the gate are load-bearing. `screenTimeAuthorized` alone is not enough:
    /// `AuthorizationCenter` reports `.approved` in the simulator whatever the entitlement does,
    /// so a gate on it alone still fires on a cold launch there. An empty selection is the
    /// honest test — with nothing selected, `Blocking` raises no shield and there is no
    /// notification to receive.
    ///
    /// Gated on the same toggle Settings already offers, so turning it off there means never
    /// being asked by the system either. iOS only ever shows the prompt once, so calling this
    /// again on later launches is a no-op.
    private func askForNotificationsIfEarned() async {
        guard model.notifications, model.screenTimeAuthorized, model.hasAppsToShield else { return }
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])
    }

    /// Home and Club links used to navigate straight out of a flight. A flight in the air owns
    /// the screen, just as `requestUnlock` enforces: the emergency exit is the only way out.
    private func handle(_ url: URL) {
        guard url.scheme == "tempus" else { return }
        let host = url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        switch host {
        case "withdraw", "redeem":
            let app = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "app" }?.value
            model.requestUnlock(app: app)
        case "home":
            guard model.phase != .flying else { return }
            model.go(.home, .zoom)
        case "status", "club":
            guard model.phase != .flying else { return }
            model.go(.status, .lift, dir: 1)
        // The Live Activity's buttons. Extending is the only thing it can change about a flight
        // in the air; ending one is deliberately not a deep link, because leaving early has to go
        // through the screen that says what it costs.
        case "extend":
            if model.phase == .flying { model.extend() }
        case "flight":
            if model.phase == .flying { model.goDirect(.flying) }
        default:
            break
        }
    }
}

/// Routes a tapped local notification back through `onOpenURL`, the same door a `Link` uses.
///
/// `ShieldActionExtension` cannot open its host app — a `ShieldAction` extension may only
/// answer `.close`/`.defer`/`.none` — so "Redeem miles" posts a local notification carrying
/// `tempus://withdraw` in `userInfo["url"]` instead. Tapping that notification only reaches
/// `TempusApp.handle(_:)` if something asks `UIApplication` to open that URL; nothing does
/// that on its own, and with no delegate the tap is silently swallowed. This is that delegate,
/// set in `TempusApp.init()` so it is in place before the scene — and any notification tap —
/// ever arrives.
private final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationRouter()

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let raw = response.notification.request.content.userInfo["url"] as? String,
           let url = URL(string: raw) {
            UIApplication.shared.open(url)
        }
        completionHandler()
    }

    /// Shows the banner even on the rare chance the notification lands while Tempus is already
    /// foreground — the shield closes before this posts, so that should be the normal case, but
    /// an unhandled notification while active would otherwise just vanish.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
