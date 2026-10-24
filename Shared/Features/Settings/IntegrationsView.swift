import SwiftUI

/// Settings → Integrations: **one row, and one screen behind it** (2026-10-25).
///
/// It used to build a `SeerrViewModel` — which held an Overseerr address, a sign-in state and a "start setup"
/// flow — and hand it to `SeerrView`. Neither the view model nor the flow exists any more: requests are answered
/// by `https://weflix.me` with the account's own WeFlix token, so there is nothing to set up and nothing to
/// store. What is left is a row that says whether the server has connected this account, and a screen that shows
/// the details it was told (`SeerrView`).
@MainActor
struct IntegrationsView: View {
    @Environment(SeerrStore.self) private var seerrStore

    var body: some View {
        List {
            NavigationLink("integrations.seerr.title") {
                SeerrView()
            }
        }
        .insetListStyle()
        .navigationTitle("settings.integrations.title")
    }
}
