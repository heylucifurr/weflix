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
            status = .signedOut

            return
        }

        isWorking = true
        status = .checking
        defer { isWorking = false }

        do {
            let user = try await client.me(token: token)

            errorMessage = nil
            status = .signedIn(user)
        } catch WeFlixAuthError.unauthenticated {
            // Revoked, or unknown to this server. The app forgets it, so the next launch does not ask again.
            store.clear()
            status = .signedOut
        } catch let error as WeFlixAuthError {
            // The token may well still be good; the network is not. Keep it and say what happened.
            errorMessage = error.message
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
        } catch let error as WeFlixAuthError {
            errorMessage = error.message
        } catch {
            errorMessage = WeFlixAuthError.unreachable.message
        }
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
