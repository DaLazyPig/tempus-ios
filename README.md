# Tempus

Tempus is a native iOS app (SwiftUI, iOS 17+) built around one loop: you study to earn Miles, and
you spend Miles to unlock the apps that Tempus blocks through Screen Time. The interface speaks an
air-travel metaphor throughout, so a study session is a flight to a real destination, starting one
issues a boarding pass you tear to depart, quitting early is a diversion that earns nothing, and your
history is a flight log. One mile buys one minute of screen time, and four studied minutes earn one
mile.

Business Class is the paid plan, sold as a monthly or annual subscription through RevenueCat.

The app was built between 9 August and 26 September 2026. This repository is the source of the
build in App Review (1.0, build 48), with developer mode since restricted to debug builds. It is
published as snapshots of each submitted build, while the working history stays in a private repository.

## Build and run

Requires **Xcode 26** (the app icon is an Icon Composer document) and nothing else. The one
package dependency, the RevenueCat SDK, resolves through Swift Package Manager on first open.

```bash
open Tempus.xcodeproj
# or, from the command line:
xcodebuild -project Tempus.xcodeproj -scheme Tempus \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Run the `Tempus` scheme on any iPhone simulator. The five extensions (Screen Time monitor, shield,
shield action, Live Activity and usage report) build with the app as dependencies.

**What the simulator can and cannot show.** Every screen, the flight lifecycle, the Miles economy,
the status tiers and the shop all run in the simulator. Real app blocking does not, because Apple's
Family Controls authorisation never approves there, so the app says "Screen time is not connected"
and mocks the blocked list rather than pretending. The screen-time cards in the flight log are drawn
by a `DeviceActivityReport` extension and are blank in the simulator for the same reason.

**On a device**, blocking needs the `com.apple.developer.family-controls` entitlement (granted by
Apple on request) and the App Group registered under your own team. SETUP.md walks through both.

**Debug launches run self-checks** (`runSelfChecks()` in `TempusApp.swift`) that pin the routing,
the hashes, the status periods and the redeem arithmetic against values produced by the original
JavaScript reference, and trap on launch if any of them drift. **Launch arguments** such as
`-tempusPhase concourse` or `-tempusPhase flying -tempusMinutes 1` jump straight to a screen or state;
CLAUDE.md lists them all.

## Where things are

| | |
|---|---|
| `Tempus/Models/AppModel.swift` | The state machine and the single source of truth |
| `Tempus/Models/Billing.swift` | RevenueCat: configuration, offerings, purchase, restore, the `business` entitlement |
| `Tempus/Models/Blocking.swift` | Screen Time shielding, shared with the monitor extension |
| `Tempus/Models/Geography.swift` | 65 airports, great-circle routing and the moving home airport |
| `Tempus/Models/Status.swift` | Five tiers over fixed 90-day qualifying periods |
| `Tempus/DesignSystem/` | Components, transitions and the Markup renderer that draws the shop's stock |
| `Tempus/Resources/shop.json` | The Concourse catalogue: 191 card faces, 60 pass headers, 18 gift faces |
| `supabase/` | The backend: schema and row-level security for backups, the shared bank and gifts |
| `DESIGN.md` | The design contract: tokens, type, motion and voice |
| `CLAUDE.md` | Architecture notes, and every place the app deliberately departs from the reference |
| `source_of_truth.html` | The web reference build the native app was ported from |

The RevenueCat and Supabase keys in `Info.plist` are the public client keys that ship inside the app
binary. Server-side secrets are not in this repository.

## Licence

[GNU Affero General Public License v3.0](LICENSE).
