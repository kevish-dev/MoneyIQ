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
            if authManager.currentAccount != nil {
                AvatarView(account: authManager.currentAccount, diameter: 30)
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
}

struct ProfileView: View {
    let authManager: AuthManager
    let settings: AppSettingsStore
    let notifications: NotificationScheduler
    let lockManager: AppLockManager

    @Environment(\.dismiss) private var dismiss
    @State private var showingAvatarPicker = false

    var body: some View {
        NavigationStack {
            List {
                if let account = authManager.currentAccount {
                    Section {
                        Button {
                            showingAvatarPicker = true
                        } label: {
                            HStack(spacing: 14) {
                                ZStack(alignment: .bottomTrailing) {
                                    AvatarView(account: account, diameter: 54)
                                    Image(systemName: "pencil.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundStyle(.white, AppTheme.accent)
                                        .background(Circle().fill(.white))
                                        .offset(x: 2, y: 2)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(account.firstName) \(account.lastName)")
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text(account.email)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, AppTheme.Spacing.xs)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section {
                    NavigationLink {
                        NetWorthView(authManager: authManager)
                    } label: {
                        Label("Net Worth", systemImage: "chart.pie.fill")
                    }
                    NavigationLink {
                        LiveActivitySettingsView(
                            authManager: authManager,
                            settings: settings,
                            notifications: notifications,
                            lockManager: lockManager
                        )
                    } label: {
                        Label("Live Activity", systemImage: "lock.display")
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
            .sheet(isPresented: $showingAvatarPicker) {
                if let account = authManager.currentAccount {
                    AvatarPickerView(account: account)
                }
            }
        }
    }
}
