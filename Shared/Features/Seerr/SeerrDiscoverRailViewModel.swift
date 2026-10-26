import Foundation
import Observation

/// The screen a Discover heading opens: the whole rail, a page at a time.
///
/// It is the Seerr counterpart of `HubDetailViewModel`, and the two differ for one reason: Plex pages by
/// `start`/`limit` while Seerr pages by **page number**, so "load more" here asks for the next page rather than an
/// offset.
///
/// **It filters exactly as the rail does.** `SeerrDiscoverViewModel` keeps only titles Seerr reports as already in
/// the library, and Luther chose to keep that filter as it is (2026-10-26). A heading that says "Trending" over a
/// filtered rail must not open a screen showing the unfiltered one, so every page here goes through the same
/// `inLibraryOnly` — the filter keeping its meaning rather than being undone by the back door.
@MainActor
@Observable
final class SeerrDiscoverRailViewModel {
    let rail: SeerrDiscoverRail
    var items: [SeerrMedia] = []
    var isLoading = false
    var isLoadingMore = false
    var errorMessage: String?

    @ObservationIgnored private var nextPage = 1
    @ObservationIgnored private var reachedEnd = false
    @ObservationIgnored private var hasLoaded = false

    /// The date boundary for the two upcoming rails, read **once** for this screen.
    ///
    /// Not read per page: paging across midnight would otherwise put page 1 and page 2 on different days, so page 2
    /// could repeat titles page 1 already showed or skip the ones between (`SeerrDiscoverRail.upcomingBoundary`).
    @ObservationIgnored private let upcomingFrom: String

    /// How many pages in a row the filter may empty before this screen stops asking for more.
    ///
    /// A page can be entirely out-of-library — on a filtered rail that is normal, not an error — and a screen that
    /// gave up after one such page would show a short list and a dead end. Bounded so a long run of them cannot
    /// turn into an unbounded burst of requests.
    @ObservationIgnored private let emptyPageLimit = 4

    /// `upcomingFrom` and `repository` are injectable so a test can pin the boundary and answer from a stubbed
    /// session (`SeerrDiscoverRailTests`); the screen never passes either.
    ///
    /// `repository` is optional and built in the body rather than defaulted: a default argument is evaluated in a
    /// nonisolated context, and `SeerrDiscoverRepository()` is main-actor isolated (its base URL reads
    /// `WeFlixServer`), so a default here warns.
    @ObservationIgnored private let repository: SeerrDiscoverRepository

    init(
        rail: SeerrDiscoverRail,
        upcomingFrom: String? = nil,
        repository: SeerrDiscoverRepository? = nil,
    ) {
        self.rail = rail
        self.upcomingFrom = upcomingFrom ?? SeerrDiscoverRail.upcomingBoundary()
        self.repository = repository ?? SeerrDiscoverRepository()
    }

    var isEmpty: Bool {
        items.isEmpty
    }

    func load() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await reload()
    }

    func reload() async {
        items = []
        nextPage = 1
        reachedEnd = false
        await loadPages(isInitialLoad: true)
    }

    func loadMoreIfNeeded(currentItem item: SeerrMedia) async {
        guard item.id == items.last?.id else { return }
        await loadMore()
    }

    func loadMore() async {
        guard !items.isEmpty else { return }
        await loadPages(isInitialLoad: false)
    }

    /// Fetches pages until this call has something to show, or the rail runs out.
    ///
    /// The loop is the filter's fault: `inLibraryOnly` can drop every item on a page, and appending nothing would
    /// leave the grid's last card unchanged — which is what triggers the next page — so the screen would sit there
    /// looking finished. Instead it keeps asking while a page contributed nothing, up to `emptyPageLimit`.
    private func loadPages(isInitialLoad: Bool) async {
        guard !reachedEnd, !isLoading, !isLoadingMore else { return }

        if isInitialLoad {
            isLoading = true
        } else {
            isLoadingMore = true
        }
        errorMessage = nil
        defer {
            if isInitialLoad {
                isLoading = false
            } else {
                isLoadingMore = false
            }
        }

        let countBefore = items.count
        var attempts = 0

        repeat {
            attempts += 1

            do {
                let response = try await rail.page(nextPage, upcomingFrom: upcomingFrom, repository: repository)
                nextPage += 1
                items.append(contentsOf: SeerrDiscoverViewModel.inLibraryOnly(response.items))

                // Seerr's own `totalPages` is the authority on the end; an empty page is the other end of the line.
                if response.items.isEmpty || response.page >= response.lastPage {
                    reachedEnd = true
                }
            } catch {
                guard !Task.isCancelled, !error.isCancellation else { return }

                ErrorReporter.capture(error)
                errorMessage = String(localized: "hub.error.loadFailed")

                if isInitialLoad {
                    items = []
                }

                return
            }
        } while items.count == countBefore && !reachedEnd && attempts < emptyPageLimit
    }
}
