import Foundation

#if os(iOS)
    import UIKit
#endif

/// The one place the WeFlix server's address lives.
///
/// WeFlix is a native client of the **WeFlix server** now: it talks to this host and to nothing else. It never
/// contacts plex.tv and never talks to a Plex or Jellyfin server directly — the server holds the Plex token (its
/// own Plex backend lives on a host this app never addresses) and does all of that on the account's behalf (see
/// `docs/PROJECT.md`).
///
/// Everything the app needs — the address, and the three paths it calls — is here rather than spread across the
/// sign-in code, so pointing the app at a different deployment is a one-line change in one file.
///
/// **`https://weflix.me` is production, and it is what the app ships with** (Luther, 2026-10-24). Luther also
/// runs a **pre-production deployment** that he redeploys on every push to `Development`; both deployments share
/// the same database, so an account works on either. That address is deliberately **not named here**: this app
/// talks to `https://weflix.me` and to nothing else, and no test site, staging host or media server has any
/// business appearing in the code, the config, a plist, the docs or the tests. The app does not fall back from
/// one deployment to another either: a client that quietly talks to a different server than the one it was
/// built for is worse than one that says it cannot reach it.
enum WeFlixServer {
    /// The address the app ships with.
    private static let productionURL = URL(string: "https://weflix.me")!

    /// The WeFlix server this app is built against. **The only host the app ever contacts.**
    ///
    /// `WEFLIX_BASE_URL` in the environment moves the whole app — the sign-in routes, the gateway and every media
    /// URL, because they are all derived from this one value. It exists so a build can be pointed at a
    /// **pre-production deployment** before production has been updated (Luther: that deployment is rebuilt on
    /// every push to `Development`, production on a merge to `main`), which is how the gateway is proved
    /// end-to-end. It is an **https-only** override with no other effect: it is not a fallback between servers, no
    /// shipped configuration sets it, and an unset variable is the production address above
    /// (`docs/PROJECT.md`).
    ///
    /// It is a *test and debug* door, never a second server: nothing may name another WeFlix host in this file,
    /// in a plist or in the docs — a client built for `weflix.me` that quietly answers from somewhere else is
    /// exactly the failure nobody notices until a friend's request lands in the wrong place.
    static var baseURL: URL {
        guard let override = ProcessInfo.processInfo.environment["WEFLIX_BASE_URL"],
              let url = URL(string: override),
              url.scheme == "https",
              url.host()?.isEmpty == false
        else { return productionURL }

        return url
    }

    /// `POST` — a WeFlix account signs this device in. Answers a bearer token, once.
    static let loginPath = "api/app/auth/login"

    /// `GET` — who this device's token belongs to. Answers `401` once the token has been revoked.
    static let mePath = "api/app/me"

    /// `POST` — ends this device's token.
    static let logoutPath = "api/app/auth/logout"

    /// `POST` — a short-lived ticket for the **player**'s media URLs, which cannot carry a header (S5).
    static let streamTicketPath = "api/app/stream-ticket"

    /// `GET` — the signed-in account's **My Watchlist**, from WeFlix's own database (2026-10-25).
    ///
    /// The list is the account's own `watchlist_entries` rows; the web reads the same store through
    /// `/api/plex-actions/watchlist` with its cookie, and this is the app's door to it with the device token.
    static let watchlistPath = "api/app/watchlist"

    /// The **gateway**: the Plex-shaped reads the app makes of this server, which holds the Plex token and does the
    /// reading on the account's behalf (PHASE APP-GATEWAY). One path, because the app talks to one host.
    static let gatewayPath = "api/plex"

    /// What the gateway calls itself when the app asks who it is talking to (`/api/plex/identity`). A literal, never
    /// the real Plex server's identifier — `lib/plex-gateway.ts` on the server answers with the same one.
    static let gatewayMachineIdentifier = "weflix-gateway"

    /// The whole gateway base URL — `https://weflix.me/api/plex`, which the Plex client treats as its server.
    static var gatewayBaseURL: URL {
        baseURL.appendingPathComponent(gatewayPath)
    }

    /// The app's **requests**: every Seerr read and write, proxied by WeFlix (2026-10-25).
    ///
    /// `SeerrNetworkClient` appends Overseerr's own `api/v1/...` to this, so the app keeps the paths it always
    /// spoke while the host, the API key, the `X-API-User` header and the identity behind them are all the
    /// server's (`docs/PROJECT.md`). Nothing here is configurable: there is no "Overseerr address" field in the
    /// app any more, because the app never addresses Overseerr.
    static let seerrPath = "api/app/seerr"

    /// The whole requests base URL — `https://weflix.me/api/app/seerr`.
    static var seerrBaseURL: URL {
        baseURL.appendingPathComponent(seerrPath)
    }

    /// What this device calls itself, and which platform it is, so the owner can tell his devices apart.
    ///
    /// Neither value is a secret and neither is trusted by the server: they are stored beside the device row
    /// (`app_devices.device_name`, `app_devices.platform`) and never echo back.
    static var deviceName: String {
        #if os(macOS)
            Host.current().localizedName ?? "WeFlix on Mac"
        #elseif os(tvOS)
            "Apple TV"
        #else
            UIDevice.current.name
        #endif
    }

    /// `iOS`, `tvOS` or `macOS` — the platform name the server records for this sign-in.
    static var platform: String {
        #if os(macOS)
            "macOS"
        #elseif os(tvOS)
            "tvOS"
        #else
            "iOS"
        #endif
    }
}
