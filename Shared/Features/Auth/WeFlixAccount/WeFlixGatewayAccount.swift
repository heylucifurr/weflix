import Foundation

/// PHASE APP-GATEWAY: how a **WeFlix account** is recorded in the app's own account model, and how the two places
/// that would otherwise call plex.tv recognise one.
///
/// The app already has a shape for "a Plex-shaped server behind an account" — `MediaAccount.plex`, a `PlexHome`
/// profile and a `.plexHome(uuid:)` link — and the gateway answers exactly that shape. So a WeFlix sign-in reuses it
/// rather than adding a fourth provider to every `switch` in the session layer:
///
/// | What | Value | Why |
/// |---|---|---|
/// | account | `MediaAccount.plex(PlexAccount(id: "weflix:<user.id>"))` | the app's own model, unchanged |
/// | link user | `.plexHome(uuid: "weflix:<user.id>")` | `LinkedUser` has no WeFlix case, and the uuid is never sent to plex.tv |
/// | server | `ServerIdentity(provider: .plex, id: WeFlixServer.gatewayMachineIdentifier)` | one server, one host |
///
/// The **`weflix:` prefix is the marker** and the whole mechanism: `ServerRegistry.resolvePlex()` and
/// `connectPlex()` branch on it *before* they would ask plex.tv for servers or call `/switch`, which is what keeps a
/// gateway sign-in off plex.tv entirely. Anything else — a real plex.tv account — is untouched.
enum WeFlixGatewayAccount {
    /// The marker. A `PlexAccount.id` that starts with this is a WeFlix account, not a plex.tv uuid.
    static let prefix = "weflix:"

    /// The `PlexAccount.id` for a WeFlix user id, and the `uuid` its link carries.
    static func plexAccountID(for userID: String) -> String {
        prefix + userID
    }

    /// Is this the app's WeFlix account rather than one from plex.tv?
    static func isGateway(_ account: PlexAccount) -> Bool {
        account.id.hasPrefix(prefix)
    }

    /// The account for a signed-in WeFlix user. The name shown is what the server called the person.
    static func account(for user: WeFlixUser) -> MediaAccount {
        .plex(PlexAccount(
            id: plexAccountID(for: user.id),
            displayName: user.displayName.isEmpty ? "WeFlix" : user.displayName,
        ))
    }
}
