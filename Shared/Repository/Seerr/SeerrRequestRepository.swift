import Foundation

final class SeerrRequestRepository {
    private let client: SeerrNetworkClient

    init(session: URLSession = .shared) {
        client = SeerrNetworkClient(session: session)
    }

    func createRequest(_ payload: SeerrMediaRequestPayload) async throws {
        try await client.send(path: "request", method: "POST", body: payload)
    }

    func updateRequest(id: Int, payload: SeerrMediaRequestPayload) async throws {
        try await client.send(path: "request/\(id)", method: "PUT", body: payload)
    }

    func cancelRequest(id: Int) async throws {
        try await client.send(path: "request/\(id)", method: "DELETE")
    }

    func getRequestCount() async throws -> SeerrRequestCount {
        try await client.request(path: "request/count")
    }

    /// `GET /request` — the signed-in account's own requests.
    ///
    /// **Only the keys Overseerr's `/request` accepts.** That route validates its query strictly and answers
    /// `400 {"message":"Unknown query parameter '<key>'"}` for anything outside its schema, so `mediaType` and
    /// `sortDirection` — legal on the discover rails — must not travel here (Luther, 2026-10-25). These four are
    /// exactly what the web UI's own "My Requests" path sends; the server adds `requestedBy=<the account's own id>`
    /// on top, so the list is always this person's own requests.
    func getRequests(
        take: Int,
        skip: Int,
        filter: String,
        sort: String = "added",
    ) async throws -> SeerrRequestPageResponse {
        let queryItems = [
            URLQueryItem(name: "take", value: "\(take)"),
            URLQueryItem(name: "skip", value: "\(skip)"),
            URLQueryItem(name: "filter", value: filter),
            URLQueryItem(name: "sort", value: sort),
        ]
        return try await client.request(path: "request", queryItems: queryItems)
    }

    func retryRequest(id: Int) async throws {
        try await client.send(path: "request/\(id)/retry", method: "POST")
    }

    func updateRequestStatus(id: Int, status: SeerrMediaRequestStatus) async throws {
        let action = switch status {
        case .approved:
            "approve"
        case .declined:
            "decline"
        case .pending, .failed, .completed:
            "approve"
        }
        try await client.send(path: "request/\(id)/\(action)", method: "POST")
    }
}
