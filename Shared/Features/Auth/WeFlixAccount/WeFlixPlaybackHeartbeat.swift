import Foundation

/// The playback report the **WeFlix server** actually reads — `POST /api/playback/heartbeat`.
///
/// **Why this exists (2026-10-25).** Luther: *"on weflix.me i can see whos playing on admin dashboard. but anyone
/// uses app is not tracking."* He was right, and the cause was that this app never adopted WeFlix's own heartbeat:
/// it still reported to Plex's `/:/timeline`, which the **server deliberately stopped writing** (`app/api/playback/
/// heartbeat/route.ts`: *"nothing at all is written to `/:/timeline` or `/:/scrobble`"*) and which the gateway also
/// refuses. So an app playback was invisible on Admin → Now Playing **and** saved no progress anywhere — the
/// `watch_progress` row the resume point and the watched mark come from is written by this same call.
///
/// The route is identity-gated the ordinary way, and since PHASE APP-GATEWAY S1 the request identity accepts this
/// app's **device bearer token**, so the client half is exactly what the web player does: the rating key, the
/// position and duration in **milliseconds**, the state, the play mode, and the live transcode's key when there is
/// one. A closing report (`state: stopped`) is what takes the row off the dashboard at once; without it the
/// server's reaper ends it after its own window.
///
/// Mechanically the web player calls it every 20 s and on every state change; the cadence here is the player's own
/// (`timelineInterval`), which is the same idea. A stream the account's limit refuses comes back `409` with the
/// server's sentence, and it is thrown so the caller can show it rather than lose it (the web pill does that).
enum WeFlixPlaybackHeartbeat {
    /// What the route accepts: `playing`, `paused`, or `stopped` to end the session.
    enum State: String {
        case playing
        case paused
        case stopped
    }

    /// One report. Everything but `ratingKey`, `position` and `state` is optional in the route's own body type.
    struct Report {
        let ratingKey: String
        /// Milliseconds — the route's unit, not seconds.
        let positionMilliseconds: Int
        let durationMilliseconds: Int
        let state: State
        /// The item's stable GUID when the app knows a real one, so the server's `watch_progress` row is keyed the
        /// same way the web's is. Empty means "key it off the rating key" (`fallbackItemGuid`), which is what the
        /// route does for a body without one.
        var itemGuid: String = ""
        /// `transcode` when the URL really is `/api/transcode`; `direct` otherwise. Never a transcode key for a
        /// direct play — the route counts it as a transcode and the reaper would try to stop a session that never
        /// existed (the web player's QW-16 item 3).
        var playMode: String = "direct"
        var transcodeSessionKey: String?
    }

    /// Thrown when the server refused the report. `message` is the server's own sentence for a limit (`409`).
    struct Refused: Error {
        let status: Int
        let message: String
        /// True when the refusal is the account's stream limit rather than a broken request.
        let isLimit: Bool
    }

    /// Send one report. Throws `Refused` when the server answered, and the transport error when it did not.
    ///
    /// `token` and `session` are parameters for the same reason `WeFlixAuthClient`'s are: so a test can drive this
    /// without a Keychain or a network.
    static func send(
        _ report: Report,
        token: String? = WeFlixDeviceTokenStore().token(),
        session: URLSession = .shared,
    ) async throws {
        guard let token, !token.isEmpty else {
            // No device token means no gateway account; there is nothing this call could be attributed to.
            return
        }

        var request = URLRequest(url: WeFlixServer.baseURL.appendingPathComponent(WeFlixServer.playbackHeartbeatPath))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body(for: report))

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw Refused(status: -1, message: String(localized: "player.playbackFailed.message"), isLimit: false)
        }

        guard 200 ..< 300 ~= http.statusCode else {
            let decoded = try? JSONDecoder().decode(RefusalBody.self, from: data)
            throw Refused(
                status: http.statusCode,
                // The server's own sentence when it sent one, so a limit reads as a limit.
                message: decoded?.error ?? String(localized: "player.playbackFailed.message"),
                isLimit: decoded?.limited == true,
            )
        }
    }

    /// The route's own field names and units. Extracted so a test can assert them without a network.
    static func body(for report: Report) -> [String: Any] {
        var body: [String: Any] = [
            "ratingKey": report.ratingKey,
            "position": report.positionMilliseconds,
            "duration": report.durationMilliseconds,
            "state": report.state.rawValue,
            "playMode": report.playMode,
        ]

        if !report.itemGuid.isEmpty {
            body["itemGuid"] = report.itemGuid
        }

        if let key = report.transcodeSessionKey, !key.isEmpty {
            body["transcodeSessionKey"] = key
        }

        return body
    }

    /// The refusal shape: `{ "error": "…", "limited": true }`.
    private struct RefusalBody: Decodable {
        let error: String?
        let limited: Bool?
    }
}
