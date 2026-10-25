import Foundation
import Observation
import SwiftUI

enum SeerrSeasonAvailabilityBadge: Hashable {
    case media(SeerrMediaStatus)
    case request(SeerrMediaRequestStatus)
}

@MainActor
@Observable
final class SeerrMediaDetailViewModel {
    @ObservationIgnored private let store: SeerrStore
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private var backdropSourceURL: URL?
    @ObservationIgnored private let permissionService = SeerrPermissionService()

    var media: SeerrMedia
    var isLoading = false
    var errorMessage: String?
    var backdropGradient: [Color] = []

    var seasons: [SeerrSeason] = []
    var episodes: [SeerrEpisode] = []
    var selectedSeasonNumber: Int?
    var isLoadingSeasons = false
    var isLoadingEpisodes = false
    var seasonsErrorMessage: String?
    var episodesErrorMessage: String?
    var recommendations: [SeerrMedia] = []
    var similar: [SeerrMedia] = []
    var isLoadingRecommendations = false
    var isLoadingSimilar = false
    var recommendationsErrorMessage: String?
    var similarErrorMessage: String?
    var ratings: SeerrMediaRatings?
    var collection: SeerrCollection?
    var isRequestingCollection = false
    var collectionErrorMessage: String?

    init(
        media: SeerrMedia,
        store: SeerrStore,
        session: URLSession = .shared,
    ) {
        self.media = media
        self.store = store
        self.session = session
        refreshFromMedia()
    }

    var heroImageURL: URL? {
        TMDBImageService.backdropURL(path: media.backdropPath, width: 1400)
    }

    private var backdropGradientURL: URL? {
        TMDBImageService.backdropURL(path: media.backdropPath, width: 300)
    }

    var genres: [String] {
        media.genreNames
    }

    var cast: [SeerrCastMember] {
        let cast = media.credits?.cast ?? []
        return cast.sorted { ($0.order ?? 0) < ($1.order ?? 0) }
    }

    var creatorsText: String? {
        let names = media.createdBy?.compactMap(\.name).filter { !$0.isEmpty } ?? []
        guard !names.isEmpty else { return nil }
        return names.joined(separator: ", ")
    }

    var productionText: String? {
        let names = media.productionCompanies?.compactMap(\.name).filter { !$0.isEmpty } ?? []
        guard !names.isEmpty else { return nil }
        return names.joined(separator: ", ")
    }

    var countriesText: String? {
        let names = media.productionCountries?.compactMap(\.name).filter { !$0.isEmpty } ?? []
        guard !names.isEmpty else { return nil }
        return names.joined(separator: ", ")
    }

    var selectedSeason: SeerrSeason? {
        guard let selectedSeasonNumber else { return nil }
        return seasons.first { $0.seasonNumber == selectedSeasonNumber }
    }

    var episodeCountDisplay: Int {
        if !episodes.isEmpty {
            return episodes.count
        }
        return selectedSeason?.episodeCount ?? 0
    }

    func loadDetails() async {
        guard !isLoading else { return }

        isLoading = true
        if media.mediaType == .tv {
            isLoadingSeasons = true
        }
        errorMessage = nil
        seasonsErrorMessage = nil
        defer {
            isLoading = false
            isLoadingSeasons = false
        }

        do {
            let repository = SeerrMediaRepository()
            switch media.mediaType {
            case .movie:
                media = try await repository.getMovie(id: media.id)
                media.mediaType = .movie
            case .tv:
                media = try await repository.getTV(id: media.id)
                media.mediaType = .tv
            case .person, .none:
                break
            }
            refreshFromMedia()
            await loadBackdropGradient()
            if media.mediaType == .tv {
                await loadSeasonIfNeeded()
            }
        } catch {
            let message = error.seerrSentence()
            errorMessage = message
            seasonsErrorMessage = message
        }
    }

    func loadRatings() async {
        let repository = SeerrMediaRepository(session: session)
        switch media.mediaType {
        case .movie:
            ratings = try? await repository.getMovieRatings(id: media.id)
        case .tv:
            ratings = try? await repository.getTVRatings(id: media.id)
        case .person, .none:
            ratings = nil
        }
    }

    func loadCollection() async {
        guard media.mediaType == .movie, let summary = media.collection else {
            collection = nil
            return
        }
        let repository = SeerrMediaRepository(session: session)
        if let refreshed = try? await repository.getCollection(id: summary.id) {
            collection = refreshed
        }
    }

    var collectionRequestableParts: [SeerrMedia] {
        guard canRequestStandard, hasQuotaForMedia else { return [] }
        let parts = collection?.parts ?? []
        let missing = parts.filter { part in
            guard part.mediaType == nil || part.mediaType == .movie else { return false }
            let status = part.mediaInfo?.status
            return status == nil || status == .unknown || status == .deleted
        }
        guard let quota = quotaRestriction, quota.restricted else { return missing }
        return Array(missing.prefix(max(0, quota.remaining ?? 0)))
    }

    var isCollectionLimitedByQuota: Bool {
        guard let quota = quotaRestriction, quota.restricted else { return false }
        let parts = collection?.parts ?? []
        let missingCount = parts.count(where: { part in
            let status = part.mediaInfo?.status
            return (part.mediaType == nil || part.mediaType == .movie)
                && (status == nil || status == .unknown || status == .deleted)
        })
        return missingCount > collectionRequestableParts.count
    }

    var collectionQuotaRemaining: Int {
        quotaRestriction?.remaining ?? 0
    }

    func requestCollection() async {
        let parts = collectionRequestableParts
        guard !parts.isEmpty else { return }

        isRequestingCollection = true
        collectionErrorMessage = nil
        defer { isRequestingCollection = false }

        let repository = SeerrRequestRepository(session: session)
        var failedCount = 0
        for part in parts {
            let payload = SeerrMediaRequestPayload(
                mediaId: part.id,
                mediaType: .movie,
                is4k: false,
                tvdbId: nil,
                seasons: nil,
                serverId: nil,
                profileId: nil,
                rootFolder: nil,
                tags: nil,
            )
            do {
                try await repository.createRequest(payload)
            } catch {
                failedCount += 1
            }
        }

        if failedCount > 0 {
            let succeeded = parts.count - failedCount
            collectionErrorMessage = String(localized: "seerr.collection.requestResult \(succeeded) \(parts.count)")
        }

        await loadDetails()
        await loadCollection()
    }

    var isDownloading: Bool {
        media.mediaInfo?.isDownloading ?? false
    }

    func loadRelatedContent() async {
        guard media.mediaType == .movie || media.mediaType == .tv else {
            recommendations = []
            similar = []
            return
        }
        guard media.mediaType == .movie || media.mediaType == .tv else {
            recommendations = []
            similar = []
            return
        }

        let repository = SeerrMediaRepository()

        isLoadingRecommendations = true
        recommendationsErrorMessage = nil
        defer { isLoadingRecommendations = false }

        do {
            switch media.mediaType {
            case .movie:
                recommendations = try await repository.getMovieRecommendations(id: media.id, page: 1).results
            case .tv:
                recommendations = try await repository.getTVRecommendations(id: media.id, page: 1).results
            case .person, .none:
                recommendations = []
            }
        } catch {
            recommendationsErrorMessage = error.seerrSentence()
        }

        isLoadingSimilar = true
        similarErrorMessage = nil
        defer { isLoadingSimilar = false }

        do {
            switch media.mediaType {
            case .movie:
                similar = try await repository.getMovieSimilar(id: media.id, page: 1).results
            case .tv:
                similar = try await repository.getTVSimilar(id: media.id, page: 1).results
            case .person, .none:
                similar = []
            }
        } catch {
            similarErrorMessage = error.seerrSentence()
        }
    }

    func selectSeason(number: Int) async {
        guard selectedSeasonNumber != number else { return }
        selectedSeasonNumber = number
        episodes = []
        episodesErrorMessage = nil
        await loadSeason(number: number)
    }

    func seasonTitle(for season: SeerrSeason) -> String {
        if let name = season.name, !name.isEmpty {
            return name
        }
        if let number = season.seasonNumber {
            return String(localized: "media.detail.season") + " \(number)"
        }
        return String(localized: "media.detail.season")
    }

    func episodeLabel(for episode: SeerrEpisode) -> String? {
        let seasonNumber = episode.seasonNumber ?? selectedSeasonNumber
        guard let seasonNumber, let episodeNumber = episode.episodeNumber else { return nil }
        return String(localized: "media.labels.seasonEpisode \(seasonNumber) \(episodeNumber)")
    }

    func episodeAirDateText(for episode: SeerrEpisode) -> String? {
        formattedDate(from: episode.airDate)
    }

    func episodeImageURL(for episode: SeerrEpisode, width: CGFloat) -> URL? {
        TMDBImageService.backdropURL(path: episode.stillPath, width: width)
    }

    func seasonAvailabilityBadge(for season: SeerrSeason) -> SeerrSeasonAvailabilityBadge? {
        guard let seasonNumber = season.seasonNumber else { return nil }
        return SeerrMediaRequestAvailability.seasonAvailabilityBadge(
            media: media,
            seasonNumber: seasonNumber,
            is4k: false,
        )
    }

    /// The title as the **library** holds it: the one fact needed to open its own detail screen from here.
    ///
    /// Overseerr reports `mediaInfo.ratingKey` once its media status is **available**, and that key is Plex's own,
    /// so it is what the library's detail screen is addressed by. `nil` when the library does not hold the title —
    /// and then there is nothing to play, so no Play button is offered.
    var libraryRatingKey: String? {
        guard isMediaAvailable(is4k: false), let key = media.mediaInfo?.ratingKey, !key.isEmpty else { return nil }
        return key
    }

    /// The library item a **Play** button opens, for the server the app is reading from.
    ///
    /// The artwork is deliberately left out: Seerr's own poster is a TMDB path and a library `MediaItem` carries a
    /// **Plex** artwork path, so passing one where the other belongs is a broken image. The detail screen fetches
    /// the real metadata (and its artwork) on open, which is why a title found through Seerr shows its poster a
    /// moment later rather than never.
    func libraryItem(server: ServerIdentity) -> MediaItem? {
        guard let key = libraryRatingKey else { return nil }
        return MediaItem.libraryEntry(
            ratingKey: key,
            server: server,
            title: media.displayTitle,
            year: media.year,
            kind: media.mediaType == .tv ? .series : .movie,
            thumbPath: nil,
        )
    }

    /// A request **of this account's** that is still live — pending or approved.
    ///
    /// Anything declined or completed is over, so the button may be offered again. Luther, 2026-10-25: a movie he
    /// had already asked for still showed an enabled **Request** button, and Overseerr auto-approves by default, so
    /// a request that is `.approved` (while the media is still `.pending`) looked like no request at all.
    var ownActiveRequest: SeerrRequest? {
        guard let userID = store.user?.id else { return nil }
        return media.mediaInfo?.requests?.first { request in
            request.requestedBy?.id == userID
                && request.status != .declined
                && request.status != .completed
        }
    }

    /// Has this account already asked for this title? Then there is nothing left to press.
    var isRequested: Bool {
        ownActiveRequest != nil
    }

    var requestButtonTitleKey: String {
        if isRequested {
            return "seerr.request.action.requested"
        }
        return "seerr.request.action.request"
    }

    var pendingManageRequestsCount: Int {
        pendingManageRequests.count
    }

    var shouldShowManageRequestsButton: Bool {
        hasManageRequestsPermission && pendingManageRequestsCount > 0
    }

    var requestButtonDisabledReasonKey: String? {
        guard media.mediaType == .movie || media.mediaType == .tv else { return nil }
        if isRequested {
            return nil
        }
        if !hasQuotaForMedia {
            return "seerr.request.disabled.noQuota"
        }
        if !canRequestStandard, !canRequest4K {
            return "seerr.request.disabled.noPermission"
        }
        if media.mediaType == .tv, media.externalIds?.tvdbId == nil {
            return "seerr.request.disabled.missingTvdb"
        }
        return nil
    }

    var isRequestButtonDisabled: Bool {
        isRequested || requestButtonDisabledReasonKey != nil
    }

    var isRequestButtonHidden: Bool {
        guard media.mediaType == .movie || media.mediaType == .tv else { return true }
        if isRequested {
            return false
        }
        let requestTypes = availableRequestTypes
        guard !requestTypes.isEmpty else {
            return false
        }

        switch media.mediaType {
        case .movie:
            return requestTypes.allSatisfy { isMediaAvailable(is4k: $0.is4k) }
        case .tv:
            return requestTypes.allSatisfy { type in
                let available = isMediaAvailable(is4k: type.is4k)
                let hasSeasons = SeerrMediaRequestAvailability.hasRequestableSeasons(
                    media: media,
                    is4k: type.is4k,
                )
                return available || !hasSeasons
            }
        case .person, .none:
            return true
        }
    }

    var pendingRequest: SeerrRequest? {
        SeerrMediaRequestAvailability.pendingRequest(in: media, for: store.user)
    }

    func makeRequestViewModel() -> SeerrMediaRequestViewModel? {
        return SeerrMediaRequestViewModel(media: media, store: store, session: session)
    }

    func makeManageRequestsViewModel() -> SeerrManageRequestsViewModel? {
        return SeerrManageRequestsViewModel(media: media, store: store, session: session)
    }

    func castImageURL(for member: SeerrCastMember, width: CGFloat, height: CGFloat) -> URL? {
        TMDBImageService.profileURL(path: member.profilePath, width: width, height: height)
    }

    private func refreshFromMedia() {
        if store.settings?.enableSpecialEpisodes == false {
            seasons = (media.seasons ?? []).filter { ($0.seasonNumber ?? -1) > 0 }
        } else {
            seasons = (media.seasons ?? []).filter { $0.seasonNumber != nil }
        }
    }

    private func loadSeasonIfNeeded() async {
        // Opens on the first regular season like library series; specials only when there is nothing else.
        let defaultSeason = seasons.first { ($0.seasonNumber ?? 0) > 0 } ?? seasons.first
        guard let number = selectedSeasonNumber ?? defaultSeason?.seasonNumber else { return }
        selectedSeasonNumber = number
        if episodes.isEmpty {
            await loadSeason(number: number)
        }
    }

    private func loadSeason(number: Int) async {
        guard media.mediaType == .tv else { return }

        isLoadingEpisodes = true
        episodesErrorMessage = nil
        defer { isLoadingEpisodes = false }

        do {
            let repository = SeerrMediaRepository()
            let season = try await repository.getTVSeason(id: media.id, seasonNumber: number)
            guard selectedSeasonNumber == number else { return }
            episodes = season.episodes ?? []
        } catch {
            guard selectedSeasonNumber == number else { return }
            episodesErrorMessage = error.seerrSentence()
        }
    }

    private func loadBackdropGradient() async {
        guard let url = backdropGradientURL else {
            backdropGradient = []
            return
        }
        guard backdropSourceURL != url else { return }
        backdropSourceURL = url

        do {
            let (data, _) = try await session.data(from: url)
            let colors = await ImageCornerColorSampler.colors(from: data)
            if colors.count == 4 {
                backdropGradient = colors
            }
        } catch {
            backdropGradient = []
        }
    }

    private var availableRequestTypes: [SeerrMediaRequestType] {
        var types: [SeerrMediaRequestType] = []
        if canRequestStandard {
            types.append(.standard)
        }
        if canRequest4K {
            types.append(.fourK)
        }
        return types
    }

    private var canRequestStandard: Bool {
        guard media.mediaType == .movie || media.mediaType == .tv else { return false }
        let permissions: [SeerrPermission] = switch media.mediaType {
        case .tv:
            [.request, .requestTV]
        case .movie:
            [.request, .requestMovie]
        case .person, .none:
            []
        }
        return permissionService.hasPermission(permissions, user: store.user, options: .init(type: .or))
    }

    private var canRequest4K: Bool {
        guard media.mediaType == .movie || media.mediaType == .tv, is4kEnabledForMedia else { return false }
        let permissions: [SeerrPermission] = switch media.mediaType {
        case .tv:
            [.request4K, .request4KTV]
        case .movie:
            [.request4K, .request4KMovie]
        case .person, .none:
            []
        }
        return permissionService.hasPermission(permissions, user: store.user, options: .init(type: .or))
    }

    private var hasManageRequestsPermission: Bool {
        permissionService.hasPermission(.manageRequests, user: store.user)
    }

    private var pendingManageRequests: [SeerrRequest] {
        media.mediaInfo?.requests?.filter { $0.status == .pending } ?? []
    }

    private var is4kEnabledForMedia: Bool {
        guard let settings = store.settings else { return false }
        switch media.mediaType {
        case .movie:
            return settings.movie4kEnabled
        case .tv:
            return settings.series4kEnabled
        case .person, .none:
            return false
        }
    }

    private var hasQuotaForMedia: Bool {
        quotaRestriction != nil
    }

    private var quotaRestriction: SeerrQuotaRestriction? {
        switch media.mediaType {
        case .movie:
            store.quota?.movie
        case .tv:
            store.quota?.tv
        case .person, .none:
            nil
        }
    }

    private func isMediaAvailable(is4k: Bool) -> Bool {
        let status = is4k ? media.mediaInfo?.status4k : media.mediaInfo?.status
        return status == .available
    }

    private func formattedDate(from dateString: String?) -> String? {
        guard let dateString else { return nil }
        guard let date = SeerrMediaDetailViewModel.inputDateFormatter.date(from: dateString) else {
            return dateString
        }
        return SeerrMediaDetailViewModel.outputDateFormatter.string(from: date)
    }

    private static let inputDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let outputDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}
