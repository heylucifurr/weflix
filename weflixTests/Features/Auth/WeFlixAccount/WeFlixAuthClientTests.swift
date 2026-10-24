import Foundation
import Testing

@testable import weflix

/// The Apple client's half of the WeFlix sign-in (2026-10-24): `WeFlixAuthClient`, and the mapping from HTTP to
/// the sentence a person reads on the sign-in screen.
///
/// Offline, always run: every answer the client can produce — a `200`, a `401`, a `403` with the server's own
/// sentence, a broken body, no network at all — is driven through a stubbed `URLSession`, so the mapping is
/// pinned by a test instead of by hand. The live half (the real server, a real refusal) is
/// `WeFlixLiveAuthTests`, which is opt-in.
///
/// Run: `xcodebuild test -project weflix.xcodeproj -scheme weflix-macOS -destination 'platform=macOS'`
///
/// **Serialised on purpose.** These tests share one stubbed transport, and Swift Testing runs a suite's tests in
/// parallel by default — two at once would each answer the other's request. `.serialized` is the honest fix:
/// the alternative is a stub keyed by host, which would hide the sharing instead of naming it.
@Suite(.serialized)
struct WeFlixAuthClientTests {
    private static let stubBaseURL = URL(string: "https://weflix.test")!

    /// A 43-character base64url value — the shape of a token, so a test's token is never mistaken for nonsense.
    private static let someToken = String(repeating: "a", count: 43)

    private static func client(_ stub: @escaping StubURLProtocol.Handler) -> WeFlixAuthClient {
        WeFlixAuthClient(baseURL: stubBaseURL, session: StubURLProtocol.session(stub))
    }

    @Test func aSignedInAnswerCarriesTheTokenAndThreeUserFields() async throws {
        let client = Self.client(StubURLProtocol.json(
            200,
            #"{"ok":true,"token":"\#(Self.someToken)","user":{"id":"7","displayName":"Luther","isOwner":true}}"#,
        ))

        let answer = try await client.signIn(identifier: "luther@example.com", password: "correct horse")

        #expect(answer.token == Self.someToken)
        #expect(answer.user == WeFlixUser(id: "7", displayName: "Luther", isOwner: true))
    }

    @Test func theTwoMeaningsOf401AreNotTheSameThing() async throws {
        // On **login** a 401 is wrong details, and the server's sentence is what the person reads…
        let wrongDetails = Self.client(
            StubURLProtocol.json(401, #"{"ok":false,"message":"Invalid username or password"}"#),
        )

        var message: String?

        do {
            _ = try await wrongDetails.signIn(identifier: "luther@example.com", password: "nope")
        } catch let error as WeFlixAuthError {
            message = error.message
        }

        #expect(message == "Invalid username or password", "not 'Please sign in again' while on the sign-in screen")

        // …and on **me** it is a token that is over: the app must forget it, so it is `unauthenticated`.
        let revokedToken = Self.client(StubURLProtocol.json(401, #"{"ok":false,"message":"Please sign in again."}"#))

        await #expect(throws: WeFlixAuthError.unauthenticated) {
            try await revokedToken.me(token: Self.someToken)
        }
    }

    @Test func aRefusalKeepsTheServersOwnSentence() async throws {
        // The pending and disabled sentences come from the server, so the app cannot drift from the web.
        let pending = "Waiting for approval. Luther has to approve this account before it can watch anything."
        let client = Self.client(StubURLProtocol.json(403, #"{"ok":false,"message":"\#(pending)"}"#))

        var message: String?

        do {
            _ = try await client.signIn(identifier: "new@example.com", password: "correct horse")
        } catch let error as WeFlixAuthError {
            message = error.message
        }

        #expect(message == pending, "the server's sentence is what the screen prints")
    }

    @Test func aRateLimitedSignInStillReadsAsASentence() async throws {
        let client = Self.client(StubURLProtocol.json(
            429,
            #"{"ok":false,"message":"Too many attempts from this connection. Try again later.","retryAfterSeconds":300}"#,
        ))

        var message: String?

        do {
            _ = try await client.signIn(identifier: "flood@example.com", password: "correct horse")
        } catch let error as WeFlixAuthError {
            message = error.message
        }

        #expect(message?.contains("Too many attempts") == true)
    }

    @Test func anAnswerThatIsNotJSONIsUnreachableNotACrash() async throws {
        // A proxy's 502, a captive portal's HTML: nothing the app can read, and nothing it should pretend to.
        let proxy = Self.client(StubURLProtocol.text(502, "Bad Gateway"))
        let html = Self.client(StubURLProtocol.text(200, "<html>hello</html>"))

        await #expect(throws: WeFlixAuthError.unreachable) {
            try await proxy.signIn(identifier: "luther@example.com", password: "correct horse")
        }

        await #expect(throws: WeFlixAuthError.unreachable) {
            try await html.me(token: Self.someToken)
        }
    }

    @Test func noNetworkAtAllIsUnreachableInPlainWords() async throws {
        let offline = Self.client(StubURLProtocol.failure(URLError(.notConnectedToInternet)))

        await #expect(throws: WeFlixAuthError.unreachable) {
            try await offline.signIn(identifier: "luther@example.com", password: "correct horse")
        }

        #expect(WeFlixAuthError.unreachable.message.contains("Can't reach WeFlix"))
        #expect(WeFlixAuthError.unauthenticated.message.contains("sign in again"))
    }

    /* ---------------------------------------------------------------------- */
    /* the request itself                                                       */
    /* ---------------------------------------------------------------------- */

    @Test func signInPostsTheFourFieldsAndNoCredentialOfItsOwn() async throws {
        var seen: URLRequest?
        let client = Self.client(StubURLProtocol.capturing(
            { seen = $0 },
            StubURLProtocol.json(
                200,
                #"{"token":"\#(Self.someToken)","user":{"id":"1","displayName":"A","isOwner":false}}"#,
            ),
        ))

        _ = try await client.signIn(identifier: "  luther@example.com  ", password: "correct horse")

        let request = try #require(seen)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://weflix.test/api/app/auth/login")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil, "a sign-in has no token yet")

        let body = try #require(request.httpBody)
        let fields = try #require(try JSONSerialization.jsonObject(with: body) as? [String: String])
        #expect(fields["identifier"] == "  luther@example.com  ", "the server trims; the client does not guess")
        #expect(fields["password"] == "correct horse")
        #expect(fields["deviceName"]?.isEmpty == false, "the device names itself")
        #expect(["iOS", "tvOS", "macOS"].contains(fields["platform"] ?? ""))
    }

    @Test func meAndLogoutCarryTheBearerTokenAndNothingElseDoes() async throws {
        var seen: [URLRequest] = []
        let client = Self.client(StubURLProtocol.capturing(
            { seen.append($0) },
            StubURLProtocol.json(
                200,
                #"{"user":{"id":"1","displayName":"A","isOwner":false},"message":"Signed out."}"#,
            ),
        ))

        _ = try await client.me(token: Self.someToken)
        try await client.signOut(token: Self.someToken)

        #expect(seen.count == 2)
        #expect(seen[0].value(forHTTPHeaderField: "Authorization") == "Bearer \(Self.someToken)")
        #expect(seen[1].value(forHTTPHeaderField: "Authorization") == "Bearer \(Self.someToken)")
        #expect(seen[0].httpMethod == "GET")
        #expect(seen[1].httpMethod == "POST")
        #expect(seen[0].url?.absoluteString == "https://weflix.test/api/app/me")
        #expect(seen[1].url?.absoluteString == "https://weflix.test/api/app/auth/logout")
    }

    /* ---------------------------------------------------------------------- */
    /* the config place                                                         */
    /* ---------------------------------------------------------------------- */

    @Test func theAppHasExactlyOneServerAndItIsWeFlix() {
        #expect(WeFlixServer.baseURL.absoluteString == "https://beta.weflix.me")
        #expect(WeFlixServer.loginPath == "api/app/auth/login")
        #expect(WeFlixServer.mePath == "api/app/me")
        #expect(WeFlixServer.logoutPath == "api/app/auth/logout")
        #expect(["iOS", "tvOS", "macOS"].contains(WeFlixServer.platform))
        #expect(WeFlixServer.deviceName.isEmpty == false)
    }
}
