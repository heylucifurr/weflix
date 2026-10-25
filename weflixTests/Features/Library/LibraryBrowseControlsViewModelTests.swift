import Foundation
@testable import weflix
import Testing

@MainActor
struct LibraryBrowseControlsViewModelTests {
    private typealias PlexSelection = LibraryBrowsePreferences.PlexSelection

    private let movieTypeKey = "/library/sections/1/all?type=1"

    @Test func `pending selection builds sort and filters before meta`() {
        let controls = makeControls(restoring: PlexSelection(
            displayTypeKey: movieTypeKey,
            sortKey: "addedAt",
            sortDirection: .desc,
            sortQueryValue: "addedAt:desc",
            filters: [
                "unwatched": .init(isEnabled: true),
                "genre": .init(
                    isEnabled: true,
                    optionKey: "28",
                    optionFastKey: "/library/sections/1/all?genre=28",
                    optionTitle: "Action",
                ),
            ],
        ))

        let items = queryItems(controls)

        #expect(controls.requestedDisplayTypeKey == movieTypeKey)
        #expect(items["sort"] == "addedAt:desc")
        #expect(items["unwatched"] == "1")
        #expect(items["genre"] == "28")
        #expect(items["includeMeta"] == "1")
    }

    @Test func `pending filter without fast key uses the option key`() {
        let controls = makeControls(restoring: PlexSelection(
            filters: ["genre": .init(isEnabled: true, optionKey: "12", optionTitle: "Drama")],
        ))

        let items = queryItems(controls)

        #expect(items["genre"] == "12")
        #expect(items["sort"] == nil)
    }

    @Test func `valid pending selection is applied without refresh`() throws {
        let controls = makeControls(restoring: PlexSelection(
            displayTypeKey: movieTypeKey,
            sortKey: "addedAt",
            sortDirection: .desc,
            sortQueryValue: "addedAt:desc",
            filters: ["genre": .init(isEnabled: true, optionKey: "28", optionTitle: "Action")],
        ))

        let restoreChanged = try controls.applyMeta(meta())

        #expect(!restoreChanged)
        #expect(controls.selectedDisplayType?.key == movieTypeKey)
        #expect(controls.selectedSort?.sort.key == "addedAt")
        #expect(controls.selectedSort?.direction == .desc)
        #expect(controls.filterPillTitle.hasSuffix("Genre: Action"))
        #expect(queryItems(controls, includeMeta: false)["sort"] == "addedAt:desc")
    }

    @Test func `unknown sort falls back to the server default`() throws {
        let controls = makeControls(restoring: PlexSelection(
            sortKey: "removed",
            sortDirection: .asc,
            sortQueryValue: "removed",
        ))

        let restoreChanged = try controls.applyMeta(meta())

        #expect(restoreChanged)
        #expect(controls.selectedSort?.sort.key == "titleSort")
        #expect(controls.selectedSort?.direction == .asc)
        #expect(controls.plexSelection.sortQueryValue == "titleSort")
    }

    @Test func `unknown filter is dropped`() throws {
        let controls = makeControls(restoring: PlexSelection(
            filters: [
                "unwatched": .init(isEnabled: true),
                "removed": .init(isEnabled: true, optionKey: "1"),
            ],
        ))

        let restoreChanged = try controls.applyMeta(meta())

        #expect(restoreChanged)
        #expect(Set(controls.selectedFilters.keys) == ["unwatched"])
        #expect(Set(controls.plexSelection.filters.keys) == ["unwatched"])
    }

    @Test func `unknown display type falls back to the active type`() throws {
        let controls = makeControls(restoring: PlexSelection(displayTypeKey: "/library/sections/1/all?type=4"))

        let restoreChanged = try controls.applyMeta(meta())

        #expect(restoreChanged)
        #expect(controls.selectedDisplayType?.key == movieTypeKey)
        #expect(controls.plexSelection.displayTypeKey == movieTypeKey)
    }

    @Test func `meta without a pending selection does not ask for a refresh`() throws {
        let controls = makeControls(restoring: nil)

        let restoreChanged = try controls.applyMeta(meta())

        #expect(!restoreChanged)
        #expect(controls.selectedSort?.sort.key == "titleSort")
        #expect(!controls.canResetSelection)
    }

    @Test func `reset restores the server default sort and clears filters`() throws {
        let controls = makeControls(restoring: PlexSelection(
            sortKey: "addedAt",
            sortDirection: .desc,
            sortQueryValue: "addedAt:desc",
            filters: ["unwatched": .init(isEnabled: true)],
        ))
        try controls.applyMeta(meta())
        var didReset = false
        controls.onSelectionReset = { didReset = true }

        #expect(controls.canResetSelection)
        controls.resetSelection()

        #expect(didReset)
        #expect(controls.selectedFilters.isEmpty)
        #expect(controls.selectedSort?.sort.key == "titleSort")
        #expect(!controls.canResetSelection)
    }

    @Test func `folder display type is detected from its key`() {
        #expect(makeControls(restoring: PlexSelection(displayTypeKey: "/library/sections/1/folder"))
            .isFolderDisplayType)
        #expect(!makeControls(restoring: PlexSelection(displayTypeKey: movieTypeKey)).isFolderDisplayType)
        #expect(!makeControls(restoring: nil).isFolderDisplayType)
    }

    @Test func `the technical filters are not offered, and the rest still are`() throws {
        let controls = makeControls(restoring: nil)
        try controls.applyMeta(meta(addingFilters: [
            ("decade", "Decade"),
            ("resolution", "Resolution"),
            ("hdr", "HDR"),
            ("hdr10", "HDR10"),
            ("dovi", "DoVi"),
            ("atmos", "ATMOS"),
            ("videoCodec", "Video Codec"),
            ("audioCodec", "Audio Codec"),
            ("subtitleCodec", "Subtitle Codec"),
            ("audioLayout", "Audio Layout"),
            ("audioLanguage", "Audio Language"),
            ("editionTitle", "Edition"),
            ("label", "Labels"),
            ("location", "Folder Location"),
        ]))

        // Luther's list, gone from the menu (2026-10-25) …
        #expect(controls.visibleFilters.map(\.filter) == ["unwatched", "genre"])
        // … while Plex still reported every one of them, and the pill still has something to open.
        #expect(controls.availableFilters.count == 16)
        #expect(controls.showsFilterPill)
    }

    @Test func `a hidden filter is caught by its key or by its title`() throws {
        // `videoCodec` is hidden by the key Plex sends; `someKey` titled `Decade` by the title it draws. Either
        // spelling of "which filter is this" is enough, so a Plex that renames one of them does not bring it back.
        let controls = makeControls(restoring: nil)
        try controls.applyMeta(meta(addingFilters: [("videoCodec", "Video Codec"), ("someKey", "Decade")]))

        #expect(controls.visibleFilters.map(\.filter) == ["unwatched", "genre"])
    }

    @Test func `Plex's folder display type is not offered either`() throws {
        let controls = makeControls(restoring: nil)
        try controls.applyMeta(meta(addingTypes: ["/library/sections/1/folder"]))

        // It is the type that shows the file tree, and the tree is gone — so it is not in the menu …
        #expect(controls.displayTypes.map(\.key) == [movieTypeKey, "/library/sections/1/all?type=18"])
        #expect(controls.selectedDisplayType?.key == movieTypeKey)
        // … and a saved selection pointing at it falls back to the library's own active type.
        let restored = makeControls(restoring: PlexSelection(displayTypeKey: "/library/sections/1/folder"))
        #expect(try restored.applyMeta(meta(addingTypes: ["/library/sections/1/folder"])))
        #expect(restored.selectedDisplayType?.key == movieTypeKey)
    }

    private func makeControls(restoring selection: PlexSelection?) -> LibraryBrowseControlsViewModel {
        LibraryBrowseControlsViewModel(advancedService: nil, pendingRestore: selection)
    }

    private func meta() throws -> PlexSectionItemMeta {
        try Fixtures.decode(PlexSectionItemMeta.self, from: "plex-section-meta")
    }

    /// The section-meta fixture with extra display types appended, in Plex's own shape.
    private func meta(addingTypes keys: [String]) throws -> PlexSectionItemMeta {
        var root = try JSONSerialization.jsonObject(with: Fixtures.data("plex-section-meta")) as? [String: Any] ?? [:]
        var types = root["Type"] as? [[String: Any]] ?? []
        types += keys.map { key in
            ["key": key, "type": "movie", "title": "Folder", "active": false] as [String: Any]
        }
        root["Type"] = types

        return try JSONDecoder().decode(PlexSectionItemMeta.self, from: JSONSerialization.data(withJSONObject: root))
    }

    /// The section-meta fixture with extra filters pushed into its movie type, in Plex's own shape.
    private func meta(addingFilters extra: [(filter: String, title: String)]) throws -> PlexSectionItemMeta {
        var root = try JSONSerialization.jsonObject(with: Fixtures.data("plex-section-meta")) as? [String: Any] ?? [:]
        var types = root["Type"] as? [[String: Any]] ?? []
        let added: [[String: Any]] = extra.map { entry in
            [
                "filter": entry.filter,
                "filterType": "string",
                "key": "/library/sections/1/\(entry.filter)",
                "title": entry.title,
                "type": "filter",
            ]
        }
        types[0]["Filter"] = (types[0]["Filter"] as? [[String: Any]] ?? []) + added
        root["Type"] = types

        return try JSONDecoder().decode(PlexSectionItemMeta.self, from: JSONSerialization.data(withJSONObject: root))
    }

    private func queryItems(_ controls: LibraryBrowseControlsViewModel, includeMeta: Bool = true) -> [String: String] {
        let items = controls.buildQueryItems(baseItems: [], includeCollections: nil, includeMeta: includeMeta)
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { _, last in last })
    }
}
