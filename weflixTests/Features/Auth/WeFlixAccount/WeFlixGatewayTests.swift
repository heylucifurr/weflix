import Foundation
import Testing

@testable import weflix

/// PHASE APP-GATEWAY, tasks A1 and A2 (2026-10-24): the client speaks Plex to **weflix.me**.
///
/// The client keeps every repository, decoder and screen it had — what changes is the server it points them at and
/// the credential it sends. Two things have to be true for that to work, and both are pinned here: the gateway is
/// named in exactly one place, and the header it is authenticated with is decided in exactly one place.
struct WeFlixGatewayTests {
    @Test @MainActor func theGatewayIsOneHostOnePath() {
        #expect(WeFlixServer.gatewayBaseURL.absoluteString == "https://weflix.me/api/plex")
        #expect(WeFlixServer.gatewayPath == "api/plex")
        #expect(WeFlixServer.gatewayMachineIdentifier == "weflix-gateway")
    }

    @Test @MainActor func selectGatewayBuildsTheSameStateAPlexSignInWouldHave() async throws {
        let context = PlexAPIContext()

        // The context identifies itself as a client asynchronously (its bootstrap reads the Keychain), so a test that
        // reads `clientIdentifier` has to wait for it — exactly as the sign-in path does.
        await context.waitForBootstrap()

        context.selectGateway(token: "a-weflix-token", accountID: "10", displayName: "sample user")

        #expect(context.speaksToGateway == true)
        let snapshot = try context.serverAccessSnapshot()

        #expect(snapshot.baseURL.absoluteString == "https://weflix.me/api/plex", "the one host")
        #expect(snapshot.authToken == "a-weflix-token", "the WeFlix device token, not a Plex token")
        #expect(snapshot.speaksToGateway == true, "so the network client sends a bearer credential")
        #expect(snapshot.serverIdentifier == "10", "the account names the server, so profiles keep matching")
        #expect(snapshot.clientIdentifier.isEmpty == false, "the app still identifies itself as a client")
    }

    @Test @MainActor func withoutAnAccountIDSTheGatewayNamesItself() throws {
        let context = PlexAPIContext()

        context.selectGateway(token: "t", accountID: "", displayName: "")

        let snapshot = try context.serverAccessSnapshot()
        #expect(snapshot.serverIdentifier == WeFlixServer.gatewayMachineIdentifier)
    }

    @Test func theHeaderIsChosenInOnePlace() throws {
        let client = readSource("Shared/Networking/Plex/PlexServerNetworkClient.swift")

        #expect(client.contains("snapshot.speaksToGateway"), "the snapshot decides which credential is sent")
        #expect(client.contains(#"forHTTPHeaderField: "Authorization""#), "the gateway gets a bearer credential")
        #expect(client.contains(#""Bearer \(snapshot.authToken)""#), "carrying the WeFlix token")
        #expect(client.contains(#"forHTTPHeaderField: "X-Plex-Token""#), "a real Plex server still gets its token")
        // Both branches are required: a client that always sent a bearer credential would break the retired
        // Plex/Jellyfin flow, which this phase deliberately leaves compiled.
        #expect(client.contains("} else {"), "and the two cases are still distinct")
    }

    @Test func theGatewayKeepsPlexsOwnPagingHeaders() throws {
        // The app pages with `X-Plex-Container-Start`/`Size` **headers** (`PlexPagination.headers`), which the
        // gateway's query whitelist does not touch — recorded here because a future reader will wonder whether the
        // server's whitelist covers paging.
        let pagination = readSource("Shared/Networking/Plex/PlexAPI.swift")

        #expect(pagination.contains("X-Plex-Container-Start"))
        #expect(pagination.contains("X-Plex-Container-Size"))
    }

    private func readSource(_ relativePath: String) -> String {
        // `#filePath` is `…/weflixTests/Features/Auth/WeFlixAccount/WeFlixGatewayTests.swift`, so the repository root
        // is five levels up: the file, its folder, `Auth`, `Features`, `weflixTests`.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // WeFlixGatewayTests.swift → WeFlixAccount
            .deletingLastPathComponent() // → Auth
            .deletingLastPathComponent() // → Features
            .deletingLastPathComponent() // → weflixTests
            .deletingLastPathComponent() // → the repository root
        let url = root.appendingPathComponent(relativePath)

        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }
}
