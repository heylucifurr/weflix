import Foundation

/// One title on the signed-in account's **My Watchlist**, as `GET /api/app/watchlist` answers it.
///
/// The shape mirrors the web UI's `MyWatchlist` rows (`lib/watchlist-server.ts`'s `AccountWatchlistEntry`), so
/// the two clients read the same store through the same fields:
///
/// - `id` — the last segment of the item's `plex://` GUID (Plex's own metadata id);
/// - `libraryRatingKey` — **present only when WeFlix's library holds the title**, which is what makes the entry
///   openable here (a title the library does not hold has no detail screen to open);
/// - `thumb` — Plex's artwork path, fetched through the gateway's `/api/image` with the app's bearer token.
struct WeFlixWatchlistEntry: Identifiable, Hashable, Decodable {
    let id: String
    let guid: String?
    let title: String
    let type: String?
    let year: Int?
    let thumb: String?
    let libraryRatingKey: String?

    /// Plex's own type word (`movie` / `show`) as the app's `MediaKind`.
    var mediaKind: MediaKind {
        type == "show" ? .series : .movie
    }

    /// Is this title in the library (so a detail screen can be opened for it)?
    var isInLibrary: Bool {
        !(libraryRatingKey ?? "").isEmpty
    }
}

/// `{ entries, ids }` — the list, plus the ids the watchlist button compares against. Only `entries` is needed
/// here, but the whole answer is decoded so a future edit cannot quietly drift from the server's contract.
struct WeFlixWatchlistAnswer: Decodable {
    let entries: [WeFlixWatchlistEntry]
    let ids: [String]
}

enum WeFlixWatchlistError: Error {
    /// The device token was refused (`401`) — the app's sign-in has ended.
    case unauthorized
    case failed
}

/// Reads the signed-in account's watchlist from WeFlix (`GET /api/app/watchlist`).
///
/// Bearer token only, in a header, exactly like the app's other `/api/app/*` calls: the token is the device's
/// own (`WeFlixDeviceTokenStore`), never a plex.tv credential, and the list it reads is this account's own rows.
struct WeFlixWatchlistClient {
    private let session: URLSession
    private let token: String?

    init(session: URLSession = .shared, token: String? = WeFlixDeviceTokenStore().token()) {
        self.session = session
        self.token = token
    }

    func list() async throws -> [WeFlixWatchlistEntry] {
        var request = URLRequest(url: WeFlixServer.baseURL.appendingPathComponent(WeFlixServer.watchlistPath))

        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw WeFlixWatchlistError.failed }

        if http.statusCode == 401 { throw WeFlixWatchlistError.unauthorized }
        guard (200 ..< 300).contains(http.statusCode) else { throw WeFlixWatchlistError.failed }

        return try JSONDecoder().decode(WeFlixWatchlistAnswer.self, from: data).entries
    }
}
