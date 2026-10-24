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

    /// The app's picture of the one WeFlix server — `weflix.me`, as `ServerRegistry` builds it.
    ///
    /// It carries **no connections and no access token**: there is nothing to discover and the credential lives in
    /// the account store, so this is a name and an identifier and nothing else.
    static var server: PlexCloudResource {
        PlexCloudResource(
            name: "WeFlix",
            clientIdentifier: WeFlixServer.gatewayMachineIdentifier,
            accessToken: nil,
            connections: nil,
        )
    }

    /// The app's **identity for one WeFlix account's server**.
    ///
    /// One per account, and that is the point: `ServerIdentity` is the key the registry stores a connected server
    /// under, so two WeFlix accounts sharing one key meant the second one found the first one's entry already there
    /// and connected with **the first account's token** — which is how a sign-in as one person produced another
    /// person's (dead) server (Luther, 2026-10-24). The machine identifier the client *reports* stays
    /// `WeFlixServer.gatewayMachineIdentifier`, because that is what the gateway answers in `/identity`.
    static func serverIdentity(for userID: String) -> ServerIdentity {
        ServerIdentity(provider: .plex, id: "\(WeFlixServer.gatewayMachineIdentifier).\(userID)")
    }
}

/// Which profile a WeFlix sign-in lands on — and the reason it is a separate, pure decision.
///
/// A profile in this app **is a person**, and a WeFlix account is one person. So the profile is the one already
/// linked to *that account*, never "whichever profile was active": on 2026-10-24 Luther signed in as a second
/// WeFlix user and the app put him on the first user's profile — the icon, the Profiles list and the name at the
/// top all said the other person, because adoption reused `activeProfile`.
///
/// Kept as a function over plain values so the rule can be tested without a store, a registry or a network.
enum WeFlixProfileChoice: Equatable {
    /// The profile this account is already linked to. `renameTo` is set when that profile is still carrying
    /// somebody else's name — the repair for the state the bug left behind.
    case reuse(profileID: String, renameTo: String?)
    /// The first time this account signs in on this device: a profile of its own, named after the person.
    case create(name: String)
}

extension WeFlixGatewayAccount {
    /// The choice, given the profiles the app knows and the links each one has.
    static func profileChoice(
        accountID: String,
        displayName: String,
        profiles: [WeFlixProfile],
        links: (WeFlixProfile) -> [ProfileLink],
    ) -> WeFlixProfileChoice {
        let name = displayName.isEmpty ? "WeFlix" : displayName

        for profile in profiles where links(profile).contains(where: { $0.accountID == accountID }) {
            let ownLinks = links(profile)
            // Only a **local** profile that this account is the *only* thing linked to is renamed, because that is
            // one an earlier adoption created for this account and left the previous person's name on. A local
            // profile several accounts share (the Jellyfin pattern) and a Plex Home profile are never renamed.
            let renameable = profile.isLocal && profile.name != name && ownLinks.count == 1

            return .reuse(profileID: profile.id, renameTo: renameable ? name : nil)
        }

        return .create(name: name)
    }
}
