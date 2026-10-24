import Foundation

/// The one thing the app still asks about its own account: **how much of its request quota is left** (2026-10-25).
///
/// This file replaces `SeerrAuthRepository`, which existed to sign in to Overseerr — `/status`, `/auth/plex`,
/// `/auth/local`, `/auth/jellyfin`, `/auth/me` — and to read a quota by an id it had just learned from
/// `/auth/me`. None of that is the app's business any more, and one of those calls was actively harmful: the
/// session `/auth/plex` produced was always the **deployment owner's** (every WeFlix account talks to Overseerr
/// with the server's own Plex token), so `/auth/me` answered "you are Luther" for everybody — the exact
/// misfiling QW-14 removed on the server.
///
/// So: the identity comes from `GET /api/app/me`, and this repository reads the quota **through the proxy**,
/// which rewrites the id in the path to the caller's own linked Overseerr user whatever the app sends. The id
/// passed here is therefore a formality — `lib/app-seerr-routes.ts` ignores it — and it is kept so the call reads
/// like the Overseerr call it is.
final class SeerrAccountRepository {
    private let client: SeerrNetworkClient

    init(session: URLSession = .shared) {
        client = SeerrNetworkClient(session: session)
    }

    /// `GET /user/<id>/quota` — the caller's own quota. A user with no restrictions answers every field `nil`,
    /// which the request sheet reads as "no limit", exactly as it did before.
    func fetchQuota(userId: Int) async throws -> SeerrUserQuota {
        try await client.request(path: "user/\(userId)/quota")
    }
}
