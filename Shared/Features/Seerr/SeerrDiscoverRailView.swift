import SwiftUI

/// A Discover heading, opened: the whole rail as a grid, a page at a time.
///
/// It mirrors `HubDetailView` — same `PosterGrid`, same load-more-on-the-last-card, same skeleton, empty and error
/// states — because Luther asked for it to behave "similar home where Recently Added in Movies is clickable and it
/// loads more list". What differs is only what feeds it: `SeerrDiscoverRailViewModel`, which pages Seerr by page
/// number and keeps the rail's own in-library filter.
@MainActor
struct SeerrDiscoverRailView: View {
    @Environment(SettingsManager.self) private var settingsManager
    @State var viewModel: SeerrDiscoverRailViewModel
    let onSelectMedia: (SeerrMedia) -> Void

    init(
        viewModel: SeerrDiscoverRailViewModel,
        onSelectMedia: @escaping (SeerrMedia) -> Void = { _ in },
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onSelectMedia = onSelectMedia
    }

    var body: some View {
        ScrollView {
            PosterGrid(spacing: columnSpacing, rowSpacing: gridSpacing) { cardWidth in
                if viewModel.isLoading, viewModel.isEmpty {
                    PosterSkeletonCards(width: cardWidth, showsLabels: settingsManager.interface.showsCardLabels)
                }

                ForEach(viewModel.items, id: \.id) { media in
                    SeerrMediaCard(
                        media: media,
                        width: cardWidth,
                        showsLabels: settingsManager.interface.showsCardLabels,
                    ) {
                        onSelectMedia(media)
                    }
                    .task {
                        await viewModel.loadMoreIfNeeded(currentItem: media)
                    }
                }

                if viewModel.isLoadingMore {
                    ProgressView()
                        .frame(width: cardWidth)
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
        }
        .navigationTitle(Text(LocalizedStringKey(viewModel.rail.titleKey)))
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .overlay {
                if viewModel.isLoading, viewModel.isEmpty {
                    EmptyView()
                } else if let errorMessage = viewModel.errorMessage, viewModel.isEmpty {
                    ContentUnavailableView(
                        errorMessage,
                        systemImage: "exclamationmark.triangle.fill",
                        description: Text("common.errors.tryAgainLater"),
                    )
                    .symbolRenderingMode(.multicolor)
                } else if viewModel.isEmpty, !viewModel.isLoading {
                    ContentUnavailableView(
                        "hub.empty",
                        systemImage: "square.grid.2x2.fill",
                    )
                }
            }
            .task {
                await viewModel.load()
            }
    }

    private var columnSpacing: CGFloat {
        #if os(tvOS)
            32
        #else
            12
        #endif
    }

    private var gridSpacing: CGFloat {
        #if os(tvOS)
            32
        #else
            16
        #endif
    }

    private var horizontalPadding: CGFloat {
        #if os(tvOS)
            48
        #else
            16
        #endif
    }

    private var verticalPadding: CGFloat {
        #if os(tvOS)
            48
        #else
            16
        #endif
    }
}
