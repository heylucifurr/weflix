import Foundation

/// The app's current **stream ticket**, and the one place that refreshes it.
///
/// A ticket is minutes long, and the URLs that need it are built by **synchronous** code deep in the Plex
/// repositories (`MediaRepository.mediaURL`, `PlaybackRepository`'s stream URL). So the ticket lives in a small cache
/// with a synchronous read and an asynchronous refresh, and the app refreshes it where it already has an `await`:
/// at sign-in, at launch, and before a playback starts.
///
/// `nil` means "no ticket yet" — the URL is built without one, and the request is refused rather than silently sent
/// with no credential. Nothing here is logged: not the ticket, not the response.
final class WeFlixStreamTicketCache: @unchecked Sendable {
    static let shared = WeFlixStreamTicketCache()

    private let lock = NSLock()
    private var ticket: String?
    private var expiresAt: Date = .distantPast
    /// Refreshed this far before it expires, so a play starting at T-1s still gets a usable ticket.
    private let margin: TimeInterval = 60

    init() {}

    /// The ticket to put in a media URL, or `nil` when there is none that is still worth using.
    func current() -> String? {
        lock.lock()
        defer { lock.unlock() }

        guard let ticket, expiresAt.timeIntervalSinceNow > margin else {
            return nil
        }

        return ticket
    }

    /// Store one, with the expiry the server named.
    func store(ticket: String, expiresAt: Date) {
        lock.lock()
        self.ticket = ticket
        self.expiresAt = expiresAt
        lock.unlock()
    }

    /// Fetch a fresh one if the current one is missing or nearly over. Answers whether a usable ticket is in hand.
    ///
    /// A failure is not an error worth surfacing here: the caller is about to build a URL that will simply be
    /// refused, and the app's own error path says so in words.
    @discardableResult
    func refreshIfNeeded(deviceToken: String?, client: WeFlixAuthClient = WeFlixAuthClient()) async -> Bool {
        if current() != nil {
            return true
        }

        guard let deviceToken, !deviceToken.isEmpty else {
            return false
        }

        guard let answer = try? await client.streamTicket(token: deviceToken) else {
            return false
        }

        store(ticket: answer.ticket, expiresAt: answer.expiresAt)

        return true
    }

    /// For sign-out, and for tests.
    func clear() {
        lock.lock()
        ticket = nil
        expiresAt = .distantPast
        lock.unlock()
    }
}
