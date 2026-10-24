import Foundation

final class SeerrSettingsRepository {
    private let client: SeerrNetworkClient

    init(session: URLSession = .shared) {
        client = SeerrNetworkClient(session: session)
    }

    func getPublicSettings() async throws -> SeerrSettings {
        try await client.request(path: "settings/public")
    }
}
