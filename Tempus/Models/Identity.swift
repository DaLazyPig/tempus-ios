import AuthenticationServices
import CryptoKit
import Foundation
import Observation
import UIKit

/// Who is signed in. The reference has no account layer at all — its three buttons are
/// `run(7)`, three ways of saying "next" — so there is nothing to port and everything to build.
///
/// **What signing in does.** It establishes a real, verified identity: Apple through
/// `AuthenticationServices`, Google through OAuth 2.0 with PKCE, email through a validated address.
/// That identity names the member, prints on the card and every pass, and survives a reinstall.
///
/// For the two real providers it also carries a save file: the `id_token` each flow already
/// receives is what `Backend` exchanges for a Supabase session, so the same tap that puts a name on
/// the card is the one that backs the account up. Email is deliberately not one of them — a
/// validated address is not an identity a server may trust. `Identity.syncAvailable` is what the
/// copy reads, and it is false in a build with no Supabase project, so the promise and the
/// capability cannot drift apart.
enum AuthProvider: String, Codable, Hashable, CaseIterable {
    case apple, google, email

    var label: String {
        switch self {
        case .apple: return "Apple"
        case .google: return "Google"
        case .email: return "Email"
        }
    }
}

/// A signed-in member. `id` is the provider's stable subject — Apple's `user`, Google's `sub`, or
/// the lowercased address for email — so re-signing in recognises the same person.
struct Account: Codable, Hashable {
    var provider: AuthProvider
    var id: String
    var name: String
    var email: String
    var at: TimeInterval = Date().timeIntervalSince1970

    /// What goes on the card. Falls back through the address's local part rather than ever
    /// printing an empty name.
    var displayName: String {
        if !name.trimmingCharacters(in: .whitespaces).isEmpty { return name }
        if let local = email.split(separator: "@").first, !local.isEmpty {
            return local.replacingOccurrences(of: ".", with: " ").capitalized
        }
        return "Tempus member"
    }
}

enum AuthError: LocalizedError {
    case cancelled
    case notConfigured(String)
    case badResponse(String)
    case invalidEmail

    var errorDescription: String? {
        switch self {
        case .cancelled: return "Sign in cancelled."
        case .notConfigured(let what): return what
        case .badResponse(let why): return why
        case .invalidEmail: return "That does not look like an email address."
        }
    }
}

@MainActor
@Observable
final class Identity {
    /// Whether this build can actually keep a member's save file. One named constant so the copy
    /// that promises sync and the code that would do it can never drift apart — onboarding screen
    /// 6 reads it, and it is false in a build with no Supabase project configured.
    static var syncAvailable: Bool { Backend.isConfigured }

    private(set) var account: Account?
    private(set) var busy: AuthProvider?
    var error: String?

    /// The `id_token` from the sign-in that just succeeded, for `Backend.link` to exchange for a
    /// Supabase session. Held rather than passed back because the two real providers produce it at
    /// different points in their flows, and neither should have to reshape `Account` to carry it.
    ///
    /// Cleared at the start of every attempt, so it can never be a stale token from last time.
    /// Email never sets one: a validated address is not an identity a server may trust.
    private(set) var lastIDToken: String?

    /// The **raw** nonce that `lastIDToken` was issued against — the token itself carries only its
    /// SHA-256, which is the point: a token lifted off the wire cannot be replayed without the
    /// preimage, and only this process ever held it.
    ///
    /// Supabase re-hashes what it is given and compares, so this must be the unhashed string.
    /// It is also all-or-nothing — GoTrue refuses a token whose nonce claim exists while the
    /// request's does not, and the reverse — so the two are always set and cleared together.
    private(set) var lastNonce: String?
    /// Apple's one-shot authorization code from the last Apple sign-in. Exchangeable with Apple for
    /// five minutes only, so `AppModel` hands it to the server right after the session is linked;
    /// the server keeps the refresh token it buys, which is what account deletion later revokes.
    private(set) var lastAppleCode: String?

    private static let key = "tempus.account.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let acc = try? JSONDecoder().decode(Account.self, from: data) {
            account = acc
        }
    }

    var isSignedIn: Bool { account != nil }

    func signOut() {
        account = nil
        UserDefaults.standard.removeObject(forKey: Self.key)
    }

    /// Delete the account and everything stored against it.
    ///
    /// App Store Review 5.1.1(v): an app whose sign-in creates an account must offer deletion from
    /// inside the app, and it has to remove the data — offering sign-out instead is called out
    /// specifically as not sufficient. Signing in here creates a Supabase user and writes a backup
    /// row, so this deletes the user and every row (`Backend.deleteAccount`), drops the session,
    /// and clears the local copy. The caller wipes the rest of the phone — see
    /// `SettingsScreen.deleteAccount`.
    ///
    /// Returns nil on success, or a sentence to show if the server refused. A network failure must
    /// not leave the member signed in believing they deleted something.
    @discardableResult
    func deleteAccount(_ backend: Backend) async -> String? {
        do {
            try await backend.deleteAccount()
        } catch {
            return Backend.describe(error)
        }
        backend.signOut()
        signOut()
        return nil
    }

    private func adopt(_ acc: Account) {
        account = acc
        if let data = try? JSONEncoder().encode(acc) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    /// Runs one sign-in and reports whether it took. Cancellation is not an error the user needs
    /// told about — they did it on purpose — so it clears the spinner and says nothing.
    @discardableResult
    private func attempt(_ provider: AuthProvider, _ work: () async throws -> Account) async -> Bool {
        guard busy == nil else { return false }
        busy = provider
        error = nil
        lastIDToken = nil
        lastNonce = nil
        lastAppleCode = nil
        defer { busy = nil }
        do {
            adopt(try await work())
            return true
        } catch AuthError.cancelled {
            return false
        } catch let e as ASAuthorizationError where e.code == .canceled {
            return false
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    // MARK: - Apple

    /// Native, and the only one of the three that needs no configuration beyond the Sign in with
    /// Apple capability on the target.
    @discardableResult
    func signInWithApple() async -> Bool {
        await attempt(.apple) {
            let nonce = try Self.randomURLSafe(32)
            let cred = try await AppleFlow.run(nonce: Self.sha256Hex(nonce))
            // Apple hands over the name and address on the FIRST authorization only; every later
            // one returns nil for both. Anything already stored for this `user` therefore wins over
            // a nil, or the member would be renamed to nothing on their second sign-in.
            let name = [cred.fullName?.givenName, cred.fullName?.familyName]
                .compactMap { $0 }.joined(separator: " ")
            let stored = self.account?.id == cred.user ? self.account : nil
            self.lastIDToken = cred.identityToken.flatMap { String(data: $0, encoding: .utf8) }
            self.lastNonce = self.lastIDToken == nil ? nil : nonce
            self.lastAppleCode = cred.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
            return Account(provider: .apple,
                           id: cred.user,
                           name: name.isEmpty ? (stored?.name ?? "") : name,
                           email: cred.email ?? stored?.email ?? "")
        }
    }

    // MARK: - Google

    /// The iOS OAuth client id, from `GIDClientID` in Info.plist. No client secret: an iOS client
    /// is a public client, which is exactly why the exchange below is PKCE.
    static var googleClientID: String? {
        let id = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String
        guard let id, !id.isEmpty, !id.hasPrefix("YOUR_") else { return nil }
        return id
    }

    static var googleConfigured: Bool { googleClientID != nil }

    /// `123-abc.apps.googleusercontent.com` → `com.googleusercontent.apps.123-abc`, which is both
    /// the callback scheme and the redirect URI's host-less prefix. Google mints this pair
    /// together; deriving it means there is only one value to paste into Info.plist, not two that
    /// can disagree.
    nonisolated static func reversedClientID(_ clientID: String) -> String {
        clientID.split(separator: ".").reversed().joined(separator: ".")
    }

    /// Authorization-code flow with PKCE, run in `ASWebAuthenticationSession` so the credentials
    /// are typed to Google in a browser this process cannot read — the same thing Google's own SDK
    /// does underneath, minus four packages.
    ///
    /// `ASWebAuthenticationSession` intercepts the callback scheme itself, so unlike a plain
    /// `openURL` round trip this needs no `CFBundleURLTypes` entry.
    ///
    /// A subject alone used to be enough to adopt the claims. This local adoption path now checks
    /// who issued the token, who it is for, when it expires and which request it answers before
    /// putting a name on the card; an explicitly unverified email is not adopted. Supabase still
    /// re-verifies the token server-side — these claim checks do not verify its signature.
    @discardableResult
    func signInWithGoogle() async -> Bool {
        await attempt(.google) {
            guard let clientID = Self.googleClientID else {
                throw AuthError.notConfigured(
                    "Google sign in is not set up yet. Add your iOS OAuth client id as GIDClientID in Info.plist.")
            }
            let redirect = "\(Self.reversedClientID(clientID)):/oauth2redirect"
            let verifier = try Self.randomURLSafe(64)
            let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).urlSafeBase64
            let state = try Self.randomURLSafe(24)
            // Distinct from the PKCE pair above and doing a different job: PKCE proves this
            // process asked for the code, the nonce proves the id_token was minted for this
            // request. Google echoes it into the token unchanged, so the hash is what is sent.
            let nonce = try Self.randomURLSafe(32)

            var auth = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
            auth.queryItems = [
                .init(name: "client_id", value: clientID),
                .init(name: "redirect_uri", value: redirect),
                .init(name: "response_type", value: "code"),
                .init(name: "scope", value: "openid email profile"),
                .init(name: "code_challenge", value: challenge),
                .init(name: "code_challenge_method", value: "S256"),
                .init(name: "nonce", value: Self.sha256Hex(nonce)),
                .init(name: "state", value: state)
            ]

            let callback = try await WebAuthFlow.run(
                url: auth.url!, scheme: Self.reversedClientID(clientID))

            let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
            func item(_ n: String) -> String? { items.first { $0.name == n }?.value }
            if let denied = item("error") {
                throw denied == "access_denied" ? AuthError.cancelled
                                                : AuthError.badResponse("Google refused: \(denied).")
            }
            // A mismatched state means the response is not the one this session asked for. Bail
            // rather than exchange a code that arrived from somewhere else.
            guard item("state") == state else { throw AuthError.badResponse("Google sign in did not verify.") }
            guard let code = item("code") else { throw AuthError.badResponse("Google returned no code.") }

            var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
            req.httpMethod = "POST"
            req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            var form = URLComponents()
            form.queryItems = [
                .init(name: "client_id", value: clientID),
                .init(name: "code", value: code),
                .init(name: "code_verifier", value: verifier),
                .init(name: "grant_type", value: "authorization_code"),
                .init(name: "redirect_uri", value: redirect)
            ]
            req.httpBody = form.percentEncodedQuery?.data(using: .utf8)

            let (data, response) = try await URLSession.shared.data(for: req)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw AuthError.badResponse("Google would not issue a token.")
            }
            struct TokenResponse: Decodable { let id_token: String? }
            guard let idToken = try? JSONDecoder().decode(TokenResponse.self, from: data).id_token,
                  let claims = Self.claims(idToken),
                  let sub = claims["sub"] as? String, !sub.isEmpty,
                  claims["aud"] as? String == clientID,
                  let issuer = claims["iss"] as? String,
                  issuer == "https://accounts.google.com" || issuer == "accounts.google.com",
                  let expiry = claims["exp"] as? TimeInterval, expiry > Date().timeIntervalSince1970,
                  claims["nonce"] as? String == Self.sha256Hex(nonce) else {
                throw AuthError.badResponse("Google sign in did not verify.")
            }
            self.lastIDToken = idToken
            self.lastNonce = nonce
            return Account(provider: .google, id: sub,
                           name: claims["name"] as? String ?? "",
                           email: claims["email_verified"] as? Bool == false ? "" : (claims["email"] as? String ?? ""))
        }
    }

    // MARK: - Email

    /// No backend means no magic link and no password to check, so this is exactly what it looks
    /// like: a validated address, kept on the phone. It is never described as verified.
    @discardableResult
    func signInWithEmail(_ raw: String) async -> Bool {
        await attempt(.email) {
            let address = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard Self.isValidEmail(address) else { throw AuthError.invalidEmail }
            return Account(provider: .email, id: address, name: "", email: address)
        }
    }

    /// Deliberately loose: something, an @, something with a dot and a two-plus letter tail. Strict
    /// address grammar rejects addresses that work, which is worse than accepting one that does not.
    nonisolated static func isValidEmail(_ s: String) -> Bool {
        s.wholeMatch(of: /[^@\s]+@[^@\s.]+(\.[^@\s.]+)*\.[A-Za-z]{2,}/) != nil
    }

    // MARK: - Bits

    /// Lowercase hex, because that is the shape both verifiers expect: GoTrue compares against
    /// `fmt.Sprintf("%x", sha256.Sum256(nonce))`, and Apple's own guidance hashes the same way.
    /// Not the base64 used for the PKCE challenge, which answers to a different spec.
    nonisolated static func sha256Hex(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Ignoring a failed random read made the zero-filled buffer a usable nonce or PKCE secret.
    /// Both sign-in flows must stop instead: predictable bytes cannot prove who asked to sign in.
    private static func randomURLSafe(_ count: Int) throws -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else {
            throw AuthError.badResponse("Could not securely start sign in. Try again.")
        }
        return Data(bytes).urlSafeBase64
    }

    /// The payload segment of a JWT. Base64url, so it is re-padded before decoding.
    private static func claims(_ jwt: String) -> [String: Any]? {
        let parts = jwt.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var b64 = String(parts[1]).replacingOccurrences(of: "-", with: "+")
                                  .replacingOccurrences(of: "_", with: "/")
        b64 += String(repeating: "=", count: (4 - b64.count % 4) % 4)
        guard let data = Data(base64Encoded: b64) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}

private extension Data {
    var urlSafeBase64: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - The two AppKit-shaped flows, wrapped in async

/// `ASWebAuthenticationSession` and `ASAuthorizationController` are both delegate-and-callback
/// shaped, and neither retains the object it calls back. Each flow below therefore holds itself
/// alive across the round trip and lets go exactly once, in `finish`.

@MainActor
private final class WebAuthFlow: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    private var cont: CheckedContinuation<URL, Error>?
    private var keep: WebAuthFlow?

    static func run(url: URL, scheme: String) async throws -> URL {
        try await WebAuthFlow().start(url: url, scheme: scheme)
    }

    private func start(url: URL, scheme: String) async throws -> URL {
        keep = self
        return try await withCheckedThrowingContinuation { cont in
            self.cont = cont
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { [weak self] callback, error in
                if let callback { self?.finish(.success(callback)) }
                else if let error = error as? ASWebAuthenticationSessionError,
                        error.code == .canceledLogin { self?.finish(.failure(AuthError.cancelled)) }
                else { self?.finish(.failure(error ?? AuthError.cancelled)) }
            }
            session.presentationContextProvider = self
            // A fresh browser session every time: otherwise a signed-in Google cookie makes the
            // account picker vanish, and there is no way to sign in as anyone else.
            session.prefersEphemeralWebBrowserSession = true
            self.session = session
            if !session.start() {
                finish(.failure(AuthError.badResponse("Could not open the sign in page.")))
            }
        }
    }

    private func finish(_ result: Result<URL, Error>) {
        guard let cont else { return }
        self.cont = nil
        session = nil
        cont.resume(with: result)
        keep = nil
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.topWindow ?? ASPresentationAnchor()
    }
}

@MainActor
private final class AppleFlow: NSObject, ASAuthorizationControllerDelegate,
                               ASAuthorizationControllerPresentationContextProviding {
    private var cont: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>?
    private var keep: AppleFlow?

    static func run(nonce: String) async throws -> ASAuthorizationAppleIDCredential {
        try await AppleFlow().start(nonce: nonce)
    }

    private func start(nonce: String) async throws -> ASAuthorizationAppleIDCredential {
        keep = self
        return try await withCheckedThrowingContinuation { cont in
            self.cont = cont
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]
            // Apple copies this into the identity token's `nonce` claim verbatim, so what goes in
            // is already the hash — the caller keeps the preimage.
            request.nonce = nonce
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    private func finish(_ result: Result<ASAuthorizationAppleIDCredential, Error>) {
        guard let cont else { return }
        self.cont = nil
        cont.resume(with: result)
        keep = nil
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let cred = authorization.credential as? ASAuthorizationAppleIDCredential else {
            finish(.failure(AuthError.badResponse("Apple returned no identity.")))
            return
        }
        finish(.success(cred))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        finish(.failure(error))
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.topWindow ?? ASPresentationAnchor()
    }
}

extension UIApplication {
    /// The key window, for anything that needs a presentation anchor. One accessor, so the scene
    /// walk is written once.
    var topWindow: UIWindow? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
    }
}

// MARK: - Biometrics

import LocalAuthentication

/// The identity check that stands between an order and the miles leaving the balance.
///
/// The reference draws this: a ring sweeps, a tick lands, and 980 ms later the ledger moves
/// whatever happened. Here the ring is drawn around a real `LAContext` evaluation, and **the miles
/// move only if it returns true** — so the ceremony reports a fact rather than performing one.
///
/// The policy is `deviceOwnerAuthentication`, not `...WithBiometrics`: it prefers Face ID or
/// Touch ID and falls back to the passcode by itself. A phone whose Face ID has failed three times,
/// or that has none, must still be able to spend its own miles.
enum Biometrics {
    enum Kind { case faceID, touchID, opticID, passcode, none }

    static var kind: Kind {
        let ctx = LAContext()
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { return .none }
        switch ctx.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        case .opticID: return .opticID
        default: return .passcode
        }
    }

    /// What to call it on screen, so no label ever promises Face ID to a phone that has none.
    static var name: String {
        switch kind {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        case .passcode: return "your passcode"
        case .none: return "your passcode"
        }
    }

    static var available: Bool { kind != .none }

    /// `.success` only when the device owner actually authenticated. `.cancelled` covers every way
    /// a person can decline — the system sheet's Cancel, the app going to the background, a
    /// fallback the user then backed out of — none of which is an error to report back at them.
    enum Outcome: Equatable { case success, cancelled, failed(String) }

    static func check(reason: String) async -> Outcome {
        let ctx = LAContext()
        ctx.localizedCancelTitle = "Cancel"
        var error: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return .failed("This phone has no passcode set, so it cannot authorise a payment.")
        }
        do {
            // Tearing the sheet down has to take the system prompt with it. The async
            // `evaluatePolicy` does not observe task cancellation on its own, so a payment
            // cancelled mid-check would otherwise leave Face ID still asking about an order that
            // no longer exists.
            let ok = try await withTaskCancellationHandler {
                try await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            } onCancel: {
                ctx.invalidate()
            }
            return ok ? .success : .cancelled
        } catch let e as LAError {
            switch e.code {
            case .userCancel, .appCancel, .systemCancel: return .cancelled
            case .userFallback: return .cancelled
            case .authenticationFailed: return .failed("Not recognised.")
            case .biometryLockout: return .failed("\(name) is locked. Use your passcode.")
            default: return .failed(e.localizedDescription)
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
