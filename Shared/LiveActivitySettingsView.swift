import SwiftUI
import MoneyIQCore

/// Dedicated tab for customizing what shows up on the Lock Screen and in
/// the Dynamic Island — replaces the old single "Show budget on Lock Screen
/// & Dynamic Island" toggle buried in Settings with two independent
/// switches, since a user might want budget status on one surface but not
/// the other (e.g. Dynamic Island only, to keep the Lock Screen clean).
struct LiveActivitySettingsView: View {
    let authManager: AuthManager
    @Bindable var settings: AppSettingsStore
    let notifications: NotificationScheduler
    let lockManager: AppLockManager

    var body: some View {
        NavigationStack {
            #if os(iOS)
            Form {
                Section {
                    Toggle(isOn: $settings.isBudgetLockScreenEnabled) {
                        Label("Lock Screen", systemImage: "lock.fill")
                    }
                    Toggle(isOn: $settings.isBudgetDynamicIslandEnabled) {
                        Label("Dynamic Island", systemImage: "capsule.inset.filled")
                    }
                } header: {
                    Text("Budget status")
                } footer: {
                    Text("Show your remaining monthly budget and spend progress. Each surface is independent — turn on just the one you want.")
                }

                if settings.isBudgetLockScreenEnabled || settings.isBudgetDynamicIslandEnabled {
                    Section("Preview") {
                        previewCard
                    }
                }
            }
            .navigationTitle("Live Activity")
            .compactFormLayout()
            .toolbar { profileToolbarItem }
            #else
            ContentUnavailableView(
                "iOS Only",
                systemImage: "iphone",
                description: Text("Lock Screen and Dynamic Island Live Activities are an iOS feature — open MoneyIQ on your iPhone to customize this.")
            )
            .navigationTitle("Live Activity")
            .toolbar { profileToolbarItem }
            #endif
        }
    }

    @ToolbarContentBuilder
    private var profileToolbarItem: some ToolbarContent {
        ToolbarItem(placement: AppTheme.trailingToolbarPlacement) {
            ProfileMenuButton(authManager: authManager, settings: settings, notifications: notifications, lockManager: lockManager)
        }
    }

    #if os(iOS)
    private var previewCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            if settings.isBudgetLockScreenEnabled {
                previewRow(icon: "lock.fill", label: "Lock Screen shows your remaining budget and progress bar.")
            }
            if settings.isBudgetDynamicIslandEnabled {
                previewRow(icon: "capsule.inset.filled", label: "Dynamic Island shows a compact remaining-amount pill.")
            }
        }
        .padding(.vertical, AppTheme.Spacing.xs)
    }

    private func previewRow(icon: String, label: String) -> some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.small) {
            Image(systemName: icon)
                .foregroundStyle(AppTheme.accent)
                .frame(width: 20)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    #endif
}

#Preview {
    let container = PersistenceController.makeContainer(inMemory: true)
    let settings = AppSettingsStore()
    LiveActivitySettingsView(
        authManager: AuthManager(modelContext: container.mainContext),
        settings: settings,
        notifications: NotificationScheduler(),
        lockManager: AppLockManager(settings: settings)
    )
}
