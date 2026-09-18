import SwiftUI
import SwiftData
import MoneyIQCore

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @State private var authManager: AuthManager?
    @State private var settingsStore = AppSettingsStore()
    @State private var notificationScheduler = NotificationScheduler()
    @State private var lockManager: AppLockManager?
    @State private var showSplash = true

    var body: some View {
        Group {
            if showSplash || authManager == nil || lockManager == nil {
                SplashView()
            } else if let account = authManager?.currentAccount {
                if account.isOnboarded {
                    if lockManager!.isLocked {
                        AppLockView(lockManager: lockManager!)
                    } else {
                        HomeView(
                            authManager: authManager!,
                            settings: settingsStore,
                            notifications: notificationScheduler,
                            lockManager: lockManager!
                        )
                    }
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
                lockManager = AppLockManager(settings: settingsStore)
            }
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation(.easeInOut(duration: 0.4)) {
                showSplash = false
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                lockManager?.lockIfEnabled()
            }
        }
    }
}

#Preview {
    RootView()
        .modelContainer(PersistenceController.makeContainer(inMemory: true))
}
