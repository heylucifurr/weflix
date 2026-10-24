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
