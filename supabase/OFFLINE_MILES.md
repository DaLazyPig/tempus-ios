# Offline miles and online gifts

## Decision

Keep one visible personal miles balance. Earning and spending personal miles work
without connectivity. Sending and accepting gifts require Supabase; offline-earned
miles are eligible after their history is reconciled. Spending a shared pot still
requires a connection, as it did before this change.

This matches the documented product boundary in comparable apps:

- [Finch](https://help.finchcare.com/hc/en-us/articles/38108378959245-Troubleshooting-bugs-within-the-app)
  supports offline use but explicitly requires connectivity for gifting and social actions.
- [Forest](https://forestapp.cc/) keeps focus sessions and local data working offline,
  then syncs on reconnection; group and shop features require connectivity.

These sources describe product behavior, not their private anti-cheat architecture.
Our implementation follows the durable local queue/reconciliation pattern described
in [Android's offline-first guidance](https://developer.android.com/topic/architecture/data-layer/offline-first),
using Swift value types and [Supabase database functions](https://supabase.com/docs/guides/database/functions).
No new hosted server, sync SDK, or production dependency is needed.

## What happens

1. Personal balance changes append a UUID, sequence, amount and timestamp to the
   local `MilesJournal`, persisted with the balance in the existing save file.
2. Before a transfer, `sync_miles` reconciles batches of up to 128 events. A matching
   replay is harmless. Gaps, altered events and competing histories are rejected.
3. The sender saves an operation ID and reserves the personal portion locally.
   `send_gift` atomically deducts the reconciled personal balance, takes any shared
   shortfall, creates the gift, and records the outcome. Direct gift INSERT is denied.
4. A timeout keeps the reservation and exact request. Reopening/foregrounding the
   app retries it. Only a durable refusal releases the reservation. Delivery is
   announced only after a confirmed response, never optimistically.
5. `receive_gift` atomically credits the recipient's wallet and stores a durable
   receipt. The phone saves its applied receipt ID and new balance together.
   Repeating a receipt never credits the server again; local IDs prevent a second
   local credit. Pending acceptance survives relaunch and a lost response.

Example: earn 100 offline, spend 20 offline, reconnect and send 30. Reconciliation
records 80; the transfer leaves 50. There are no different classes of miles in the UI.

## Trust and limits

Offline activity is self-reported. This is bounded abuse resistance for virtual
productivity points, not cryptographic proof of studying. A modified client can
still fabricate activity within the limits. We deliberately do not describe this
as eliminating fraud or trust a secret embedded in the app as authentication.

Current server limits:

- One history per account, with immutable events and serialized writes.
- A one-time legacy balance import of up to 1,000,000 mi so existing balances survive.
  This is an explicit migration trust allowance, not verified historical earning.
- Subsequent credits: at most 3,000 mi per event and per reported UTC day.
- Gifts: at most 2,000 mi per transfer and per rolling 24 hours, measured by server
  time and immutable transfer records. Backdating events cannot reset this cap.
- Any sync refusal leaves the personal balance usable locally; it prevents transfers.

Cloud backup is still backup, not multi-device wallet sync. A restored device keeps
its history ID. Independent installations cannot re-import a second opening balance
into the same account. Forked offline histories fail closed for transfers; they are
not merged or silently overwritten. Use the device with the current history. Fully
independent simultaneous offline spending across devices needs allocation/merge rules
and remains outside this change.

[Apple App Attest](https://developer.apple.com/videos/play/wwdc2021/10244/) can strengthen
transfer requests by checking app/device integrity. It needs server-side attestation
verification and key lifecycle handling. It does not prove offline human behavior;
it is the next layer if modified-client abuse warrants it, not a reason to make the
focus timer or personal redemption depend on the internet.

## Deployment and verification

Run the complete `supabase/schema.sql` in an isolated staging project first. Part six
adds the event stream, removes direct gift creation, revokes the old unsafe acceptance
RPC, and installs the new transfer functions. Old clients cannot send/accept gifts
with the obsolete protocol. Deploy the updated app together with this migration.
No live database was changed during implementation.

The regression check uses a temporary in-memory PostgreSQL runtime:

```sh
npm install --prefix /tmp/tempus-codex/sql-check --no-save --ignore-scripts --no-audit --no-fund @electric-sql/pglite
node supabase/tests/offline-gifts.mjs /tmp/tempus-codex/sql-check/node_modules/@electric-sql/pglite/dist/index.js
```

It checks policy enforcement, schema reruns, replay/conflicting histories, insufficient
funds, transfer limits, shared shortfalls and durable receipts. PGlite uses one database
connection; independent-connection concurrency and real Supabase authentication still
need staging verification with two accounts. App DEBUG self-checks also cover journal
persistence, receipt deduplication and personal redemption without a backend.
