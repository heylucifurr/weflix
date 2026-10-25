import SwiftUI

@MainActor
struct UserMenuView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(WeFlixSessionController.self) private var weflixSession
    @EnvironmentObject private var coordinator: MainCoordinator
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                NavigationLink {
                    SettingsView()
                } label: {
                    Label("settings.title", systemImage: "gearshape.fill")
                }

                if !settingsManager.interface.displayDownloadsTab {
                    NavigationLink {
                        DownloadsView()
                    } label: {
                        Label("downloads.title", systemImage: "arrow.down.circle.fill")
                    }
                }

                NavigationLink {
                    WatchlistView(onSelectMedia: { media in
                        dismiss()
                        coordinator.showMediaDetail(media)
                    })
                } label: {
                    Label("My Watchlist", systemImage: "bookmark.fill")
                }

                if !settingsManager.interface.displayFavoritesTab {
                    NavigationLink {
                        FavoritesView(
                            sessionManager: sessionManager,
                            onSelectMedia: { media in
                                dismiss()
                                coordinator.showMediaDetail(media)
                            },
                        )
                    } label: {
                        Label("tabs.favorites", systemImage: "star.fill")
                    }
                }
            }

            // **Sign out, not a profile switch** (Luther, 2026-10-25): the app holds one WeFlix account, and the
            // one useful action is the same sequence the signed-in card runs — tell the server, then forget the
            // account here. `WeFlixSessionController` is handed down by `WeFlixAppGate` for exactly this.
            Section {
                Button(role: .destructive) {
                    Task {
                        await weflixSession.signOut()
                        sessionManager.forgetWeFlixAccount()
                    }
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .disabled(weflixSession.isWorking)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(sessionManager.activeProfile?.name ?? String(localized: "tabs.more"))
    }
}

