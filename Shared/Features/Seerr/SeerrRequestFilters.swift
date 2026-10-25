import Foundation

enum SeerrRequestStatusFilter: String, CaseIterable, Identifiable {
    case all
    case pending
    case approved
    case completed
    case processing
    case failed
    case available
    case unavailable
    case deleted

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
        case .completed:
            "seerr.requests.filter.completed"
        case .processing:
            "seerr.media.availability.processing"
        case .failed:
            "seerr.request.status.failed"
        case .available:
            "seerr.media.availability.available"
        case .unavailable:
            "seerr.media.availability.unavailable"
        case .deleted:
            "seerr.request.status.deleted"
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
