import Foundation

/// Who the WeFlix server says this device is signed in as — the three fields `GET /api/app/me` answers.
struct WeFlixUser: Decodable, Equatable, Sendable {
    let id: String
    let displayName: String
    let isOwner: Bool
}

/// A refusal, already worded for a person.
///
/// The server's own sentences are used where the server sent one — "Invalid username or password", the pending
/// and disabled sentences — because saying the same thing two ways in two places is how a message drifts. The
/// three local cases (no network, an answer we cannot read, an unexpected status) get their own plain sentence
/// here, so no screen has to invent one.
enum WeFlixAuthError: Error, Equatable {
    /// `401` — no token, an unknown token, or a **revoked** one. The app returns to the sign-in screen.
    case unauthenticated
    /// The server refused, and said why, in words meant for a person.
    case refused(String)
    /// `404` — the server is reachable and does not know this route.
    ///
    /// This is not a hypothetical: production (`weflix.me`) is deployed from `main`, so a `/api/app` route that
    /// only exists on `Development` answers exactly this until the two are merged, and the app would otherwise
    /// tell the person to check a connection that is perfectly fine.
    case serverNeedsUpdate
    /// The app could not reach WeFlix at all.
    case unreachable

    /// The sentence a screen prints for this failure.
    ///
    /// Plain English literals, not lookup keys: the sign-in screen is new and has no catalogue entries yet, and
    /// `String(localized:)` with a missing key would print the key itself (see the report's question for Luther).
    var message: String {
        switch self {
        case .unauthenticated:
            "Please sign in again."
        case let .refused(message):
            message
        case .serverNeedsUpdate:
            "This WeFlix server does not have the app's sign-in yet. Ask Luther to update WeFlix."
        case .unreachable:
            "Can't reach WeFlix. Check your connection and try again."
        }
    }
}

/// The app's whole conversation with the WeFlix server's sign-in API — three calls, nothing else.
///
/// `docs/PROJECT.md` has the rule this type exists to keep: the app talks to the **WeFlix server** and never to
/// plex.tv or to a Plex/Jellyfin server directly. The Plex token lives on the server inside the identity; the
/// app only ever holds its own bearer token.
///
/// Nothing here logs anything: no token, no password, no header and no response body is ever printed. A failure
/// becomes a `WeFlixAuthError` with a sentence and stops there.
///
/// `baseURL` and `session` are injectable for one reason: so the answers this type produces — 401, a refusal
/// with the server's sentence, a broken answer, no network at all — can be driven by a test instead of guessed
/// at. Production always uses the defaults, which are `WeFlixServer.baseURL` and the shared session.
struct WeFlixAuthClient {
    private let baseURL: URL
    private let session: URLSession

    /// Longer than a sign-in should ever take on a phone network, shorter than a person's patience.
    private let timeout: TimeInterval = 20

    init(baseURL: URL = WeFlixServer.baseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    /// `POST /api/app/auth/login` — the account's email (or display name) and password.
    ///
    /// Answers the token **once**; the caller stores it in the Keychain and never keeps a copy elsewhere.
    ///
    /// A `401` here is **wrong details**, not a dead session — the server's own sentence ("Invalid username or
    /// password") is carried through as a refusal. `me` and `logout` are the opposite: their `401` means the
    /// token is over. The two meanings were the same until the live test in this repository caught it: a person
    /// typing a wrong password was being told to *sign in again* while looking at the sign-in screen.
    func signIn(
        identifier: String,
        password: String,
        deviceName: String = WeFlixServer.deviceName,
        platform: String = WeFlixServer.platform,
    ) async throws -> (token: String, user: WeFlixUser) {
        let body: [String: String] = [
            "identifier": identifier,
            "password": password,
            "deviceName": deviceName,
            "platform": platform,
        ]

        let answer: SignInAnswer = try await send(
            WeFlixServer.loginPath,
            method: "POST",
            token: nil,
            body: body,
            unauthorized: .wrongDetails,
        )

        return (answer.token, answer.user)
    }

    /// `GET /api/app/me` — who this token belongs to, or `.unauthenticated` once it has been revoked.
    ///
    /// Called on every launch: a token the server no longer recognises must not keep a signed-in screen up.
    func me(token: String) async throws -> WeFlixUser {
        let answer: MeAnswer = try await send(
            WeFlixServer.mePath,
            method: "GET",
            token: token,
            body: nil,
            unauthorized: .tokenIsOver,
        )

        return answer.user
    }

    /// `POST /api/app/auth/logout` — end this device's token on the server.
    ///
    /// Deliberately forgiving: a logout that fails must still let the app forget the token locally, so the caller
    /// clears the Keychain whether or not this threw. The server answers `200` for a token it never knew, so a
    /// refusal here means the network, not the credential.
    func signOut(token: String) async throws {
        let _: LogoutAnswer = try await send(
            WeFlixServer.logoutPath,
            method: "POST",
            token: token,
            body: nil,
            unauthorized: .tokenIsOver,
        )
    }

    /// `POST /api/app/stream-ticket` — the credential the **player**'s URLs carry (PHASE APP-GATEWAY S5).
    ///
    /// `AVPlayer` fetches artwork, direct plays and HLS streams itself, and those requests cannot carry an
    /// `Authorization` header, so the app asks for a signed, minutes-long ticket instead of putting its device token
    /// in a URL. Only the three streaming routes accept one.
    func streamTicket(token: String) async throws -> (ticket: String, expiresAt: Date) {
        let answer: StreamTicketAnswer = try await send(
            WeFlixServer.streamTicketPath,
            method: "POST",
            token: token,
            body: nil,
            unauthorized: .tokenIsOver,
        )

        return (answer.ticket, Date(timeIntervalSince1970: answer.expiresAt / 1000))
    }

    /* ---------------------------------------------------------------------- */
    /* the one place a request is made                                          */
    /* ---------------------------------------------------------------------- */

    private struct SignInAnswer: Decodable {
        let token: String
        let user: WeFlixUser
        /// Present on every answer; the app has no password screen yet — see `docs/PROJECT.md`.
        let mustChangePassword: Bool?
    }

    private struct MeAnswer: Decodable {
        let user: WeFlixUser
    }

    private struct LogoutAnswer: Decodable {
        let message: String?
    }

    /// `POST /api/app/stream-ticket`'s answer: the ticket and the epoch **milliseconds** it expires at.
    private struct StreamTicketAnswer: Decodable {
        let ticket: String
        let expiresAt: Double
    }

    /// The server's refusal body: `{ ok: false, message: "…" }`.
    private struct RefusalBody: Decodable {
        let message: String?
    }

    /// What this call's `401` means — the same status, two different truths.
    private enum UnauthorizedMeaning {
        /// `me`, `logout`: the token is unknown or revoked. The app forgets it and shows the sign-in screen.
        case tokenIsOver
        /// `login`: the details were wrong. The server's sentence is what the person is shown.
        case wrongDetails
    }

    private func send<Answer: Decodable>(
        _ path: String,
        method: String,
        token: String?,
        body: [String: String]?,
        unauthorized: UnauthorizedMeaning,
    ) async throws -> Answer {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("WeFlix/\(Self.appVersion)", forHTTPHeaderField: "User-Agent")

        if let token {
            // The one header that carries a credential. It is never logged and never stored elsewhere.
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            // Offline, DNS, TLS, a timeout — all the same thing to the person holding the phone.
            throw WeFlixAuthError.unreachable
        }

        guard let http = response as? HTTPURLResponse else {
            throw WeFlixAuthError.unreachable
        }

        switch http.statusCode {
        case 200 ..< 300:
            guard let answer = try? JSONDecoder().decode(Answer.self, from: data) else {
                throw WeFlixAuthError.unreachable
            }

            return answer
        case 401:
            if case .wrongDetails = unauthorized, let message = refusalMessage(in: data) {
                throw WeFlixAuthError.refused(message)
            }

            throw WeFlixAuthError.unauthenticated
        case 404:
            // Reachable, and it does not know this route — production lagging `Development`, not a dead network.
            throw WeFlixAuthError.serverNeedsUpdate
        default:
            // Every other refusal the app can act on carries the server's own sentence; a 502 from a proxy in
            // front of a restarting container carries nothing readable, which is the `unreachable` answer.
            throw refusalMessage(in: data).map(WeFlixAuthError.refused) ?? .unreachable
        }
    }

    /// The sentence in a refusal body, when there is one and it is worth showing.
    private func refusalMessage(in data: Data) -> String? {
        let message = (try? JSONDecoder().decode(RefusalBody.self, from: data))?.message?.trimmingCharacters(
            in: .whitespacesAndNewlines,
        )

        return (message?.isEmpty ?? true) ? nil : message
    }

    /// Reported in the `User-Agent` so a rate-limited address can be traced to the app rather than to a browser.
    private static var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "app"
    }
}
