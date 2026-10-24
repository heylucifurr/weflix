import Foundation

final class ImageRepository {
    private weak var context: PlexAPIContext?

    init(context: PlexAPIContext) throws {
        _ = try context.serverAccessSnapshot()
        self.context = context
    }

    func transcodeImageURL(
        path: String,
        width: Int = 240,
        height: Int = 360,
        minSize: Int = 1,
        upscale: Int = 1,
        format: String? = nil,
    ) -> URL? {
        guard let snapshot = try? context?.serverAccessSnapshot() else { return nil }

        // PHASE APP-GATEWAY — artwork goes through WeFlix's own image route, with **no credential in the URL**:
        // `CachedArtworkService` loads it with `URLSession`, so the app's bearer token travels in a header
        // (`WeFlixGatewayURL.imageURL`, and `CachedArtworkService`'s request). The Plex path is what the route
        // accepts, and it applies the per-account library rule to it.
        if snapshot.speaksToGateway {
            return WeFlixGatewayURL.imageURL(path: path, width: width, height: height, format: format)
        }

        var components = URLComponents(
            url: snapshot.baseURL.appendingPathComponent("photo/:/transcode"),
            resolvingAgainstBaseURL: false,
        )
        components?.queryItems = [
            URLQueryItem(name: "X-Plex-Token", value: snapshot.authToken),
            URLQueryItem(name: "url", value: path),
            URLQueryItem(name: "width", value: String(width)),
            URLQueryItem(name: "height", value: String(height)),
            URLQueryItem(name: "minSize", value: String(minSize)),
            URLQueryItem(name: "upscale", value: String(upscale)),
        ]
        if let format {
            components?.queryItems?.append(URLQueryItem(name: "format", value: format))
        }
        return components?.url
    }
}
