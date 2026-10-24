import SwiftUI

/// **Requests, as the server told us they are** (2026-10-25) — read-only, and deliberately so.
///
/// This screen used to be a setup form: an Overseerr address to type, a "start setup" button, and three ways to
/// sign in to somebody else's instance (Plex, local, Jellyfin). All of it is gone, and not because it was untidy.
/// The app is not allowed to know an Overseerr address, hold an Overseerr key or have a Seerr session of its own:
/// requests are the server's job, and the only thing a person can meaningfully do here is read whether their
/// account is connected.
///
/// So it is the server's own answer, and nothing else:
///
/// | `GET /api/app/me` | What this screen says |
/// |---|---|
/// | `requests.enabled: true` | *Requests — connected via WeFlix*, which Overseerr account it is linked as, and the quota left |
/// | `requests.enabled: false` | *Requests aren't set up for your account yet. Ask Luther.* |
///
/// There is no "sign out of Seerr" here either: signing out of **WeFlix** is the only sign-out the app has, and
/// it lives in Settings (`Shared/Features/Settings/SettingsView.swift`) — the same place it always did.
@MainActor
struct SeerrView: View {
    @Environment(SeerrStore.self) private var seerrStore

    var body: some View {
        List {
            Section("integrations.seerr.title") {
                LabeledContent("integrations.seerr.server.url.title") {
                    HStack(spacing: 8) {
                        Text(statusText)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)

                        Spacer(minLength: 0)

                        Image(systemName: seerrStore.isRequestsEnabled ? "checkmark.circle.fill" : "exclamationmark.circle")
                            .foregroundStyle(seerrStore.isRequestsEnabled ? .green : .secondary)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
            }

            if let user = seerrStore.user {
                Section("integrations.seerr.account.title") {
                    LabeledContent("integrations.seerr.account.userId") {
                        Text("\(user.id)")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("integrations.seerr.quota.title") {
                    LabeledContent("integrations.seerr.quota.movies") {
                        Text(SeerrRequestFormatting.quotaSummary(seerrStore.quota?.movie))
                            .foregroundStyle(.secondary)
                    }

                    LabeledContent("integrations.seerr.quota.tv") {
                        Text(SeerrRequestFormatting.quotaSummary(seerrStore.quota?.tv))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .insetListStyle()
        .navigationTitle("integrations.seerr.title")
    }

    /// The one sentence this screen is really about.
    ///
    /// **Three states, three sentences** — and the middle one is the one that was wrong on 2026-10-25: a WeFlix
    /// that has not been updated to answer `requests` at all must never be reported as *this account's* fault.
    private var statusText: String {
        switch seerrStore.requestsState {
        case .enabled:
            // The whole story: there is no second service to connect, no key to paste and no address to
            // remember — the WeFlix account *is* the requests account.
            "Connected via WeFlix"
        case .notLinked:
            "Requests aren't set up for your account yet. Ask Luther."
        case .unknown:
            "This WeFlix server does not have requests yet. Ask Luther to update WeFlix."
        }
    }
}

