import Foundation

/// Every failure the requests screen can hit, and **the plain sentence it prints for it** (2026-10-25).
///
/// The old set was `invalidURL` / `requestFailed` / `decodingFailed`, which a screen could only answer with
/// "the connection failed" — and that was wrong three times out of four: a `409` from an account with no linked
/// Overseerr user, a `401` after a revoked device token, and a title that has already been asked for are not
/// connection problems, and telling somebody to check their Wi-Fi for them is a lie.
///
/// So the cases are now the *things a person can act on*, and the wording lives here, in one place, rather than
/// being spelled out again in each view model:
///
/// | Case | What the screen says |
/// |---|---|
/// | `.signInAgain` | "Please sign in again." — and the app goes back to the sign-in screen |
/// | `.unreachable` | "Can't reach WeFlix. Check your connection and try again." |
/// | `.refused(sentence)` | the server's own words (the unlinked sentence, "already requested", a quota refusal) |
/// | `.requestFailed(status)` | a sentence built from the status, for a refusal that carried none |
///
/// The three original cases are kept deliberately: they are the vocabulary the rest of the app already throws,
/// and `SeerrNetworkClient` still produces them for the two situations that really are about the request itself.
enum SeerrAPIError: Error {
    /// A URL that could not be built. Impossible with a fixed base, and kept so a caller has something to throw.
    case invalidURL
    /// An HTTP status the client has nothing better to say about. `statusCode` is `-1` for a non-HTTP answer.
    case requestFailed(statusCode: Int)
    /// A successful answer whose body could not be read as the model asked for.
    case decodingFailed(Error)
    /// `401` — the server does not accept this device's token any more. The app returns to its sign-in screen.
    case signInAgain
    /// The app could not reach WeFlix at all: no network, DNS, TLS, a timeout.
    case unreachable
    /// The server refused, and said why in words meant for a person. **Shown verbatim.**
    case refused(String)

    /// The sentence a screen prints for this failure.
    ///
    /// Plain English literals rather than lookup keys, for the reason `WeFlixAuthError.message` gives: these are
    /// new sentences, `String(localized:)` with a missing key prints the key itself, and a screen that says
    /// `integrations.seerr.error.connection` to a friend is worse than one that says nothing.
    var message: String {
        switch self {
        case .invalidURL:
            "The requests service isn't available right now."
        case let .requestFailed(statusCode):
            Self.sentence(for: statusCode)
        case .decodingFailed:
            "WeFlix sent an answer the app could not read."
        case .signInAgain:
            "Please sign in again."
        case .unreachable:
            "Can't reach WeFlix. Check your connection and try again."
        case let .refused(sentence):
            sentence
        }
    }

    /// What a bare status means, said plainly. Only reached when the server sent no sentence of its own.
    private static func sentence(for statusCode: Int) -> String {
        switch statusCode {
        case -1:
            "WeFlix sent an answer the app could not read."
        case 401:
            "Please sign in again."
        case 403:
            "Your WeFlix account can't do that."
        case 404:
            "That isn't available in the app."
        case 409:
            "That has already been requested."
        case 429:
            "That is a lot of requests just now. Try again in a moment."
        case 500 ... 599:
            "WeFlix is having trouble with requests. Try again in a moment."
        default:
            "The request could not be completed."
        }
    }
}

extension Error {
    /// The sentence a requests screen prints for this failure, whatever produced it.
    func seerrSentence() -> String {
        switch self {
        case let error as SeerrAPIError:
            error.message
        case is URLError:
            SeerrAPIError.unreachable.message
        default:
            "The request could not be completed."
        }
    }

    /// Does this failure mean the device's WeFlix token is over? (`401` — the one answer that returns the app to
    /// its sign-in screen.)
    var seerrMeansSignedOut: Bool {
        guard let error = self as? SeerrAPIError else { return false }

        if case .signInAgain = error {
            return true
        }

        return false
    }
}

/// The one thing the requests layer can tell the rest of the app: **the server refused this device's token**
/// (2026-10-25).
///
/// A `401` from the proxy is not a requests problem — the whole app is signed out — and the screen that must
/// change is the root, not the pill on the requests screen. `SeerrNetworkClient` posts this from the one place
/// every Seerr call is validated, so no view model has to remember to check, and `WeFlixAppGate` listens: it
/// forgets the token and puts the sign-in screen back up, exactly as it does when a gateway read is refused.
///
/// A notification rather than a shared object because the network client is deliberately not `@MainActor` and
/// holds no reference to any state: it is the seam between "a call failed" and "the app is signed out".
extension Notification.Name {
    /// Posted when a `/api/app/seerr/**` call is answered `401`. Carries nothing — not even the status.
    static let weflixSignInEnded = Notification.Name("weflix.signInEnded")
}

/// The sender for the above, so the name is posted from one place and misspelled nowhere.
enum WeFlixSignInEnded {
    static func post() {
        NotificationCenter.default.post(name: .weflixSignInEnded, object: nil)
    }
}


