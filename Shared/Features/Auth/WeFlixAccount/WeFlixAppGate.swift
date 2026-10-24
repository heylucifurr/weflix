import SwiftUI

/// The app's root: **sign in to WeFlix, or already signed in** — and nothing else.
///
/// This is where the old entry point was. The root view used to ask `SessionManager` which Plex or Jellyfin
/// screen to show, and a fresh install landed on `AccountSetupView(purpose: .firstLaunch, …)` — the
/// "Choose a service" screen with the Plex and Jellyfin buttons. **That screen is no longer reachable**: the
/// app is a native client of the WeFlix server, it holds no Plex or Jellyfin credentials of its own, and it
/// never talks to plex.tv or to a media server directly (`docs/PROJECT.md`). The Plex and Jellyfin views, the
/// session machinery and the server-selection code are all still in the project — unused from here — until the
/// step that removes them; the settings and profile flows that still reference `AccountSetupView` are behind
/// this gate and cannot be reached either.
///
/// Three states, and the third is a spinner:
///
/// | Launch | What happens |
/// |---|---|
/// | no token in the Keychain | the sign-in screen, immediately |
/// | a token | `GET /api/app/me`, then the signed-in screen — or, on `401`, the token is forgotten and the sign-in screen returns |
/// | while that call is in flight | `ProfileActivationView`'s spinner |
struct WeFlixAppGate: View {
    @State private var session = WeFlixSessionController()

    var body: some View {
        content
            .task {
                // Once per launch. A re-render must not re-ask the server who we are.
                if case .checking = session.status {
                    await session.start()
                }
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
            WeFlixSignedInView(user: user, isWorking: session.isWorking) {
                Task { await session.signOut() }
            }
            .transition(.opacity)
        }
    }
}
