import SwiftUI
import SwiftData
import MoneyIQCore

struct SettingsView: View {
    let authManager: AuthManager
    @Bindable var settings: AppSettingsStore
    @Bindable var notifications: NotificationScheduler
    let lockManager: AppLockManager

    @Query(sort: \ExpenseTransaction.date) private var transactions: [ExpenseTransaction]
    @State private var notificationDeniedAlertKind: NotificationToggleKind?

    private enum NotificationToggleKind {
        case daily
        case weekly
    }

    var body: some View {
        Form {
            securitySection
            notificationsSection
            importSection
            dataSection
            accountSection
        }
        .navigationTitle("Settings")
        .compactFormLayout()
        .alert(
            "Notifications are off",
            isPresented: Binding(
                get: { notificationDeniedAlertKind != nil },
                set: { if !$0 { notificationDeniedAlertKind = nil } }
            )
        ) {
            Button("Open Settings") { openSystemNotificationSettings() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Turn on notifications for MoneyIQ in Settings to enable reminders.")
        }
        .task {
            if settings.isWeeklySummaryEnabled {
                rescheduleWeeklySummary()
            }
        }
    }

    private var securitySection: some View {
        Section {
            let biometry = lockManager.availableBiometry
            Toggle(isOn: $settings.isAppLockEnabled) {
                Label("Require \(biometry.displayName)", systemImage: biometry.systemImageName)
            }
            .disabled(biometry == .none)
        } header: {
            Text("Security")
        } footer: {
            if lockManager.availableBiometry == .none {
                Text("Face ID or Touch ID isn't set up on this device.")
            } else {
                Text("Lock MoneyIQ behind \(lockManager.availableBiometry.displayName) whenever you open or return to the app.")
            }
        }
    }

    private var notificationsSection: some View {
        Section {
            Toggle("Daily spending reminder", isOn: dailyReminderBinding)
            if settings.isDailyReminderEnabled {
                DatePicker(
                    "Remind me at",
                    selection: timeBinding(for: \.dailyReminderTime),
                    displayedComponents: .hourAndMinute
                )
            }

            Toggle("Weekly summary", isOn: weeklySummaryBinding)
            if settings.isWeeklySummaryEnabled {
                Picker("Day", selection: $settings.weeklySummaryWeekday) {
                    ForEach(1...7, id: \.self) { weekday in
                        Text(weekdaySymbol(weekday)).tag(weekday)
                    }
                }
                DatePicker(
                    "At",
                    selection: timeBinding(for: \.weeklySummaryTime),
                    displayedComponents: .hourAndMinute
                )
            }

            NavigationLink {
                RemindersView(authManager: authManager, notifications: notifications)
            } label: {
                Label("Custom Payment Reminders", systemImage: "bell.badge")
            }
        } header: {
            Text("Notifications")
        } footer: {
            Text("Reminders are scheduled entirely on this device.")
        }
    }

    private var dataSection: some View {
        Section {
            NavigationLink {
                BackupRestoreView(authManager: authManager)
            } label: {
                Label("Backup & Restore", systemImage: "arrow.clockwise.icloud")
            }
        } header: {
            Text("Data")
        } footer: {
            Text("Export your data so it survives an uninstall, or restore it on a new device.")
        }
    }

    private var importSection: some View {
        Section {
            NavigationLink {
                UPIAutomationSetupView()
            } label: {
                Label("Automatic UPI import", systemImage: "arrow.down.message")
            }
        } header: {
            Text("Expense capture")
        } footer: {
            Text("Connect a bank debit SMS through Shortcuts to log eligible UPI payments automatically.")
        }
    }

    private var accountSection: some View {
        Section {
            if let account = authManager.currentAccount {
                LabeledContent("Name", value: "\(account.firstName) \(account.lastName)")
                LabeledContent("Email", value: account.email)
            }
            Button("Sign Out", role: .destructive) {
                authManager.signOut()
            }
        } header: {
            Text("Account")
        }
    }

    private var dailyReminderBinding: Binding<Bool> {
        Binding(
            get: { settings.isDailyReminderEnabled },
            set: { newValue in
                guard newValue else {
                    settings.isDailyReminderEnabled = false
                    notifications.cancelDailyReminder()
                    return
                }
                Task {
                    let granted = await notifications.requestPermissionIfNeeded()
                    if granted {
                        settings.isDailyReminderEnabled = true
                        notifications.scheduleDailyReminder(at: settings.dailyReminderTime)
                    } else {
                        settings.isDailyReminderEnabled = false
                        notificationDeniedAlertKind = .daily
                    }
                }
            }
        )
    }

    private var weeklySummaryBinding: Binding<Bool> {
        Binding(
            get: { settings.isWeeklySummaryEnabled },
            set: { newValue in
                guard newValue else {
                    settings.isWeeklySummaryEnabled = false
                    notifications.cancelWeeklySummary()
                    return
                }
                Task {
                    let granted = await notifications.requestPermissionIfNeeded()
                    if granted {
                        settings.isWeeklySummaryEnabled = true
                        rescheduleWeeklySummary()
                    } else {
                        settings.isWeeklySummaryEnabled = false
                        notificationDeniedAlertKind = .weekly
                    }
                }
            }
        )
    }

    /// Local notification content is fixed at schedule time, so this
    /// recomputes real spending numbers (via `InsightsEngine`) and
    /// re-registers the notification — called whenever the schedule changes
    /// and once more whenever Settings appears, so the number stays fresh.
    private func rescheduleWeeklySummary() {
        let forecast = InsightsEngine.cashFlowForecast(
            transactions: transactions,
            monthlyIncome: authManager.currentAccount?.monthlyIncome ?? 0
        )
        let currencyCode = authManager.currentAccount?.preferredCurrencyCode ?? "USD"
        let spentText = forecast.spentSoFarThisMonth.formatted(.currency(code: currencyCode))
        let body = "You've spent \(spentText) so far this month. Open MoneyIQ to see the full breakdown."

        notifications.scheduleWeeklySummary(
            weekday: settings.weeklySummaryWeekday,
            time: settings.weeklySummaryTime,
            body: body
        )
    }

    private func timeBinding(for keyPath: ReferenceWritableKeyPath<AppSettingsStore, DateComponents>) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(from: settings[keyPath: keyPath]) ?? .now
            },
            set: { newDate in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                settings[keyPath: keyPath] = comps
                if settings.isDailyReminderEnabled {
                    notifications.scheduleDailyReminder(at: settings.dailyReminderTime)
                }
                if settings.isWeeklySummaryEnabled {
                    rescheduleWeeklySummary()
                }
            }
        )
    }

    private func weekdaySymbol(_ weekday: Int) -> String {
        let symbols = Calendar.current.weekdaySymbols
        return symbols[(weekday - 1) % 7]
    }

    private func openSystemNotificationSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

import UIKit

#Preview {
    let container = PersistenceController.makeContainer(inMemory: true)
    let settings = AppSettingsStore()
    NavigationStack {
        SettingsView(
            authManager: AuthManager(modelContext: container.mainContext),
            settings: settings,
            notifications: NotificationScheduler(),
            lockManager: AppLockManager(settings: settings)
        )
    }
}
