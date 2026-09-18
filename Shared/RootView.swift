import SwiftUI
import SwiftData
import MoneyIQCore

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var authManager: AuthManager?
    @State private var showSplash = true

    var body: some View {
        Group {
            if showSplash || authManager == nil {
                SplashView()
            } else if let account = authManager?.currentAccount {
                if account.isOnboarded {
                    HomeView(authManager: authManager!)
                } else {
                    OnboardingView(account: account)
                }
            } else {
                SignInView(authManager: authManager!)
            }
        }
        .task {
            if authManager == nil {
                PersistenceController.seedDefaultCategoriesIfNeeded(context: modelContext)
                authManager = AuthManager(modelContext: modelContext)
            }
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation(.easeInOut(duration: 0.4)) {
                showSplash = false
            }
        }
    }
}

#Preview {
    RootView()
        .modelContainer(PersistenceController.makeContainer(inMemory: true))
}
