import SwiftUI
import SwiftData
import MoneyIQCore

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var authManager: AuthManager?

    var body: some View {
        Group {
            if let authManager {
                if let account = authManager.currentAccount {
                    if account.isOnboarded {
                        HomeView(authManager: authManager)
                    } else {
                        OnboardingView(account: account)
                    }
                } else {
                    SignInView(authManager: authManager)
                }
            } else {
                ProgressView()
            }
        }
        .task {
            if authManager == nil {
                PersistenceController.seedDefaultCategoriesIfNeeded(context: modelContext)
                authManager = AuthManager(modelContext: modelContext)
            }
        }
    }
}

#Preview {
    RootView()
        .modelContainer(PersistenceController.makeContainer(inMemory: true))
}
