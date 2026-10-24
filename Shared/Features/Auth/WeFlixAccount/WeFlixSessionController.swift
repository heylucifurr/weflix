import Foundation
import Observation

/// The app's sign-in state: what the root shows, and the three things that move it.
///
/// The sequence the app promises, in the order it happens:
///
/// 1. **At launch** — a token in the Keychain is asked about (`GET /api/app/me`). The server's answer decides:
///    a user means the signed-in screen, a `401` means the token is gone (revoked, or from a wiped database) and
///    the app clears it and asks for a sign-in.
/// 2. **Signing in** — the WeFlix account's email or display name and its password, through
///    `WeFlixAuthClient.signIn()`. The token that comes back goes into the Keychain, and **only** there.
/// 3. **Signing out** — the server is told first (`POST /api/app/auth/logout`, which revokes the row), and the
///    Keychain is cleared whatever the network did. A token the server has forgotten is worse than useless: it
///    is a locked door the app keeps rattling.
///
/// A failure to reach WeFlix at launch **keeps the token**: a train tunnel is not a reason to make somebody type
/// their password again. Not being able to reach the server is shown as its own sentence, with the sign-in form
/// still there underneath it.
@MainActor
@Observable
final class WeFlixSessionController {
    enum Status: Equatable {
        /// Asking the server about the stored token. The launch screen's spinner.
        case checking
        /// No token, or one the server refused. The sign-in screen.
        case signedOut
        /// A real, server-confirmed sign-in.
        case signedIn(WeFlixUser)
    }

    private(set) var status: Status = .checking
    /// What the server said about this account's requests — the `requests` block of `GET /api/app/me`.
    ///
    /// Carried here because the sign-in state is where it comes from: `start()` reads it at launch, and
    /// `signIn()` reads it again straight after a password sign-in (the login answer does not carry it), so the
    /// main screen knows whether it has anything to show without a second, separate round trip.
    private(set) var requests: WeFlixRequests?
    /// The one field a person types into: an email address, or the display name the owner gave them.
    var identifier = ""
    var password = ""
    private(set) var isWorking = false
    /// A sentence for the sign-in screen — the server's own words, or one of ours for the network.
    private(set) var errorMessage: String?

    @ObservationIgnored private let client = WeFlixAuthClient()
    @ObservationIgnored private let store: WeFlixDeviceTokenStore
    @ObservationIgnored private var hasStarted = false

    init(store: WeFlixDeviceTokenStore = WeFlixDeviceTokenStore()) {
        self.store = store
    }

    /// Ask the server who this device is — once per launch, and again after a "try again" tap.
    func start() async {
        guard !isWorking else { return }

        guard let token = store.token() else {
            // PHASE APP-GATEWAY: a build that was pointed at a test deployment can also sign itself in for a live
            // proof, which is the only way a simulator with no keyboard automation can reach the library.
            if await signInFromEnvironment() { return }

            status = .signedOut

            return
        }

        isWorking = true
        status = .checking
        defer { isWorking = false }

        do {
            let answer = try await client.me(token: token)

            errorMessage = nil
            requests = answer.requests
            status = .signedIn(answer.user)
        } catch WeFlixAuthError.unauthenticated {
            // Revoked, or unknown to this server. The app forgets it, so the next launch does not ask again.
            store.clear()
            requests = nil
            status = .signedOut
        } catch let error as WeFlixAuthError {
            // The token may well still be good; the network is not. Keep it and say what happened.
            errorMessage = error.message
            requests = nil
            status = .signedOut
        } catch {
            errorMessage = WeFlixAuthError.unreachable.message
            status = .signedOut
        }
    }

    /// Sign in with the fields on screen.
    func signIn() async {
        guard !isWorking else { return }

        let identifier = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = password

        guard !identifier.isEmpty, !password.isEmpty else {
            errorMessage = "Enter your username or email and your password."

            return
        }

        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            let answer = try await client.signIn(identifier: identifier, password: password)

            store.save(answer.token)
            // The password is not kept, not even in memory: the screen is about to be replaced anyway, and a
            // password left in a property is a password in a heap dump.
            self.password = ""
            status = .signedIn(answer.user)

            // The login answer carries no `requests` block (it is the token that is new, not the account), so the
            // app asks once more now that it holds the token. A failure here is not a failed sign-in — the person
            // is signed in and the requests screen will say what it can — but it must not look like silence
            // either, so the sentence travels to the screen that is about to appear.
            await refreshRequests(token: answer.token)
        } catch let error as WeFlixAuthError {
            errorMessage = error.message
        } catch {
            errorMessage = WeFlixAuthError.unreachable.message
        }
    }

    /// Who is signed in — the display name the requests store keeps with the account's Overseerr id, and `""`
    /// when nobody is.
    var displayName: String {
        if case let .signedIn(user) = status {
            return user.displayName
        }

        return ""
    }

    /// Ask the server, once, what this account's requests are — after a sign-in and after a "try again".
    ///
    /// `requests = nil` on a refusal, which the requests screen reads as "not set up for your account" rather
    /// than as a lie about what is allowed. A `401` here cannot happen (the token was just issued), and a
    /// network failure is reported in `errorMessage` without disturbing the sign-in.
    func refreshRequests(token: String? = nil) async {
        let credential = token ?? store.token()

        guard let credential else {
            requests = nil

            return
        }

        do {
            requests = try await client.me(token: credential).requests
        } catch {
            requests = nil
            errorMessage = (error as? WeFlixAuthError)?.message ?? WeFlixAuthError.unreachable.message
        }
    }

    /// `WEFLIX_TEST_IDENTIFIER` + `WEFLIX_TEST_PASSWORD`: sign in without a keyboard (PHASE APP-GATEWAY's live proof).
    ///
    /// The variables are read **only when there is no stored token**, so they can never replace a real sign-in, and
    /// nothing in a shipped configuration sets them — a build proves itself end to end on a simulator only when
    /// whoever ran it passed credentials in the environment. The same two variables the macOS scheme's live tests
    /// already use (`weflixTests/…/WeFlixLiveAuthTests.swift`), with the same rule: they are never committed.
    ///
    /// Answers whether a sign-in came back, so `start()` can fall through to the sign-in screen when they are absent.
    private func signInFromEnvironment() async -> Bool {
        let environment = ProcessInfo.processInfo.environment

        guard let testIdentifier = environment["WEFLIX_TEST_IDENTIFIER"], !testIdentifier.isEmpty,
              let testPassword = environment["WEFLIX_TEST_PASSWORD"], !testPassword.isEmpty
        else { return false }

        identifier = testIdentifier
        password = testPassword
        await signIn()

        return status != .signedOut
    }

    /// The server refused this device's token (a `401` from a gateway read, or the account has no token at all).
    ///
    /// The app is a WeFlix client with one sign-in, so the only useful answer is the sign-in screen — with a
    /// sentence that says what happened. Without it the person is left on a home screen reading "Your servers did
    /// not respond", which is where Luther ended up (2026-10-24) with no way to act on it.
    ///
    /// Idempotent, and deliberately not guarded on the current status: it says "this device's session is over",
    /// which is true whether the app had noticed it yet or not.
    func reportSignInEnded() {
        store.clear()
        requests = nil
        errorMessage = "Your WeFlix sign-in has ended. Sign in again."
        status = .signedOut
    }

    /// Sign out: tell the server, then forget the token locally whether or not it answered.
    func signOut() async {
        guard !isWorking else { return }

        isWorking = true
        defer { isWorking = false }

        if let token = store.token() {
            try? await client.signOut(token: token)
        }

        store.clear()
        requests = nil
        identifier = ""
        password = ""
        errorMessage = nil
        status = .signedOut
    }

    /// The error label's own "dismiss" — tapping it must not require a second failure to clear.
    func clearError() {
        errorMessage = nil
    }
}
