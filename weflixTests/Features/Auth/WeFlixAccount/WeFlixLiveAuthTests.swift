import Foundation
import Testing

@testable import weflix

/// The **live** half of the Apple client's sign-in (2026-10-24): the real beta is asked for real answers.
///
/// Opt-in, deliberately. A suite that needs the network fails on a plane, and a suite that needs an *account*
/// needs a credential that must never be committed.
///
/// How to turn it on (measured 2026-10-24 — the `TEST_RUNNER_` spelling does **not** reach the test process, and
/// neither does the shell's environment):
///
/// 1. In `weflix.xcodeproj/xcshareddata/xcschemes/weflix-macOS.xcscheme`, inside `<TestAction>`, set
///    `WEFLIX_LIVE_TESTS`'s `isEnabled` to `"YES"` — it ships as `"NO"`. Or tick it in Xcode's scheme editor
///    (Test → Arguments → Environment Variables).
/// 2. `xcodebuild test -project weflix.xcodeproj -scheme weflix-macOS -destination 'platform=macOS'`.
/// 3. Put it back to `"NO"` so the default run stays hermetic.
///
/// Note the `shouldUseLaunchSchemeArgsEnv = "NO"` on that TestAction: with `"YES"` — the default — the test action
/// takes the **Run** action's variables and ignores its own, which is why the flag had no effect at first.
///
/// What these prove, and what they cannot: the client's *refusals* are verified against the real server — an
/// identifier nobody owns, a token the server has never seen, the logout of one. The **success** path (a good
/// password, then `me`, then `logout`, then `me` again = 401) needs a real approved WeFlix account, so it is
/// gated a second time on `WEFLIX_TEST_IDENTIFIER` and `WEFLIX_TEST_PASSWORD`. Without them that one test is
/// skipped, not faked — see `checkpoints/CURRENT.md`.
struct WeFlixLiveAuthTests {
    private static var live: Bool {
        ProcessInfo.processInfo.environment["WEFLIX_LIVE_TESTS"] == "1"
    }

    private static var account: (identifier: String, password: String)? {
        let environment = ProcessInfo.processInfo.environment
        guard let identifier = environment["WEFLIX_TEST_IDENTIFIER"], !identifier.isEmpty,
              let password = environment["WEFLIX_TEST_PASSWORD"], !password.isEmpty
        else {
            return nil
        }

        return (identifier, password)
    }

    /// A well-shaped token the server has certainly never issued.
    private static let unknownToken = String(repeating: "a", count: 43)

    @Test(.enabled(if: live))
    func theRealServerRefusesAnIdentifierItDoesNotKnowInItsOwnWords() async throws {
        // An identifier nobody owns, with a real password-shaped value: the server runs the argon2id comparison
        // against a dummy hash and answers the one sentence that must not reveal whether the account exists.
        let client = WeFlixAuthClient()

        var message: String?

        do {
            _ = try await client.signIn(
                identifier: "cline-no-such-account@example.invalid",
                password: "wrong-password-1234567890",
            )
        } catch let error as WeFlixAuthError {
            message = error.message
        }

        #expect(message == "Invalid username or password")
    }

    @Test(.enabled(if: live))
    func aTokenTheServerHasNeverSeenIsUnauthenticated() async throws {
        let client = WeFlixAuthClient()

        await #expect(throws: WeFlixAuthError.unauthenticated) {
            try await client.me(token: Self.unknownToken)
        }
    }

    @Test(.enabled(if: live))
    func loggingOutATokenThatWasNeverRealIsStillAnswered() async throws {
        // The server answers 200 for a token it never knew — logout is idempotent, which is what lets the app
        // forget the Keychain copy without asking the network's permission.
        try await WeFlixAuthClient().signOut(token: Self.unknownToken)
    }

    @Test(.enabled(if: live && account != nil))
    func aRealAccountSignsInIsRecognisedAndCanSignOut() async throws {
        let account = try #require(Self.account)
        let client = WeFlixAuthClient()

        // 1. sign in — the one time the token exists in full.
        let signedIn = try await client.signIn(
            identifier: account.identifier,
            password: account.password,
            deviceName: "WeFlix live test",
            platform: "iOS",
        )

        #expect(signedIn.token.count == 43)
        #expect(signedIn.user.displayName.isEmpty == false)

        // 2. the token works.
        let me = try await client.me(token: signedIn.token)
        #expect(me == signedIn.user)

        // 3. sign out, and it really ends: the same token is refused afterwards.
        try await client.signOut(token: signedIn.token)

        await #expect(throws: WeFlixAuthError.unauthenticated) {
            try await client.me(token: signedIn.token)
        }
    }
}
