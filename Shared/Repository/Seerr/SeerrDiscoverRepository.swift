import Foundation

final class SeerrDiscoverRepository {
    private let client: SeerrNetworkClient

    /// - Parameters:
    ///   - baseURL: defaults to the app's one requests base (`WeFlixServer.seerrBaseURL`). **Only a test passes
    ///     anything else** — same rule and same wording as `SeerrNetworkClient`, so a stubbed session can be
    ///     pointed at `https://weflix.test` and nothing else in the app can retarget the requests routes.
    ///   - session: a test's stubbed session; the app uses the shared one.
    init(
        baseURL: URL = WeFlixServer.seerrBaseURL,
        session: URLSession = .shared,
    ) {
        client = SeerrNetworkClient(baseURL: baseURL, session: session)
    }

    func getTrending(page: Int) async throws -> SeerrPaginatedResponse<SeerrMedia> {
        let queryItems = paginationQueryItems(page: page, primaryReleaseDateGte: nil)
        return try await client.request(path: "discover/trending", queryItems: queryItems)
    }

    func discoverMovies(
        page: Int,
        primaryReleaseDateGte: String? = nil,
    ) async throws -> SeerrPaginatedResponse<SeerrMedia> {
        let queryItems = paginationQueryItems(
            page: page,
            primaryReleaseDateGte: primaryReleaseDateGte,
        )
        return try await client.request(path: "discover/movies", queryItems: queryItems)
    }

    func discoverTV(
        page: Int,
        firstAirDateGte: String? = nil,
    ) async throws -> SeerrPaginatedResponse<SeerrMedia> {
        let queryItems = paginationQueryItems(
            page: page,
            primaryReleaseDateGte: nil,
            firstAirDateGte: firstAirDateGte,
        )
        return try await client.request(path: "discover/tv", queryItems: queryItems)
    }

    func search(query: String, page: Int) async throws -> SeerrPaginatedResponse<SeerrMedia> {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let queryItems = [
            URLQueryItem(name: "query", value: trimmedQuery),
            URLQueryItem(name: "page", value: String(page)),
        ]
        return try await client.request(path: "search", queryItems: queryItems)
    }

    private func paginationQueryItems(
        page: Int,
        primaryReleaseDateGte: String?,
        firstAirDateGte: String? = nil,
    ) -> [URLQueryItem] {
        var items = [URLQueryItem(name: "page", value: String(page))]

        if let primaryReleaseDateGte, !primaryReleaseDateGte.isEmpty {
            items.append(URLQueryItem(name: "primaryReleaseDateGte", value: primaryReleaseDateGte))
        }

        if let firstAirDateGte, !firstAirDateGte.isEmpty {
            items.append(URLQueryItem(name: "firstAirDateGte", value: firstAirDateGte))
        }

        return items
    }
}
