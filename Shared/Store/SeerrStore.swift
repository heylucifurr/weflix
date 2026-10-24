import Foundation
import Observation

/// The app's requests state: **the server's answer about this account, and nothing the app decides for itself**
/// (2026-10-25).
///
/// Before this, the store *was* the integration: it kept an Overseerr address in `UserDefaults`, a signed-in
/// Seerr user, a quota and the public settings, and a screen could point it anywhere. Now there is one thing to
/// know — what `GET /api/app/me` answered — and the store holds exactly that:
///
/// | `GET /api/app/me` | What the app does |
/// |---|---|
/// | `requests.enabled: false` | the whole requests UI is hidden, and Settings says it is not set up for this account |
/// | `requests.enabled: true` | the discover, search and requests screens, with the permission bits the server reported |
///
/// `baseURL` is `WeFlixServer.seerrBaseURL` and is **not settable**: the app cannot be pointed at another host,
/// and no field anywhere in the UI tries to. The Overseerr address, its API key and the identity behind them all
/// belong to the server.
@MainActor
@Observable
final class SeerrStore {
    /// The one requests base the app has, read by every view model instead of a stored, user-editable address.
    var baseURL: URL {
        WeFlixServer.seerrBaseURL
    }

    /// May this account browse and request? `false` until `/api/app/me` says otherwise — and the switch the
    /// requests UI hangs on (the Seerr tab, the sidebar entry, the requests screens).
    var isRequestsEnabled: Bool {
        requestsState == .enabled
    }

    /// **What the server actually said about requests**, which is three different things and used to be one.
    ///
    /// `enabled: false` and *no answer at all* were collapsed into a single flag on 2026-10-25, and that is exactly
    /// how a signed-in person ended up reading **"Requests aren't set up for your account yet. Ask Luther."** on a
    /// server that had never heard of requests: the app shipped pointed at `weflix.me`, `weflix.me` did not have
    /// the new `/api/app/me` yet, `requests` decoded as `nil`, and the app blamed the account for the server's
    /// missing feature. Luther, 2026-10-25: *"when i sign it says Requests arent setup for this account … THIS IS
    /// WRONG."* He was right, and the fix is this distinction.
    enum RequestsState: Equatable {
        /// The server has not told us anything: a launch still in flight, or a WeFlix that predates the feature
        /// (its `/api/app/me` carries no `requests` block). **Never an accusation about the account.**
        case unknown
        /// The server answered, and this account has no linked Overseerr user — Luther's to fix, and the sentence
        /// says so.
        case notLinked
        /// The server answered, and this account may browse and request.
        case enabled
    }

    private(set) var requestsState: RequestsState = .unknown

    /// The Overseerr user this account is (`requests.overseerrUserId`) together with the permission bits the
    /// server reported, in the shape the app's permission checks already take (`SeerrPermissionService`).
    ///
    /// `nil` while requests are off, which is what makes every permission check false — no admin queue, no
    /// advanced configuration, no Request button. `permissions` is the server's answer, never the app's guess.
    private(set) var user: SeerrUser?

    /// The account's own quota, read through the proxy. `nil` while unknown, which the request sheet reads as
    /// "no limit" — the same meaning it had when the quota could not be fetched.
    private(set) var quota: SeerrUserQuota?

    /// **Always `nil`, deliberately** — and this doc comment is the reason.
    ///
    /// These are Overseerr's *public settings* (`/settings/public`): whether 4K is offered, whether partial
    /// (per-season) requests are allowed, and whether specials are listed. That path is **not** in the app's
    /// allow-list on the server (`lib/app-seerr-routes.ts`), so the app does not ask for it and cannot have it.
    /// What a `nil` therefore means, field by field, is fixed and safe:
    ///
    /// - `movie4kEnabled` / `series4kEnabled` → 4K is not offered, which is what the proxy allows anyway;
    /// - `partialRequestsEnabled` → treated as allowed (the sheet's own default when the setting is unknown);
    /// - `enableSpecialEpisodes` → season zero is listed, because hiding it would be a claim the app cannot make.
    ///
    /// The property stays so those three answers live in one place rather than being spelled out at each use.
    private(set) var settings: SeerrSettings?

    private(set) var isHydrating = false

    @ObservationIgnored private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Take the server's answer about this account — the one thing that turns the requests UI on.
    ///
    /// Called whenever the sign-in state moves: at launch from `GET /api/app/me`, and again after a sign-in.
    /// **An absent `requests` block is `.unknown`, not a refusal** — a WeFlix that predates the feature says
    /// nothing about the account, and the app must not say otherwise (see `RequestsState`).
    func adopt(requests: WeFlixRequests?, displayName: String) async {
        isHydrating = true
        defer { isHydrating = false }

        guard let requests else {
            requestsState = .unknown
            user = nil
            quota = nil

            return
        }

        guard requests.enabled, let overseerrUserId = requests.overseerrUserId else {
            requestsState = .notLinked
            user = nil
            quota = nil

            return
        }

        requestsState = .enabled
        user = SeerrUser(
            id: overseerrUserId,
            permissions: requests.permissions,
            displayName: displayName,
            avatar: nil,
        )

        // The quota is a nicety, never a gate: a read that fails leaves it unknown, which reads as "no limit".
        quota = try? await SeerrAccountRepository(session: session).fetchQuota(userId: overseerrUserId)
    }

    /// Forget everything the server said about requests. Called on sign-out, and when the server refuses the
    /// device's token — a signed-out app must not keep a name, an id or a quota on screen.
    func clear() {
        requestsState = .unknown
        user = nil
        quota = nil
    }
}
