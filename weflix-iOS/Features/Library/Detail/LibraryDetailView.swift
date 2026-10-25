import SwiftUI

struct LibraryDetailView: View {
    @Environment(MediaServices.self) private var mediaServices
    @Environment(SettingsManager.self) private var settingsManager
    let library: Library
    let onSelectMedia: (MediaDisplayItem) -> Void

    @State private var selectedTab: LibraryDetailTab = .recommended
    @State private var browseSession = LibraryBrowseSession()
    /// The browse screen's model, owned **here** rather than inside `LibraryBrowseView`.
    ///
    /// It has to be: the browse filter pills belong to the one row at the top of this screen, and there is no
    /// longer a Browse chip to reach them from (Luther, 2026-10-25 — *"1 combined filter"*). Created on first
    /// appearance, because its dependencies are environment values.
    @State private var browseViewModel: LibraryBrowseViewModel?

    init(
        library: Library,
        onSelectMedia: @escaping (MediaDisplayItem) -> Void = { _ in },
    ) {
        self.library = library
        self.onSelectMedia = onSelectMedia
        _selectedTab = State(
            initialValue: library.type == .collection || library.type == .playlist ? .browse : .recommended,
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            filterRow

            Group {
                if let browseViewModel, selectedTab == .browse {
                    LibraryBrowseView(
                        viewModel: browseViewModel,
                        onSelectMedia: onSelectMedia,
                        showsControlsRow: false,
                    )
                } else {
                    switch selectedTab {
                    case .recommended:
                        LibraryRecommendedView(
                            viewModel: LibraryRecommendedViewModel(
                                library: library,
                                services: mediaServices,
                            ),
                            onSelectMedia: onSelectMedia,
                        )
                    case .browse:
                        Color.clear
                    case .collections:
                        LibraryCollectionsView(
                            viewModel: LibraryCollectionsViewModel(
                                library: library,
                                services: mediaServices,
                            ),
                            onSelectMedia: onSelectMedia,
                        )
                    case .playlists:
                        LibraryPlaylistsView(
                            viewModel: LibraryPlaylistsViewModel(
                                library: library,
                                services: mediaServices,
                            ),
                            onSelectMedia: onSelectMedia,
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationTitle(library.title)
        .toolbarTitleDisplayMode(.inline)
        .task {
            guard browseViewModel == nil else { return }

            let model = LibraryBrowseViewModel(
                library: library,
                services: mediaServices,
                settingsManager: settingsManager,
                browseSession: browseSession,
            )
            // Using a pill means "show me the grid": that is what the removed Browse chip used to do.
            model.controls.onUserInteraction = { showBrowse() }
            browseViewModel = model

            /*
             * And load the section **now**, not when the grid appears.
             *
             * The display type, the filters and the sorts only arrive with a browse fetch (`applyMeta`), and they
             * are what the pills in this row are made of. Waiting for the grid meant the row showed
             * `Recommended · 🔳` — nothing to filter with and no way in (Luther's screenshot, 2026-10-25).
             * `load()` fetches once, so the grid's own `.task` becomes a no-op rather than a second request.
             */
            await model.load()
        }
        .onChange(of: settingsManager.interface.displayCollections) { _, displayCollections in
            if !displayCollections, selectedTab == .collections {
                selectedTab = .recommended
            }
        }
        .onChange(of: settingsManager.interface.displayPlaylists) { _, displayPlaylists in
            if !displayPlaylists, selectedTab == .playlists {
                selectedTab = .recommended
            }
        }
    }

    /// **One** row: the chips, then the browse filter pills in the same scroll view.
    ///
    /// `Recommended · Movies · Filter · Sort · 🔳` — no Browse chip, and no Collections or Playlists chips (both
    /// asked for on 2026-10-25; Collections and Playlists keep their other doors on the Libraries screen and the
    /// rails). A collection or a playlist library has no rails to recommend, so it shows the pills alone.
    @ViewBuilder
    private var filterRow: some View {
        if let browseViewModel {
            let model = browseViewModel

            LibraryDetailTabPicker(selection: $selectedTab, tabs: tabChips) {
                LibraryBrowsePillsRow(
                    viewModel: model.controls,
                    showsBackButton: model.canNavigateBack,
                    onNavigateBack: model.navigateBack,
                    leadingToggle: leadingToggle(for: model),
                    showsServerControls: model.showsServerControls,
                    isTypePillSelected: selectedTab == .browse,
                    layoutToggle: .layout(current: model.layout) { layout in
                        model.setLayout(layout)
                        showBrowse()
                    },
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
    }

    /// The chips that survive: `Recommended`, and only where there is something to recommend.
    private var tabChips: [LibraryDetailTab] {
        if library.type == .collection || library.type == .playlist {
            return []
        }
        return [.recommended]
    }

    private func showBrowse() {
        guard selectedTab != .browse else { return }
        withAnimation(Motion.crossfade) {
            selectedTab = .browse
        }
    }

    private func leadingToggle(for model: LibraryBrowseViewModel) -> LibraryBrowseToggle? {
        guard model.showsDownloadedOnlyToggle else { return nil }
        return LibraryBrowseToggle(
            title: String(localized: "offline.library.downloadedOnly"),
            systemImage: "arrow.down.circle",
            isSelected: model.isDownloadedOnly,
            action: {
                model.toggleDownloadedOnly()
                showBrowse()
            },
        )
    }
}
