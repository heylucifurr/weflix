import Foundation

/// PHASE APP-GATEWAY: the WeFlix URLs a **player or an image loader** needs, and the ticket that authorises them.
///
/// Two different problems, two different answers, and the code says which is which:
///
/// - **Artwork** is fetched by `CachedArtworkService` with `URLSession`, so the app's bearer token travels in an
///   `Authorization` header — `imageURL(path:size:)` builds a URL with **no credential in it at all**.
/// - **Playback** is fetched by `AVPlayer`, which cannot set a header on a media request. Those URLs carry a
///   **stream ticket** (`?ticket=…`): signed, minutes long, naming one account, and accepted only by the three
///   streaming routes. The long-lived device token never goes into a URL.
///
/// The gateways themselves live in one place (`WeFlixServer`); this type is the only thing that knows how the three
/// routes are addressed, so a change to one of them cannot be made in two out of three callers.
enum WeFlixGatewayURL {
    /// `/api/image?path=<artwork path>&size=<poster|backdrop|thumb|logo|square>` — the web UI's own image route.
    ///
    /// The app asks for explicit dimensions; the route takes one of five named sizes and transcodes Plex-side, so
    /// the requested box is mapped to the closest of them (`gatewayImageSize`).
    static func imageURL(path: String, width: Int, height: Int, format: String?) -> URL? {
        var components = URLComponents(
            url: WeFlixServer.baseURL.appendingPathComponent("api/image"),
            resolvingAgainstBaseURL: false,
        )

        components?.queryItems = [
            URLQueryItem(name: "path", value: path),
            URLQueryItem(name: "size", value: gatewayImageSize(width: width, height: height, format: format)),
        ]

        return components?.url
    }

    /// `/api/video?...` — a direct play. The Plex path and its own query travel as the route's `path`, and the
    /// `ratingKey` stays a parameter of its own because the route uses it for the per-account library check.
    static func directPlayURL(path: String, ratingKey: String?, ticket: String?) -> URL? {
        let (pathOnly, pathQuery) = splitPathAndQuery(path)
        var items = [URLQueryItem(name: "path", value: pathOnly)]

        items.append(contentsOf: queryItems(from: pathQuery))

        if let ratingKey, !ratingKey.isEmpty {
            items.append(URLQueryItem(name: "ratingKey", value: ratingKey))
        }

        if let ticket {
            items.append(URLQueryItem(name: STREAM_TICKET_QUERY_KEY, value: ticket))
        }

        return url(path: "api/video", items: items)
    }

    /// `/api/transcode?path=<Plex transcode path>?...` — an HLS stream. The route proxies the playlist **and
    /// rewrites it**, which is why the stream must not go through the gateway's own proxy: a rewritten playlist's
    /// segment URLs carry no token.
    static func transcodeURL(plexPath: String, plexQuery: String, ticket: String?) -> URL? {
        var nested = plexPath

        if !plexQuery.isEmpty {
            nested += "?" + plexQuery
        }

        var items = [URLQueryItem(name: "path", value: nested)]

        if let ticket {
            items.append(URLQueryItem(name: STREAM_TICKET_QUERY_KEY, value: ticket))
        }

        return url(path: "api/transcode", items: items)
    }

    /// The query key the ticket travels under — the same word the server uses (`lib/stream-ticket.ts`).
    static let STREAM_TICKET_QUERY_KEY = "ticket"

    /// The five sizes `/api/image` accepts, mapped from the box the app asked for.
    ///
    /// The aspect ratio decides first — a poster is 2:3 (so *width ÷ height* is about 0.67, and it is the shape the
    /// app asks for as 400×600), a backdrop and an episode thumb are 16:9, a cast photo is square, and a logo is
    /// asked for as PNG — and the width breaks the tie between the two 16:9 sizes. Nothing here is a guess about
    /// Plex: the route's own table is `lib/plex-image.ts`'s `PLEX_IMAGE_SIZES`.
    static func gatewayImageSize(width: Int, height: Int, format: String?) -> String {
        if format?.lowercased() == "png" {
            return "logo"
        }

        let safeHeight = max(1, height)
        let ratio = Double(width) / Double(safeHeight)

        if abs(ratio - 1.0) < 0.15 {
            return "square"
        }

        if abs(ratio - 2.0 / 3.0) < 0.15 {
            return "poster"
        }

        return width >= 800 ? "backdrop" : "thumb"
    }

    /* ---------------------------------------------------------------------- */

    private static func url(path: String, items: [URLQueryItem]) -> URL? {
        var components = URLComponents(
            url: WeFlixServer.baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false,
        )

        components?.queryItems = items

        return components?.url
    }

    /// `"/library/parts/1/file.mkv?a=1"` → `("/library/parts/1/file.mkv", "a=1")`.
    static func splitPathAndQuery(_ path: String) -> (path: String, query: String) {
        let parts = path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)

        return (String(parts[0]), parts.count == 2 ? String(parts[1]) : "")
    }

    /// A query string → items, without re-encoding what is already encoded.
    static func queryItems(from query: String) -> [URLQueryItem] {
        guard !query.isEmpty else { return [] }

        var components = URLComponents()
        components.percentEncodedQuery = query

        return components.queryItems ?? []
    }
}
