import SwiftUI

@MainActor
struct SettingsView: View {
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(LibraryStore.self) private var libraryStore
    @Environment(SessionManager.self) private var sessionManager

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

                NavigationLink("settings.interface.title") {
                    SettingsInterfaceView(
                        settingsManager: settingsManager,
                        libraryStore: libraryStore,
                    )
                }

                #if os(macOS)
                    NavigationLink("settings.downloads.title") {
                        SettingsDownloadsView()
                    }
                    NavigationLink("settings.storage.title") {
                        SettingsStorageView()
                    }
                    NavigationLink("settings.integrations.title") {
                        IntegrationsView()
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

                Section("settings.integrations.title") {
                    NavigationLink("settings.integrations.manage") {
                        IntegrationsView()
                    }
                }
            #endif

            // GPL-3.0: a modified version has to say what it came from, and the app says it here as well as in
            // `README.md` (`LicencesView`). Not behind a debug flag and not only on macOS — it is the licence.
            Section {
                NavigationLink("Licences") {
                    LicencesView()
                }
            }
        }
        #if os(iOS)
            .listStyle(.insetGrouped)
        #endif
        .navigationTitle("settings.title")
    }
}
