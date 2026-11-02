import SwiftUI
import MoneyIQCore

enum MoneyIQTab: Hashable {
    case home, split, insights, goals, projects
}

struct MainTabView: View {
    let authManager: AuthManager
    let settings: AppSettingsStore
    let notifications: NotificationScheduler
    let lockManager: AppLockManager
    @Binding var selectedTab: MoneyIQTab
    @Binding var expenseActionRequest: WidgetRoute?

    var body: some View {
        // Net Worth, Settings, and Live Activity deliberately aren't tabs —
        // they're visited far less often than the 5 below, so they live
        // behind the profile icon (top-right of each tab, App Store-style)
        // instead. Live Activity's old tab slot is now Projects (freelance
        // client work), which earns a tab since it's a primary workflow.
        TabView(selection: $selectedTab) {
            Tab("Home", systemImage: "house.fill", value: .home) {
                HomeView(authManager: authManager, settings: settings, notifications: notifications, lockManager: lockManager, expenseActionRequest: $expenseActionRequest)
            }
            Tab("Split", systemImage: "person.2.fill", value: .split) {
                LedgerView(authManager: authManager, settings: settings, notifications: notifications, lockManager: lockManager)
            }
            Tab("Insights", systemImage: "chart.line.uptrend.xyaxis", value: .insights) {
                InsightsView(authManager: authManager, settings: settings, notifications: notifications, lockManager: lockManager)
            }
            Tab("Goals", systemImage: "target", value: .goals) {
                GoalsView(authManager: authManager, settings: settings, notifications: notifications, lockManager: lockManager)
            }
            Tab("Projects", systemImage: "briefcase.fill", value: .projects) {
                ProjectsView(authManager: authManager, settings: settings, notifications: notifications, lockManager: lockManager)
            }
        }
    }
}
