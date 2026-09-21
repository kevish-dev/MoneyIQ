import SwiftUI
import MoneyIQCore

struct MainTabView: View {
    let authManager: AuthManager
    let settings: AppSettingsStore
    let notifications: NotificationScheduler
    let lockManager: AppLockManager

    var body: some View {
        // Net Worth, Settings, and Live Activity deliberately aren't tabs —
        // they're visited far less often than the 5 below, so they live
        // behind the profile icon (top-right of each tab, App Store-style)
        // instead. Live Activity's old tab slot is now Projects (freelance
        // client work), which earns a tab since it's a primary workflow.
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
            Tab("Projects", systemImage: "briefcase.fill") {
                ProjectsView(authManager: authManager, settings: settings, notifications: notifications, lockManager: lockManager)
            }
        }
    }
}
