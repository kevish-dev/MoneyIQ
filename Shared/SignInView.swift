import SwiftUI
import MoneyIQCore

struct SignInView: View {
    @Bindable var authManager: AuthManager

    var body: some View {
        ZStack {
            GlassBackdrop()

            VStack(spacing: 28) {
                Spacer(minLength: 40)

                VStack(spacing: 14) {
                    MLogoView(size: 84)

                    Text("Welcome to MoneyIQ")
                        .font(.system(size: 26, weight: .bold, design: .rounded))

                    Text("Sign in to start tracking your spending")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Spacer(minLength: 20)

                GlassEffectContainer(spacing: 14) {
                    VStack(spacing: 14) {
                        appleButton
                        googleButton
                        gitHubButton
                    }
                }
                .padding(.horizontal, 28)

                if let error = authManager.lastError {
                    Text(error.localizedDescription)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Spacer(minLength: 32)
            }
            .padding()
        }
        .overlay {
            if authManager.isSigningIn {
                ProgressView()
                    .controlSize(.large)
                    .glassEffect()
                    .padding(24)
            }
        }
    }

    // Apple's HIG calls for a black (or white) "Sign in with Apple" button
    // with the Apple mark — kept as an SF Symbol since it's a system glyph,
    // not a bundled asset.
    private var appleButton: some View {
        signInButton(kind: .apple, title: "Continue with Apple", tint: .black, labelColor: .white) {
            Image(systemName: "apple.logo")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    // Google's own brand guidelines call for a white/neutral button with the
    // full-color "G" mark — never recolored, never placed on a saturated tint.
    private var googleButton: some View {
        signInButton(kind: .google, title: "Continue with Google", tint: .white, labelColor: .black.opacity(0.87)) {
            Image("GoogleLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
        }
    }

    // GitHub's own docs show a dark button with the white Octocat mark.
    private var gitHubButton: some View {
        signInButton(kind: .github, title: "Continue with GitHub", tint: Color(red: 0.13, green: 0.13, blue: 0.15), labelColor: .white) {
            Image("GitHubMark")
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .foregroundStyle(.white)
        }
    }

    @ViewBuilder
    private func signInButton(
        kind: AuthProviderKind,
        title: String,
        tint: Color,
        labelColor: Color,
        @ViewBuilder icon: () -> some View
    ) -> some View {
        let available = authManager.isAvailable(kind)
        Button {
            Task { await authManager.signIn(with: kind) }
        } label: {
            HStack(spacing: 12) {
                icon()
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(labelColor)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 8)
                if !available {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(labelColor)
                }
            }
            .padding(.horizontal, 20)
            .frame(height: 54)
        }
        .buttonStyle(.glassProminent)
        .tint(tint)
        .disabled(!available || authManager.isSigningIn)
        .opacity(available ? 1 : 0.5)
    }
}

#Preview {
    let container = PersistenceController.makeContainer(inMemory: true)
    SignInView(authManager: AuthManager(modelContext: container.mainContext))
}
