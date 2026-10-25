import SwiftUI

/// A toggle pill shown first in the controls row, independent of the server-side type, filter and sort controls.
struct LibraryBrowseToggle {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void
}

extension LibraryBrowseToggle {
    /// Shows the layout the button switches to, like the Photos toolbar toggles.
    static func layout(
        current: LibraryBrowseLayout,
        onChange: @escaping (LibraryBrowseLayout) -> Void,
    ) -> LibraryBrowseToggle {
        let target: LibraryBrowseLayout = current == .grid ? .list : .grid
        return switch target {
        case .grid:
            LibraryBrowseToggle(
                title: String(localized: "library.browse.layout.grid"),
                systemImage: "square.grid.2x2",
                isSelected: false,
                action: { onChange(.grid) },
            )
        case .list:
            LibraryBrowseToggle(
                title: String(localized: "library.browse.layout.list"),
                systemImage: "list.bullet",
                isSelected: false,
                action: { onChange(.list) },
            )
        }
    }

    static func folderTree(isSelected: Bool, action: @escaping () -> Void) -> LibraryBrowseToggle {
        LibraryBrowseToggle(
            title: String(localized: "library.browse.folders.tree"),
            systemImage: "list.bullet.indent",
            isSelected: isSelected,
            action: action,
        )
    }
}

struct LibraryBrowseControlsView: View {
    @Bindable var viewModel: LibraryBrowseControlsViewModel
    let showsBackButton: Bool
    let onNavigateBack: () -> Void
    let leadingToggle: LibraryBrowseToggle?
    let showsServerControls: Bool
    /// Icon-only toggle shown last in the controls row; its title is used as the accessibility label.
    let layoutToggle: LibraryBrowseToggle?
    /// Whether the grid is on screen, so the type pill can wear the white active capsule (2026-10-25).
    let isTypePillSelected: Bool
    let itemCount: Int?
    /// `false` when the caller renders `pills` itself in another row — the library detail screen does exactly
    /// that, so the pills and the tab chips are one line (2026-10-25).
    let showsTopRow: Bool

    init(
        viewModel: LibraryBrowseControlsViewModel,
        showsBackButton: Bool = false,
        onNavigateBack: @escaping () -> Void = {},
        leadingToggle: LibraryBrowseToggle? = nil,
        showsServerControls: Bool = true,
        layoutToggle: LibraryBrowseToggle? = nil,
        isTypePillSelected: Bool = true,
        itemCount: Int? = nil,
        showsTopRow: Bool = true,
    ) {
        self.viewModel = viewModel
        self.showsBackButton = showsBackButton
        self.onNavigateBack = onNavigateBack
        self.leadingToggle = leadingToggle
        self.showsServerControls = showsServerControls
        self.layoutToggle = layoutToggle
        self.isTypePillSelected = isTypePillSelected
        self.itemCount = itemCount
        self.showsTopRow = showsTopRow
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsTopRow {
                topRow
            }

            if let itemCount, itemCount > 0 {
                Text(String(localized: "library.browse.count.items \(itemCount)"))
                    .font(.facts)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, rowPadding.leading)
            }
        }
        .taskPresentation(item: $viewModel.activeFilterSheet, style: .contextual) { sheet in
            LibraryBrowseFilterSheetView(viewModel: viewModel, filter: sheet.filter)
        }
        .taskPresentation(item: $viewModel.activeJellyfinFilterSheet, style: .contextual) { filter in
            JellyfinLibraryBrowseFilterSheetView(viewModel: viewModel, filter: filter)
        }
    }

    private var topRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            pills
                .padding(rowPadding)
        }
        .mouseDragScrolling()
    }

    /// The filter pills themselves, without a scroll view or padding of their own.
    ///
    /// `LibraryDetailView` embeds this in the **tab picker's** row, which is what makes the library screen one row
    /// instead of two (Luther, 2026-10-25): `Recommended · Movies · Filter · Sort · 🔳`.
    var pills: some View {
        LibraryBrowsePillsRow(
            viewModel: viewModel,
            showsBackButton: showsBackButton,
            onNavigateBack: onNavigateBack,
            leadingToggle: leadingToggle,
            showsServerControls: showsServerControls,
            isTypePillSelected: isTypePillSelected,
            layoutToggle: layoutToggle,
        )
    }

    private var rowPadding: EdgeInsets {
        #if os(tvOS)
            EdgeInsets(top: 12, leading: 36, bottom: 12, trailing: 36)
        #else
            EdgeInsets(top: 0, leading: 2, bottom: 0, trailing: 2)
        #endif
    }
}

/// The filter pills on their own — the type pill, Filter, Sort and the reset — with **no** scroll view and no
/// padding, so a caller can put them in a row it already has.
///
/// The library detail screen is that caller: its tab chips and these pills are one horizontally scrolling row,
/// which is the "1 combined filter" Luther asked for on 2026-10-25 (`Recommended · Movies · Filter · Sort · 🔳`,
/// with `Recommended` the way back to the rails and the pills the way into the grid).
struct LibraryBrowsePillsRow: View {
    @Bindable var viewModel: LibraryBrowseControlsViewModel
    let showsBackButton: Bool
    let onNavigateBack: () -> Void
    let leadingToggle: LibraryBrowseToggle?
    let showsServerControls: Bool
    /// Whether the **grid** is what is on screen.
    ///
    /// The type pill wears the white "active" capsule when it is (Luther, 2026-10-25: *"if you tap Movies it gets
    /// activated right? but it looks like it doesnt as it doesnt have White BG"*) — tapping it is what put the grid
    /// there, so it has to look like the mode that is on, exactly as `Recommended` does on the rails.
    let isTypePillSelected: Bool
    let layoutToggle: LibraryBrowseToggle?

    var body: some View {
        HStack(spacing: LayoutMetrics.chipSpacing) {
            if let leadingToggle {
                LibraryBrowsePillButton(
                    title: leadingToggle.title,
                    systemImage: leadingToggle.systemImage,
                    isSelected: leadingToggle.isSelected,
                    showsDisclosure: false,
                    action: leadingToggle.action,
                )
            }
            if showsServerControls {
                serverPills
            }
            if let layoutToggle {
                LibraryBrowsePillButton(
                    title: layoutToggle.title,
                    systemImage: layoutToggle.systemImage,
                    isSelected: layoutToggle.isSelected,
                    showsDisclosure: false,
                    showsTitle: false,
                    action: layoutToggle.action,
                )
            }
        }
    }

    @ViewBuilder
    private var serverPills: some View {
        if showsBackButton {
            LibraryBrowsePillButton(
                title: String(localized: "library.browse.folders.back"),
                systemImage: "chevron.left",
                isSelected: false,
                showsDisclosure: false,
                action: onNavigateBack,
            )
        }
        if viewModel.hasDisplayTypes {
            Menu {
                ForEach(viewModel.displayTypes) { type in
                    Button {
                        viewModel.selectDisplayType(type)
                    } label: {
                        if type.key == viewModel.selectedDisplayType?.key {
                            Label(type.title, systemImage: "checkmark")
                        } else {
                            Text(type.title)
                        }
                    }
                }
            } label: {
                LibraryBrowsePillLabel(
                    title: viewModel.typePillTitle,
                    systemImage: "square.grid.2x2",
                    isSelected: isTypePillSelected,
                    showsDisclosure: true,
                )
            }
        }

        /*
         * **One pill per control, and never a second line** (Luther, 2026-10-25).
         *
         * The row he asked for is `Recommended · Movies · Filter · Sort · 🔳`. An earlier attempt expanded every
         * filter into its own chip in this row — *"why there are a lot of filter types you added i did not asked
         * for"* — so the chips are gone and `Filter` is one pill again.
         *
         * Each pill is a **menu**: the choices appear over the screen, never as a row that pushes the grid down,
         * which is what *"no need to uncollapse"* asked for.
         */
        if viewModel.showsFilterPill {
            Menu {
                if viewModel.isJellyfinBrowse {
                    ForEach(LibraryBrowseControlsViewModel.JellyfinFilter.allCases) { filter in
                        let isSelected = viewModel.jellyfinFilterIsSelected(filter)
                        Button {
                            viewModel.toggleJellyfinFilter(filter)
                        } label: {
                            if isSelected {
                                Label(viewModel.jellyfinFilterLabel(filter), systemImage: "checkmark")
                            } else {
                                Text(viewModel.jellyfinFilterLabel(filter))
                            }
                        }
                    }
                } else {
                    ForEach(viewModel.visibleFilters, id: \.filter) { filter in
                        let selection = viewModel.filterSelection(for: filter)

                        Button {
                            viewModel.toggleFilter(filter)
                        } label: {
                            if selection?.isEnabled == true {
                                Label(filterLabel(for: filter, selection: selection), systemImage: "checkmark")
                            } else {
                                Text(filterLabel(for: filter, selection: selection))
                            }
                        }
                    }
                }
            } label: {
                LibraryBrowsePillLabel(
                    title: viewModel.filterPillTitle,
                    systemImage: "line.3.horizontal.decrease.circle",
                    isSelected: hasActiveFilter,
                    showsDisclosure: true,
                )
            }
        }

        if viewModel.showsSortPill {
            Menu {
                if viewModel.isJellyfinBrowse {
                    ForEach(viewModel.jellyfinSortOptions) { sort in
                        let isSelected = viewModel.browseSessionSort == sort.id
                        Button {
                            viewModel.toggleJellyfinSort(sort)
                        } label: {
                            if isSelected {
                                Label(sort.title, systemImage: viewModel.jellyfinSortDirectionImage)
                            } else {
                                Text(sort.title)
                            }
                        }
                    }
                } else {
                    ForEach(viewModel.availableSorts, id: \.key) { sort in
                        let selection = viewModel.selectedSort

                        Button {
                            viewModel.toggleSort(sort)
                        } label: {
                            if let image = sortDirectionImage(for: selection, sort: sort) {
                                Label(sort.title, systemImage: image)
                            } else {
                                Text(sort.title)
                            }
                        }
                    }
                }
            } label: {
                LibraryBrowsePillLabel(
                    title: viewModel.sortPillTitle,
                    systemImage: "arrow.up.arrow.down.circle",
                    isSelected: false,
                    showsDisclosure: true,
                )
            }
        }

        if viewModel.canResetSelection {
            LibraryBrowsePillButton(
                title: String(localized: "library.browse.filters.reset"),
                systemImage: "arrow.counterclockwise",
                isSelected: false,
                showsDisclosure: false,
                action: viewModel.resetSelection,
            )
        }
    }

    /// A filter's chip title: its own name, plus the chosen value when it has one — `Genre: Action`.
    private func filterLabel(
        for filter: PlexSectionItemFilter,
        selection: LibraryBrowseControlsViewModel.FilterSelection?,
    ) -> String {
        guard let selection, let option = selection.selectedOption else { return filter.title }
        return filter.title + ": " + option.title
    }

    /// Whether any filter is on, so the `Filter` pill can show it — a selection mark, not a second line.
    private var hasActiveFilter: Bool {
        if viewModel.isJellyfinBrowse {
            return LibraryBrowseControlsViewModel.JellyfinFilter.allCases.contains {
                viewModel.jellyfinFilterIsSelected($0)
            }
        }
        return viewModel.availableFilters.contains { viewModel.filterSelection(for: $0)?.isEnabled == true }
    }

    private func sortDirectionImage(
        for selection: LibraryBrowseControlsViewModel.SortSelection?,
        sort: PlexSectionItemSort,
    ) -> String? {
        guard let selection, selection.sort.key == sort.key else { return nil }
        switch selection.direction {
        case .asc:
            return "arrow.up"
        case .desc:
            return "arrow.down"
        }
    }
}


/// The pill's **look**, on its own, so a `Button` and a `Menu` can wear exactly the same capsule.
private struct LibraryBrowsePillLabel: View {
    let title: String
    let systemImage: String?
    let isSelected: Bool
    let showsDisclosure: Bool
    var showsTitle = true

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            if showsTitle {
                Text(title)
            }
            if showsDisclosure {
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .opacity(0.7)
            }
        }
        .chipAppearance(isSelected: isSelected)
    }
}

private struct LibraryBrowsePillButton: View {
    let title: String
    let systemImage: String?
    let isSelected: Bool
    let showsDisclosure: Bool
    var showsTitle = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            LibraryBrowsePillLabel(
                title: title,
                systemImage: systemImage,
                isSelected: isSelected,
                showsDisclosure: showsDisclosure,
                showsTitle: showsTitle,
            )
        }
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct LibraryBrowseFilterSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: LibraryBrowseControlsViewModel
    let filter: PlexSectionItemFilter

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(filter.title)
            #if !os(tvOS)
                .toolbar {
                    ToolbarItem(placement: leadingToolbarPlacement) {
                        if viewModel.filterSelection(for: filter) != nil {
                            Button("library.browse.filters.clear") {
                                viewModel.clearFilter(filter)
                                dismiss()
                            }
                        }
                    }
                    ToolbarItem(placement: trailingToolbarPlacement) {
                        Button("common.actions.done") {
                            dismiss()
                        }
                    }
                }
            #endif
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 360)
        #endif
    }

    private var leadingToolbarPlacement: ToolbarItemPlacement {
        #if os(macOS)
            .cancellationAction
        #else
            .topBarLeading
        #endif
    }

    private var trailingToolbarPlacement: ToolbarItemPlacement {
        #if os(macOS)
            .confirmationAction
        #else
            .topBarTrailing
        #endif
    }

    @ViewBuilder
    private var content: some View {
        #if os(tvOS)
            VStack(alignment: .leading, spacing: 16) {
                headerRow
                contentBody
            }
            .padding(.top, 12)
        #else
            contentBody
        #endif
    }

    @ViewBuilder
    private var contentBody: some View {
        if viewModel.isLoadingOptions(for: filter) {
            VStack(spacing: 12) {
                ProgressView()
                Text("library.browse.filters.loading")
                    .font(.facts)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = viewModel.optionsError(for: filter) {
            ContentUnavailableView(
                errorMessage,
                systemImage: "exclamationmark.triangle.fill",
                description: Text("common.errors.tryAgainLater"),
            )
            .symbolRenderingMode(.multicolor)
        } else if viewModel.options(for: filter).isEmpty {
            ContentUnavailableView(
                "common.empty.nothingToShow",
                systemImage: "line.3.horizontal.decrease.circle",
            )
        } else {
            List {
                ForEach(viewModel.options(for: filter)) { option in
                    Button {
                        viewModel.selectFilterOption(option, for: filter)
                        dismiss()
                    } label: {
                        HStack {
                            Text(option.title)
                            Spacer()
                            if viewModel.filterSelection(for: filter)?.selectedOption?.id == option.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.textPrimary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    #if os(tvOS)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    #endif
                }
            }
            #if os(tvOS)
            .padding(.horizontal, 16)
            #endif
            .listStyle(.plain)
        }
    }

    private var headerRow: some View {
        HStack {
            if viewModel.filterSelection(for: filter) != nil {
                Button("library.browse.filters.clear") {
                    viewModel.clearFilter(filter)
                    dismiss()
                }
            }
            Spacer()
            Button("common.actions.done") {
                dismiss()
            }
        }
        .padding(.horizontal, 24)
    }
}

private struct JellyfinLibraryBrowseFilterSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: LibraryBrowseControlsViewModel
    let filter: LibraryBrowseControlsViewModel.JellyfinFilter
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                #if os(tvOS)
                    headerRow
                #endif
                content
            }
            .navigationTitle(filter.title)
            #if !os(tvOS)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        if viewModel.jellyfinFilterIsSelected(filter) {
                            Button("library.browse.filters.clear") {
                                viewModel.clearJellyfinFilter(filter)
                            }
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("common.actions.done") { dismiss() }
                    }
                }
            #endif
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 420)
        #endif
    }

    @ViewBuilder
    private var content: some View {
        if filter != .watchStatus, viewModel.isLoadingJellyfinFilterOptions {
            VStack(spacing: 12) {
                ProgressView()
                Text("library.browse.filters.loading")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filter != .watchStatus, let errorMessage = viewModel.jellyfinFilterOptionsError {
            ContentUnavailableView(
                errorMessage,
                systemImage: "exclamationmark.triangle.fill",
                description: Text("common.errors.tryAgainLater"),
            )
            .symbolRenderingMode(.multicolor)
        } else if filteredOptions.isEmpty {
            ContentUnavailableView(
                "common.empty.nothingToShow",
                systemImage: "line.3.horizontal.decrease.circle",
            )
        } else {
            optionsList
        }
    }

    private var optionsList: some View {
        List(filteredOptions) { option in
            Button {
                viewModel.selectJellyfinOption(option, for: filter)
                if !filter.supportsMultiple {
                    dismiss()
                }
            } label: {
                HStack {
                    Text(option.title)
                    Spacer()
                    if viewModel.jellyfinOptionIsSelected(option, for: filter) {
                        Image(systemName: filter.supportsMultiple ? "checkmark.square.fill" : "checkmark")
                            .foregroundStyle(.textPrimary)
                    }
                }
            }
            .buttonStyle(.plain)
            #if os(tvOS)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            #endif
        }
        .listStyle(.plain)
        .modifier(JellyfinFilterSearchModifier(isEnabled: filter.supportsMultiple, searchText: $searchText))
    }

    private var filteredOptions: [LibraryBrowseValueOption] {
        let options = viewModel.jellyfinOptions(for: filter)
        guard !searchText.isEmpty else { return options }
        return options.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    private var headerRow: some View {
        HStack {
            if viewModel.jellyfinFilterIsSelected(filter) {
                Button {
                    viewModel.clearJellyfinFilter(filter)
                } label: {
                    Text("library.browse.filters.clear")
                }
            }
            Spacer()
            Button("common.actions.done") { dismiss() }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
    }
}

private struct JellyfinFilterSearchModifier: ViewModifier {
    let isEnabled: Bool
    @Binding var searchText: String

    func body(content: Content) -> some View {
        if isEnabled {
            content.searchable(text: $searchText, prompt: Text("library.browse.filters.search"))
        } else {
            content
        }
    }
}
