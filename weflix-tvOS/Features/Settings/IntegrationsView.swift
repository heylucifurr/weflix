import SwiftUI

/// Settings → Integrations on tvOS: **one card, and one screen behind it** (2026-10-25).
///
/// It used to build a `SeerrViewModel` (an Overseerr address, a sign-in state, a "start setup" flow) and pass it
/// to `SeerrView`. None of that exists any more: requests are answered by `https://weflix.me` with the account's
/// own WeFlix token, so the card says whether the server has connected this account and `SeerrView` shows what it
/// was told. The card's subtitle used to print the user's Overseerr address, which is exactly the thing the app
/// must not know — it prints the server's answer instead.
@MainActor
struct IntegrationsView: View {
    @Environment(SeerrStore.self) private var seerrStore

    var body: some View {
        ZStack {
            Color("Background").ignoresSafeArea()

            SettingsScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    SettingsLink(title: "integrations.seerr.title") {
                        SeerrView()
                    } label: {
                        integrationCard(
                            title: "integrations.seerr.title",
                            subtitle: seerrStatusText,
                            systemImage: "film",
                            isConnected: seerrStore.isRequestsEnabled,
                        )
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle(radius: LayoutMetrics.cardCornerRadius))
                    .settingsFocus("seerr", isDefault: true)

                    Spacer(minLength: 0)
                }
                .padding(20)
            }
        }
    }

    private var seerrStatusText: String {
        seerrStore.isRequestsEnabled
            ? "Connected via WeFlix"
            : "Requests aren't set up for your account yet. Ask Luther."
    }

    private func integrationCard(
        title: LocalizedStringKey,
        subtitle: String,
        systemImage: String,
        isConnected: Bool,
    ) -> some View {
        HStack(spacing: 24) {
            ZStack {
                // Hierarchical styles: the card is the label of a bordered button, which turns white when focused.
                RoundedRectangle(cornerRadius: MediaArtworkMetrics.compactCornerRadius, style: .continuous)
                    .fill(.secondary.opacity(0.2))

                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(.primary)
            }
            .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.sectionTitle)
                Text(subtitle)
                    .foregroundStyle(.secondary)
                    .font(.facts)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)

            if isConnected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .symbolRenderingMode(.hierarchical)
            }

            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
