import Foundation
import Observation
import Security

/// The cloud copy of one member's save file.
///
/// **What this is, and what it deliberately is not.** It is a backup: the phone stays the source
/// of truth and the server holds the most recent copy of the same `AppModel.Stored` blob that
/// already lives in `UserDefaults`. It is not a shared bank and not a sync engine — two phones
/// signed into one account will not agree about miles, and nothing here pretends they would.
/// That is the next feature, and it needs the server to own the balance rather than mirror it.
///
/// **Why the blob and not columns.** `Stored` is every field optional on purpose, so an old save
/// keeps decoding when a new field lands. Mirroring it into a table would trade that for a
/// migration on every release. One `jsonb` column keeps the property and costs nothing: Postgres
/// never reads inside it, because only this app ever will.
///
/// Talks to PostgREST and GoTrue over `URLSession`, the same way `Identity` talks to Google —
/// four endpoints do not earn a package.
@MainActor
@Observable
final class Backend {

    // MARK: - Configuration

    /// From `SupabaseURL` / `SupabaseAnonKey` in Info.plist, both treated as absent while they
    /// still read `YOUR_…`, exactly like `Billing.apiKey` and `Identity.googleClientID`.
    nonisolated static var url: URL? {
        let s = Bundle.main.object(forInfoDictionaryKey: "SupabaseURL") as? String
        guard let s, !s.isEmpty, !s.hasPrefix("YOUR_") else { return nil }
        return URL(string: s)
    }

    nonisolated static var anonKey: String? {
        let k = Bundle.main.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String
        guard let k, !k.isEmpty, !k.hasPrefix("YOUR_") else { return nil }
        return k
    }

    /// The one constant the copy and the code share. `Identity.syncAvailable` reads this, so a
    /// build with no project configured says "your name on the card" and a configured one says
    /// the backup line — neither can promise what the other cannot do.
    nonisolated static var isConfigured: Bool { url != nil && anonKey != nil }

    // MARK: - State

    enum SyncState: Equatable {
        case idle
        case working
        case ok(Date)
        case failed(String)
    }

    private(set) var state: SyncState = .idle

    /// When this device last successfully pushed. Local-only; the server's `updated_at` is what
    /// actually orders writes.
    private(set) var lastPush: Date?

    private var session: Session?
    private var pushTask: Task<Void, Never>?
    /// Bumped by `signOut` and by every `store` of a *new* session. A refresh that was already in
    /// flight when the member signed out used to land afterwards and quietly sign them back in —
    /// `accessToken()` now captures the generation before the round trip and discards a result
    /// from an older one, success or failure alike.
    private var generation = 0

    // MARK: - Session

    /// GoTrue's reply. The refresh token is a credential, so it goes to the Keychain rather than
    /// `UserDefaults` — a device backup carries the latter in the clear.
    private struct Session: Codable {
        var accessToken: String
        var refreshToken: String
        var userID: String
        /// Absolute, not a duration: a session read back from the Keychain was minted in a
        /// previous launch and "expires in 3600" would be a lie by then.
        var expiresAt: Date

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case userID, expiresAt
        }

        var isFresh: Bool { expiresAt.timeIntervalSinceNow > 60 }
    }

    private static let keychainAccount = "tempus.backend.session.v1"

    init() {
        session = Keychain.read(Self.keychainAccount).flatMap {
            try? JSONDecoder().decode(Session.self, from: $0)
        }
    }

    var isLinked: Bool { session != nil }
    var userID: String? { session?.userID.lowercased() }

    func signOut() {
        pushTask?.cancel()
        generation += 1
        session = nil
        state = .idle
        Keychain.delete(Self.keychainAccount)
    }

    private func store(_ s: Session?) {
        session = s
        guard let s, let data = try? JSONEncoder().encode(s) else {
            Keychain.delete(Self.keychainAccount); return
        }
        Keychain.write(data, account: Self.keychainAccount)
    }

    // MARK: - Signing in

    /// Exchanges a provider's `id_token` for a Supabase session. Both of `Identity`'s real
    /// providers already hold one of these by the time they build an `Account` — Apple's arrives
    /// on the credential, Google's in the token response — so nothing new is asked of the member.
    ///
    /// Email is not a provider here: `Identity.signInWithEmail` validates an address and nothing
    /// more, which is not an identity a server may trust.
    func link(idToken: String, nonce: String?, provider: AuthProvider) async throws {
        guard let url = Self.url, let anon = Self.anonKey else {
            throw BackendError.notConfigured
        }
        let name: String
        switch provider {
        case .apple: name = "apple"
        case .google: name = "google"
        case .email: throw BackendError.unsupportedProvider
        }

        var req = URLRequest(url: url.appending(path: "auth/v1/token")
            .appending(queryItems: [.init(name: "grant_type", value: "id_token")]))
        req.httpMethod = "POST"
        req.setValue(anon, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // GoTrue refuses the pair where one side has a nonce and the other does not, so the nonce
        // is sent exactly when the token carries one — never an empty string standing in for it.
        var body: [String: String] = ["provider": name, "id_token": idToken]
        if let nonce { body["nonce"] = nonce }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        generation += 1
        store(try await Self.session(from: req))
    }

    private static func session(from req: URLRequest) async throws -> Session {
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw BackendError.transport }
        guard http.statusCode == 200 else {
            throw BackendError.rejected(Self.message(data) ?? "status \(http.statusCode)")
        }
        struct Reply: Decodable {
            let access_token: String
            let refresh_token: String
            let expires_in: Double
            let user: User
            struct User: Decodable { let id: String }
        }
        let r = try JSONDecoder().decode(Reply.self, from: data)
        return Session(accessToken: r.access_token,
                       refreshToken: r.refresh_token,
                       userID: r.user.id,
                       expiresAt: Date().addingTimeInterval(r.expires_in))
    }

    /// GoTrue's error bodies are `{"error_description":…}` or `{"msg":…}` depending on the
    /// endpoint, and PostgREST's are `{"message":…}`. Read all three rather than show a bare code.
    private static func message(_ data: Data) -> String? {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (o["error_description"] ?? o["msg"] ?? o["message"]) as? String
    }

    /// Returns a live access token, refreshing first if the stored one has aged out. A refresh
    /// that is refused means the session is genuinely gone — signed out elsewhere, or revoked —
    /// so the local one is dropped rather than retried forever.
    private func accessToken() async throws -> (token: String, userID: String) {
        guard let current = session else { throw BackendError.notLinked }
        if current.isFresh { return (current.accessToken, current.userID) }

        guard let url = Self.url, let anon = Self.anonKey else { throw BackendError.notConfigured }
        var req = URLRequest(url: url.appending(path: "auth/v1/token")
            .appending(queryItems: [.init(name: "grant_type", value: "refresh_token")]))
        req.httpMethod = "POST"
        req.setValue(anon, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(
            withJSONObject: ["refresh_token": current.refreshToken])

        let gen = generation
        do {
            let fresh = try await Self.session(from: req)
            guard gen == generation else { throw BackendError.notLinked }
            store(fresh)
            return (fresh.accessToken, fresh.userID)
        } catch BackendError.rejected(let why) {
            // Only this refresh's own session may be dropped — not one a sign-out or a newer
            // sign-in has already replaced.
            if gen == generation { store(nil) }
            throw BackendError.rejected(why)
        }
    }

    /// A PostgREST request already carrying the anon key and this member's bearer token, plus the
    /// member's id — every call below needs both, and the id is only known once a refresh has
    /// settled.
    private func authorized(_ path: String, _ items: [URLQueryItem] = []) async throws -> (req: URLRequest, userID: String) {
        guard let url = Self.url, let anon = Self.anonKey else { throw BackendError.notConfigured }
        let (token, userID) = try await accessToken()
        let endpoint = url.appending(path: path)
        var req = URLRequest(url: items.isEmpty ? endpoint : endpoint.appending(queryItems: items))
        req.setValue(anon, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return (req, userID)
    }

    /// The member's own id, for a query that has to name it. Refreshes if needed.
    private func currentUserID() async throws -> String {
        try await accessToken().userID
    }

    // MARK: - The backup itself

    /// Coalesces a burst of saves into one upload. `AppModel.save()` runs on nearly every
    /// mutation — a dial drag writes it many times a second — and the backup is worth exactly one
    /// round trip per pause, not one per frame.
    func schedulePush(_ blob: Data) {
        guard isLinked, Self.isConfigured else { return }
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.push(blob)
        }
    }

    /// Upserts this member's one row. `resolution=merge-duplicates` makes the primary key do the
    /// work, so there is no read-then-write and nothing to race against.
    func push(_ blob: Data) async {
        guard isLinked else { return }
        state = .working
        do {
            let (base, userID) = try await authorized("rest/v1/backups")
            var req = base
            req.httpMethod = "POST"
            req.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
            req.httpBody = try JSONSerialization.data(withJSONObject: [
                "user_id": userID,
                "blob": try JSONSerialization.jsonObject(with: blob),
                "updated_at": ISO8601DateFormatter().string(from: Date())
            ])
            let (data, response) = try await URLSession.shared.data(for: req)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(code) else {
                throw BackendError.rejected(Self.message(data) ?? "status \(code)")
            }
            lastPush = Date()
            state = .ok(Date())
        } catch {
            state = .failed(Self.describe(error))
        }
    }

    /// Delete the account: every row this member wrote, and the auth user itself.
    ///
    /// App Store Review 5.1.1(v) requires an account-deletion path in any app whose sign-in creates
    /// an account, and it has to remove the data — signing out is explicitly not enough. This used
    /// to DELETE the backup row directly, and under RLS with no delete policy that matched nothing,
    /// returned 204, and the app reported success over a row that was still there. It is now one
    /// call to `delete_my_account()` (see `supabase/schema.sql`), a definer function that splits a
    /// shared pot, removes the backup and every invite, and deletes the auth user — which also
    /// revokes every session and refresh token. The function can only ever delete its caller.
    ///
    /// Returns the member's half of a shared pot, if there was one. The caller is about to wipe the
    /// phone as well, so the figure is informational; it is returned rather than dropped so a future
    /// "delete account but keep this phone" path has it.
    ///
    /// A 404 means the function has not been run against the project yet, and that is reported as
    /// `.notProvisioned` rather than swallowed: a deletion that did not happen must never be
    /// announced as one that did.
    @discardableResult
    func deleteAccount() async throws -> Int {
        guard isLinked, Self.isConfigured else { return 0 }
        // Apple's grant goes first, while the session that authorises the call still exists.
        await revokeAppleToken()
        let (base, _) = try await authorized("rest/v1/rpc/delete_my_account")
        var req = base
        req.httpMethod = "POST"
        req.httpBody = Data("{}".utf8)
        let (data, response) = try await URLSession.shared.data(for: req)
        try Self.checkLinkResponse(data, response)
        return (try? JSONDecoder().decode(Int.self, from: data)) ?? 0
    }

    // MARK: - Sign in with Apple's revocation

    /// Apple asks an app that offers Sign in with Apple to revoke the member's token when their
    /// account is deleted, and revoking needs a refresh token only the *authorization code* from
    /// sign-in can buy — within five minutes, once. The `apple-token` Edge Function
    /// (`supabase/functions/apple-token`) holds the Apple private key, does the exchange, and keeps
    /// the refresh token in `public.apple_tokens`, a table no client policy can read.
    ///
    /// Best effort on purpose: a member signing in for the name on their card must never see a
    /// revocation error, and a deletion must not be refused because Apple's endpoint was down —
    /// the data goes regardless. A 404 means the function is not deployed yet (SETUP.md).
    func storeAppleCode(_ code: String) async {
        await appleToken(["action": "store", "code": code])
    }

    func revokeAppleToken() async {
        await appleToken(["action": "revoke"])
    }

    private func appleToken(_ body: [String: String]) async {
        guard let (base, _) = try? await authorized("functions/v1/apple-token") else { return }
        var req = base
        req.httpMethod = "POST"
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await URLSession.shared.data(for: req)
    }

    /// The stored blob for this member, or nil when the server has never seen them. Decoding is
    /// left to the caller so this file never needs to know what `Stored` looks like.
    func pull() async throws -> Data? {
        let me = try await currentUserID()
        let (req, _) = try await authorized("rest/v1/backups", [
            .init(name: "user_id", value: "eq.\(me)"),
            .init(name: "select", value: "blob")
        ])
        let (data, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw BackendError.rejected(Self.message(data) ?? "status \(code)")
        }
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let blob = rows.first?["blob"] else { return nil }
        return try JSONSerialization.data(withJSONObject: blob)
    }

    // MARK: - The shared bank (linking)

    /// The Postgres columns are snake_case and these three types spell their properties the
    /// ordinary camelCase way, so every decode of them goes through one decoder with the
    /// automatic conversion rather than three sets of `CodingKeys`.
    private static let snakeDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    /// The failure shape every `link_*` call shares on top of `push`/`pull`'s: a 404 means the
    /// tables or functions in `supabase/schema.sql` have not been run against this project yet —
    /// PostgREST answers a relation or RPC it cannot find with 404, same as it would for a typo —
    /// so that specific case becomes a message the app can show plainly instead of a raw failure.
    private static func checkLinkResponse(_ data: Data, _ response: URLResponse) throws {
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            if code == 404 { throw BackendError.notProvisioned }
            throw BackendError.rejected(message(data) ?? "status \(code)")
        }
    }

    /// Posts a new invite. `link_invites` carries `unique (from_user, to_email)`, so a second
    /// invite to someone already invited comes back 409 — checked before the general failure path
    /// so it can surface as `.duplicateInvite`, a refusal the sender can act on, rather than a
    /// generic rejection.
    func sendInvite(toName: String, toEmail: String, fromName: String) async throws -> LinkInvite {
        let (base, userID) = try await authorized("rest/v1/link_invites")
        var req = base
        req.httpMethod = "POST"
        req.setValue("return=representation", forHTTPHeaderField: "Prefer")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "from_user": userID,
            "from_name": fromName,
            "to_email": toEmail,
            "to_name": toName
        ])
        let (data, response) = try await URLSession.shared.data(for: req)
        if (response as? HTTPURLResponse)?.statusCode == 409 { throw BackendError.duplicateInvite }
        try Self.checkLinkResponse(data, response)
        guard let invite = try Self.snakeDecoder.decode([LinkInvite].self, from: data).first else {
            throw BackendError.rejected("no invite returned")
        }
        return invite
    }

    /// RLS already restricts the read to invites naming this member on either end — sender or
    /// addressee — so one filtered GET returns everything open at both ends, and Swift only has to
    /// sort the two rows apart by comparing `fromUser` against the caller's own id.
    func openInvites() async throws -> (incoming: [LinkInvite], outgoing: [LinkInvite]) {
        let (req, userID) = try await authorized("rest/v1/link_invites", [
            .init(name: "accepted_by", value: "is.null"),
            .init(name: "declined_at", value: "is.null")
        ])
        let (data, response) = try await URLSession.shared.data(for: req)
        try Self.checkLinkResponse(data, response)
        let all = try Self.snakeDecoder.decode([LinkInvite].self, from: data)
        return (incoming: all.filter { $0.fromUser != userID }, outgoing: all.filter { $0.fromUser == userID })
    }

    /// The other member's name, recovered from the invite the pair was made out of.
    ///
    /// `link_pairs` carries two user ids and nothing else — no name, and there is no profile table
    /// to look one up in — so a device that never saw the invite itself (a reinstall, a second
    /// phone) had nothing to show and printed the placeholder "Linked member" for good. The
    /// invite row survives being accepted (`accepted_by` is stamped, the row is not deleted) and
    /// RLS lets both ends read it, so the names are still there to be read back. Whichever end
    /// this caller is, the partner is the other one.
    func partnerName() async throws -> String? {
        let (req, userID) = try await authorized("rest/v1/link_invites", [
            .init(name: "accepted_by", value: "not.is.null"),
            .init(name: "order", value: "accepted_at.desc"),
            .init(name: "limit", value: "1")
        ])
        let (data, response) = try await URLSession.shared.data(for: req)
        try Self.checkLinkResponse(data, response)
        guard let invite = try Self.snakeDecoder.decode([LinkInvite].self, from: data).first else { return nil }
        let name = invite.fromUser == userID ? invite.toName : invite.fromName
        return name.trimmingCharacters(in: .whitespaces).isEmpty ? nil : name
    }

    func acceptInvite(id: String) async throws -> LinkPair {
        let (base, _) = try await authorized("rest/v1/rpc/accept_link_invite")
        var req = base
        req.httpMethod = "POST"
        req.httpBody = try JSONSerialization.data(withJSONObject: ["invite": id])
        let (data, response) = try await URLSession.shared.data(for: req)
        try Self.checkLinkResponse(data, response)
        // The function returns `public.link_pairs`, not `setof` — PostgREST hands back one JSON
        // object for a single-row return, not an array.
        return try Self.snakeDecoder.decode(LinkPair.self, from: data)
    }

    func declineInvite(id: String) async throws {
        let (base, _) = try await authorized("rest/v1/rpc/decline_link_invite")
        var req = base
        req.httpMethod = "POST"
        req.httpBody = try JSONSerialization.data(withJSONObject: ["invite": id])
        let (data, response) = try await URLSession.shared.data(for: req)
        try Self.checkLinkResponse(data, response)
    }

    /// Withdrawing is a plain delete, not a function — only the sender's own row can match, and
    /// RLS's delete policy (`auth.uid() = from_user`) is what actually enforces that; the filter
    /// here just narrows it to the one invite.
    func withdrawInvite(id: String) async throws {
        let (base, _) = try await authorized("rest/v1/link_invites", [
            .init(name: "id", value: "eq.\(id)")
        ])
        var req = base
        req.httpMethod = "DELETE"
        let (data, response) = try await URLSession.shared.data(for: req)
        try Self.checkLinkResponse(data, response)
    }

    /// The caller's own pair, or nil when unlinked. RLS means only a pair naming this member can
    /// come back at all; more than one row would be a server-side bug, so this takes the first
    /// rather than crash on it.
    func currentPair() async throws -> LinkPair? {
        let (req, _) = try await authorized("rest/v1/link_pairs")
        let (data, response) = try await URLSession.shared.data(for: req)
        try Self.checkLinkResponse(data, response)
        return try Self.snakeDecoder.decode([LinkPair].self, from: data).first
    }

    /// `nil` is Postgres's own "not enough" answer: `spend_from_pair`'s `UPDATE ... WHERE miles >=
    /// amount` finds no row when the pot is short, so the function returns SQL `null`, which
    /// PostgREST serialises as the bare JSON literal `null` under a 200 — decoded here as `nil`,
    /// not thrown. Anything outside 2xx is a real failure and still throws; that split is the
    /// entire point of this method existing rather than just calling the RPC inline.
    func spendShared(pair: String, amount: Int, label: String) async throws -> Int? {
        let (base, _) = try await authorized("rest/v1/rpc/spend_from_pair")
        var req = base
        req.httpMethod = "POST"
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "pair": pair, "amount": amount, "label": label
        ])
        let (data, response) = try await URLSession.shared.data(for: req)
        try Self.checkLinkResponse(data, response)
        // The RPC's return is a bare scalar (an integer, or `null`), not a row, so this decodes
        // the top-level fragment directly rather than through a wrapper type.
        return try JSONDecoder().decode(Int?.self, from: data)
    }

    /// A landing is the only caller, so this never refuses on balance — `earn_to_pair` always
    /// matches a row it is allowed to touch or raises, which becomes a thrown `.rejected` rather
    /// than a `nil` the way `spendShared` returns one for a refusal that is not an error.
    ///
    /// `op` names the landing: a UUID the client minted when the flight landed and persisted with
    /// the queued credit. The server keeps it unique, so a retry after a dropped reply — or a
    /// replay — answers with the balance and credits nothing twice.
    func earnShared(pair: String, amount: Int, label: String, op: String) async throws -> Int {
        let (base, _) = try await authorized("rest/v1/rpc/earn_to_pair")
        var req = base
        req.httpMethod = "POST"
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "pair": pair, "amount": amount, "label": label, "op": op
        ])
        let (data, response) = try await URLSession.shared.data(for: req)
        try Self.checkLinkResponse(data, response)
        return try JSONDecoder().decode(Int.self, from: data)
    }

    /// Moves this member's whole personal balance into the pot, once, when the pair first goes
    /// live. Not `earnShared`: `earn_to_pair` is capped at 2,000 a call and 3,000 a rolling day,
    /// which is a landing's credit, not a balance. The member's own deposit row in `link_ledger`
    /// is the idempotency key, so a reply lost on the wire is safe to retry — the second call
    /// moves nothing and answers with the same balance.
    struct DepositSettlement: Decodable { let pot: Int; let sequence: Int }

    /// Paid out of the reconciled wallet, not taken on the client's word — the server refuses more
    /// than the wallet holds and debits it in the same transaction (schema part nine).
    func depositShared(pair: String, journal: MilesJournal, owner: String,
                       amount: Int) async throws -> DepositSettlement {
        try await giftRPC("deposit_to_pair", owner: owner, body: [
            "pair": pair, "wallet": journal.wallet.uuidString,
            "events": try JSONSerialization.jsonObject(with: JSONEncoder().encode(journal.pending)),
            "expected": journal.sequence, "amount": amount
        ])
    }

    /// Ends the pair. The pot is split into `link_payouts`, one row per member, and the reply is
    /// always 0 — each member collects their half through `claimPayouts`, the caller included, so
    /// a reply lost on the wire is not a share lost for good. (It used to hand the caller's half
    /// back here and delete the partner's with the row.) Unlinking always succeeds for either
    /// member, so there is nothing here to refuse.
    func unlinkPair(pair: String) async throws -> Int {
        let (base, _) = try await authorized("rest/v1/rpc/unlink_pair")
        var req = base
        req.httpMethod = "POST"
        req.httpBody = try JSONSerialization.data(withJSONObject: ["pair": pair])
        let (data, response) = try await URLSession.shared.data(for: req)
        try Self.checkLinkResponse(data, response)
        return try JSONDecoder().decode(Int.self, from: data)
    }

    /// Everything waiting for this member from an unlink, claimed atomically; 0 when nothing is.
    /// Called after every unlink and on every refresh, because the other side can unlink while
    /// this phone is in a drawer.
    func claimPayouts() async throws -> Int {
        let (base, _) = try await authorized("rest/v1/rpc/claim_payouts")
        var req = base
        req.httpMethod = "POST"
        req.httpBody = Data("{}".utf8)
        let (data, response) = try await URLSession.shared.data(for: req)
        try Self.checkLinkResponse(data, response)
        return (try? JSONDecoder().decode(Int.self, from: data)) ?? 0
    }

    // MARK: - Gifts

    struct GiftSettlement: Decodable {
        let state: String
        let reason: String?
        let sequence: Int
        let pot: Int?
    }

    struct GiftReceipt: Decodable {
        let amount: Int
        let sequence: Int
    }

    /// One transaction reconciles offline activity, debits the sender and creates the gift.
    /// A replay returns the same settlement, including a definite refusal.
    func sendGift(_ pending: PendingGift) async throws -> GiftSettlement {
        let order = pending.order
        var body: [String: Any] = [
            "operation": order.id.uuidString, "wallet": pending.wallet.uuidString,
            "events": try JSONSerialization.jsonObject(with: JSONEncoder().encode(pending.entries)),
            "expected": pending.sequence, "personal": pending.personal,
            "amount": order.amt, "cost": order.cost, "from_name": pending.fromName,
            "to_name": order.who ?? "", "to_email": order.whoEmail ?? ""
        ]
        body["pair"] = (pending.pair as Any?) ?? NSNull()
        body["face"] = (order.face as Any?) ?? NSNull()
        return try await giftRPC("send_gift", owner: pending.owner, body: body)
    }

    /// The wallet this account actually holds, or nil when it has never held one.
    ///
    /// **What it is for.** `reconcile_miles` allows exactly one wallet per account and refuses any
    /// other stream with "Restore the latest account backup before transferring miles." A phone
    /// that mints a fresh `MilesJournal` — a reinstall, an erased install, a second device — is
    /// therefore locked out of every transfer for good, with an instruction it has no way to
    /// carry out (signing in after onboarding *pushes* this phone's state over the cloud backup,
    /// so the old journal is gone by the time the refusal arrives). This is the repair: ask the
    /// account which wallet is the real one and adopt it. See `AppModel.repairMilesWallet`.
    func myWallet() async throws -> WalletState? {
        let (base, _) = try await authorized("rest/v1/rpc/my_wallet")
        var req = base
        req.httpMethod = "POST"
        req.httpBody = try JSONSerialization.data(withJSONObject: [:] as [String: Any])
        let (data, response) = try await URLSession.shared.data(for: req)
        try Self.checkLinkResponse(data, response)
        guard !data.isEmpty, String(decoding: data, as: UTF8.self) != "null" else { return nil }
        return try Self.snakeDecoder.decode(WalletState.self, from: data)
    }

    func syncMiles(_ journal: MilesJournal) async throws -> Int {
        guard let owner = journal.owner else { throw BackendError.notLinked }
        let batch = Array(journal.pending.prefix(128))
        struct Reply: Decodable { let sequence: Int }
        let reply: Reply = try await giftRPC("sync_miles", owner: owner, body: [
            "wallet": journal.wallet.uuidString,
            "events": try JSONSerialization.jsonObject(with: JSONEncoder().encode(batch)),
            "expected": batch.last?.seq ?? journal.sequence
        ])
        return reply.sequence
    }

    func acceptGift(id: String, journal: MilesJournal) async throws -> GiftReceipt {
        guard let owner = journal.owner else { throw BackendError.notLinked }
        return try await giftRPC("receive_gift", owner: owner, body: [
            "gift": id, "wallet": journal.wallet.uuidString,
            "events": try JSONSerialization.jsonObject(with: JSONEncoder().encode(journal.pending)),
            "expected": journal.sequence
        ])
    }

    /// Account switches must never submit a previous member's pending transfer.
    private func giftRPC<T: Decodable>(_ name: String, owner: String,
                                      body: [String: Any]) async throws -> T {
        let (base, user) = try await authorized("rest/v1/rpc/" + name)
        guard user.lowercased() == owner else { throw BackendError.notLinked }
        var req = base
        req.httpMethod = "POST"
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        try Self.checkLinkResponse(data, response)
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// RLS already restricts the read to gifts naming this member on either end, exactly like
    /// `openInvites` — one filtered GET, sorted apart by comparing `fromUser` to the caller's id.
    func openGifts() async throws -> (incoming: [RemoteGift], outgoing: [RemoteGift]) {
        let (req, userID) = try await authorized("rest/v1/gifts", [
            .init(name: "accepted_by", value: "is.null"),
            .init(name: "declined_at", value: "is.null")
        ])
        let (data, response) = try await URLSession.shared.data(for: req)
        try Self.checkLinkResponse(data, response)
        let all = try Self.snakeDecoder.decode([RemoteGift].self, from: data)
        return (incoming: all.filter { $0.fromUser != userID }, outgoing: all.filter { $0.fromUser == userID })
    }

    func declineGift(id: String) async throws {
        let (base, _) = try await authorized("rest/v1/rpc/decline_gift")
        var req = base
        req.httpMethod = "POST"
        req.httpBody = try JSONSerialization.data(withJSONObject: ["gift": id])
        let (data, response) = try await URLSession.shared.data(for: req)
        try Self.checkLinkResponse(data, response)
    }

    func sharedLedger(pair: String, limit: Int) async throws -> [LinkLedgerLine] {
        let (req, me) = try await authorized("rest/v1/link_ledger", [
            .init(name: "pair_id", value: "eq.\(pair)"),
            .init(name: "order", value: "at.desc"),
            .init(name: "limit", value: "\(limit)")
        ])
        let (data, response) = try await URLSession.shared.data(for: req)
        try Self.checkLinkResponse(data, response)
        var lines = try Self.snakeDecoder.decode([LinkLedgerLine].self, from: data)
        // Both members read every line, so a line has to say whose it is or the ledger answers
        // "where did the miles go" without answering "who spent them" — which is most of the
        // question when two people share a bank. `authorized` already knows the caller's id;
        // stamping it here means no screen has to go asking for it.
        for i in lines.indices { lines[i].mine = (lines[i].userId == me) }
        return lines
    }

    /// **A read-only sweep of what `supabase/schema.sql` has actually been run against this
    /// project.** The developer panel's answer to "did I deploy the schema?", which is otherwise
    /// only discoverable by hitting a feature and reading a failure — and PostgREST answers a
    /// missing function and a missing *grant* with the same 404, so guessing from a feature is
    /// guessing.
    ///
    /// Nothing here writes. The one function called with real arguments, `earn_to_pair`, is given
    /// an amount of 0, which it refuses (`amount out of range`) before touching a row — and a
    /// refusal is exactly the proof wanted: the function is there and this member may call it.
    func probe() async -> [(String, String)] {
        func run(_ label: String, _ call: @escaping () async throws -> Void) async -> (String, String) {
            do { try await call(); return (label, "ok") }
            catch BackendError.notProvisioned { return (label, "NOT DEPLOYED (404)") }
            catch BackendError.rejected(let why) { return (label, "reachable \u{2014} \(why)") }
            catch { return (label, Self.describe(error)) }
        }
        var rows: [(String, String)] = []
        rows.append(await run("link_invites") { _ = try await self.openInvites() })
        rows.append(await run("link_pairs") { _ = try await self.currentPair() })
        rows.append(await run("gifts") { _ = try await self.openGifts() })
        rows.append(await run("earn_to_pair(op)") {
            try await self.rpcProbe("earn_to_pair", ["pair": UUID().uuidString, "amount": 0,
                                                     "label": "probe", "op": UUID().uuidString])
        })
        rows.append(await run("deposit_to_pair") {
            // −1 is refused by the range check before a row is read, let alone written.
            try await self.rpcProbe("deposit_to_pair", ["pair": UUID().uuidString, "amount": -1])
        })
        rows.append(await run("my_wallet") { _ = try await self.myWallet() })
        return rows
    }

    /// Posts an RPC purely to see whether it answers at all. The body is expected to be refused.
    private func rpcProbe(_ name: String, _ body: [String: Any]) async throws {
        let (base, _) = try await authorized("rest/v1/rpc/\(name)")
        var req = base
        req.httpMethod = "POST"
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        try Self.checkLinkResponse(data, response)
    }

    static func describe(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

enum BackendError: LocalizedError {
    case notConfigured
    case notLinked
    case unsupportedProvider
    case transport
    case rejected(String)
    /// The tables and functions in `supabase/schema.sql` have not been run against this project
    /// yet. PostgREST answers a missing relation or RPC function with a 404 — indistinguishable
    /// from a typo in the path — so `checkLinkResponse` turns that specific status into this case
    /// rather than a raw failure, letting the app say "the shared bank isn't set up yet".
    case notProvisioned
    /// `link_invites` carries `unique (from_user, to_email)`; sending a second invite to someone
    /// already invited is a 409. Worth telling apart from a generic rejection because it is
    /// recoverable — the sender already has an open invite waiting, not a broken connection.
    case duplicateInvite

    /// Whether a refusal is `reconcile_miles` saying this phone's miles stream is not the one the
    /// account holds. All three of its wallet-identity exceptions name the same repair, and the
    /// client's answer to all three is the same: adopt the account's own stream
    /// (`AppModel.repairMilesWallet`). Matched on the server's text because PostgREST collapses
    /// every `check_violation` to one status — there is no code to switch on.
    static func isWalletMismatch(_ error: Error) -> Bool {
        guard case .rejected(let why)? = error as? BackendError else { return false }
        return why.contains("Restore the latest account backup")
            || why.contains("Conflicting offline history")
            || why.contains("miles history is out of date")
    }

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Cloud backup is not set up in this build."
        case .notLinked: return "Not signed in to cloud backup."
        case .unsupportedProvider: return "That sign in cannot back up to the cloud."
        case .transport: return "Could not reach the backup."
        case .rejected(let why): return why
        case .notProvisioned: return "This part of the account server isn't set up yet."
        case .duplicateInvite: return "You've already invited that address."
        }
    }
}

/// A pending or answered invite to link banks. Mirrors `public.link_invites`; the Postgres
/// columns are snake_case and these properties are the ordinary camelCase spelling, decoded
/// through `Backend.snakeDecoder`'s automatic conversion.
struct LinkInvite: Codable, Identifiable, Hashable {
    let id: String
    let fromUser: String
    let fromName: String
    let toEmail: String
    let toName: String
    let createdAt: String
    let acceptedBy: String?
    let acceptedAt: String?
    let declinedAt: String?
}

/// Two linked members and the pot they share. Mirrors `public.link_pairs`.
struct LinkPair: Codable, Identifiable, Hashable {
    let id: String
    let aUser: String
    let bUser: String
    let miles: Int
    let linkedAt: String
}

/// What `my_wallet()` answers with: the one miles stream this account is allowed to write.
struct WalletState: Codable, Hashable {
    let wallet: UUID
    let sequence: Int
    let balance: Int
}

/// A real gift, sent or received. Mirrors `public.gifts`; same shape as `LinkInvite`, decoded
/// through `Backend.snakeDecoder`.
struct RemoteGift: Codable, Identifiable, Hashable {
    let id: String
    let fromUser: String
    let fromName: String
    let toEmail: String
    let toName: String
    let amount: Int
    let face: String?
    let createdAt: String
    let acceptedBy: String?
    let acceptedAt: String?
    let declinedAt: String?
}

/// One movement of the shared pot. Mirrors `public.link_ledger`.
struct LinkLedgerLine: Codable, Identifiable, Hashable {
    let id: String
    let userId: String
    let amount: Int      // positive credit, negative debit
    let label: String
    let at: String

    /// Whether this line is the reading member's own movement. Not a column — the server has no
    /// idea who is asking — so it is stamped by `sharedLedger` from the caller's own id, and is
    /// deliberately excluded from decoding so a missing key can never fail the whole fetch.
    var mine: Bool = false

    private enum CodingKeys: String, CodingKey { case id, userId, amount, label, at }
}

// MARK: - Keychain

/// Four lines of `SecItem` rather than a wrapper package. Only one item is ever stored, so the
/// query is a constant and there is nothing to generalise.
private enum Keychain {
    private static let service = "com.crescerestudios.tempus"

    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func write(_ data: Data, account: String) {
        SecItemDelete(query(account) as CFDictionary)
        var add = query(account)
        add[kSecValueData as String] = data
        // The session is only ever refreshed while the member is using the app, so it never needs
        // reading before first unlock — and `ThisDeviceOnly` keeps it out of an iCloud backup,
        // where a refresh token has no business being.
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    static func read(_ account: String) -> Data? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    static func delete(_ account: String) {
        SecItemDelete(query(account) as CFDictionary)
    }
}
