import Foundation

enum SeerrRequestFormatting {
    static func displayName(for user: SeerrUser?) -> String {
        if let name = user?.displayName, !name.isEmpty {
            return name
        }
        if let id = user?.id {
            return String(localized: "seerr.manageRequests.userId \(id)")
        }
        return String(localized: "seerr.manageRequests.unknownUser")
    }

    /// The requester's avatar, **only when it is a URL the app may fetch** (2026-10-25).
    ///
    /// Overseerr answers a user's `avatar` either as an absolute URL (a TMDB or Gravatar image, for a person who
    /// linked one) or as a relative path — `/avatar/<something>.jpg` — which is *its own* file server. The old
    /// version turned the relative kind into `baseURL + path`, and that is exactly what the app may no longer do:
    /// the requests base is now `https://weflix.me/api/app/seerr`, an image request cannot carry the bearer token
    /// the proxy requires, and "nothing calls Overseerr directly" is the rule this app is built on. So a relative
    /// avatar is `nil`, the card falls back to the person's name, and the 404 that used to be logged on every
    /// request row is not made at all.
    static func avatarURL(for user: SeerrUser?) -> URL? {
        guard let avatar = user?.avatar, !avatar.isEmpty,
              let url = URL(string: avatar), url.scheme != nil
        else { return nil }

        return url
    }

    /// How much of a quota is left, in the words the app already used (2026-10-25).
    ///
    /// It lives here rather than beside either settings screen because **both** of them show it — the shared
    /// `Settings/SeerrView.swift` on iOS and macOS, and `weflix-tvOS/Features/Settings/SeerrView.swift` on Apple
    /// TV, which is a separate file because tvOS's settings are a sidebar and a focus engine rather than a `List`.
    ///
    /// `nil` (the read failed, or the account has no restriction) reads as "unavailable" — never as "unlimited",
    /// which would be a claim the app cannot make from a missing answer.
    static func quotaSummary(_ restriction: SeerrQuotaRestriction?) -> String {
        guard let restriction else {
            return String(localized: "integrations.seerr.quota.unavailable")
        }

        if restriction.limit == 0 {
            return String(localized: "integrations.seerr.quota.unlimited")
        }

        var parts: [String] = []

        if let used = restriction.used {
            parts.append(String(localized: "integrations.seerr.quota.used \(used)"))
        }

        if let remaining = restriction.remaining {
            parts.append(String(localized: "integrations.seerr.quota.remaining \(remaining)"))
        }

        if let limit = restriction.limit {
            parts.append(String(localized: "integrations.seerr.quota.limit \(limit)"))
        }

        if parts.isEmpty {
            return String(localized: "integrations.seerr.quota.unavailable")
        }

        return parts.joined(separator: " • ")
    }

    static func parsedDate(from value: String?) -> Date? {
        guard let value else { return nil }
        if let date = isoFormatterWithFractional.date(from: value) {
            return date
        }
        return isoFormatter.date(from: value)
    }

    static func mediumDateTimeText(for date: Date) -> String {
        mediumDateTimeFormatter.string(from: date)
    }

    static func relativeText(for date: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let isoFormatterWithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let mediumDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()
}
