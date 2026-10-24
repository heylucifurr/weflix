import Foundation

/// The app's whole conversation with Overseerr — **and it is not with Overseerr at all** (2026-10-25).
///
/// Every call goes to `WeFlixServer.seerrBaseURL` — `https://weflix.me/api/app/seerr`, one constant, one host —
/// carrying this device's WeFlix bearer token. The server holds the Overseerr address and its API key, adds them
/// itself, and decides who the request acts as; the app knows none of those things and can send none of them.
///
/// Four consequences worth stating, because the previous version did the opposite of all four:
///
/// - **there is no address to configure.** `baseURL` is not a parameter a screen can set; it is the app's one
///   server plus the requests path, and the settings screen that asked for an Overseerr URL is gone.
/// - **there is no sign-in of Seerr's own.** No `/auth/plex`, `/auth/local`, `/auth/jellyfin`, no `connect.sid`
///   and no cookie storage: the credential is the same WeFlix token the sign-in screen produced.
/// - **the token is never logged.** It is read from the Keychain per request and put in one header.
/// - **a refusal says something a person can act on.** `SeerrAPIError` carries the server's own sentence when
///   there is one (`409` "Requests aren't set up for your account yet…", Overseerr's "already requested") and a
///   plain line otherwise, and a `401` is `signInAgain` — which is what returns the app to the sign-in screen.
final class SeerrNetworkClient {
    private let session: URLSession
    private let baseURL: URL
    private let token: String?

    /// - Parameters:
    ///   - baseURL: defaults to the one requests base the app has (`WeFlixServer.seerrBaseURL`). Only a test
    ///     passes anything else.
    ///   - token: defaults to the Keychain's device token. `nil` (nobody signed in) means the server answers
    ///     `401`, which is the honest outcome.
    init(
        baseURL: URL = WeFlixServer.seerrBaseURL,
        session: URLSession = .shared,
        token: String? = WeFlixDeviceTokenStore().token(),
    ) {
        self.baseURL = baseURL
        self.session = session
        self.token = token
    }

    func request<Response: Decodable>(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem]? = nil,
    ) async throws -> Response {
        try await request(
            path: path,
            method: method,
            queryItems: queryItems,
            body: Never?.none,
        )
    }

    func request<Response: Decodable>(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem]? = nil,
        body: (some Encodable)? = nil,
    ) async throws -> Response {
        let data = try await perform(path: path, method: method, queryItems: queryItems, body: body)

        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw SeerrAPIError.decodingFailed(error)
        }
    }

    func send(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem]? = nil,
    ) async throws {
        try await send(
            path: path,
            method: method,
            queryItems: queryItems,
            body: Never?.none,
        )
    }

    func send(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem]? = nil,
        body: (some Encodable)? = nil,
    ) async throws {
        _ = try await perform(path: path, method: method, queryItems: queryItems, body: body)
    }

    /// One call, from the URL to the validated answer — so the four public methods above cannot drift apart on
    /// the header, the timeout or the error vocabulary.
    private func perform(
        path: String,
        method: String,
        queryItems: [URLQueryItem]?,
        body: (some Encodable)?,
    ) async throws -> Data {
        let request = try buildRequest(
            path: path,
            queryItems: queryItems,
            method: method,
            body: body,
        )

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            // Offline, DNS, TLS, a timeout — all the same thing to the person holding the phone.
            throw SeerrAPIError.unreachable
        }

        try validateResponse(response, body: data)

        return data
    }

    private func buildRequest(
        path: String,
        queryItems: [URLQueryItem]?,
        method: String,
        body: (some Encodable)?,
    ) throws -> URLRequest {
        let cleanedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let apiBase = baseURL.appendingPathComponent("api/v1")
        let url = apiBase.appendingPathComponent(cleanedPath)
        let resolvedURL = try resolveURL(url, queryItems: queryItems)

        var request = URLRequest(url: resolvedURL)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // The one header that carries a credential, and the same one the sign-in routes use. Never logged.
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        return request
    }

    private func resolveURL(_ url: URL, queryItems: [URLQueryItem]?) throws -> URL {
        guard let queryItems, !queryItems.isEmpty else {
            return url
        }

        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw SeerrAPIError.invalidURL
        }

        components.queryItems = queryItems

        guard let resolvedURL = components.url else {
            throw SeerrAPIError.invalidURL
        }

        return resolvedURL
    }

    /// The status, turned into the one thing the caller can act on.
    ///
    /// A `2xx` passes. A `401` is the device token being over — `signInAgain`, never "check your connection".
    /// Anything else gets the server's own sentence when its body carried one (`{ error }`, or Overseerr's
    /// `{ message }`), because those sentences are already written for a person: "Requests aren't set up for your
    /// account yet. Ask Luther." and "This title has already been requested" both arrive exactly like that, from
    /// `lib/seerr-routes.ts` and from Overseerr itself.
    private func validateResponse(_ response: URLResponse, body: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SeerrAPIError.unreachable
        }

        guard 200 ..< 300 ~= httpResponse.statusCode else {
            throw Self.error(for: httpResponse.statusCode, body: body)
        }
    }

    private static func error(for statusCode: Int, body: Data) -> SeerrAPIError {
        if statusCode == 401 {
            // The whole app is signed out, not just this screen: say so once, from the one place every call is
            // validated, and let `WeFlixAppGate` put the sign-in screen back up.
            WeFlixSignInEnded.post()

            return .signInAgain
        }

        if let sentence = sentence(in: body) {
            return .refused(sentence)
        }

        return .requestFailed(statusCode: statusCode)
    }

    /// The sentence in a refusal body, when there is one and it is worth showing. Never a token, never a dump:
    /// one of two fields, trimmed, and only when it is short enough to be a sentence.
    private static func sentence(in body: Data) -> String? {
        guard
            let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
            let raw = (object["error"] as? String) ?? (object["message"] as? String)
        else { return nil }

        let sentence = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        return sentence.isEmpty || sentence.count > 300 ? nil : sentence
    }
}
