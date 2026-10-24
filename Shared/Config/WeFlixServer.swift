import Foundation

#if os(iOS)
    import UIKit
#endif

/// The one place the WeFlix server's address lives.
///
/// WeFlix is a native client of the **WeFlix server** now: it talks to this host and to nothing else. It never
/// contacts plex.tv and never talks to a Plex or Jellyfin server directly — the server holds the Plex token (its
/// own Plex backend lives at `plex.weflix.me`, which the app never addresses) and does all of that on the
/// account's behalf (see `docs/PROJECT.md`).
///
/// Everything the app needs — the address, and the three paths it calls — is here rather than spread across the
/// sign-in code, so pointing the app at a different deployment is a one-line change in one file.
///
/// **`https://weflix.me` is production, and it is what the app ships with** (Luther, 2026-10-24).
/// `https://beta.weflix.me` is the test site he redeploys on every push to `Development`; both deployments share
/// the same database, so an account works on either. The app does not fall back from one to the other: a client
/// that quietly talks to a different server than the one it was built for is worse than one that says it cannot
/// reach it.
enum WeFlixServer {
    /// The WeFlix server this app is built against. **The only host the app ever contacts.**
    static let baseURL = URL(string: "https://weflix.me")!

    /// `POST` — a WeFlix account signs this device in. Answers a bearer token, once.
    static let loginPath = "api/app/auth/login"

    /// `GET` — who this device's token belongs to. Answers `401` once the token has been revoked.
    static let mePath = "api/app/me"

    /// `POST` — ends this device's token.
    static let logoutPath = "api/app/auth/logout"

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
