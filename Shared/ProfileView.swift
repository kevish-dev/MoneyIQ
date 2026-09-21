import SwiftUI
import MoneyIQCore

/// The profile icon shown in the top-right corner of every top-level tab
/// (App Store-style) — replaces the old "More" tab. Net Worth and Settings
/// live behind it instead of being their own tabs, since they're visited
/// far less often than Home/Split/Insights/Goals.
struct ProfileMenuButton: View {
    let authManager: AuthManager
    let settings: AppSettingsStore
    let notifications: NotificationScheduler
    let lockManager: AppLockManager

    @State private var showingProfile = false

    var body: some View {
        Button {
            showingProfile = true
        } label: {
            if let account = authManager.currentAccount {
                Circle()
                    .fill(AppTheme.accent.opacity(0.15))
                    .frame(width: 30, height: 30)
                    .overlay {
                        Text(initials(for: account))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.accent)
                    }
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .font(.title3)
            }
        }
        .accessibilityLabel("Profile")
        .sheet(isPresented: $showingProfile) {
            ProfileView(
                authManager: authManager,
                settings: settings,
                notifications: notifications,
                lockManager: lockManager
            )
        }
    }

    private func initials(for account: UserAccount) -> String {
        let first = account.firstName.first.map(String.init) ?? ""
        let last = account.lastName.first.map(String.init) ?? ""
        return (first + last).uppercased()
    }
}

struct ProfileView: View {
    let authManager: AuthManager
    let settings: AppSettingsStore
    let notifications: NotificationScheduler
    let lockManager: AppLockManager

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let account = authManager.currentAccount {
                    Section {
                        HStack(spacing: 14) {
                            Circle()
                                .fill(AppTheme.accent.opacity(0.15))
                                .frame(width: 54, height: 54)
                                .overlay {
                                    Text(initials(for: account))
                                        .font(.title3.weight(.semibold))
                                        .foregroundStyle(AppTheme.accent)
                                }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(account.firstName) \(account.lastName)")
                                    .font(.headline)
                                Text(account.email)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, AppTheme.Spacing.xs)
                    }
                }

                Section {
                    NavigationLink {
                        NetWorthView(authManager: authManager)
                    } label: {
                        Label("Net Worth", systemImage: "chart.pie.fill")
                    }
                    NavigationLink {
                        SettingsView(
                            authManager: authManager,
                            settings: settings,
                            notifications: notifications,
                            lockManager: lockManager
                        )
                    } label: {
                        Label("Settings", systemImage: "gearshape.fill")
                    }
                }
            }
            .navigationTitle("Profile")
            .compactListLayout()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func initials(for account: UserAccount) -> String {
        let first = account.firstName.first.map(String.init) ?? ""
        let last = account.lastName.first.map(String.init) ?? ""
        return (first + last).uppercased()
    }
}
