import Foundation

/// Where the app keeps its WeFlix sign-in, and nowhere else.
///
/// **The Keychain, never `UserDefaults`.** A bearer token is a credential: it is as good as the password that
/// created it until it is revoked, so it belongs in the same place the Plex tokens have always been kept
/// (`Shared/Storage/Keychain.swift`) and not in a plist any other app or a backup reader can open.
///
/// Only the token is kept. The display name, the account id and whether the account is the owner are **not**
/// cached: they are asked for again on every launch through `GET /api/app/me`, because a stale name writes
/// somebody else's onto the screen and a stale token is exactly the thing the server has to be believed about.
struct WeFlixDeviceTokenStore {
    /// One key, one token, one device. A second WeFlix account on the same device replaces it.
    private static let tokenKey = "weflix.app.deviceToken"

    private let keychain: Keychain

    init(service: String? = nil) {
        keychain = Keychain(service: service ?? Bundle.main.bundleIdentifier ?? "me.weflix")
    }

    /// The last token this device stored, or `nil` when it has never signed in (or signed out).
    func token() -> String? {
        (try? keychain.string(forKey: Self.tokenKey)) ?? nil
    }

    /// Remember a fresh token. A Keychain that refuses is not fatal — the app simply asks for a sign-in again on
    /// the next launch — but the failure is reported so it does not go unnoticed.
    func save(_ token: String) {
        do {
            try keychain.setString(token, forKey: Self.tokenKey)
        } catch {
            ErrorReporter.capture(error)
        }
    }

    /// Forget it. Called on sign-out, and whenever the server refuses the token it held.
    func clear() {
        try? keychain.deleteValue(forKey: Self.tokenKey)
    }
}
