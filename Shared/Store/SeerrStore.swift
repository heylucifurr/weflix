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
    /// whole requests UI hangs on.
    private(set) var isRequestsEnabled = false

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
    /// An account the server has not linked to an Overseerr user (or a deployment with no Seerr) leaves
    /// `isRequestsEnabled` false, which is the honest answer and the one the Settings row prints.
    func adopt(requests: WeFlixRequests?, displayName: String) async {
        isHydrating = true
        defer { isHydrating = false }

        guard let requests, requests.enabled, let overseerrUserId = requests.overseerrUserId else {
            isRequestsEnabled = false
            user = nil
            quota = nil

            return
        }

        isRequestsEnabled = true
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
        isRequestsEnabled = false
        user = nil
        quota = nil
    }
}
