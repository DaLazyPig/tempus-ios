# Tempus

Fly further than you scroll with Tempus, an app that combines studying with screen time management. You earn Miles by studying, which you can then use to unlock apps you've blocked. For every four minutes you study, you get one Mile, and one Mile lets you use a blocked app for one minute. Each study session is framed as a flight to a city. You start by tearing a boarding pass, and if you quit before finishing, your flight is diverted and you earn nothing.

We are two high school students from Australia who created Tempus between August and September 2026. Every other focus app we tried was eventually deleted, mostly because they took up our time without offering any real benefit. We wanted an app that genuinely rewards you for earning your screen time.

This repository contains the source code for the version we submitted for App Review (1.0, build 48).

## How it's built

Tempus is built natively for iOS using SwiftUI, supporting iOS 17 and later. Before writing any Swift code, we first created a web prototype (source_of_truth.html) to test the app's flow and animations. We then translated this into the native app, screen by screen. Debug builds include self-checks (SelfChecks.swift) that run on launch. These checks compare the app's routing, status periods and Miles redemption maths against the original prototype's numbers, and the app stops immediately if anything doesn't match.

### Blocking

The app uses Apple's Screen Time frameworks (Family Controls, Managed Settings and Device Activity) to block apps. Five extensions are included. TempusMonitor runs in the background to handle blocking, TempusShield displays the screen you see when you try to open a blocked app, TempusShieldAction manages the button on that screen, TempusReport generates the screen time charts in the flight log, and TempusActivity runs the Live Activity during a flight. FocusGuard.swift detects if you leave the app or pick up your phone during a flight.

### Flights, Miles and Status

Geography.swift includes 65 airports with great circle routing, so longer study sessions take you further around the world. The city you land in becomes your new home airport. Status.swift manages the Status Club, which has five tiers awarded over fixed 90 day periods. Higher tiers earn Miles faster, rewarding the people who study the most, and keeping your tier means you have to keep studying.

### Business Class (Subscription)

Lots of focus apps hide their core features behind a paywall but we chose not to. We believe students need help focusing the most and often have the least money to spend. So the free plan (Economy class) already offers the complete experience. You can fly, earn Miles, block apps and redeem screen time without paying anything.

Business Class offers a stricter experience. In Economy, leaving the app or moving your phone during a flight gives you a warning and two chances before the session ends. Business Class gives you no warnings, and a single lapse ends your flight straight away. We designed it this way because students who choose to pay are usually looking for stricter accountability, and this directly supports that. Business Class also unlocks flights longer than 90 minutes, higher Status Club tiers with bigger Miles multipliers, linking Miles with a friend, your full boarding pass history and the Business stock in the Concourse.

Purchases are managed through RevenueCat, which works on top of StoreKit 2. All the purchase logic is in Billing.swift. There's one entitlement called business and one offering with both an annual and a monthly subscription. The app never decides whether you've paid on its own. It listens to RevenueCat's customerInfoStream, and your plan is whatever the entitlement says, checked on every launch and after every purchase. This means RevenueCat verifies the receipt on its servers instead of the app keeping its own record that someone could edit. It also means Business Class carries over if you reinstall the app or move to a new phone with the same Apple ID. Only two things can turn on Business Class in AppModel, which are the RevenueCat entitlement and developer mode (only available in debug builds). The self-checks make sure a store downgrade can't override a developer grant and that a developer grant is never saved as a real purchase.

A lot of the code in Billing.swift came from problems we ran into along the way.

- The annual plan (\$39.99) is selected by default, with the monthly plan (\$7.99) next to it to clearly show the annual saving. The app works out the saving percentage automatically. At first we only offered the annual plan, but on 21 September we added the monthly plan after realising people wanted to try it for a month first.
- The one week free trial only appears if RevenueCat confirms that Apple ID is eligible. Eligibility is checked again whenever you switch plans because it's different for each product, so we never offer a free week the receipt won't honour.
- Prices are shown in the store's local currency instead of a hardcoded dollar sign.
- App Review rejected build 43 because the per month price on the annual plan card was displayed more prominently than the amount actually charged. Now the billed price is always the biggest figure on the screen, with the trial and per month costs shown underneath it.
- RevenueCat deliberately crashes any release build that is set up with a Test Store key, which is what happened to our TestFlight build 3. Billing now refuses to set up with a test key outside of debug builds, so the paywall says the store isn't connected instead of the app crashing.
- Offer codes are redeemed through Apple's own redemption sheet, and Restore is always available.

The paywall is designed to feel like a seat upgrade, with Seat 1A at the top. Moving from Economy to Business Class is meant to feel like getting upgraded at the gate.

### Backend

Supabase manages accounts, backups, the shared Miles bank and gifts, with row level security on every table (supabase/schema.sql). The apple-token function revokes Sign in with Apple access when a user deletes their account, which Apple requires. The RevenueCat and Supabase keys in Info.plist are the public client keys that already ship inside the app. No server secrets are stored in this repository.

### Design

DESIGN.md sets out our design system, including colour tokens, typography, motion and voice. The app uses navy and copper, the Outfit font for text and DM Mono for small labels so they look like the print on a real boarding pass. The Concourse catalogue (Resources/shop.json) has 191 card designs, 60 pass headers and 18 gift designs, all drawn by our own Markup renderer in DesignSystem.

### File locations

| File | Purpose |
|---|---|
| Tempus/Models/AppModel.swift | The state machine and central source of truth for the app |
| Tempus/Models/Billing.swift | RevenueCat setup, offerings, purchases, restoring and the business entitlement |
| Tempus/Models/Blocking.swift | Screen Time blocking, shared with the monitor extension |
| Tempus/Models/FocusGuard.swift | Detects when the user leaves the app or moves the phone during a flight |
| Tempus/Models/Geography.swift | 65 airports, great circle routing and the moving home airport |
| Tempus/Models/Status.swift | The five status tiers over fixed 90 day periods |
| Tempus/Screens/PaywallSheet.swift | The Business Class paywall |
| Tempus/DesignSystem/ | UI components, transitions and the Markup renderer |
| supabase/ | Database schema, row level security and the apple-token function |
| DESIGN.md | Design tokens, typography, motion and voice |
| source_of_truth.html | The web prototype the native app was built from |

## How to run it

You'll need Xcode 26, because the app icon is an Icon Composer file. The only external dependency is the RevenueCat SDK, which Swift Package Manager installs the first time you open the project.

To open the project in Xcode

```bash
open Tempus.xcodeproj
```

To build from the command line

```bash
xcodebuild -project Tempus.xcodeproj -scheme Tempus \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Run the Tempus scheme on any iPhone simulator, and all five extensions will build along with the main app.

Most features work in the simulator, including every screen, flights, Miles, Status and the Concourse. Real app blocking doesn't, because Apple doesn't approve Family Controls in the simulator. Instead of pretending, the app shows "Screen time is not connected". The screen time charts in the flight log are also blank for the same reason.

To run it on a real iPhone, you need the family-controls entitlement from Apple and the App Group registered under your own developer team. SETUP.md explains both. Launch arguments such as `-tempusPhase concourse` let you jump straight to a specific screen, and CLAUDE.md lists all of them.

## Licence

GNU Affero General Public License v3.0

Made by Jimmy and Kyle

