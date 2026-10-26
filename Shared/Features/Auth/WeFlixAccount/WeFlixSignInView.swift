import SwiftUI

/// The app's first screen: **Sign in to WeFlix**.
///
/// It replaces "Choose a service" (Plex / Jellyfin). The look is the one that screen had and still is — the
/// black background, the red WeFlix icon tile, a large bold title, a grey subtitle, fields on a subtle surface,
/// one full-width rounded button — because nothing about the app's *appearance* changed: what changed is who it
/// signs in to. The Plex and Jellyfin code is still in the project and no longer reachable from here.
///
/// Shared by iOS, iPadOS, macOS and tvOS. On tvOS the fields keep the system's own focus treatment
/// (`textFieldStyle(.automatic)`, large control size) so the remote can move between them; everywhere else the
/// field is drawn on the app's own surface.
struct WeFlixSignInView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var session: WeFlixSessionController
    @FocusState private var focusedField: Field?

    /// The line under **Sign in** — one of `SignInGreeting.all`, drawn once when this screen is built.
    ///
    /// Held here rather than asked for in `body` so it cannot change while a person is typing: `body` runs on
    /// every keystroke, and a greeting re-rolled under the field would be text moving on its own. Because
    /// `WeFlixAppGate` builds this view fresh each time it returns to `.signedOut`, a new line is drawn for every
    /// visit, which is the "changes every time" this is for.
    ///
    /// `SignInGreeting.current` **reads** without moving the rotation — the step on happens in `onAppear` below,
    /// once per appearance. Doing it here instead would run on every re-render, because SwiftUI re-creates this
    /// struct each time its parent's body runs.
    @State private var greeting = SignInGreeting.current

    private enum Field: Hashable {
        case identifier
        case password
        case button
    }

    var body: some View {
        ScrollView {
            VStack(spacing: verticalSpacing) {
                header
                form
                signInButton
                errorLabel
            }
            .frame(maxWidth: contentMaxWidth)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Steps the rotation on for the *next* visit, once per appearance — not once per re-render. The line on
        // screen is already `greeting`, captured when this view was built, so this cannot move it.
        .onAppear { SignInGreeting.advance() }
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image("Icon")
                .resizable()
                .scaledToFit()
                .frame(width: appLogoSize, height: appLogoSize)
                .clipShape(RoundedRectangle(cornerRadius: appLogoCornerRadius, style: .continuous))
                .accessibilityHidden(true)

            Text("Sign in")
                .font(.heroTitle)
                .foregroundStyle(.textPrimary)
                .multilineTextAlignment(.center)

            Text(greeting)
                .font(.bodyText)
                .foregroundStyle(.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 620)
    }

    private var form: some View {
        VStack(spacing: fieldSpacing) {
            TextField("Username or email", text: $session.identifier)
                .textContentType(.username)
            #if os(iOS)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.emailAddress)
            #endif
                .focused($focusedField, equals: .identifier)
                .submitLabel(.next)
                .onSubmit { focusedField = .password }
                .weFlixAccountFieldStyle()
                .disabled(session.isWorking)

            SecureField("Password", text: $session.password)
                .textContentType(.password)
                .focused($focusedField, equals: .password)
                .submitLabel(.go)
                .onSubmit { Task { await session.signIn() } }
                .weFlixAccountFieldStyle()
                .disabled(session.isWorking)
        }
        .frame(maxWidth: 520)
    }

    private var signInButton: some View {
        Button {
            focusedField = nil
            Task { await session.signIn() }
        } label: {
            HStack(spacing: 10) {
                if session.isWorking {
                    ProgressView()
                        .controlSize(.small)
                }

                Text("Sign In")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .weFlixSignInButtonStyle()
        .controlSize(.large)
        .frame(maxWidth: 520)
        .focused($focusedField, equals: .button)
        .disabled(session.isWorking || !canSignIn)
        .animation(Motion.animation(Motion.focus, reduceMotion: reduceMotion), value: canSignIn)
    }

    @ViewBuilder
    private var errorLabel: some View {
        if let errorMessage = session.errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                .font(.facts)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
                .accessibilityHint(Text("Tap to dismiss"))
                .onTapGesture { session.clearError() }
        }
    }

    /// The button is live as soon as there is something in both fields — a local check, so an obviously empty
    /// form does not need a round trip. The server checks again, and is the authority.
    private var canSignIn: Bool {
        !session.identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !session.password.isEmpty
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

    private var contentMaxWidth: CGFloat {
        #if os(tvOS)
            720
        #else
            520
        #endif
    }

    private var horizontalPadding: CGFloat {
        #if os(tvOS)
            64
        #else
            24
        #endif
    }

    private var verticalPadding: CGFloat {
        #if os(tvOS)
            72
        #else
            32
        #endif
    }

    private var verticalSpacing: CGFloat {
        #if os(tvOS)
            56
        #else
            32
        #endif
    }

    private var fieldSpacing: CGFloat {
        #if os(tvOS)
            28
        #else
            14
        #endif
    }
}

private extension View {
    /**
     * The Sign In button: a full-width capsule in the WeFlix red (`BrandPrimary`).
     *
     * The app's own `.actionButtonStyle(.primary)` is the *white* main action (Play, Continue), and the tvOS
     * branch of it is `borderedProminent` — so this screen asks for the red one instead, and on tvOS it keeps the
     * system's bordered-prominent treatment (with the tint) so the remote's focus lift and the focused colours
     * are still the native ones.
     */
    @ViewBuilder
    func weFlixSignInButtonStyle() -> some View {
        #if os(tvOS)
            buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(.brandPrimary)
                .foregroundStyle(.white)
        #else
            buttonStyle(WeFlixSignInButtonStyle())
        #endif
    }

    /**
     * The field look the app's other forms use (`JellyfinAuthenticationView`): a subtle surface with a hairline
     * stroke, filling the form's width — except on tvOS, where the system's own field is kept so the focus engine
     * and the remote-driven keyboard behave natively.
     */
    @ViewBuilder
    func weFlixAccountFieldStyle() -> some View {
        #if os(tvOS)
            textFieldStyle(.automatic)
                .controlSize(.large)
        #else
            textFieldStyle(.plain)
                .padding(.horizontal, 16)
                .frame(minHeight: 54)
                .background(
                    .surfaceSubtle,
                    in: RoundedRectangle(cornerRadius: LayoutMetrics.cardCornerRadius, style: .continuous),
                )
                .overlay {
                    RoundedRectangle(cornerRadius: LayoutMetrics.cardCornerRadius, style: .continuous)
                        .stroke(.strokeSubtle)
                }
        #endif
    }
}

#if !os(tvOS)
    /// WeFlix red, disabled while the form is incomplete or a sign-in is in flight.
    private struct WeFlixSignInButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            WeFlixSignInButton(configuration: configuration)
        }
    }

    private struct WeFlixSignInButton: View {
        @Environment(\.isEnabled) private var isEnabled
        let configuration: ButtonStyleConfiguration

        var body: some View {
            configuration.label
                .fontWeight(.semibold)
                .foregroundStyle(isEnabled ? Color.white : Color.white.opacity(0.7))
                .padding(.horizontal, 20)
                .frame(minHeight: LayoutMetrics.actionButtonHeight)
                // WeFlix red in **both** states: an empty form dims the button rather than draining its colour, so
                // the screen still reads as WeFlix before anything is typed.
                .background(
                    Color.brandPrimary.opacity(isEnabled ? 1 : 0.45),
                    in: Capsule(style: .continuous),
                )
                .contentShape(Capsule(style: .continuous))
                .opacity(configuration.isPressed ? 0.7 : 1)
            #if os(macOS)
                .hoverLift(scale: 1.03)
            #endif
        }
    }
#endif

