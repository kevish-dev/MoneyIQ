import SwiftUI
import MoneyIQCore

struct MainTabView: View {
    let authManager: AuthManager
    let settings: AppSettingsStore
    let notifications: NotificationScheduler
    let lockManager: AppLockManager

    var body: some View {
        // Net Worth and Settings deliberately aren't tabs — they're visited
        // far less often than the 5 below, so they live behind the profile
        // icon (top-left of each tab, App Store-style) instead. "More" is
        // gone; its slot is now the Live Activity customization screen.
        TabView {
            Tab("Home", systemImage: "house.fill") {
                HomeView(authManager: authManager, settings: settings, notifications: notifications, lockManager: lockManager)
            }
            Tab("Split", systemImage: "person.2.fill") {
                LedgerView(authManager: authManager, settings: settings, notifications: notifications, lockManager: lockManager)
            }
            Tab("Insights", systemImage: "chart.line.uptrend.xyaxis") {
                InsightsView(authManager: authManager, settings: settings, notifications: notifications, lockManager: lockManager)
            }
            Tab("Goals", systemImage: "target") {
                GoalsView(authManager: authManager, settings: settings, notifications: notifications, lockManager: lockManager)
            }
            Tab("Live Activity", systemImage: "lock.display") {
                LiveActivitySettingsView(
                    authManager: authManager,
                    settings: settings,
                    notifications: notifications,
                    lockManager: lockManager
                )
            }
        }
    }
}
