import Foundation
import Testing

@testable import weflix

/// The app's playback report to the WeFlix server — `WeFlixPlaybackHeartbeat` (2026-10-25).
///
/// **Why these exist.** The dashboard's Now Playing has two halves: Plex's `/status/sessions` and WeFlix's own
/// `playback_sessions` rows, which `POST /api/playback/heartbeat` writes. This app never called that route — it
/// reported to Plex's `/:/timeline`, which WeFlix stopped writing *and* the gateway refuses — so a playback from
/// the app was invisible on the dashboard and saved no progress. The body it must send is the route's own
/// contract, and these pin it, field by field, without a network.
///
/// The units are the ones that bite: **milliseconds**, not seconds.
struct WeFlixPlaybackHeartbeatTests {
    private static func body(_ report: WeFlixPlaybackHeartbeat.Report) -> [String: Any] {
        WeFlixPlaybackHeartbeat.body(for: report)
    }

    @Test func aDirectPlayReportsMillisecondsAndNoTranscodeKey() {
        let body = Self.body(
            WeFlixPlaybackHeartbeat.Report(
                ratingKey: "7192",
                positionMilliseconds: 90_000,
                durationMilliseconds: 7_200_000,
                state: .playing,
                itemGuid: "plex://movie/5d776b7e",
            ),
        )

        #expect(body["ratingKey"] as? String == "7192")
        #expect(body["position"] as? Int == 90_000, "the route counts milliseconds")
        #expect(body["duration"] as? Int == 7_200_000)
        #expect(body["state"] as? String == "playing")
        #expect(body["playMode"] as? String == "direct")
        #expect(body["itemGuid"] as? String == "plex://movie/5d776b7e")
        #expect(body["transcodeSessionKey"] == nil, "a direct play opens no Plex session to stop")
    }

    @Test func aTranscodeReportsItsKeySoTheDashboardCanStopIt() {
        let body = Self.body(
            WeFlixPlaybackHeartbeat.Report(
                ratingKey: "7192",
                positionMilliseconds: 1_000,
                durationMilliseconds: 2_000,
                state: .paused,
                playMode: "transcode",
                transcodeSessionKey: "weflix-7192-1690000000",
            ),
        )

        #expect(body["playMode"] as? String == "transcode")
        #expect(body["transcodeSessionKey"] as? String == "weflix-7192-1690000000")
        #expect(body["state"] as? String == "paused")
    }

    @Test func theClosingReportSaysStopped() {
        let body = Self.body(
            WeFlixPlaybackHeartbeat.Report(
                ratingKey: "7192",
                positionMilliseconds: 4_000,
                durationMilliseconds: 6_000,
                state: .stopped,
            ),
        )

        #expect(body["state"] as? String == "stopped", "`stopped` is what takes the row off Now Playing")
    }

    @Test func anEmptyGuidOrKeyIsOmittedRatherThanSentEmpty() {
        let body = Self.body(
            WeFlixPlaybackHeartbeat.Report(
                ratingKey: "7192",
                positionMilliseconds: 0,
                durationMilliseconds: 0,
                state: .playing,
                itemGuid: "",
                transcodeSessionKey: "",
            ),
        )

        #expect(body["itemGuid"] == nil, "the route falls back to the rating key when there is none")
        #expect(body["transcodeSessionKey"] == nil)
    }

    @Test func theThreeStatesAreExactlyTheRoutesOwnWords() {
        #expect(WeFlixPlaybackHeartbeat.State.playing.rawValue == "playing")
        #expect(WeFlixPlaybackHeartbeat.State.paused.rawValue == "paused")
        #expect(WeFlixPlaybackHeartbeat.State.stopped.rawValue == "stopped")
    }
}
