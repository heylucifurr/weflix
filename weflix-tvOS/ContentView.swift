import SwiftUI

struct ContentView: View {
    init() {
        ErrorReporter.start()
    }

    var body: some View {
        ZStack {
            Color("Background").ignoresSafeArea()

            // 2026-10-24 — this is where "Choose a service" used to be. A fresh install landed on
            // `AccountSetupView(purpose: .firstLaunch, …)` and picked Plex or Jellyfin from there; the app is a
            // native client of the **WeFlix server** now (`docs/PROJECT.md`), so the root is a WeFlix sign-in.
            // Signing in hands over to `WeFlixReadyView` below, which is this platform's library UI.
            WeFlixAppGate {
                WeFlixReadyView()
            }
        }
    }
}

/// The library, once the WeFlix session has adopted its account and a server is up (PHASE APP-GATEWAY A4).
///
/// It is the same `MainTabView` the app has always shown for a connected server — only reachable now through a
/// WeFlix sign-in instead of a Plex or Jellyfin one. The Plex/Jellyfin root below is kept, and stays unreachable.
private struct WeFlixReadyView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(ServerRegistry.self) private var registry
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(LibraryStore.self) private var libraryStore

    var body: some View {
        MainTabView(
            homeViewModel: HomeViewModel(sessionManager: sessionManager, settingsManager: settingsManager),
            libraryViewModel: LibraryViewModel(
                sessionManager: sessionManager,
                libraryStore: libraryStore,
                settingsManager: settingsManager,
            ),
            settingsManager: settingsManager,
        )
        .id(registry.generation)
    }
}

/// The Plex/Jellyfin root this app had before it became a WeFlix client (2026-10-24).
///
/// **Kept, and deliberately not reachable.** `ContentView` shows `WeFlixAppGate()` instead: the app holds no
/// Plex or Jellyfin credentials of its own any more and never talks to plex.tv or to a media server directly.
/// This view stays compiled — so it cannot rot unnoticed — beside the Plex and Jellyfin code it uses, until the
/// step that removes them.
private struct PlexLibraryRootView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(ServerRegistry.self) private var registry
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(LibraryStore.self) private var libraryStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Color("Background").ignoresSafeArea()

            switch sessionManager.status {
            case .hydrating:
                if let profile = sessionManager.activeProfile {
                    ProfileActivationView(profile: profile)
                        .transition(.profileActivation)
                } else {
                    ProgressView(sessionManager.loadingPhase.title)
                        .progressViewStyle(.circular)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            case .needsAccount:
                AccountSetupView(purpose: .firstLaunch, sessionManager: sessionManager)
            case .needsProfileSelection:
                NavigationStack {
                    ProfileSwitcherView(viewModel: ProfileSwitcherViewModel(sessionManager: sessionManager))
                }
            case .migrationFailed:
                MigrationFailedView()
            case .ready:
                MainTabView(
                    homeViewModel: HomeViewModel(sessionManager: sessionManager, settingsManager: settingsManager),
                    libraryViewModel: LibraryViewModel(
                        sessionManager: sessionManager,
                        libraryStore: libraryStore,
                        settingsManager: settingsManager,
                    ),
                    settingsManager: settingsManager,
                )
                .id(registry.generation)
            }
        }
        .onChange(of: registry.readyServers) { _, _ in
            sessionManager.updateTopShelf()
        }
        .onChange(of: sessionManager.status) { _, status in
            if status != .ready {
                sessionManager.updateTopShelf()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                registry.retryUnavailable()
            }
        }
    }
}

