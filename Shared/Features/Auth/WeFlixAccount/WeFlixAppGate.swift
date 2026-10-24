import SwiftUI

/// The app's root: **sign in to WeFlix, and then the real app** (PHASE APP-GATEWAY A4).
///
/// This is where the old entry point was. The root view used to ask `SessionManager` which Plex or Jellyfin
/// screen to show, and a fresh install landed on `AccountSetupView(purpose: .firstLaunch, …)` — the
/// "Choose a service" screen with the Plex and Jellyfin buttons. **That screen is no longer reachable**: the
/// app is a native client of the WeFlix server, it holds no Plex or Jellyfin credentials of its own, and it
/// never talks to plex.tv or to a media server directly (`docs/PROJECT.md`).
///
/// ## The handover
///
/// The gate owns two states and joins them:
///
/// | | What it is | Where it comes from |
/// |---|---|---|
/// | **signed in to WeFlix?** | an email and password, or a device token in the Keychain | `WeFlixSessionController` |
/// | **is the library up?** | the app's own account, profile and connected server | `SessionManager` |
///
/// A WeFlix sign-in is not on its own enough to show a library: the app needs an account, a profile and a server
/// session, which is what `SessionManager.adoptWeFlixAccount()` builds out of the sign-in (`weflix.me` as one
/// Plex-shaped server). So on `.signedIn` the gate adopts the account, and when `SessionManager` answers `.ready`
/// it hands the screen over to the platform's own main UI — `MainTabView` on iOS, the library root on macOS and
/// tvOS — passed in as `ready`. Until then the signed-in card (`WeFlixSignedInView`) says who is signed in and
/// offers sign-out, so a slow connection never looks like a dead end.
///
/// Three states before that, and the third is a spinner:
///
/// | Launch | What happens |
/// |---|---|
/// | no token in the Keychain | the sign-in screen, immediately |
/// | a token | `GET /api/app/me`, then the handover — or, on `401`, the token is forgotten and the sign-in screen returns |
/// | while that call is in flight | `ProfileActivationView`'s spinner |
struct WeFlixAppGate<Ready: View>: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(ServerRegistry.self) private var registry
    /// The requests, so the server's answer about them can be taken as it arrives (2026-10-25).
    ///
    /// **It is read here and used elsewhere**: the gate does not change what it shows because of requests. The
    /// signed-in screen is the library, and the requests appear inside it — the Seerr tab and the sidebar entry
    /// light up when `isRequestsEnabled` is true, exactly as they did before this work. That is deliberate: on
    /// 2026-10-25 an earlier version of this file made the *requests* the signed-in screen, which turned a
    /// server that did not yet have the feature into a dead end for every signed-in person.
    @Environment(SeerrStore.self) private var seerrStore
    @State private var session = WeFlixSessionController()
    /// The platform's own main UI — iOS's tabs, macOS's and tvOS's library roots. Shown only when the library is up.
    @ViewBuilder private let ready: () -> Ready

    init(@ViewBuilder ready: @escaping () -> Ready) {
        self.ready = ready
    }

    var body: some View {
        // The `ZStack` is load-bearing: `content` switches between three view *types* (a spinner, the sign-in form,
        // the signed-in states), and a `.task` attached directly to a view whose type changes is torn down and
        // started again — which reset `@State` (so `session` went back to `.checking`) and re-ran `start()` forever.
        // That is the loop that starved every other request (2026-10-24). One stable container, and the modifiers
        // below belong to something whose identity does not move.
        ZStack { content }
            .task {
                // Once per launch, and again after a "try again" tap.
                if case .checking = session.status {
                    await session.start()
                }
            }
            // Adoption follows the sign-in state, and `.onChange` is not scoped to the view's identity, so a
            // status change is exactly one adoption — never a restart of `start()`.
            .onChange(of: session.status, initial: true) { _, status in
                guard case .signedIn = status else { return }

                Task { await adopt() }
            }
            // A WeFlix sign-in that the server no longer accepts comes back to the sign-in screen with a sentence
            // instead of leaving the person on a home screen that says the server did not respond. Two sources: the
            // gateway marks its link `.needsReauthentication` on a `401`, and the requests proxy posts
            // `.weflixSignInEnded` from the one place its calls are validated.
            .onChange(of: weflixSignInHasEnded, initial: true) { _, hasEnded in
                guard hasEnded else { return }

                seerrStore.clear()
                session.reportSignInEnded()
            }
            .onReceive(NotificationCenter.default.publisher(for: .weflixSignInEnded)) { _ in
                seerrStore.clear()
                session.reportSignInEnded()
            }
            // The server's answer about requests is what the Seerr tab and the requests screens hang on, so it is
            // taken as it arrives — at launch, and again after a password sign-in. It changes nothing about what
            // this gate shows (see `seerrStore` above).
            .onChange(of: session.requests) { _, requests in
                Task { await seerrStore.adopt(requests: requests, displayName: session.displayName) }
            }
            // A sign-out must take the requests with it: the id, the quota and the name belong to the account that
            // just left.
            .onChange(of: isSignedOut) { _, signedOut in
                guard signedOut else { return }

                seerrStore.clear()
            }
    }

    /// Is the app looking at anything but a signed-in screen? Used to take the requests down with a sign-out.
    private var isSignedOut: Bool {
        if case .signedIn = session.status { return false }

        return true
    }

    /// Has the server refused the WeFlix account's token? (`ServerRegistry` marks the link `.needsReauthentication`
    /// when a request is answered `401`, and when the account has no token to connect with at all.)
    private var weflixSignInHasEnded: Bool {
        guard let account = sessionManager.accounts.first(where: {
            $0.plexAccount.map(WeFlixGatewayAccount.isGateway) == true
        })
        else { return false }

        return registry.linkStatuses[account.id] == .needsReauthentication
    }

    @ViewBuilder
    private var content: some View {
        switch session.status {
        case .checking:
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .signedOut:
            WeFlixSignInView(session: session)
        case let .signedIn(user):
            if sessionManager.status == .ready {
                ready()
                    .transition(.opacity)
            } else if let profile = sessionManager.activeProfile {
                // The app's own activation screen: it names the profile and the phase it is in, so a slow
                // connection reads as "working on it" rather than as a dead end.
                ProfileActivationView(profile: profile)
                    .transition(.profileActivation)
            } else {
                WeFlixSignedInView(user: user, isWorking: session.isWorking) {
                    Task {
                        await session.signOut()
                        // The account, its link and its token go with the sign-out: leaving them behind is how a
                        // second person's sign-in ended up on the first person's profile (2026-10-24).
                        sessionManager.forgetWeFlixAccount()
                    }
                }
                .transition(.opacity)
            }
        }
    }

    /// Turn the WeFlix sign-in into a library: the account, its link, and a connected `weflix.me` server.
    ///
    /// Nothing on this path talks to plex.tv — `SessionManager.adoptWeFlixAccount()` branches before both of the
    /// calls that would (`ServerRegistry.resolvePlex`/`connectPlex`). The stream ticket is fetched here, where the
    /// app already has an `await`, so a film started from the library has one in hand.
    private func adopt() async {
        guard case let .signedIn(user) = session.status,
              let token = WeFlixDeviceTokenStore().token()
        else { return }

        let adopted = await sessionManager.adoptWeFlixAccount(user: user, token: token)
        await WeFlixStreamTicketCache.shared.refreshIfNeeded(deviceToken: token)
    }
}
