import SwiftUI
import UIKit

/// The signed-in account's **My Watchlist**, opened from the profile menu (Luther, 2026-10-25).
///
/// The list is WeFlix's own (`watchlist_entries`, per account) read through `/api/app/watchlist` with the app's
/// device token — the same store the web's `/watchlist` page shows, through the door the native client needs.
///
/// A poster the library holds opens the title: `onSelectMedia` hands back the item built from the entry's library
/// rating key, and the menu closes itself and pushes the detail (the same handoff the Favorites row uses). A title
/// the library does **not** hold has no detail screen yet, so its poster is shown but inert — never a tap that
/// goes nowhere.
@MainActor
struct WatchlistView: View {
    @Environment(SessionManager.self) private var sessionManager

    let onSelectMedia: (MediaItem) -> Void

    @State private var entries: [WeFlixWatchlistEntry] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let columns = [GridItem(.adaptive(minimum: 108), spacing: 16)]

    var body: some View {
        ScrollView {
            content
        }
        .navigationTitle("My Watchlist")
        .task { await load() }
        .refreshable { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading, entries.isEmpty {
            ProgressView()
                .controlSize(.large)
                .padding(.top, 80)
                .frame(maxWidth: .infinity)
        } else if let errorMessage {
            ContentUnavailableView(
                "Couldn't load your watchlist",
                systemImage: "exclamationmark.triangle",
                description: Text(errorMessage),
            )
            .padding(.top, 40)
        } else if entries.isEmpty {
            ContentUnavailableView(
                "Your watchlist is empty",
                systemImage: "bookmark",
                description: Text("Add titles with the Watchlist button."),
            )
            .padding(.top, 40)
        } else {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(entries) { entry in
                    card(for: entry)
                }
            }
            .padding(16)
        }
    }

    private func card(for entry: WeFlixWatchlistEntry) -> some View {
        let item = mediaItem(for: entry)

        return Button {
            if let item {
                onSelectMedia(item)
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                WatchlistArtwork(path: entry.thumb)
                    .aspectRatio(2.0 / 3.0, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(.strokeSubtle, lineWidth: 1),
                    )
                    .opacity(item == nil ? 0.5 : 1)

                Text(entry.title)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let year = entry.year {
                    Text(String(year))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(item == nil)
    }

    /// The item a poster opens: only a title WeFlix's library holds has a detail screen, and only when a server
    /// session is up to read it from.
    private func mediaItem(for entry: WeFlixWatchlistEntry) -> MediaItem? {
        guard let key = entry.libraryRatingKey, !key.isEmpty, let server = activeServer else { return nil }

        return MediaItem.libraryEntry(
            ratingKey: key,
            server: server,
            title: entry.title,
            year: entry.year,
            kind: entry.mediaKind,
            thumbPath: entry.thumb,
            guid: entry.guid ?? "",
        )
    }

    private var activeServer: ServerIdentity? {
        sessionManager.registry.sessions.first { $0.isEnabled && $0.status == .ready }?.identity
            ?? sessionManager.registry.sessions.first?.identity
    }

    private func load() async {
        isLoading = entries.isEmpty
        errorMessage = nil

        do {
            entries = try await WeFlixWatchlistClient().list()
        } catch WeFlixWatchlistError.unauthorized {
            errorMessage = "Your WeFlix sign-in has ended. Sign in again."
        } catch {
            errorMessage = "Check your connection and try again."
        }

        isLoading = false
    }
}

/// A watchlist poster, fetched through the gateway's `/api/image` **with the app's bearer token**.
///
/// The gateway's image route needs a credential, and `AsyncImage` cannot set a header — so the artwork is loaded
/// here, through the one place that knows how (`WeFlixGatewayURL.artworkRequest`), exactly as the app's other
/// gateway artwork is.
private struct WatchlistArtwork: View {
    let path: String?

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.surfaceSubtle

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "film")
                    .font(.title2)
                    .foregroundStyle(.textSecondary)
            }
        }
        .clipped()
        .task(id: path) { await load() }
    }

    private func load() async {
        guard let path,
              let url = WeFlixGatewayURL.imageURL(path: path, width: 300, height: 450, format: nil)
        else { return }

        let request = WeFlixGatewayURL.artworkRequest(for: url)
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let loaded = UIImage(data: data)
        else { return }

        image = loaded
    }
}
