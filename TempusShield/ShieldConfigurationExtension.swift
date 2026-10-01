// The shield — what you see instead of the app you just opened.
//
// This is the one Tempus surface that cannot be designed: ShieldConfiguration only takes a
// background colour, an optional blur, an icon, two labels and two buttons — no custom
// layout, and no way to load Outfit or DM Mono into this process. So the tokens carry the
// identity here and the type falls back to the system face.
//
// This is also the one surface that deliberately does not match the reference. The
// reference's BlockedApp offers "Redeem miles" and jumps into Redeem. A ShieldAction
// extension cannot open its host app — it can only close the shield — so a button that
// *says* it redeems is a button that does nothing (removed 18 Sep 2026, on device). The
// shield states the position and closes; redeeming is done in Tempus. Three positions:
//   - the balance covers the cheapest unlock → say so, and that Tempus is where to spend it
//   - it doesn't → say how far short the balance is
//   - a daily spend limit is what stands in the way → say so. The balance is irrelevant
//     there, so naming a shortfall would name a number that buys nothing.
//
// Target membership: this file, plus Tempus/Shared/SharedStore.swift. See SETUP.md.
import ManagedSettings
import ManagedSettingsUI
import UIKit

final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    // Duplicated because this process cannot import Theme/Colors.swift. Keep these in step
    // with TColor: navy-700, cloud-100, copper-500, and text-on-dark-muted (sky, muted).
    private let navy700 = UIColor(red: 0x23 / 255, green: 0x39 / 255, blue: 0x5B / 255, alpha: 1)
    private let cloud100 = UIColor(red: 0xF2 / 255, green: 0xF5 / 255, blue: 0xFA / 255, alpha: 1)
    private let copper500 = UIColor(red: 0xB8 / 255, green: 0x6F / 255, blue: 0x52 / 255, alpha: 1)
    private let skyMuted = UIColor(red: 0x9F / 255, green: 0xB3 / 255, blue: 0xD1 / 255, alpha: 1)

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        shield(named: application.localizedDisplayName)
    }

    override func configuration(shielding application: Application,
                                in category: ActivityCategory) -> ShieldConfiguration {
        shield(named: application.localizedDisplayName ?? category.localizedDisplayName)
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        shield(named: webDomain.domain)
    }

    override func configuration(shielding webDomain: WebDomain,
                                in category: ActivityCategory) -> ShieldConfiguration {
        shield(named: webDomain.domain ?? category.localizedDisplayName)
    }

    /// Airline-operational: state the position, never scold. Matches the reference's
    /// BlockedApp word for word — "is locked", the balance stated, "Not now" — except that
    /// the one button closes, per the header.
    private func shield(named name: String?) -> ShieldConfiguration {
        let store = SharedStore.shared
        let subject = name ?? "This app"
        let canRedeem = store.canAffordSmallestUnlock
        let short = max(0, store.smallestUnlockCost - store.balance)
        // Three states, not two: the balance covers it, the balance does not, or a daily spend
        // limit does. The third has nothing to do with how many miles are banked, so quoting a
        // shortfall there would name a number that buys nothing.
        let limited = store.limitReached

        return ShieldConfiguration(
            backgroundBlurStyle: .systemMaterialDark,
            backgroundColor: navy700,
            icon: nil,
            title: ShieldConfiguration.Label(text: "\(subject) is locked", color: cloud100),
            subtitle: ShieldConfiguration.Label(
                text: canRedeem
                    ? "You have \(grouped(store.balance)) mi. Open Tempus to redeem them."
                    : limited
                        ? "Today's spend limit is reached."
                        : "You need \(grouped(short)) mi more.",
                color: skyMuted),
            primaryButtonLabel: ShieldConfiguration.Label(text: "Not now", color: .white),
            primaryButtonBackgroundColor: copper500)
    }

    /// `toLocaleString('en-US')` — the reference groups the balance, and four figures of
    /// miles is reachable.
    private func grouped(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        f.locale = Locale(identifier: "en_US")
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}
