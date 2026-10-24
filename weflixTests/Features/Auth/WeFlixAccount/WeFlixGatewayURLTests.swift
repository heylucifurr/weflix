import XCTest

@testable import weflix

/// PHASE APP-GATEWAY A3/A5's client half: what a WeFlix account looks like in the app's own model, and the URLs the
/// player and the artwork loader are given.
///
/// Nothing here needs a network: these are the rules that must hold *before* a request is made — the marker that
/// keeps a WeFlix sign-in off plex.tv, the sizes the image route accepts, and the ticket that a media URL carries
/// because an `AVPlayer` request cannot send a header.
final class WeFlixGatewayURLTests: XCTestCase {
    // MARK: - The account marker (A3)

    func testAWeFlixAccountIsMarkedAndAPlexAccountIsNot() {
        XCTAssertEqual(WeFlixGatewayAccount.plexAccountID(for: "10"), "weflix:10")
        XCTAssertTrue(WeFlixGatewayAccount.isGateway(PlexAccount(id: "weflix:10", displayName: "sample user")))
        XCTAssertFalse(
            WeFlixGatewayAccount.isGateway(PlexAccount(id: "8f4c1e8a-0000-0000-0000-000000000000", displayName: "L")),
            "a plex.tv account must never be treated as a WeFlix one",
        )
    }

    func testTheAdoptedAccountIsAPlexShapedAccountWithTheWeFlixMarker() {
        let user = WeFlixUser(id: "10", displayName: "sample user", isOwner: false)
        guard let account = WeFlixGatewayAccount.account(for: user).plexAccount else {
            return XCTFail("a WeFlix account is stored as the app's own Plex-shaped account")
        }

        XCTAssertEqual(account.id, "weflix:10")
        XCTAssertEqual(account.displayName, "sample user")
        XCTAssertTrue(WeFlixGatewayAccount.isGateway(account))
        XCTAssertEqual(MediaAccount.plex(account).id, "plex:weflix:10")
    }

    // MARK: - Artwork (no credential in the URL)

    func testPosterArtworkGoesToTheImageRouteWithNoCredentialInTheURL() {
        let url = WeFlixGatewayURL.imageURL(
            path: "/library/metadata/6635/thumb/1690000000",
            width: 400,
            height: 600,
            format: nil,
        )

        XCTAssertEqual(url?.path, "/api/image")
        let query = queryItems(url)
        XCTAssertEqual(query["path"], "/library/metadata/6635/thumb/1690000000")
        XCTAssertEqual(query["size"], "poster")
        XCTAssertNil(query["X-Plex-Token"], "artwork carries no credential in its URL")
        XCTAssertNil(query["ticket"], "artwork needs no ticket either: URLSession can send a header")
    }

    func testImageSizesAreTheFiveTheRouteAccepts() {
        XCTAssertEqual(WeFlixGatewayURL.gatewayImageSize(width: 400, height: 600, format: nil), "poster")
        XCTAssertEqual(WeFlixGatewayURL.gatewayImageSize(width: 1600, height: 900, format: nil), "backdrop")
        XCTAssertEqual(WeFlixGatewayURL.gatewayImageSize(width: 480, height: 270, format: nil), "thumb")
        XCTAssertEqual(WeFlixGatewayURL.gatewayImageSize(width: 320, height: 320, format: nil), "square")
        XCTAssertEqual(WeFlixGatewayURL.gatewayImageSize(width: 600, height: 200, format: "png"), "logo")
        XCTAssertEqual(
            WeFlixGatewayURL.gatewayImageSize(width: 900, height: 500, format: nil),
            "backdrop",
            "a wide box is a backdrop even when the route would call a smaller one a thumb",
        )
    }

    // MARK: - Playback (the ticket)

    func testADirectPlayURLCarriesThePathTheRatingKeyAndTheTicket() {
        let url = WeFlixGatewayURL.directPlayURL(
            path: "/library/parts/13456/1690000000/file.mkv?download=1",
            ratingKey: "6635",
            ticket: "signed.ticket",
        )

        XCTAssertEqual(url?.path, "/api/video")
        let query = queryItems(url)
        XCTAssertEqual(query["path"], "/library/parts/13456/1690000000/file.mkv")
        XCTAssertEqual(query["download"], "1", "the Plex query travels with the path")
        XCTAssertEqual(query["ratingKey"], "6635")
        XCTAssertEqual(query["ticket"], "signed.ticket")
        XCTAssertNil(query["X-Plex-Token"], "the device token must never appear in a media URL")
    }

    func testAStreamURLKeepsTheWholePlexTranscodePathAndItsQuery() {
        let url = WeFlixGatewayURL.transcodeURL(
            plexPath: "/video/:/transcode/universal/start.m3u8",
            plexQuery: "path=%2Flibrary%2Fparts%2F1%2Ffile.mkv&session=abc&protocol=hls",
            ticket: "signed.ticket",
        )

        XCTAssertEqual(url?.path, "/api/transcode")
        let query = queryItems(url)
        XCTAssertEqual(
            query["path"],
            "/video/:/transcode/universal/start.m3u8?path=%2Flibrary%2Fparts%2F1%2Ffile.mkv&session=abc&protocol=hls",
            "the route is given exactly the Plex path it must proxy",
        )
        XCTAssertEqual(query["ticket"], "signed.ticket")
    }

    func testATicketIsUsedWhileItIsValidAndNotAfter() {
        let cache = WeFlixStreamTicketCache()

        XCTAssertNil(cache.current(), "no ticket until one is fetched")

        cache.store(ticket: "first", expiresAt: Date().addingTimeInterval(600))
        XCTAssertEqual(cache.current(), "first")

        // The last minute of a ticket is not used: a play started then would expire mid-stream.
        cache.store(ticket: "nearly-over", expiresAt: Date().addingTimeInterval(30))
        XCTAssertNil(cache.current())

        cache.store(ticket: "stale", expiresAt: Date().addingTimeInterval(-1))
        XCTAssertNil(cache.current())

        cache.store(ticket: "second", expiresAt: Date().addingTimeInterval(600))
        cache.clear()
        XCTAssertNil(cache.current())
    }

    // MARK: - A5: a WeFlix session cannot reach plex.tv

    func testAGatewaySessionHasNoPlexTokenAndSoNoCloudRequest() {
        // No bootstrap wait: this is about the two setters and what they leave behind, and bootstrapping reaches
        // for the network — a unit test must not (it took two minutes when it did).
        let context = PlexAPIContext()
        // What the sign-in does first, then what the gateway connection does: the cloud (plex.tv) token must end
        // up empty, because that token is what a cloud request would send to plex.tv.
        context.setAuthToken("a-weflix-device-token")
        context.selectGateway(token: "a-weflix-device-token", accountID: "weflix-gateway", displayName: "Lucifurr")

        XCTAssertNil(context.authTokenCloud, "a WeFlix session must hold no plex.tv token")

        let snapshot = try? context.serverAccessSnapshot()
        XCTAssertEqual(snapshot?.speaksToGateway, true)
        XCTAssertEqual(snapshot?.baseURL, WeFlixServer.gatewayBaseURL)
        XCTAssertEqual(snapshot?.authToken, "a-weflix-device-token", "the gateway's own credential is the device token")
    }

    func testACloudClientWithoutAPlexTokenRefusesBeforeItSendsAnything() async {
        // No token, so no request — a WeFlix session can reach no plex.tv path, and nothing is sent to try.
        let client = PlexCloudNetworkClient(authToken: nil, clientIdentifier: "weflix-gateway")
        do {
            let _: PlexCloudUser = try await client.request(path: "/user")
            XCTFail("a cloud request without a Plex token must not be made")
        } catch PlexAPIError.missingAuthToken {
            // Exactly the refusal, and it happened before any URL was built.
        } catch {
            XCTFail("expected the missing-token refusal, got \(error)")
        }

        let empty = PlexCloudNetworkClient(authToken: "", clientIdentifier: "weflix-gateway")
        do {
            try await empty.send(path: "/home/users")
            XCTFail("nor may a write")
        } catch PlexAPIError.missingAuthToken {
            // The same rule for the writes.
        } catch {
            XCTFail("expected the missing-token refusal, got \(error)")
        }
    }

    func testTheWeFlixServerIsOneServerWithNoConnectionsAndNoToken() {
        let server = WeFlixGatewayAccount.server

        XCTAssertEqual(server.clientIdentifier, WeFlixServer.gatewayMachineIdentifier)
        XCTAssertNil(server.accessToken, "the credential is in the account store, not in a resource")
        XCTAssertNil(server.connections, "there is nothing to discover through plex.tv")
    }

    // MARK: - The reported bug: a second WeFlix user landed on the first user's profile (2026-10-24)

    /// Two people's profiles, as the app stores them: one local profile per person, linked to their own account.
    private func profile(name: String, id: String) -> WeFlixProfile {
        .local(LocalProfile(id: id, name: name))
    }

    private func link(profileID: String, accountID: String) -> ProfileLink {
        ProfileLink(profileID: profileID, accountID: accountID, user: .plexHome(uuid: accountID.replacingOccurrences(of: "plex:", with: "")))
    }

    func testANewAccountGetsItsOwnProfileAndNotWhoeverWasSignedIn() {
        // Luther was signed in (the owner, "Lucifurr", account `plex:weflix:2`) and then signed in as Melvie. The
        // app reused the active profile, so the icon, the Profiles list and the name all said Lucifurr.
        let luther = profile(name: "Lucifurr", id: "local.luther")
        let melvieAccountID = "plex:weflix:8"
        let choice = WeFlixGatewayAccount.profileChoice(
            accountID: melvieAccountID,
            displayName: "Melvie Ramos",
            profiles: [luther],
            links: { profile in profile.id == "local.luther" ? [self.link(profileID: profile.id, accountID: "plex:weflix:2")] : [] },
        )

        XCTAssertEqual(
            choice,
            .create(name: "Melvie Ramos"),
            "a WeFlix account with no profile of its own gets one, named after the person signing in",
        )
    }

    func testSigningInAgainLandsOnThatAccountSProfile() {
        let melvie = profile(name: "Melvie Ramos", id: "local.melvie")
        let accountID = "plex:weflix:8"
        let choice = WeFlixGatewayAccount.profileChoice(
            accountID: accountID,
            displayName: "Melvie Ramos",
            profiles: [melvie],
            links: { _ in [self.link(profileID: "local.melvie", accountID: accountID)] },
        )

        XCTAssertEqual(choice, .reuse(profileID: "local.melvie", renameTo: nil), "a second sign-in is a no-op")
    }

    func testTheNameTheBugLeftBehindIsRepaired() {
        // The exact state Luther is in: one profile, one link, and the *previous* person's name on it.
        let stale = profile(name: "Lucifurr", id: "local.0197d07c")
        let accountID = "plex:weflix:8"
        let choice = WeFlixGatewayAccount.profileChoice(
            accountID: accountID,
            displayName: "Melvie Ramos",
            profiles: [stale],
            links: { _ in [self.link(profileID: "local.0197d07c", accountID: accountID)] },
        )

        XCTAssertEqual(
            choice,
            .reuse(profileID: "local.0197d07c", renameTo: "Melvie Ramos"),
            "the profile this account is the only link of is renamed to the person who is signed in",
        )
    }

    func testAProfileWithSeveralLinksAndAPlexHomeProfileAreNeverRenamed() {
        let shared = profile(name: "Living room", id: "local.shared")
        let accountID = "plex:weflix:8"
        let sharedChoice = WeFlixGatewayAccount.profileChoice(
            accountID: accountID,
            displayName: "Melvie Ramos",
            profiles: [shared],
            links: { _ in
                [self.link(profileID: "local.shared", accountID: accountID), self.link(profileID: "local.shared", accountID: "jellyfin:home.melvie")]
            },
        )

        XCTAssertEqual(
            sharedChoice,
            .reuse(profileID: "local.shared", renameTo: nil),
            "a profile a human built for two accounts keeps its name",
        )
    }

    func testEachWeFlixAccountHasItsOwnServerIdentity() {
        let melvie = WeFlixGatewayAccount.serverIdentity(for: "weflix:8")
        let luther = WeFlixGatewayAccount.serverIdentity(for: "weflix:2")

        XCTAssertNotEqual(
            melvie,
            luther,
            "two accounts sharing one identity is how the second sign-in connected with the first account's token",
        )
        XCTAssertTrue(melvie.id.hasPrefix(WeFlixServer.gatewayMachineIdentifier))
        XCTAssertTrue(melvie.id.contains("weflix:8"))
    }

    func testASessionTheServerRefusedComesBackToTheSignInScreen() {
        let controller = WeFlixSessionController(store: WeFlixDeviceTokenStore(service: "me.weflix.tests"))
        controller.reportSignInEnded()

        XCTAssertEqual(controller.status, .signedOut, "the only useful answer to a refused token is the sign-in screen")
        XCTAssertEqual(
            controller.errorMessage,
            "Your WeFlix sign-in has ended. Sign in again.",
            "and it says what happened instead of leaving a dead home screen",
        )
    }

    func testTheArtworkRequestCarriesTheTokenOnlyForWeFlix() {
        let ours = WeFlixServer.baseURL.appendingPathComponent("api/image")
        let someoneElse = URL(string: "https://plex.example.com/photo/:/transcode?X-Plex-Token=t")!

        XCTAssertEqual(
            WeFlixGatewayURL.artworkRequest(for: ours, token: "app-token").value(forHTTPHeaderField: "Authorization"),
            "Bearer app-token",
            "the app's own image route needs the credential — and a URL cannot carry the device token",
        )
        XCTAssertNil(
            WeFlixGatewayURL.artworkRequest(for: someoneElse, token: "app-token").value(forHTTPHeaderField: "Authorization"),
            "another host's artwork URL keeps its own query token and gets no WeFlix credential",
        )
        XCTAssertNil(WeFlixGatewayURL.artworkRequest(for: ours, token: nil).value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(WeFlixGatewayURL.artworkRequest(for: ours, token: "").value(forHTTPHeaderField: "Authorization"))
    }

    func testTheGatewayResourceIdentifierIsTheIdentityTheItemsCarry() {
        // The bug this pins (2026-10-24): the registry keyed the server as one identity while the media items named
        // another, so every card looked up an artwork service for a server that did not exist and the whole home
        // rendered without posters.
        let context = PlexAPIContext()
        context.selectGateway(token: "a-token", accountID: "weflix-gateway.weflix:2", displayName: "Lucifurr")

        XCTAssertEqual(
            try? context.serverAccessSnapshot().serverIdentifier,
            "weflix-gateway.weflix:2",
            "the resource identifier and the registry's server identity are the same string",
        )
    }

    // MARK: - The host (this build's own rule)

    func testTheAppTalksToWeFlixAndOnlyWeFlix() {
        XCTAssertEqual(WeFlixServer.baseURL.host(), "weflix.me", "unset, the app ships pointed at production")
        XCTAssertEqual(WeFlixServer.gatewayBaseURL.absoluteString, "https://weflix.me/api/plex")
        XCTAssertEqual(WeFlixServer.gatewayMachineIdentifier, "weflix-gateway")
    }

    /* ---------------------------------------------------------------------- */

    /// The query items of a URL, as a dictionary, for readable assertions.
    private func queryItems(_ url: URL?) -> [String: String] {
        guard let url, let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
            return [:]
        }

        return items.reduce(into: [:]) { result, item in
            result[item.name] = item.value
        }
    }
}
