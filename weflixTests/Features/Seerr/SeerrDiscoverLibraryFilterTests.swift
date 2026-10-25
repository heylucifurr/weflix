import Foundation
@testable import weflix
import Testing

/// Luther, 2026-10-25 — "show only what's in library": the discover rails keep a title only when Seerr reports the
/// server already has it. These tests pin the rule to the two statuses it allows, so a later change cannot quietly
/// put unavailable titles back on the rails.
struct SeerrDiscoverLibraryFilterTests {
    @Test func `a title the server has is in the library`() throws {
        #expect(SeerrDiscoverViewModel.isInLibrary(try media(id: 1, status: .available)))
        #expect(SeerrDiscoverViewModel.isInLibrary(try media(id: 2, status: .partiallyAvailable)))
    }

    @Test func `a title the server does not have is not in the library`() throws {
        let absent: [SeerrMediaStatus?] = [.unknown, .pending, .processing, .blacklisted, .deleted, nil]
        for status in absent {
            #expect(!SeerrDiscoverViewModel.isInLibrary(try media(id: 1, status: status)))
        }
    }

    @Test func `a title Seerr knows nothing about is not in the library`() throws {
        #expect(!SeerrDiscoverViewModel.isInLibrary(try mediaWithoutInfo(id: 1)))
    }

    @Test func `a rail keeps its in-library titles in order and drops the rest`() throws {
        let items = [
            try media(id: 10, status: .available),
            try media(id: 11, status: .pending),
            try media(id: 12, status: .partiallyAvailable),
            try media(id: 13, status: nil),
            try mediaWithoutInfo(id: 14),
            try media(id: 15, status: .available),
        ]

        #expect(SeerrDiscoverViewModel.inLibraryOnly(items).map(\.id) == [10, 12, 15])
    }

    @Test func `an empty rail stays empty`() {
        #expect(SeerrDiscoverViewModel.inLibraryOnly([]).isEmpty)
    }

    /// A minimal discover row: the keys the model needs, plus the `mediaInfo` Seerr sends with a discover hit.
    private func media(id: Int, status: SeerrMediaStatus?) throws -> SeerrMedia {
        let statusValue = status.map { String($0.rawValue) } ?? "null"
        let json = #"""
        {
            "id": \#(id),
            "mediaType": "movie",
            "title": "Title \#(id)",
            "mediaInfo": {"id": \#(id), "status": \#(statusValue)}
        }
        """#
        return try JSONDecoder().decode(SeerrMedia.self, from: Data(json.utf8))
    }

    /// A row Seerr has no `mediaInfo` for: the server has no record of it, so it is not in the library either.
    private func mediaWithoutInfo(id: Int) throws -> SeerrMedia {
        let json = #"""
        {"id": \#(id), "mediaType": "movie", "title": "Title \#(id)"}
        """#
        return try JSONDecoder().decode(SeerrMedia.self, from: Data(json.utf8))
    }
}
