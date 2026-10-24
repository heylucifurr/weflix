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
            // native client of the **WeFlix server** now (`docs/PROJECT.md`), so the root is a WeFlix sign-in
            // and nothing else. The Plex/Jellyfin root that used to be here is kept below, unreachable.
            WeFlixAppGate()
        }
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
    @Environment(DownloadManager.self) private var downloadManager
    @Environment(OfflineCoordinator.self) private var offlineCoordinator
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Color("Background").ignoresSafeArea()

            if showsStaticDownloads {
                OfflineDownloadsRootView()
            } else {
                switch sessionManager.status {
                case .hydrating:
                    if let profile = sessionManager.activeProfile {
                        ProfileActivationView(profile: profile)
                            .transition(.profileActivation)
                    } else {
                        ProgressView(sessionManager.loadingPhase.title)
                            .progressViewStyle(.circular)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        }
        .onChange(of: offlineCoordinator.availability.hasNetworkPath) { _, hasNetworkPath in
            guard hasNetworkPath, sessionManager.status == .migrationFailed else { return }
            Task {
                await sessionManager.hydrate()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                offlineCoordinator.availability.refresh()
                registry.retryUnavailable()
            case .background:
                offlineCoordinator.evictCacheIfNeeded()
            case .inactive:
                break
            @unknown default:
                break
            }
        }
        .onChange(of: settingsManager.downloads.offlineCacheLimitMB, initial: true) { _, megabytes in
            offlineCoordinator.setCacheLimit(megabytes: megabytes)
        }
        .onChange(of: registry.connectedServices.map(ObjectIdentifier.init), initial: true) { _, _ in
            downloadManager.activateSession(services: registry.connectedServices)
        }
    }

    /// Without a restorable session and without network, downloads are shown directly at launch.
    private var showsStaticDownloads: Bool {
        guard !offlineCoordinator.availability.hasNetworkPath, downloadManager.playableCount > 0 else { return false }
        switch sessionManager.status {
        case .needsAccount, .migrationFailed:
            return true
        case .hydrating, .needsProfileSelection, .ready:
            return false
        }
    }
}

