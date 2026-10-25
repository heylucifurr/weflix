import SwiftUI

@MainActor
struct SettingsView: View {
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(LibraryStore.self) private var libraryStore
    @Environment(SessionManager.self) private var sessionManager
    @Environment(WeFlixSessionController.self) private var weflixSession

    /// The **owner**'s settings. A friend's app is the same app, but the interface section, the integrations
    /// section and the licence notice belong to whoever runs the server (Luther, 2026-10-25).
    private var isOwner: Bool {
        weflixSession.isOwner
    }

    var body: some View {
        List {
            if sessionManager.canManageAccounts {
                Section {
                    NavigationLink("settings.accounts.title") {
                        AccountsSettingsView()
                    }
                    // Profiles are a Plex Home / local-profile idea the WeFlix client no longer manages from
                    // Settings on iPhone (Luther, 2026-10-25). The Mac keeps the entry.
                    #if os(macOS)
                        NavigationLink("profiles.title") {
                            ProfilesSettingsView()
                        }
                    #endif
                }
            }

            Section {
                NavigationLink("settings.playback.title") {
                    SettingsPlaybackView()
                }

                NavigationLink("settings.playback.audio.title") {
                    SettingsAudioView()
                }

                NavigationLink("settings.playback.subtitles.title") {
                    SettingsSubtitlesView()
                }

                if isOwner {
                    NavigationLink("settings.interface.title") {
                        SettingsInterfaceView(
                            settingsManager: settingsManager,
                            libraryStore: libraryStore,
                        )
                    }
                }

                #if os(macOS)
                    NavigationLink("settings.downloads.title") {
                        SettingsDownloadsView()
                    }
                    NavigationLink("settings.storage.title") {
                        SettingsStorageView()
                    }
                    if isOwner {
                        NavigationLink("settings.integrations.title") {
                            IntegrationsView()
                        }
                    }
                #endif
            }

            #if os(iOS)
                Section("settings.downloads.title") {
                    NavigationLink("settings.downloads.manage") {
                        SettingsDownloadsView()
                    }

                    NavigationLink("settings.storage.title") {
                        SettingsStorageView()
                    }
                }

                if isOwner {
                    Section("settings.integrations.title") {
                        NavigationLink("settings.integrations.manage") {
                            IntegrationsView()
                        }
                    }
                }
            #endif

            // GPL-3.0: a modified version has to say what it came from, and the app says it here as well as in
            // `README.md` (`LicencesView`). The owner sees it.
            if isOwner {
                Section {
                    NavigationLink("Licences") {
                        LicencesView()
                    }
                }
            }
        }
        #if os(iOS)
            .listStyle(.insetGrouped)
        #endif
        .navigationTitle("settings.title")
    }
}
