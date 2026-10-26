import Foundation

/// One page of a rail, whichever routes were needed to build it.
///
/// A plain `SeerrPaginatedResponse` will not do any more: the last rail asks **two** routes (movies and series) and
/// merges them, so one page of that rail is two responses rolled into one list. `page` and `lastPage` are the merged
/// answers, which is all the screen needs to know whether to ask for more.
struct SeerrDiscoverRailPage {
    let page: Int
    let lastPage: Int
    let items: [SeerrMedia]

    /// A single route's page, as a rail page.
    init(_ response: SeerrPaginatedResponse<SeerrMedia>) {
        self.init(page: response.page, lastPage: response.totalPages, items: response.results)
    }

    init(page: Int, lastPage: Int, items: [SeerrMedia]) {
        self.page = page
        self.lastPage = lastPage
        self.items = items
    }
}

/// One of the **four** rails on the Discover screen, named so that a heading, the screen that heading opens and
/// every page of that screen cannot disagree about which query they are showing.
///
/// 2026-10-26, Luther: *"ON DISCOVER. Trending / Popular Movies / Popular TV Shows / Upcoming Movies & TV Shows"* —
/// four rails, where there used to be five. The two upcoming routes are **one** rail now, so this type merges them
/// rather than treating them as two.
///
/// **Nothing here changes which titles appear.** `SeerrDiscoverViewModel` still filters every page through
/// `inLibraryOnly`, and so does the screen this opens — Luther chose to keep that filter as it is.
enum SeerrDiscoverRail: String, CaseIterable, Identifiable, Hashable {
    case trending
    case popularMovies
    case popularTVShows
    case upcomingMoviesAndTVShows

    var id: String { rawValue }

    /// The raw key. Exists so a test can prove the heading is not falling back to it — a namespaced key shown as a
    /// heading is unreadable, and that is the one failure this feature could ship with silently.
    var titleKey: String {
        switch self {
        case .trending: "integrations.seerr.discover.trending"
        case .popularMovies: "integrations.seerr.discover.popularMovies"
        case .popularTVShows: "integrations.seerr.discover.popularTVShows"
        case .upcomingMoviesAndTVShows: "integrations.seerr.discover.upcomingMoviesAndTVShows"
        }
    }

    /// The heading on the Discover screen, **and** the title of the screen its heading opens.
    ///
    /// Read from `titleKey` so the two cannot end up naming different rails, which is the one way this feature could
    /// lie to a person. Both new keys carry an English value in `Localizable.xcstrings` — a namespaced key with no
    /// value would be drawn as the key itself.
    var title: String {
        String(localized: String.LocalizationValue(stringLiteral: titleKey))
    }

    /// The one rail that asks for what is not out yet, and is therefore built on a date.
    var isUpcoming: Bool {
        self == .upcomingMoviesAndTVShows
    }

    /// The date boundary the upcoming rail is built on — **one value for every page of it.**
    ///
    /// Computed once by the caller and handed to `page(_:upcomingFrom:repository:)`, never read per page: a rail
    /// paged across midnight would otherwise have page 1 and page 2 built on different days — two different searches
    /// wearing one heading, and a page 2 that could repeat or skip the titles page 1 had.
    ///
    /// `timeZone` exists so a test can pin the answer; the app never passes one.
    static func upcomingBoundary(now: Date = Date(), timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = timeZone

        let day = calendar.dateComponents([.year, .month, .day], from: now)

        return String(format: "%04d-%02d-%02d", day.year ?? 0, day.month ?? 0, day.day ?? 0)
    }

    /// One page of this rail, as the routes accept it.
    ///
    /// **The repository is required, not defaulted.** A default argument constructing `SeerrDiscoverRepository()`
    /// would be evaluated in a *nonisolated* context, and that type's initialiser is main-actor isolated (its default
    /// base URL reads `WeFlixServer`) — so the default warned on every build.
    ///
    /// The merged rail is the only one that costs **two** requests per page.
    func page(
        _ page: Int,
        upcomingFrom day: String,
        repository: SeerrDiscoverRepository,
    ) async throws -> SeerrDiscoverRailPage {
        switch self {
        case .trending:
            return try await SeerrDiscoverRailPage(repository.getTrending(page: page))
        case .popularMovies:
            return try await SeerrDiscoverRailPage(repository.discoverMovies(page: page))
        case .popularTVShows:
            return try await SeerrDiscoverRailPage(repository.discoverTV(page: page))
        case .upcomingMoviesAndTVShows:
            // One rail over two routes, merged soonest first. The two are asked **one after the other**, not with
            // `async let`: a child task is a `@concurrent` context, and `SeerrMedia`'s `Decodable` conformance is
            // main-actor isolated, so decoding in one warns today and is an error in Swift 6.
            let moviePage = try await repository.discoverMovies(page: page, primaryReleaseDateGte: day)
            let seriesPage = try await repository.discoverTV(page: page, firstAirDateGte: day)

            return SeerrDiscoverRailPage(
                page: page,
                // The longer of the two, so the rail ends only when **both** routes are spent: with 20 pages of films
                // and 3 of series, page 4 is still films and must not be cut off.
                lastPage: max(moviePage.totalPages, seriesPage.totalPages),
                items: SeerrDiscoverViewModel.mergedSoonestFirst(moviePage.results, seriesPage.results),
            )
        }
    }
}
