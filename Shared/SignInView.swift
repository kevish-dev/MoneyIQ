import SwiftUI
import MoneyIQCore

struct SignInView: View {
    @Bindable var authManager: AuthManager

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 8) {
                Image(systemName: "indianrupeesign.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)
                Text("MoneyIQ")
                    .font(.largeTitle.bold())
                Text("Track spending. Stay on budget.")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(spacing: 12) {
                signInButton(kind: .apple, title: "Continue with Apple", systemImage: "apple.logo")
                signInButton(kind: .google, title: "Continue with Google", systemImage: "globe")
                signInButton(kind: .github, title: "Continue with GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
            }
            .padding(.horizontal, 32)

            if let error = authManager.lastError {
                Text(error.localizedDescription)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()
        }
        .padding()
        .overlay {
            if authManager.isSigningIn {
                ProgressView()
            }
        }
    }

    @ViewBuilder
    private func signInButton(kind: AuthProviderKind, title: String, systemImage: String) -> some View {
        let available = authManager.isAvailable(kind)
        Button {
            Task { await authManager.signIn(with: kind) }
        } label: {
            Label(available ? title : "\(title) (not configured)", systemImage: systemImage)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!available || authManager.isSigningIn)
    }
}

#Preview {
    let container = PersistenceController.makeContainer(inMemory: true)
    SignInView(authManager: AuthManager(modelContext: container.mainContext))
}
