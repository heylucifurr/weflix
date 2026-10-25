import SwiftUI

@MainActor
struct SeerrMediaDetailView: View {
    @State var viewModel: SeerrMediaDetailViewModel
    let onSelectMedia: (SeerrMedia) -> Void
    /// Open a title the **library** holds, from a Seerr page. `nil` (the default) means this screen has nowhere to
    /// open it, and then no Play button is offered at all.
    let onPlayInLibrary: ((MediaItem) -> Void)?
    @Environment(SessionManager.self) private var sessionManager
    @State private var requestSheet: SeerrMediaRequestSheetState?
    @State private var manageRequestsSheet: SeerrManageRequestsSheetState?
    #if os(iOS)
        @State private var isSummaryExpanded = false
        private let heroHeight: CGFloat = 320
    #endif

    init(
        viewModel: SeerrMediaDetailViewModel,
        onSelectMedia: @escaping (SeerrMedia) -> Void = { _ in },
        onPlayInLibrary: ((MediaItem) -> Void)? = nil,
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onSelectMedia = onSelectMedia
        self.onPlayInLibrary = onPlayInLibrary
    }

    var body: some View {
        @Bindable var bindableViewModel = viewModel

        ScrollView {
            LazyVStack(alignment: .leading, spacing: sectionSpacing) {
                #if os(iOS)
                    SeerrMediaDetailHeaderSection(
                        viewModel: bindableViewModel,
                        isSummaryExpanded: $isSummaryExpanded,
                        heroHeight: heroHeight,
                        onRequestTap: presentRequestSheet,
                        onManageRequestsTap: presentManageRequestsSheet,
                        onPlayTap: playAction,
                    )
                #else
                    SeerrMediaDetailHeaderSection(
                        viewModel: bindableViewModel,
                        onRequestTap: presentRequestSheet,
                        onManageRequestsTap: presentManageRequestsSheet,
                    )
                #endif

                if bindableViewModel.media.mediaType == .tv {
                    SeerrSeasonEpisodesSection(viewModel: bindableViewModel)
                }

                SeerrCastSection(viewModel: bindableViewModel)

                SeerrCollectionSection(viewModel: bindableViewModel, onSelectMedia: onSelectMedia)

                SeerrRelatedSection(
                    viewModel: bindableViewModel,
                    section: .recommendations,
                    onSelectMedia: onSelectMedia,
                )

                SeerrRelatedSection(
                    viewModel: bindableViewModel,
                    section: .similar,
                    onSelectMedia: onSelectMedia,
                )

                SeerrDetailFactsSection(viewModel: bindableViewModel)
                    .padding(.horizontal, LayoutMetrics.detailSectionMargin)
                    .padding(.bottom, 32)
            }
        }
        #if os(iOS)
        .ignoresSafeArea(edges: .top)
        .toolbar(.hidden, for: .tabBar)
        #else
        .navigationTitle(bindableViewModel.media.displayTitle)
        #endif
        .task {
            await bindableViewModel.loadDetails()
            async let ratings: Void = bindableViewModel.loadRatings()
            async let collection: Void = bindableViewModel.loadCollection()
            _ = await (ratings, collection)
            await bindableViewModel.loadRelatedContent()
        }
        .background(gradientBackground(for: bindableViewModel))
        .sheet(item: $requestSheet) { sheet in
            SeerrMediaRequestSheetView(viewModel: sheet.viewModel) {
                Task {
                    await viewModel.loadDetails()
                    await viewModel.loadRelatedContent()
                }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $manageRequestsSheet) { sheet in
            SeerrManageRequestsSheetView(viewModel: sheet.viewModel) {
                Task {
                    await viewModel.loadDetails()
                    await viewModel.loadRelatedContent()
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func gradientBackground(for viewModel: SeerrMediaDetailViewModel) -> some View {
        MediaBackdropGradient(colors: viewModel.backdropGradient)
            .ignoresSafeArea()
    }

    private func presentRequestSheet() {
        guard let viewModel = viewModel.makeRequestViewModel() else { return }
        requestSheet = SeerrMediaRequestSheetState(viewModel: viewModel)
    }

    /// Open this title in the library — **only** when both halves are known: the library's own key for it, and a
    /// handler to open it with. Anything less and the button is not offered, so it can never be a dead tap.
    private var playAction: (() -> Void)? {
        guard let handler = onPlayInLibrary, let item = playableLibraryItem else { return nil }
        return { handler(item) }
    }

    /// The library's item for this title, built for the server the app is reading from.
    private var playableLibraryItem: MediaItem? {
        let sessions = sessionManager.registry.sessions
        let server = sessions.first { $0.isEnabled && $0.status == .ready }?.identity ?? sessions.first?.identity
        guard let server else { return nil }
        return viewModel.libraryItem(server: server)
    }

    private func presentManageRequestsSheet() {
        guard let viewModel = viewModel.makeManageRequestsViewModel() else { return }
        manageRequestsSheet = SeerrManageRequestsSheetState(viewModel: viewModel)
    }

    private var sectionSpacing: CGFloat {
        #if os(iOS)
            16
        #else
            24
        #endif
    }
}

private struct SeerrMediaRequestSheetState: Identifiable {
    let id = UUID()
    let viewModel: SeerrMediaRequestViewModel
}

private struct SeerrManageRequestsSheetState: Identifiable {
    let id = UUID()
    let viewModel: SeerrManageRequestsViewModel
}
