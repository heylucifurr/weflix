import Foundation

#if os(iOS)
    import UIKit
#endif

/// The one place the WeFlix server's address lives.
///
/// WeFlix is a native client of the **WeFlix server** now: it talks to this host and to nothing else. It never
/// contacts plex.tv and never talks to a Plex or Jellyfin server directly — the server holds the Plex token and
/// does all of that on the account's behalf (see `docs/PROJECT.md`).
///
/// Everything the app needs — the address, and the three paths it calls — is here rather than spread across the
/// sign-in code, so pointing the app at a different deployment (production `weflix.me`, or a local one) is a
/// one-line change in one file.
enum WeFlixServer {
    /// The WeFlix server this app is built against. **The only host the app ever contacts.**
    static let baseURL = URL(string: "https://beta.weflix.me")!

    /// `POST` — a WeFlix account signs this device in. Answers a bearer token, once.
    static let loginPath = "api/app/auth/login"

    /// `GET` — who this device's token belongs to. Answers `401` once the token has been revoked.
    static let mePath = "api/app/me"

    /// `POST` — ends this device's token.
    static let logoutPath = "api/app/auth/logout"

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
