import Foundation

/// The status chips on the requests screen — **exactly** the values Overseerr's `GET /request` accepts.
///
/// Overseerr validates that one query strictly, and its own refusal names the whole set (measured live,
/// 2026-10-25, from the app): *"request.query.filter should be equal to one of the allowed values: all,
/// approved, available, pending, processing, unavailable, failed"*. The app used to offer **`completed`** and
/// **`deleted`** as well, and either one answered that `400` instead of a list — a chip that could only fail.
/// There is no `completed` here because Overseerr's own "available" already means a fulfilled request.
enum SeerrRequestStatusFilter: String, CaseIterable, Identifiable {
    case all
    case pending
    case approved
    case processing
    case failed
    case available
    case unavailable

    var id: String {
        rawValue
    }

    var titleKey: String {
        switch self {
        case .all:
            "seerr.requests.filter.all"
        case .pending:
            "seerr.media.availability.pending"
        case .approved:
            "seerr.requests.filter.approved"
        case .processing:
            "seerr.media.availability.processing"
        case .failed:
            "seerr.request.status.failed"
        case .available:
            "seerr.media.availability.available"
        case .unavailable:
            "seerr.media.availability.unavailable"
        }
    }
}

enum SeerrRequestSort: String, CaseIterable, Identifiable {
    case added
    case modified

    var id: String {
        rawValue
    }

    var titleKey: String {
        switch self {
        case .added:
            "seerr.requests.sort.added"
        case .modified:
            "seerr.requests.sort.modified"
        }
    }
}

struct SeerrRequestQuery: Hashable {
    var status: SeerrRequestStatusFilter = .all
    var sort: SeerrRequestSort = .added

    var isDefault: Bool {
        self == SeerrRequestQuery()
    }
}

struct SeerrRequestsRoute: Hashable {}
