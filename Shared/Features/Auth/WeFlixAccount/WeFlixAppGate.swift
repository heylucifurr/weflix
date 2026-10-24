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
    @State private var session = WeFlixSessionController()
    /// The platform's own main UI — iOS's tabs, macOS's and tvOS's library roots. Shown only when the library is up.
    @ViewBuilder private let ready: () -> Ready

    init(@ViewBuilder ready: @escaping () -> Ready) {
        self.ready = ready
    }

    var body: some View {
        content
            .task {
                // Once per launch. A re-render must not re-ask the server who we are.
                if case .checking = session.status {
                    await session.start()
                }
            }
            // Adopting is idempotent (the account and the link are found already there), so this is safe to key on
            // the status: a sign-in adopts, and a relaunch adopts again for the token it already had.
            .task(id: session.status) {
                await adopt()
            }
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
            } else {
                WeFlixSignedInView(user: user, isWorking: session.isWorking) {
                    Task { await session.signOut() }
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

        await sessionManager.adoptWeFlixAccount(user: user, token: token)
        await WeFlixStreamTicketCache.shared.refreshIfNeeded(deviceToken: token)
    }
}
