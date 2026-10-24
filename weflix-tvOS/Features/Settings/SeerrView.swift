import SwiftUI

/// **Requests, as the server told us they are** (2026-10-25) — the tvOS half of `Shared/…/SeerrView.swift`, and
/// read-only for the same reason: the app has no Overseerr address, no Overseerr key and no Seerr sign-in of its
/// own, so there is nothing here to set up. What is left is the server's own answer, drawn with tvOS's focus
/// engine (`SettingsList`, so the remote can move through it).
///
/// | `GET /api/app/me` | What this screen says |
/// |---|---|
/// | `requests.enabled: true` | *Requests — connected via WeFlix*, which Overseerr account it is linked as, and the quota left |
/// | `requests.enabled: false` | *Requests aren't set up for your account yet. Ask Luther.* |
///
/// Signing out of WeFlix is in the Settings tab of the library UI, not here: it is the app's only sign-out, and
/// putting a second one behind a settings page would be two doors to one room.
@MainActor
struct SeerrView: View {
    @Environment(SeerrStore.self) private var seerrStore

    var body: some View {
        ZStack {
            Color("Background").ignoresSafeArea()

            SettingsScrollView {
                SettingsList {
                    Section("integrations.seerr.title") {
                        infoRow("integrations.seerr.server.url.title", value: statusText)

                        if let user = seerrStore.user {
                            infoRow("integrations.seerr.account.userId", value: "\(user.id)")
                        }
                    }

                    if seerrStore.user != nil {
                        Section("integrations.seerr.quota.title") {
                            infoRow("integrations.seerr.quota.movies", value: SeerrRequestFormatting.quotaSummary(seerrStore.quota?.movie))
                            infoRow("integrations.seerr.quota.tv", value: SeerrRequestFormatting.quotaSummary(seerrStore.quota?.tv))
                        }
                    }

                    Section("Licences") {
                        infoRow("Licences", value: LicencesView.attribution)
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle("integrations.seerr.title")
    }

    /// "Connected via WeFlix" is the whole story: there is no second service to connect, no key to paste and no
    /// address to remember — the WeFlix account *is* the requests account.
    private var statusText: String {
        seerrStore.isRequestsEnabled
            ? "Connected via WeFlix"
            : "Requests aren't set up for your account yet. Ask Luther."
    }

    private func infoRow(_ title: LocalizedStringKey, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(title)
                .font(.sectionTitle)
                .foregroundStyle(.textPrimary)

            Spacer(minLength: 0)

            Text(value)
                .font(.facts)
                .foregroundStyle(.textSecondary)
                .multilineTextAlignment(.trailing)
        }
    }
}
