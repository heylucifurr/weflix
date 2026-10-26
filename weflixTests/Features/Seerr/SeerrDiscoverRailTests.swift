import Foundation
import Testing

@testable import weflix

/// The Discover headings, and the screens behind them (2026-10-26).
///
/// These pin what keeps a heading honest: that its **title is the one the opened screen shows**, that the rail set is
/// the four Luther named, and that the merged upcoming rail is built on **one** date for every page rather than one
/// per page. No network — the repository is pointed at a stubbed `URLSession` (`StubURLProtocol`).
///
/// `.serialized` because these tests share one handler for their host: Swift Testing runs the tests *within* a suite
/// in parallel too, so two of them at once would each answer the other's request. Two different suites are safe from
/// each other — each holds its own host — which is what `StubURLProtocol` was changed to support.
@Suite(.serialized)
@MainActor
struct SeerrDiscoverRailTests {
    /// A host of this suite's own: `StubURLProtocol` keys a handler by host, so nothing here can answer
    /// `WeFlixAuthClientTests` (which uses `weflix.test`) even though the two suites run at the same time.
    private static let stubHost = "weflix.rail.test"
    private static let stubBaseURL = URL(string: "https://weflix.rail.test")!
    private static let day = "2026-10-26"

    // MARK: - The headings

    @Test func `there are four headings, in Luther's order, and no two read the same`() {
        // "ON DISCOVER. Trending / Popular Movies / Popular TV Shows / Upcoming Movies & TV Shows" — four, where
        // there used to be five: the two upcoming routes are one rail now.
        #expect(SeerrDiscoverRail.allCases == [.trending, .popularMovies, .popularTVShows, .upcomingMoviesAndTVShows])

        let titles = SeerrDiscoverRail.allCases.map(\.title)
        #expect(Set(titles).count == titles.count, "two headings reading the same would be one rail shown twice")
    }

    @Test func `every heading resolves to its translation, not to its key`() {
        // The failure this catches: the headings are **namespaced** keys, so a missing catalogue entry draws
        // "integrations.seerr.discover.popularTVShows" as the heading — unreadable, and silent. Requiring the title
        // to differ from the key is the whole check, and it does not pin the wording.
        for rail in SeerrDiscoverRail.allCases {
            #expect(!rail.title.isEmpty)
            #expect(rail.title != rail.titleKey, "\(rail.rawValue) drew its key instead of its translation")
        }
    }

    @Test func `only the merged rail is built on a date`() {
        #expect(SeerrDiscoverRail.allCases.filter(\.isUpcoming) == [.upcomingMoviesAndTVShows])
    }

    @Test func `the boundary is a plain date, in the rail's own day`() throws {
        // The format the routes take, and the proof the day is the *rail's* day rather than UTC's: a rail paged near
        // midnight must not jump a day.
        let epoch = Date(timeIntervalSince1970: 0)
        let utc = try #require(TimeZone(identifier: "UTC"))
        let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))

        #expect(SeerrDiscoverRail.upcomingBoundary(now: epoch, timeZone: utc) == "1970-01-01")
        #expect(SeerrDiscoverRail.upcomingBoundary(now: epoch, timeZone: losAngeles) == "1969-12-31")
    }

    // MARK: - The requests each heading makes

    @Test func `a single-route rail asks its own route once, and carries no date`() async throws {
        for rail in [SeerrDiscoverRail.trending, .popularMovies, .popularTVShows] {
            let box = RequestBox()
            _ = try await rail.page(1, upcomingFrom: Self.day, repository: Self.pagedRepository(box) { page, _ in
                Self.pageBody(number: page, totalPages: 1, rows: [])
            })

            let request = try #require(box.requests.first)
            #expect(box.requests.count == 1, "\(rail.rawValue) is one route, so one request")
            #expect(Self.query(of: request)["page"] == "1")
            #expect(Self.query(of: request)["primaryReleaseDateGte"] == nil, "\(rail.rawValue) is not dated")
            #expect(Self.query(of: request)["firstAirDateGte"] == nil, "\(rail.rawValue) is not dated")
            #expect(
                request.url?.path.hasSuffix(Self.route(of: rail)) == true,
                "\(rail.rawValue) opened the wrong route",
            )
        }
    }

    @Test func `the merged rail is two routes in one page, both dated from the same day`() async throws {
        let box = RequestBox()
        let railPage = try await SeerrDiscoverRail.upcomingMoviesAndTVShows.page(
            2,
            upcomingFrom: Self.day,
            repository: Self.pagedRepository(box) { page, _ in
                Self.pageBody(number: page, totalPages: 9, rows: [])
            },
        )

        #expect(box.requests.count == 2, "one page of the merged rail costs two requests")
        #expect(
            Set(box.requests.compactMap { $0.url?.path }) == Set(["/api/v1/discover/movies", "/api/v1/discover/tv"]),
        )
        #expect(box.requests.compactMap { Self.query(of: $0)["page"] } == ["2", "2"])
        #expect(
            box.requests.compactMap { Self.query(of: $0)["primaryReleaseDateGte"] } == [Self.day],
            "the films half is dated from today",
        )
        #expect(
            box.requests.compactMap { Self.query(of: $0)["firstAirDateGte"] } == [Self.day],
            "the series half is dated from the same day",
        )
        #expect(railPage.page == 2)
    }

    @Test func `a rail paged twice asks for the next page the second time`() async throws {
        let box = RequestBox()
        let repository = Self.pagedRepository(box) { page, _ in
            Self.pageBody(number: page, totalPages: 5, rows: [(page, true)])
        }

        _ = try await SeerrDiscoverRail.popularMovies.page(1, upcomingFrom: Self.day, repository: repository)
        _ = try await SeerrDiscoverRail.popularMovies.page(2, upcomingFrom: Self.day, repository: repository)

        let queries = box.requests.map(Self.query(of:))
        #expect(queries.count == 2)
        #expect(queries[0]["page"] == "1")
        #expect(queries[1]["page"] == "2", "the second page must ask for page 2, not ask again for page 1")
    }

    @Test func `the merged rail ends only when both routes are spent`() async throws {
        // 20 pages of films and 3 of series: page 4 is still films and must not be cut off at the series' end.
        let box = RequestBox()
        let railPage = try await SeerrDiscoverRail.upcomingMoviesAndTVShows.page(
            4,
            upcomingFrom: Self.day,
            repository: Self.pagedRepository(box) { page, path in
                Self.pageBody(number: page, totalPages: path.hasSuffix("/tv") ? 3 : 20, rows: [(page, true)])
            },
        )

        #expect(railPage.lastPage == 20, "the longer of the two routes is where the rail ends")
        #expect(railPage.items.count == 2, "page 4 of both routes, merged into one page")
    }

    // MARK: - The merge itself

    @Test func `the two upcoming routes are merged soonest first, with undated titles last`() throws {
        let films = [
            try Self.media(id: 1, releaseDate: "2026-12-01"),
            try Self.media(id: 2, releaseDate: nil),
        ]
        let series = [
            try Self.media(id: 3, releaseDate: "2026-11-01"),
            try Self.media(id: 4, releaseDate: "2026-12-01"),
        ]

        // 11-01 first; then the two on 12-01 in the order the routes gave them (the merge is stable, so a refresh
        // does not reshuffle equal dates); then the one with no date at all, which cannot take a place in that order
        // and must not be pushed to the top where it would bury the nearest release.
        #expect(SeerrDiscoverViewModel.mergedSoonestFirst(films, series).map(\.id) == [3, 1, 4, 2])
    }

    @Test func `a series is dated by its first air date when it has no release date`() throws {
        let films = [try Self.media(id: 1, releaseDate: "2026-12-01")]
        let series = [try Self.media(id: 2, releaseDate: nil, firstAirDate: "2026-11-01")]

        #expect(SeerrDiscoverViewModel.mergedSoonestFirst(films, series).map(\.id) == [2, 1])
    }

    // MARK: - The screen a heading opens

    @Test func `the opened screen keeps the rail's own filter`() async {
        let box = RequestBox()
        let viewModel = SeerrDiscoverRailViewModel(
            rail: .trending,
            repository: Self.pagedRepository(box) { page, _ in
                Self.pageBody(number: page, totalPages: 2, rows: [(1, true), (2, false), (3, true)])
            },
        )

        await viewModel.load()

        #expect(
            viewModel.items.map(\.id) == [1, 3],
            "the heading's screen must filter exactly as the heading's rail does, or the two disagree",
        )
    }

    @Test func `a page the filter empties does not end the screen`() async {
        // Page 1 entirely outside the library is normal on a filtered rail. Appending nothing would leave the grid
        // unchanged — no new last card, so nothing would ever ask for page 2 — and the list would look finished.
        let box = RequestBox()
        let viewModel = SeerrDiscoverRailViewModel(
            rail: .trending,
            repository: Self.pagedRepository(box) { page, _ in
                page == 1
                    ? Self.pageBody(number: 1, totalPages: 5, rows: [(1, false), (2, false)])
                    : Self.pageBody(number: page, totalPages: 5, rows: [(10 + page, true)])
            },
        )

        await viewModel.load()

        #expect(viewModel.items.map(\.id) == [12])
        #expect(box.requests.count == 2, "an emptied page is a reason to ask for the next one, not to stop")
    }

    @Test func `a rail wholly outside the library stops asking, and is not an error`() async {
        // The run of emptied pages is bounded, so a filter matching nothing cannot turn one heading into an endless
        // burst of requests. Four is `SeerrDiscoverRailViewModel.emptyPageLimit`.
        let box = RequestBox()
        let viewModel = SeerrDiscoverRailViewModel(
            rail: .popularTVShows,
            repository: Self.pagedRepository(box) { page, _ in
                Self.pageBody(number: page, totalPages: 20, rows: [(page, false)])
            },
        )

        await viewModel.load()

        #expect(viewModel.isEmpty)
        #expect(viewModel.errorMessage == nil, "an empty filtered rail is not an error, it is an empty rail")
        #expect(box.requests.count == 4)
    }

    @Test func `the screen asks once, and stops when the rail says it is the last page`() async {
        let box = RequestBox()
        let viewModel = SeerrDiscoverRailViewModel(
            rail: .popularMovies,
            repository: Self.pagedRepository(box) { page, _ in
                Self.pageBody(number: page, totalPages: 1, rows: [(7, true)])
            },
        )

        await viewModel.load()
        await viewModel.load()
        await viewModel.loadMore()

        #expect(viewModel.items.map(\.id) == [7])
        #expect(box.requests.count == 1, "one load, and no page past the rail's own last page")
    }

    // MARK: - The stubbed session and the fixtures

    private static func route(of rail: SeerrDiscoverRail) -> String {
        switch rail {
        case .trending: "/discover/trending"
        case .popularMovies, .upcomingMoviesAndTVShows: "/discover/movies"
        case .popularTVShows: "/discover/tv"
        }
    }

    /// The requests a stubbed session saw, written from the loading thread and read from the test's.
    ///
    /// A box rather than a captured `var` because the merged rail records **two** requests per page and the session
    /// calls back off the test's thread. (`WeFlixAuthClientTests` copies the plain-`var` trick, but for one request.)
    private final class RequestBox: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [URLRequest] = []

        func record(_ request: URLRequest) {
            lock.lock()
            defer { lock.unlock() }

            stored.append(request)
        }

        var requests: [URLRequest] {
            lock.lock()
            defer { lock.unlock() }

            return stored
        }
    }

    /// A repository whose session answers each page with the body the test builds for that page, and records what was
    /// asked for. The body closure is given the page number **and the route**, because the merged rail asks two
    /// routes in one page and a test may need to answer them differently.
    private static func pagedRepository(
        _ box: RequestBox,
        _ body: @escaping @Sendable (Int, String) -> String,
    ) -> SeerrDiscoverRepository {
        SeerrDiscoverRepository(
            baseURL: stubBaseURL,
            session: StubURLProtocol.session(
                StubURLProtocol.capturing({ box.record($0) }, { request in
                    let number = Int(Self.query(of: request)["page"] ?? "1") ?? 1
                    let path = request.url?.path ?? ""

                    return try StubURLProtocol.json(200, body(number, path))(request)
                }),
                host: stubHost,
            ),
        )
    }

    /// One page, with its rows given as `(id, inLibrary)`. `totalPages` is the rail's own count, which is what the
    /// screen reads to know it has reached the end.
    ///
    /// `nonisolated` on this and `query(of:)` because the stubbed session calls back off the main actor; neither
    /// touches any state, so nothing is lost by it.
    nonisolated private static func pageBody(number: Int, totalPages: Int, rows: [(id: Int, inLibrary: Bool)]) -> String {
        let results = rows.map { row in
            // **The numeric raw value, not a word** (2026-10-26): `SeerrMediaStatus` is an `Int` enum, so
            // `"status":"available"` fails the whole page with a decoding error — which is exactly how the first
            // version of this fixture made six tests fail while the app was fine. Read from the enum so a
            // renumbering cannot quietly break the fixture.
            let status = row.inLibrary ? SeerrMediaStatus.available.rawValue : SeerrMediaStatus.pending.rawValue

            return #"{"id":\#(row.id),"mediaType":"movie","title":"Title \#(row.id)","mediaInfo":{"id":\#(row.id),"status":\#(status)}}"#
        }
        .joined(separator: ",")

        return #"{"page":\#(number),"totalPages":\#(totalPages),"totalResults":100,"results":[\#(results)]}"#
    }

    /// A discover hit with the dates the merge reads: `releaseDate` for a film, `firstAirDate` for a series.
    private static func media(id: Int, releaseDate: String?, firstAirDate: String? = nil) throws -> SeerrMedia {
        let json = #"""
        {
            "id": \#(id),
            "mediaType": "movie",
            "title": "Title \#(id)",
            "releaseDate": \#(releaseDate.map { "\"\($0)\"" } ?? "null"),
            "firstAirDate": \#(firstAirDate.map { "\"\($0)\"" } ?? "null")
        }
        """#
        return try JSONDecoder().decode(SeerrMedia.self, from: Data(json.utf8))
    }

    nonisolated private static func query(of request: URLRequest) -> [String: String] {
        guard
            let url = request.url,
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        else { return [:] }

        return items.reduce(into: [:]) { result, item in
            result[item.name] = item.value
        }
    }
}
