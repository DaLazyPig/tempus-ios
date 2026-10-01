import SwiftUI
import UIKit

/// iOS's own shake gesture, as a view modifier.
///
/// **Why this exists next to `FocusGuard`'s accelerometer.** The guard decides that a phone was
/// *picked up* by watching |‖a‖ − 1g| cross a threshold and stay there — which is the right shape
/// for the thing it actually polices, and the wrong shape for answering "did that count?" when
/// somebody is deliberately testing it. Whether a lift trips it depends on the phone, the desk and
/// two tunable numbers, and a careful lift can slide under both of them.
///
/// A shake does not. `UIEvent.EventSubtype.motionShake` is recognised by UIKit itself, with no
/// thresholds to set, on every device, and it means exactly one thing: somebody shook the phone on
/// purpose. So it is wired straight through as an unambiguous lapse — it does not wait for the
/// guard to be armed, because there is nothing ambiguous to disambiguate.
///
/// **The window catches it, not a first responder.** This used to hang a zero-sized
/// `UIViewController` in a `.background()` and have it call `becomeFirstResponder()`. That never
/// fired on a real phone, and it could not say why: `becomeFirstResponder()` returns `false` for a
/// view that is not in a window yet — which is exactly what SwiftUI's second layout pass for
/// background content can produce — and both call sites discarded the result, so the failure was
/// silent. `UIWindow` sits at the end of the responder chain and is handed `motionEnded` whenever
/// nothing ahead of it consumes the event, so it sees a strict superset of what a first responder
/// could: there is nothing to win, nothing to lose on a background transition, and nothing to
/// diagnose.
///
/// `applicationSupportsShakeToEdit` is **not** part of this. It defaults to `true`, nothing here
/// sets it, and it governs whether the undo alert appears — not whether the event is delivered.
/// Setting it to `false` would not "fix" anything and would break shake-to-undo.
extension Notification.Name {
    static let tempusDeviceShaken = Notification.Name("tempus.device.shaken")
}

/// Whether the gesture is arriving at all, separately from whether anything reacted to it.
///
/// "The shake does nothing" has two completely different causes — iOS never delivered it, or it
/// did and `FocusGuard` was not watching — and the guard's own readout cannot tell them apart.
/// This counts the raw event, before anything decides what it means. Read by the developer panel.
enum ShakeLog {
    private(set) static var count = 0
    private(set) static var last: Date?

    static func record() {
        count += 1
        last = Date()
    }
}

extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            ShakeLog.record()
            NotificationCenter.default.post(name: .tempusDeviceShaken, object: nil)
        }
        // Forwarded on purpose. Swallowing this would take shake-to-undo away from every text
        // field in the app — the subject name, the email sign-in, Concourse search, the Founders
        // invite — and the undo alert only appears when there is actually something to undo, so
        // passing it on costs nothing.
        super.motionEnded(motion, with: event)
    }
}

extension View {
    /// Fires when the device is shaken. Adds no view and changes no layout.
    func onShake(perform action: @escaping () -> Void) -> some View {
        onReceive(NotificationCenter.default.publisher(for: .tempusDeviceShaken)) { _ in action() }
    }
}
