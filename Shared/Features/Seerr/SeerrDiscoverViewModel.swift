import Foundation
import Observation

@MainActor
@Observable
final class SeerrDiscoverViewModel {
    @ObservationIgnored private let store: SeerrStore
    @ObservationIgnored private let permissionService = SeerrPermissionService()
    @ObservationIgnored private var refreshGate = AutomaticRefreshGate()

    /// The four rails, one list each — **exactly the rails `SeerrDiscoverRail` names**, so the screen, a heading and
    /// the screen a heading opens all read the same description of what a rail is.
    ///
    /// (Until 2026-10-26 there were five: the two upcoming routes were separate. They are merged now, so
    /// `upcomingMoviesAndTVShows` is one list built from both routes — which is why it costs two requests.)
    var trending: [SeerrMedia] = []
    var popularMovies: [SeerrMedia] = []
    var popularTVShows: [SeerrMedia] = []
    var upcomingMoviesAndTVShows: [SeerrMedia] = []
    var isLoading = false
    var errorMessage: String?
    var pendingRequestsCount = 0

    init(store: SeerrStore) {
        self.store = store
    }

    var isLoggedIn: Bool {
        store.isRequestsEnabled
    }

    var hasContent: Bool {
        !trending.isEmpty
            || !popularMovies.isEmpty
            || !popularTVShows.isEmpty
            || !upcomingMoviesAndTVShows.isEmpty
    }

    var canManageRequests: Bool {
        permissionService.hasPermission(.manageRequests, user: store.user)
    }

    func load() async {
        guard refreshGate.startInitialLoadIfNeeded() else { return }
        await fetch(preservingExistingContent: false)
    }

    func reload() async {
        trending = []
        popularMovies = []
        popularTVShows = []
        upcomingMoviesAndTVShows = []
        await fetch(preservingExistingContent: false)
    }

    func refreshIfNeeded(now: Date = Date()) async {
        guard refreshGate.shouldRefresh(now: now, isLoading: isLoading) else { return }
        await fetch(preservingExistingContent: true)
    }

    private func fetch(preservingExistingContent: Bool) async {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let upcomingFrom = SeerrDiscoverRail.upcomingBoundary()
            let repository = SeerrDiscoverRepository()

            // **One loop over `SeerrDiscoverRail.allCases`.** The screen, a heading and the screen a heading opens all
            // read the same description of what a rail is, so none of them can ask for something different from the
            // others. The boundary is read **once**, so the merged rail and its later pages share one day.
            for rail in SeerrDiscoverRail.allCases {
                let page = try await rail.page(1, upcomingFrom: upcomingFrom, repository: repository)
                let items = Self.inLibraryOnly(page.items)

                switch rail {
                case .trending: trending = items
                case .popularMovies: popularMovies = items
                case .popularTVShows: popularTVShows = items
                case .upcomingMoviesAndTVShows: upcomingMoviesAndTVShows = items
                }
            }
        } catch {
            handleLoadError(error, preservingExistingContent: preservingExistingContent)
        }

        await loadRequestCount()
    }

    var requestsBadgeCount: Int {
        canManageRequests ? pendingRequestsCount : 0
    }

    private func loadRequestCount() async {
        guard canManageRequests else {
            pendingRequestsCount = 0
            return
        }

        do {
            let repository = SeerrRequestRepository()
            let count = try await repository.getRequestCount()
            pendingRequestsCount = count.pending
        } catch {
            pendingRequestsCount = 0
        }
    }

    /// The two upcoming routes as **one** rail: soonest first, because "upcoming" is a question about *when*.
    ///
    /// 2026-10-26 — Luther's fourth Discover rail is "Upcoming Movies & TV Shows", so the two routes are one list.
    /// Neither route arrives in date order (Seerr orders each by popularity), so the merge does the ordering, and a
    /// title with neither a release nor a first-air date goes **last** rather than to the top, where it would push
    /// the nearest release down the rail.
    ///
    /// Stable: equal dates keep the order the routes returned them in, so a refresh does not reshuffle them — the
    /// same offset trick `HomeAggregation.sortedByLastViewed` uses.
    nonisolated static func mergedSoonestFirst(_ movies: [SeerrMedia], _ series: [SeerrMedia]) -> [SeerrMedia] {
        let day: (SeerrMedia) -> String? = { media in
            let value = media.releaseDate ?? media.firstAirDate
            return (value?.isEmpty ?? true) ? nil : value
        }

        return (movies + series)
            .enumerated()
            .map { (offset: $0.offset, media: $0.element, day: day($0.element)) }
            .sorted { lhs, rhs in
                switch (lhs.day, rhs.day) {
                case let (left?, right?) where left != right:
                    left < right
                case (_?, nil):
                    true
                case (nil, _?):
                    false
                default:
                    lhs.offset < rhs.offset
                }
            }
            .map(\.media)
    }

    /// "Show only what's in the library": a title belongs to the library when Seerr reports the server already has
    /// it — fully available, or partially available (some seasons or episodes are present). Anything else is not in
    /// the library and is hidden from the discover rails: `.unknown`, `.pending`, `.processing`, `.blacklisted`,
    /// `.deleted`, and a title with no `mediaInfo` at all (Seerr has no record of it for this server).
    ///
    /// The rails are filtered where they are assigned in `fetch`, so every surface that reads `trending`,
    /// `popularMovies`, `popularTV`, `upcomingMovies` and `upcomingTV` — the iOS/macOS discover screen and the tvOS
    /// one, plus its hero — sees the same in-library set. A rail whose titles are all outside the library simply
    /// disappears, and the screen falls back to its "nothing to show" state when every rail does.
    nonisolated static func isInLibrary(_ media: SeerrMedia) -> Bool {
        switch media.mediaInfo?.status {
        case .available, .partiallyAvailable: return true
        default: return false
        }
    }

    nonisolated static func inLibraryOnly(_ items: [SeerrMedia]) -> [SeerrMedia] {
        items.filter(isInLibrary)
    }

    private func handleLoadError(_ error: Error, preservingExistingContent: Bool) {
        if preservingExistingContent, hasContent {
            errorMessage = nil
        } else {
            // The server's own sentence (or a plain line about the status): "Requests aren't set up for your
            // account yet. Ask Luther.", "Can't reach WeFlix…", "WeFlix is having trouble with requests."
            errorMessage = error.seerrSentence()
        }
    }
}
