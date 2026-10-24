import SwiftUI

/// What the app shows once a WeFlix account is signed in — deliberately almost nothing.
///
/// This is the placeholder the first step ends at: the home, the libraries and the player are loaded from the
/// WeFlix server in the next step, and until they exist there is nothing honest to draw but the account's own
/// name and a way out. Saying "signed in as …" is not a stand-in for a feature: it is the proof that the token
/// works, that `GET /api/app/me` answered, and that the Keychain survived the launch.
///
/// `notice` is the one sentence that can appear here (2026-10-25): *"This WeFlix server doesn't have the app's
/// library yet. Ask Luther to update WeFlix."* — the case where the sign-in is fine and the **deployment** is
/// behind. It belongs on this card rather than on the sign-in form, because the person is still signed in.
struct WeFlixSignedInView: View {
    let user: WeFlixUser
    let isWorking: Bool
    var notice: String?
    let onSignOut: () -> Void

    @FocusState private var signOutIsFocused: Bool

    var body: some View {
        VStack(spacing: verticalSpacing) {
            Spacer(minLength: 0)

            Image("Icon")
                .resizable()
                .scaledToFit()
                .frame(width: appLogoSize, height: appLogoSize)
                .clipShape(RoundedRectangle(cornerRadius: appLogoCornerRadius, style: .continuous))
                .accessibilityHidden(true)

            VStack(spacing: 12) {
                Text("Signed in as \(user.displayName)")
                    .font(.heroTitle)
                    .foregroundStyle(.textPrimary)
                    .multilineTextAlignment(.center)

                Text(user.isOwner ? "WeFlix owner account" : "WeFlix account")
                    .font(.bodyText)
                    .foregroundStyle(.textSecondary)
                    .multilineTextAlignment(.center)

                if let notice {
                    Text(notice)
                        .font(.bodyText)
                        .foregroundStyle(.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }
            }

            Spacer(minLength: 0)

            Button(action: onSignOut) {
                Text("Sign Out")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .actionButtonStyle(.secondary)
            .controlSize(.large)
            .frame(maxWidth: 420)
            .focused($signOutIsFocused)
            .disabled(isWorking)
        }
        .frame(maxWidth: 620)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(horizontalPadding)
        .onAppear { signOutIsFocused = true }
    }

    private var appLogoSize: CGFloat {
        #if os(tvOS)
            192
        #else
            128
        #endif
    }

    private var appLogoCornerRadius: CGFloat {
        #if os(tvOS)
            40
        #else
            28
        #endif
    }

    private var verticalSpacing: CGFloat {
        #if os(tvOS)
            56
        #else
            32
        #endif
    }

    private var horizontalPadding: CGFloat {
        #if os(tvOS)
            64
        #else
            24
        #endif
    }
}
