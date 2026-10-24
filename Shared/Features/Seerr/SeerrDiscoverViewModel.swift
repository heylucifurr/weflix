import Foundation
import Observation

@MainActor
@Observable
final class SeerrDiscoverViewModel {
    @ObservationIgnored private let store: SeerrStore
    @ObservationIgnored private let permissionService = SeerrPermissionService()
    @ObservationIgnored private var refreshGate = AutomaticRefreshGate()

    var trending: [SeerrMedia] = []
    var popularMovies: [SeerrMedia] = []
    var popularTV: [SeerrMedia] = []
    var upcomingMovies: [SeerrMedia] = []
    var upcomingTV: [SeerrMedia] = []
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
            || !popularTV.isEmpty
            || !upcomingMovies.isEmpty
            || !upcomingTV.isEmpty
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
        popularTV = []
        upcomingMovies = []
        upcomingTV = []
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
            let repository = SeerrDiscoverRepository()
            let trendingPage = try await repository.getTrending(page: 1)
            let moviesPage = try await repository.discoverMovies(page: 1)
            let tvPage = try await repository.discoverTV(page: 1)
            let upcomingDate = Self.upcomingDateFormatter.string(from: Date())
            let upcomingMoviesPage = try await repository.discoverMovies(
                page: 1,
                primaryReleaseDateGte: upcomingDate,
            )
            let upcomingTVPage = try await repository.discoverTV(
                page: 1,
                firstAirDateGte: upcomingDate,
            )

            trending = trendingPage.results
            popularMovies = moviesPage.results
            popularTV = tvPage.results
            upcomingMovies = upcomingMoviesPage.results
            upcomingTV = upcomingTVPage.results
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

    private static let upcomingDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

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
