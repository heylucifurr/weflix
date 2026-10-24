import SwiftUI

/// What the app shows once a WeFlix account is signed in: **the requests** (2026-10-25).
///
/// This is the main screen, and it replaced the library as the signed-in root — deliberately, because it is what
/// a friend can actually use today: browse what is trending and popular, search a title, ask for it, and see
/// their own requests and their quota. Library browsing comes in a later task, and until it does the app must
/// not open on a home screen that needs a Plex-shaped gateway to say anything.
///
/// Three things it does, and nothing else:
///
/// | | |
/// |---|---|
/// | **requests on** | the existing discover/search experience (`SeerrDiscoverView` → detail → request sheet) and the requests list, unchanged — only what is behind them changed |
/// | **requests off** | the server's own sentence, and a *Try again* — an account that has not been linked yet reads as exactly that rather than as an empty screen |
/// | **always** | a Sign Out action, and a way into Settings, which is where "Requests — connected via WeFlix" and the licence notice live |
///
/// There is no Overseerr setup here and no address to type: the app talks to `https://weflix.me` and the server
/// decides the rest (`SeerrStore`). tvOS gets a two-tab layout (Requests, Settings) because a remote has no
/// toolbar to hang a menu off; iOS, iPadOS and macOS get a `NavigationStack` with both actions in the toolbar.
@MainActor
struct WeFlixRequestsRootView: View {
    @Environment(SeerrStore.self) private var seerrStore
    @Environment(SessionManager.self) private var sessionManager
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let session: WeFlixSessionController

    /// tvOS's own navigation state for the requests tab, and the focus model its cards use. Built here rather
    /// than inherited from `MainTabView`, which this screen replaces on that platform.
    @StateObject private var coordinator: MainCoordinator
    @State private var tvOSTab: RequestsTab = .requests
    #if !os(tvOS)
        @State private var path = NavigationPath()
        @State private var isShowingSettings = false
    #endif
    @State private var isSigningOut = false

    private enum RequestsTab: Hashable {
        case requests
        case settings
    }

    init(session: WeFlixSessionController, settingsManager: SettingsManager) {
        self.session = session
        _coordinator = StateObject(wrappedValue: MainCoordinator(settingsManager: settingsManager))
    }

    var body: some View {
        #if os(tvOS)
            tvOSBody
        #else
            standardBody
        #endif
    }

    /* ---------------------------------------------------------------------- */
    /* iOS, iPadOS, macOS                                                      */
    /* ---------------------------------------------------------------------- */

    #if !os(tvOS)
        private var standardBody: some View {
            NavigationStack(path: $path) {
                content
                    .navigationTitle("seerr.requests.title")
                    #if os(iOS)
                        .navigationBarTitleDisplayMode(.inline)
                    #endif
                    .navigationDestination(for: SeerrMedia.self) { media in
                        SeerrMediaDetailView(
                            viewModel: SeerrMediaDetailViewModel(media: media, store: seerrStore),
                            onSelectMedia: { path.append($0) },
                        )
                    }
                    .navigationDestination(for: SeerrRequestsRoute.self) { _ in
                        SeerrRequestsView(
                            viewModel: SeerrRequestsViewModel(store: seerrStore),
                            onSelectMedia: { path.append($0) },
                        )
                    }
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            accountMenu
                        }
                    }
            }
            .sheet(isPresented: $isShowingSettings) {
                NavigationStack {
                    SettingsView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("common.actions.done") { isShowingSettings = false }
                            }
                        }
                }
            }
        }

        /// The one place both actions live, as a menu: the account's own name first, then Settings, then the way
        /// out. A toolbar has room for one control, and this is the control that keeps Sign Out reachable on
        /// every screen of the stack.
        private var accountMenu: some View {
            Menu {
                if !session.displayName.isEmpty {
                    Text(session.displayName)
                }

                Button {
                    isShowingSettings = true
                } label: {
                    Label("settings.title", systemImage: "gearshape")
                }

                Divider()

                Button(role: .destructive, action: signOut) {
                    Label("accounts.actions.signOut", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .disabled(isSigningOut)
            } label: {
                Image(systemName: "person.crop.circle")
                    .accessibilityLabel(Text("settings.title"))
            }
        }
    #endif


    /* ---------------------------------------------------------------------- */
    /* the two states                                                          */
    /* ---------------------------------------------------------------------- */

    @ViewBuilder
    private var content: some View {
        if seerrStore.isRequestsEnabled {
            #if os(tvOS)
                tvOSDiscover
            #else
                discover
            #endif
        } else if seerrStore.isHydrating {
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            notSetUp
        }
    }

    #if !os(tvOS)
        /// The existing discover experience, unchanged: trending, popular and upcoming rails, a search field, and
        /// the way into the requests list — all of it now answered by `https://weflix.me/api/app/seerr`.
        private var discover: some View {
            SeerrDiscoverView(
                viewModel: SeerrDiscoverViewModel(store: seerrStore),
                searchViewModel: SeerrSearchViewModel(store: seerrStore),
                onSelectMedia: { path.append($0) },
                onShowRequests: { path.append(SeerrRequestsRoute()) },
            )
            .unavailableWhenOffline()
        }
    #endif

    /// An account the server has not linked to an Overseerr user — or a deployment with no Seerr at all.
    ///
    /// The sentence is the server's own (`lib/app-seerr-routes.ts`'s `409`), because it names the one person who
    /// can fix it, and *Try again* is here rather than nowhere: Luther links the account, the friend taps it, and
    /// the app asks `GET /api/app/me` once more.
    private var notSetUp: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray.full.fill")
                .font(.system(size: 44))
                .foregroundStyle(.textSecondary)

            Text("Requests aren't set up for your account yet. Ask Luther.")
                .font(.bodyText)
                .foregroundStyle(.textSecondary)
                .multilineTextAlignment(.center)

            Button("Try again") {
                Task { await session.refreshRequests() }
            }
            .actionButtonStyle(.primary)
            .controlSize(.large)
        }
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    /* ---------------------------------------------------------------------- */
    /* tvOS                                                                    */
    /* ---------------------------------------------------------------------- */

    #if os(tvOS)
        private var tvOSBody: some View {
            TabView(selection: $tvOSTab) {
                Tab("seerr.requests.title", systemImage: "sparkles", value: RequestsTab.requests) {
                    NavigationStack(path: coordinator.pathBinding(for: .seerrDiscover)) {
                        content
                            .navigationDestination(for: SeerrRequestsRoute.self) { _ in
                                SeerrRequestsView(
                                    viewModel: SeerrRequestsViewModel(store: seerrStore),
                                    onSelectMedia: coordinator.showSeerrMediaDetail,
                                )
                            }
                            .navigationDestination(for: SeerrMedia.self) { media in
                                SeerrMediaDetailView(
                                    viewModel: SeerrMediaDetailViewModel(media: media, store: seerrStore),
                                )
                            }
                    }
                    .environmentObject(coordinator)
                }

                Tab("settings.title", systemImage: "gearshape.fill", value: RequestsTab.settings) {
                    NavigationStack {
                        SettingsView(canManageAccounts: false)
                            .toolbar {
                                ToolbarItem(placement: .primaryAction) {
                                    Button("accounts.actions.signOut", action: signOut)
                                        .disabled(isSigningOut)
                                }
                            }
                    }
                }
            }
            // `MainCoordinator.showSeerrRequests()` only appends on the discover tab, and this screen has exactly
            // that tab — so the requests route has to be the coordinator's own, or the entry does nothing.
            .onAppear { coordinator.tab = .seerrDiscover }
        }

        /// tvOS's own discover screen (its hero, its focus engine and its remote-driven rails), because that is
        /// the platform's requests experience and the shared one is iOS and macOS's.
        private var tvOSDiscover: some View {
            SeerrDiscoverView(
                viewModel: SeerrDiscoverViewModel(store: seerrStore),
                onSelectMedia: coordinator.showSeerrMediaDetail,
            )
        }
    #endif

    /* ---------------------------------------------------------------------- */
    /* signing out                                                             */
    /* ---------------------------------------------------------------------- */

    /// Sign out: the server is told, the Keychain is cleared, the account and its link are forgotten, and the
    /// requests go with them — leaving any of that behind is how a second person's sign-in ended up on the first
    /// person's profile (2026-10-24).
    private func signOut() {
        guard !isSigningOut else { return }

        isSigningOut = true

        Task {
            await session.signOut()
            seerrStore.clear()
            sessionManager.forgetWeFlixAccount()
            isSigningOut = false
        }
    }
}

