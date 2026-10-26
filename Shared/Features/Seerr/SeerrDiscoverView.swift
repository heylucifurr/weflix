import SwiftUI

@MainActor
struct SeerrDiscoverView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(SettingsManager.self) private var settingsManager
    @State var viewModel: SeerrDiscoverViewModel
    @State var searchViewModel: SeerrSearchViewModel
    let onSelectMedia: (SeerrMedia) -> Void
    let onShowRequests: () -> Void

    init(
        viewModel: SeerrDiscoverViewModel,
        searchViewModel: SeerrSearchViewModel,
        onSelectMedia: @escaping (SeerrMedia) -> Void = { _ in },
        onShowRequests: @escaping () -> Void = {},
    ) {
        _viewModel = State(initialValue: viewModel)
        _searchViewModel = State(initialValue: searchViewModel)
        self.onSelectMedia = onSelectMedia
        self.onShowRequests = onShowRequests
    }

    /// The rail whose heading is open, if any — the same shape Home uses for its rows (`HomeView.selectedHub`).
    @State private var selectedRail: SeerrDiscoverRail?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if searchViewModel.isSearchActive {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(searchViewModel.searchResults, id: \.id) { media in
                            SeerrSearchCard(media: media) {
                                onSelectMedia(media)
                            }
                        }
                    }
                } else {
                    requestsEntry

                    // Luther's four rails, in his order (2026-10-26). The last one is **one** rail over two routes:
                    // the two upcoming ones are merged, so they are no longer two headings.
                    rail(.trending, items: viewModel.trending)
                    rail(.popularMovies, items: viewModel.popularMovies)
                    rail(.popularTVShows, items: viewModel.popularTVShows)
                    rail(.upcomingMoviesAndTVShows, items: viewModel.upcomingMoviesAndTVShows)
                }

                if viewModel.isLoading, !viewModel.hasContent, !searchViewModel.isSearchActive {
                    VStack(alignment: .leading, spacing: 24) {
                        ForEach(0 ..< 3, id: \.self) { _ in
                            SectionSkeleton(showsLabels: settingsManager.interface.showsCardLabels)
                        }
                    }
                }

                if let errorMessage = activeErrorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                } else if !viewModel.hasContent, !viewModel.isLoading, !searchViewModel.isSearchActive {
                    Text("common.empty.nothingToShow")
                        .foregroundStyle(.textSecondary)
                } else if searchViewModel.isSearchActive,
                          !searchViewModel.isSearching,
                          searchViewModel.searchResults.isEmpty
                {
                    Text("common.empty.nothingToShow")
                        .foregroundStyle(.textSecondary)
                }
            }
            .padding(.horizontal, LayoutMetrics.pageMargin)
            .padding(.vertical, 20)
        }
        .navigationTitle("tabs.discover")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .task {
                await viewModel.load()
            }
            .onAppear {
                Task { await viewModel.refreshIfNeeded() }
            }
            .onChange(of: scenePhase) { _, newValue in
                guard newValue == .active else { return }
                Task { await viewModel.refreshIfNeeded() }
            }
            .task(id: searchViewModel.searchQuery) {
                await searchViewModel.search()
            }
            .refreshable {
                if searchViewModel.isSearchActive {
                    await searchViewModel.search()
                } else {
                    await viewModel.reload()
                }
            }
        #if os(iOS)
            .searchable(
                text: $searchViewModel.searchQuery,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: Text("integrations.seerr.search.placeholder"),
            )
        #else
            .searchable(
                text: $searchViewModel.searchQuery,
                prompt: Text("integrations.seerr.search.placeholder"),
            )
        #endif
            // The rail's own screen, presented the way Home presents one of its rows: a sheet, with the rail's
            // title over a grid that pages in more as the last card is reached.
            .sheet(item: $selectedRail) { rail in
                NavigationStack {
                    SeerrDiscoverRailView(
                        viewModel: SeerrDiscoverRailViewModel(rail: rail),
                        onSelectMedia: { media in
                            selectedRail = nil
                            onSelectMedia(media)
                        },
                    )
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("hub.close") {
                                selectedRail = nil
                            }
                        }
                    }
                }
            }
    }

    private var requestsEntry: some View {
        Button(action: onShowRequests) {
            HStack(spacing: 12) {
                Image(systemName: "tray.full.fill")
                    .font(.title3)
                    .foregroundStyle(.textSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("seerr.requests.title")
                        .font(.rowTitle)
                    if viewModel.requestsBadgeCount > 0 {
                        Text(String(localized: "seerr.requests.pendingCount \(viewModel.requestsBadgeCount)"))
                            .font(.cardMetadata)
                            .foregroundStyle(.textSecondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .glassSurface(in: RoundedRectangle(cornerRadius: LayoutMetrics.cardCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// One rail: **hidden when it is empty**, and its heading opens the whole rail.
    ///
    /// The heading is a `MediaHubSection.onViewAll` button — the title with a chevron beside it and the
    /// `hub.viewAll` accessibility label — which is the mechanism Home's "Recently Added in …" rows already use.
    /// Luther pointed at that behaviour, so Discover reuses it rather than growing a second pattern.
    @ViewBuilder
    private func rail(_ rail: SeerrDiscoverRail, items: [SeerrMedia]) -> some View {
        if !items.isEmpty {
            MediaHubSection(title: rail.title, onViewAll: { selectedRail = rail }) {
                SeerrMediaCarousel(
                    items: items,
                    showsLabels: settingsManager.interface.showsCardLabels,
                    onSelectMedia: onSelectMedia,
                )
            }
        }
    }

    private var activeErrorMessage: String? {
        if searchViewModel.isSearchActive {
            return searchViewModel.errorMessage
        }
        return viewModel.errorMessage
    }
}
