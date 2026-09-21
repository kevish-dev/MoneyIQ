import SwiftUI
import MoneyIQCore

struct MainTabView: View {
    let authManager: AuthManager
    let settings: AppSettingsStore
    let notifications: NotificationScheduler
    let lockManager: AppLockManager

    var body: some View {
        TabView {
            Tab("Home", systemImage: "house.fill") {
                HomeView(authManager: authManager, settings: settings)
            }
            Tab("Split", systemImage: "person.2.fill") {
                LedgerView(authManager: authManager)
            }
            Tab("Insights", systemImage: "chart.line.uptrend.xyaxis") {
                InsightsView(authManager: authManager)
            }
            Tab("Goals", systemImage: "target") {
                GoalsView(authManager: authManager)
            }
            Tab("Net Worth", systemImage: "chart.pie.fill") {
                NetWorthView(authManager: authManager)
            }
            Tab("Settings", systemImage: "gearshape.fill") {
                SettingsView(
                    authManager: authManager,
                    settings: settings,
                    notifications: notifications,
                    lockManager: lockManager
                )
            }
        }
    }
}
