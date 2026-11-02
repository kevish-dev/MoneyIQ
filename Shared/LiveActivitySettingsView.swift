import SwiftUI
import MoneyIQCore

/// Lives behind the profile menu (see `ProfileView`) — customizes what
/// shows up on the Lock Screen and in the Dynamic Island. Two independent
/// switches, since a user might want budget status on one surface but not
/// the other (e.g. Dynamic Island only, to keep the Lock Screen clean).
struct LiveActivitySettingsView: View {
    let authManager: AuthManager
    @Bindable var settings: AppSettingsStore
    let notifications: NotificationScheduler
    let lockManager: AppLockManager

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $settings.isBudgetLockScreenEnabled) {
                    Label("Lock Screen", systemImage: "lock.fill")
                }
                if settings.isBudgetLockScreenEnabled {
                    contentKindPicker(selection: $settings.lockScreenContentKind)
                }
            } header: {
                Text("Lock Screen")
            } footer: {
                Text("Choose what shows on your Lock Screen while a Live Activity is running.")
            }

            Section {
                Toggle(isOn: $settings.isBudgetDynamicIslandEnabled) {
                    Label("Dynamic Island", systemImage: "capsule.inset.filled")
                }
                if settings.isBudgetDynamicIslandEnabled {
                    contentKindPicker(selection: $settings.dynamicIslandContentKind)
                }
            } header: {
                Text("Dynamic Island")
            } footer: {
                Text("Choose separate content for the Island. If only the Lock Screen activity is on, the Island shows an icon without financial amounts.")
            }

            if settings.isBudgetLockScreenEnabled || settings.isBudgetDynamicIslandEnabled {
                Section("Preview") {
                    previewCard
                }
            }
        }
        .navigationTitle("Live Activity")
        .compactFormLayout()
    }

    private func contentKindPicker(selection: Binding<LiveActivityContentKind>) -> some View {
        Picker("Shows", selection: selection) {
            ForEach(LiveActivityContentKind.allCases, id: \.self) { kind in
                Label(kind.displayName, systemImage: kind.systemIconName).tag(kind)
            }
        }
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            if settings.isBudgetLockScreenEnabled {
                previewRow(icon: "lock.fill", label: "Lock Screen: \(previewDescription(for: settings.lockScreenContentKind))")
            }
            if settings.isBudgetDynamicIslandEnabled {
                previewRow(icon: "capsule.inset.filled", label: "Dynamic Island: \(previewDescription(for: settings.dynamicIslandContentKind))")
            }
        }
        .padding(.vertical, AppTheme.Spacing.xs)
    }

    private func previewDescription(for kind: LiveActivityContentKind) -> String {
        switch kind {
        case .budgetProgress: "remaining budget and spend progress bar."
        case .savingsGoalProgress: "your nearest savings goal's progress."
        case .dailyPace: "how much you can spend per day to stay on budget."
        }
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
}

#Preview {
    let container = PersistenceController.makeContainer(inMemory: true)
    let settings = AppSettingsStore()
    NavigationStack {
        LiveActivitySettingsView(
            authManager: AuthManager(modelContext: container.mainContext),
            settings: settings,
            notifications: NotificationScheduler(),
            lockManager: AppLockManager(settings: settings)
        )
    }
}
