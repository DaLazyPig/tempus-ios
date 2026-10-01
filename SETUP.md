# Turning on real blocking

Everything in `Tempus/` builds and runs today with **no setup at all** — blocking runs
through `MockBlockingService`, which records what *would* have been enforced. The app says
so on the Blocking screen rather than pretending.

To make iOS actually hold apps shut you need two things Apple controls. The Xcode side is
done — the five extension targets are in the project and build with the app — so what is left
is the entitlement, which takes days, and one identifier you register yourself.

---

## 1. Ask Apple for the entitlement

`com.apple.developer.family-controls` is not self-serve. Request it at
<https://developer.apple.com/contact/request/family-controls-distribution> — you describe
the app and wait. Until it's granted, builds signed with it fail, so keep the capability
off in Xcode until Apple replies.

**None of this works in the simulator.** `AuthorizationCenter` never approves there, by
design. Real device only.

## 2. Set a team

All five targets name `DEVELOPMENT_TEAM = T7CTRA8XT3`. If you are building on another
account, change it in Xcode ▸ each target ▸ Signing & Capabilities.

The five extensions sign automatically, so a **device** build needs a profile for each of their
bundle ids as well as the app's — Xcode creates them on first build, or pass
`-allowProvisioningUpdates` to `xcodebuild`. The app's Release configuration signs manually
against `Tempus: Focus Timer`; if you archive for the store, the extensions need their own
distribution profiles too. Simulator builds need none of this.

## 3. Register the App Group

The five extension targets are **already in the project** — nothing to add by hand:

| Target | Bundle id | Entitlements | Shares from `Tempus/` |
|---|---|---|---|
| `TempusMonitor` | `com.crescerestudios.tempus.monitor` | Family Controls, App Group | `Shared/SharedStore.swift`, `Models/Blocking.swift` |
| `TempusShield` | `com.crescerestudios.tempus.shield` | Family Controls, App Group | `Shared/SharedStore.swift` |
| `TempusShieldAction` | `com.crescerestudios.tempus.shieldaction` | Family Controls, App Group | `Shared/SharedStore.swift` |
| `TempusActivity` | `com.crescerestudios.tempus.activity` | none | `Shared/FlightActivityAttributes.swift`, `Shared/UnlockActivityAttributes.swift` |
| `TempusReport` | `com.crescerestudios.tempus.report` | Family Controls, App Group | the four Outfit weights, `Fonts/Outfit-*.ttf`, and `Shared/SharedStore.swift` (the projection horizon and the report window cross the group) |

Each takes its own folder as a filesystem-synchronized group, so adding a file to
`TempusShield/` puts it in that target with no project editing — the same property the app
target has. The files each one reaches into `Tempus/` for are membership exceptions on the
`Tempus` group; if you add another shared file, add it to that target's exception list rather
than duplicating the file.

`TempusActivity` is the odd one out: it is the flight's Live Activity — the Dynamic Island
pill and the lock-screen banner — and needs **neither** Family Controls nor the App Group,
only `NSSupportsLiveActivities` in the app's Info.plist (already set).

**`TempusReport` is an ExtensionKit extension, not an NSExtension.** The
`com.apple.deviceactivityui.report-extension` point requires `EXAppExtensionAttributes` in its
Info.plist (not `NSExtension`), `EXTENSIONKIT_EXTENSION = YES` on the target, and embedding through
the "Embed ExtensionKit Extensions" phase into `Tempus.app/Extensions/` — the other four are
NSExtensions under `PlugIns/`. App Store Connect rejects the upload otherwise ("Invalid extension …
must be built as an ExtensionKit extension"); build 21 was refused for exactly that.

`TempusReport` is the flight log's screen-time feed: a `DeviceActivityReport` extension that
iOS hands the per-app usage to, and that draws the two screen-time cards itself — the numbers
never reach the app. It needs Family Controls and nothing else, its Info.plist carries **no**
principal class (the `@main` type is the entry point, and the installer refuses one), and it
draws nothing in the simulator. For a Release archive it needs its own App Store profile,
named `Tempus Report App Store` in the project, for the bundle id above.

The one thing you must do yourself: **register `group.com.crescerestudios.tempus` in the
developer portal under exactly that name.** All five targets' entitlements say it and
`SharedStore.suiteName` says it, and a mismatch is silent — `UserDefaults(suiteName:)` simply
opens nothing and the extensions read an empty store.

## 4. Check it

On a real device, signed:

1. Launch Tempus ▸ Settings ▸ Screen time. Tap **Connect** on the "Screen time is not
   connected" banner (or answer onboarding's permission screen with Allow). iOS shows its own
   consent sheet. Approve.
2. The banner disappears — it *is* the status indicator; if it's still there, authorization
   didn't take.
3. Tap **Apps that cost miles**. It now opens iOS's own picker rather than the six-name
   stand-in list. Pick a couple of apps.
4. Open one of them. You should get the navy Tempus shield rather than the app. Open an app
   you did *not* pick — it should open normally.
5. Tap **Redeem miles** on the shield (or **Open Tempus**, if the balance is short of the
   cheapest unlock) ▸ tap the notification, or just switch back to Tempus yourself ▸ Tempus
   opens on Redeem.
6. Redeem an unlock, then reopen the same app — the shield should be down. **Wait past the
   unlock's deadline without opening Tempus**, then open the app again: the shield should be
   back. That last step is the one that proves `TempusMonitor` is installed and being woken —
   everything before it works with the app in the foreground.
7. Start a flight. The Dynamic Island should carry a copper progress ring and the countdown;
   long-press it for the expanded card, and lock the phone for the banner. If nothing
   appears, check Settings ▸ Tempus ▸ Live Activities, then the app's own Live Activity
   toggle — `startLiveActivity` honours that switch before it asks iOS for anything.

If step 4 shows Apple's plain grey shield instead of the navy one, `TempusShield` isn't
installed or its `NSExtensionPrincipalClass` doesn't match — check the Info.plist actually
in use for that target.

---

## Why it's built this way

- **There are no blocking schedules or hardcore mode.** Blocking is just a list of blocked
  app ids plus at most one unlock running until a wall-clock deadline — both mirrored into
  `SharedStore` by `AppModel.syncSharedStore`. `TempusMonitor` re-derives one answer, "should
  the shield be up right now?", every time iOS wakes it at an `unlockedUntil` or
  `flightEndsAt` boundary, rather than keeping a schedule of its own. A flight in the air
  always overrides a live unlock — miles can't buy your way out of it.
- **Two processes raise the shield, and they run the same code to decide.** `Blocking` is
  compiled into both the app and `TempusMonitor`. The app writes the shield every time the
  state behind it changes, because a `ManagedSettingsStore` write is durable and outlives the
  process; the monitor writes it when the app is not running. Both read the answer from
  `SharedStore.shouldShield`, which is a pure function of four inputs and is pinned row by row
  by `blockingSelfCheck`.
- **Only one wake-up is scheduled, and it is the only one needed.** An unlock expires at a
  wall-clock deadline that will pass with Tempus closed. `Blocking.scheduleReshield` arms a
  DeviceActivity interval that *starts* at that deadline, so `intervalDidStart` is the moment
  the shield returns. It starts rather than ends there because intervals have a fifteen-minute
  minimum and the dial sells unlocks from five — only the start instant is read, and the
  length is ours to choose. A flight landing needs no wake-up: the shield is up during a
  flight and stays up after it.
- **An unlock lifts the shield off the whole selection, not one app.** Redeem's strip names
  what you are unlocking *for*; the price never depended on it and neither does this. Naming
  one app would mean a stable identity for an opaque `ApplicationToken`, which iOS does not
  offer.
- **The apps are chosen through iOS's own picker.** Settings ▸ "Apps that cost miles" opens
  `FamilyActivityPicker` once Screen Time is authorized, and the tokens it returns are what
  `AppModel.selection` holds and `SharedStore` mirrors. Until it is authorized the row falls
  back to the six-name stand-in list, under a banner that says blocking is not connected.
- **The shield cannot open the app.** `ShieldActionDelegate` may only answer `.close`,
  `.defer` or `.none`. So the primary button calls `SharedStore.requestUnlock(appID:)` and
  posts a local notification; `TempusApp.swift` calls `takeUnlockRequest()` on every
  foreground and routes to Redeem when one is waiting, so it fires whether or not the
  notification itself was tapped. If notifications are declined the request still sits in
  the store for that same check to pick up next time the app opens.
- **The shield cannot be designed.** `ShieldConfiguration` accepts a background colour, a
  blur style, an icon, two labels and two buttons. No custom layout, no custom fonts — the
  extension can't load Outfit. Tokens carry the identity; the type is the system face. This
  is also the one place the app deliberately differs from the reference: its Redeem can
  never fail, so its shield always offers "Redeem miles". Ours can refuse an unlock the
  balance doesn't cover, so a shield must not promise it — see
  `TempusShield/ShieldConfigurationExtension.swift` for the two states this reads out of
  `SharedStore.canAffordSmallestUnlock`.


## Turning on the store, Google sign in, and Face ID

Three things ship as placeholders because they are account-specific. Everything below works
without them — the app just says so instead of pretending. `Billing.isConfigured` and
`Identity.googleConfigured` both treat a `YOUR_…` value as absent.

### RevenueCat (Business Class)

1. Create the app in RevenueCat, and paste its **public SDK key** (`appl_…`) over
   `RevenueCatAPIKey` in `Info.plist`.
2. In App Store Connect, create the auto-renewing subscription and its 7-day introductory
   free trial. In RevenueCat, attach that product to a **package** in the **current offering**,
   and to an entitlement whose identifier is exactly **`business`** — `Billing.entitlement`.
   `Billing.package` prefers the offering's `annual` package and falls back to its first, so a
   monthly-only offering still sells.
3. The SPM dependency is already in the project (`purchases-ios`, 5.x).

**Local testing in the simulator.** `Tempus.storekit` at the repo root declares the same product
(annual, $39.99, 7 days free), and the shared `Tempus` scheme already selects it (Edit Scheme ▸ Run ▸
Options ▸ StoreKit Configuration), so Run from Xcode sells in the simulator with no App Store Connect at all;
RevenueCat validates those purchases because the product is registered in its dashboard. Without
it, StoreKit has nothing to answer with and the paywall reads "Business Class is not on sale".

**On a phone, that same sentence means App Store Connect is not ready** (verified 19 Sep 2026:
the RevenueCat side is complete — offering `default` ▸ `$rc_annual` ▸ `com.crescerestudios.tempus.annual`
▸ entitlement `business`). What remains is entirely in App Store Connect: the auto-renewable
subscription `com.crescerestudios.tempus.annual` in a subscription group, with a 7-day free
introductory offer, in **Ready to Submit**; the Paid Applications agreement signed with banking
and tax **Clear**; the In-App Purchase Key and the app-specific shared secret pasted into
RevenueCat's App Store credentials; and, for the first submission, the subscription **attached to
the app version** in the version's In-App Purchases and Subscriptions section — a first IAP is
reviewed with the app, never on its own.

**Test Store keys (`test_…`) must not ship.** RevenueCat's Test Store sells products configured in
its dashboard rather than through StoreKit, so it needs no App Store Connect product — which is
what makes it easy to leave in by accident. RevenueCat's own position is blunt: a release build
that configures with one **shows an alert and crashes**, and an app submitted with one **is
rejected during App Review**. `Billing.storeUsable` therefore declines to configure at all when the
key is `test_` and the build is neither DEBUG nor TestFlight, so the worst case is the paywall
saying "the store is not connected" rather than a crash on launch. **Swap in the `appl_` key before
submitting** — the guard stops the crash, it does not make a test key shippable.

Until step 1 is done the paywall shows the reference's "$39 / yr" copy, disables the buy button
and reads "The store is not connected in this build." Until step 2 is done it reads "Business
Class is not on sale right now." Neither state ever offers a purchase that cannot happen.

Once an offering loads, **every figure on the paywall comes from the store** — the price, the
period, the button and the sub-copy. The reference's "$39" and "7 days free" are only the fallback.
If the button reads "Upgrade for \u{2026}" rather than "Start N days free", the product has no
introductory free-trial offer attached; add one in App Store Connect (or in the Test Store product)
and the trial copy appears on its own.

**Testing a purchase** needs a sandbox Apple ID on a real device, or a StoreKit configuration
file added to the scheme. Developer mode's **Plan ▸ Business Class** switch grants the plan
without the store, which is what the rest of the app should be walked with.

### Google sign in

1. In Google Cloud console, create an **OAuth client ID of type iOS** with this app's bundle id
   (`com.crescerestudios.tempus`).
2. Paste the client id over `GIDClientID` in `Info.plist`. That is the only value needed — there
   is no client secret (an iOS client is a public client, which is why the flow is PKCE), and no
   `CFBundleURLTypes` entry, because `ASWebAuthenticationSession` intercepts its own callback.
   `Identity.reversedClientID` derives the redirect scheme from the client id, so the two cannot
   disagree.

Without it, the Google button reports "Google sign in is not set up yet" and onboarding continues.
Apple and email need no configuration; Apple needs the **Sign in with Apple** capability, which is
in `Tempus.entitlements` (`com.apple.developer.applesignin`) and must also be enabled on the App ID
in the developer portal.

### Face ID

`NSFaceIDUsageDescription` is in `Info.plist`; nothing else is needed. The pay sheet evaluates
`.deviceOwnerAuthentication`, so a device with no biometry falls back to its passcode rather than
being unable to spend its own miles.

**In the Simulator** enable *Features ▸ Face ID ▸ Enrolled*, then use *Features ▸ Face ID ▸
Matching Face* when the sheet appears. Or turn on developer mode's **Skip Face ID when paying**.

## Developer mode

Seven taps on the **Settings** title. It grants Business Class, moves the miles balance, seeds the
hours ledger (never the tier — the tier stays earned), speeds the flight clock, suspends the focus
guard, skips the biometric check, and erases the install.

`Dev.available` is `true` in DEBUG builds only. TestFlight and the App Store build have no door at
all: App Review installs through the same sandbox a tester does, and a panel that grants Business
Class does not belong on a build a reviewer can open. The launch seams (`Dev.seams`) are DEBUG-only
for the same reason.

`-tempusDev` is the launch seam, since the Simulator takes no synthetic taps:

```bash
xcrun simctl launch booted com.crescerestudios.tempus -tempusPhase settings -tempusDev
```

### Still outstanding

- ~~The App Group and the Family Controls entitlement~~ — **both granted**, as of the profiles
  issued 4 Sep 2026 (valid to 4 Sep 2027). Four of the five bundle ids carry
  `group.com.crescerestudios.tempus` — the Live Activity is the deliberate exception, since it
  takes a typed payload rather than reading the App Group — and the app's profile carries *both*
  `com.apple.developer.family-controls` and `…family-controls.app-and-website-usage`, so Apple
  granted the data-access variant, not just the plain one. Verify at any time with:
  `for f in ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/*.mobileprovision; do
  security cms -D -i "$f" | grep -l family-controls; done`
  The simulator still never approves `AuthorizationCenter`, so blocking there stays mocked whatever
  you do, and the Settings banner will keep saying so — correctly. Device only.
### Deleting an account, and the legal pages

**Run `supabase/schema.sql` again** — its third part (added 18 Sep 2026) is what makes "Delete
account" real. Before it, the app issued a DELETE the row policies never allowed, PostgREST answered
204, and the member was told their data was gone while it sat there. Now Settings ▸ Account ▸ Delete
account calls `delete_my_account()`, a definer function that splits any shared pot, removes the
backup and every invite, and deletes the auth user (which revokes every session) — then wipes the
phone back to a first launch. Until the SQL is run the button says "This part of the account
server isn't set up yet" rather than pretending. The same part adds length and size checks on
everything the client can post, and caps a single pot credit at 2,000 mi.

The **fourth part** of the same file (also 18 Sep 2026) is the shared bank's integrity: a
`link_payouts` table and `claim_payouts()`, an advisory lock in `accept_link_invite`, and a new
four-argument `earn_to_pair(pair, amount, label, op)` with a daily cap — the three-argument one is
dropped, so a build older than build 23 cannot credit a pot once part four is run. Run the whole
file; it is idempotent.

The **fifth part** is gift cards, for real: a `public.gifts` table addressed by email exactly like
`link_invites`, and `accept_gift(gift)` / `decline_gift(gift)`, the same shape as
`accept_link_invite` / `decline_link_invite`. The sender's miles already leave on the client
(`AppModel.postGift`, through the same `payOrder` every Concourse purchase uses) — this part only
carries the credit to the recipient. Without it, the Concourse's Gifts chip stays hidden (it is
gated on `Backend.isConfigured && backend.isLinked` in `ConcourseScreen.categories`) and sending
one anyway would fail with "This part of the account server isn't set up yet." Run the whole file
again; it is idempotent.

**Rotate an old credential.** Commit `cf0821d` (12 Aug 2026) committed a `.env` holding the direct
Postgres connection string — user, password and host — for the *previous* Supabase project
(`wjembwbiqaqkxbpafvxj`). It was removed the next commit and the repository is private, but the
password is recoverable from history by anyone with the repo. Reset that project's database
password in its dashboard (or delete the project if it is unused). The history itself has not been
rewritten — that is a force-push to every clone, and it is your call, not the app's.

**Apple's half of deletion.** Apple asks an app that offers Sign in with Apple to revoke the
member's grant when their account is deleted. That needs a server holding the Apple private key, and
it is `supabase/functions/apple-token`: the app posts the sign-in's authorization code to it right
after linking (`Backend.storeAppleCode`), it exchanges the code and keeps the refresh token in
`public.apple_tokens` (schema part seven, service role only), and `Backend.deleteAccount` posts
`revoke` before `delete_my_account()`. Both calls are best effort — a member never sees a revocation
error and a deletion is never refused for one — and a 404 just means this is not deployed yet. To
deploy it:

1. Developer portal ▸ Certificates, Identifiers & Profiles ▸ Keys ▸ + ▸ tick **Sign in with Apple**,
   configure it for the Tempus App ID, download the `.p8` (once — Apple does not offer it again) and
   note the Key ID. The Team ID is `T7CTRA8XT3`.
2. Run schema part seven (the whole file is idempotent), then:
   ```bash
   brew install supabase/tap/supabase && supabase login
   supabase link --project-ref yyvvjaryykobialjbrjb
   supabase secrets set APPLE_TEAM_ID=T7CTRA8XT3 APPLE_KEY_ID=<key id> \
     APPLE_PRIVATE_KEY="$(cat AuthKey_<key id>.p8)"
   supabase functions deploy apple-token
   ```
3. Check it: sign in with Apple on a phone, delete the account from Settings, then look at
   Settings ▸ Apple ID ▸ Sign in with Apple on that phone — Tempus should be gone from the list.

**The legal pages.** `Tempus/Resources/Legal/Terms.md` and `Privacy.md` are the Terms of Use and
Privacy Policy, readable in-app from Settings ▸ Legal. Before submission:

1. The same two documents are hosted from the public `DaLazyPig/tempus-legal` repo by GitHub
   Pages, at `Billing.termsURL` / `privacyURL` (lowercase paths; done 18 Sep 2026). A change to either
   document goes to both the bundle and that repo. Its README is the App Store Connect support URL.
2. App Store Connect ▸ App Information: paste the privacy URL. App Privacy questionnaire: name,
   email address, user ID, purchase history and "other user content", all linked to the user, none
   used for tracking — which is exactly what `Tempus/PrivacyInfo.xcprivacy` declares.
3. Both documents name `tempus.support@gmail.com`, which is also the App Store Connect support
   contact. Changing it means both files, the repo, and App Store Connect.
4. The governing-law clause says "Australia" without a state. Add the state the business is
   registered in.

**Privacy manifests.** Every target now carries a `PrivacyInfo.xcprivacy` (the app's declares the
data above; the five extensions declare only the UserDefaults access they share through the App
Group). Apple has rejected uploads without them since May 2024.

### The shared bank

Built, and **not yet switched on** — the client is done, the SQL is written, and nothing has been
run against the live project. Two steps remain, both yours.

**1. Run `supabase/schema.sql`** in the dashboard ▸ SQL Editor. Safe to re-run: everything is
`create ... if not exists` or `create or replace`. It holds the original `backups` table plus
`link_invites`, `link_pairs`, `link_ledger`, their RLS policies, and six functions.

**Re-run it after 25 Sep 2026 even if it has been run before** — part nine's `deposit_to_pair()`
was replaced: the old two-argument version let any signed-in account mint miles into a shared pot,
and the new one drops it. Until it is re-run, that hole is open on the live project. **Re-run it after 22 Sep 2026 even if it has been run before** — **part nine** adds
`deposit_to_pair()`, which is how linking merges two balances into the shared pot; without it a
new link still shares a pot that starts empty, and each phone keeps retrying the deposit on every
refresh. **Part eight** adds `my_wallet()`, and without it a phone that reinstalled the app can never accept or send a gift
again. `reconcile_miles` allows one miles stream per account and refuses any other with "Restore
the latest account backup before transferring miles"; a fresh install mints a new stream, and
`my_wallet()` is how the client finds the real one and adopts it (`AppModel.repairMilesWallet`).
Until it is deployed the app says so in plain words and leaves the gift waiting rather than
repeating the server's instruction. **Settings ▸ Developer ▸ Account server ▸ Check the
schema** lists what this project actually has: anything reading `NOT DEPLOYED (404)` is a part of
this file that has not been run (PostgREST answers a missing function and a missing grant with the
same 404, so a feature that silently does nothing cannot tell you which it was).

**2. Test it with two real accounts.** A shared bank cannot be tested any other way, and none of
the network paths have been exercised — not once. In order: A sends an invite to B's email; B sees
it in the Status Club requests card and accepts; both then read the same pair; A lands a flight and
the pot rises for both; **B then spends more than B's own personal balance**, which is the step
that exercises the atomic debit and the only one that can prove the race is actually settled.

**How the two balances divide.** Accepting moves nothing across — each member keeps the personal
balance they already had, and the pair gets a shared pot that starts empty and fills as either of
them lands. `AppModel.pool` is personal + pot, so no screen learned a new number. Spending takes
personal first — those miles cannot be raced, so that path stays synchronous and works offline —
and only the shortfall is a round-trip.

**Where the race is settled, and why not on the client.** `spend_from_pair` is one conditional
`UPDATE ... WHERE miles >= amount`, atomic under Postgres's row lock, so two members spending the
same 40 mi at the same moment cannot both succeed however the clients behave. The loser gets SQL
`null`, which the client reads as a **refusal** rather than an error — and that distinction is
carried all the way to the pay sheet, because "those miles have already been spent" and "could not
reach the shared bank" are different sentences, and telling a member the first when the second is
true is the worst thing this feature can do.

**A landing's credit cannot be lost.** While linked, earned miles go to the pot, which makes
banking them a call that can fail. `land()` queues the credit, persists the queue, and retries
oldest-first, stopping at the first failure so a later flight cannot jump ahead of an earlier one
still stuck. A flight that was flown always pays eventually.

**`potStale` is a promise, like the Screen Time banner.** The pot is the one number in the app that
another person can change while you are not looking, so a remembered value is never drawn as if it
were live. Every cold launch and every cloud restore starts unconfirmed until a refresh lands.

**Three things the schema does that the sketch this replaced did not**, each because the sketch had
a bug: accept and decline are `security definer` functions rather than a `PATCH`, so stamping the
invite and creating the pair are one transaction and there is no update policy a recipient could
use to rewrite an invite on the way through; the invite uniqueness constraint is **partial**, over
open invites only, because a plain `unique (from_user, to_email)` survives a decline and would have
barred that person from ever being invited again; and `accept_link_invite` refuses when either end
is already paired, because `AppModel.link` is a single optional and a pot two partners could both
spend from is a leak rather than a bank.

**What is still missing.** There is no push, so the sender learns an invite was accepted on their
next refresh rather than the moment it happens, and neither member is told when the other spends.
Both are additive; neither blocks using it.


### Offline miles and gifts (schema part six)

Deploy the complete schema and the updated app together: direct gift inserts and the old
`accept_gift` RPC are now disabled. `sync_miles`, `send_gift`, and `receive_gift` reconcile
personal offline activity and settle online transfers with replay-safe receipts. Earning and
personal redemption remain offline; no new hosted service is needed.

See [supabase/OFFLINE_MILES.md](supabase/OFFLINE_MILES.md) for research, the migration trust
allowance, transfer limits, multi-device constraints, and the isolated SQL regression command.
This migration has **not** been run against the live Supabase project. Verify in staging with
two accounts, including a dropped response, retry, relaunch, and conflicting device history.
