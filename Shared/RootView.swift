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

    /// Payments shared in from other apps, waiting to be reviewed one at a
    /// time. Fed by the `moneyiq://import-share` URL and by
    /// `ShareImportInbox`, which also catches shares made while MoneyIQ
    /// couldn't be opened directly.
    @State private var importQueue: [PendingShareImport] = []
    @State private var activeImport: PendingShareImport?
    /// `activeImport` is already nil by the time the sheet's `onDismiss`
    /// runs, so remember which one was showing.
    @State private var presentedImportID: UUID?
    @State private var handledImportIDs: Set<UUID> = []
    @State private var suspendedImportForLock = false
    @State private var selectedTab: MoneyIQTab = .home
    @State private var expenseActionRequest: WidgetRoute?
    @State private var pendingWidgetRoute: WidgetRoute?

    var body: some View {
        Group {
            if showSplash || authManager == nil || lockManager == nil {
                SplashView()
            } else if let account = authManager?.currentAccount {
                if account.isOnboarded {
                    if lockManager!.isLocked {
                        AppLockView(lockManager: lockManager!)
                    } else {
                        MainTabView(
                            authManager: authManager!,
                            settings: settingsStore,
                            notifications: notificationScheduler,
                            lockManager: lockManager!,
                            selectedTab: $selectedTab,
                            expenseActionRequest: $expenseActionRequest
                        )
                    }
                } else {
                    OnboardingView(account: account)
                }
            } else {
                SignInView(authManager: authManager!)
            }
        }
        .background {
            if let authManager {
                WidgetSnapshotBridge(account: authManager.currentAccount)
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
            collectPendingImports()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                lockManager?.lockIfEnabled()
                collectPendingImports()
                openPendingWidgetRoute()
            }
        }
        .onChange(of: canPresentImports) { _, canPresent in
            if canPresent {
                openPendingWidgetRoute()
                presentNextImport()
            } else if let active = activeImport {
                // Locked mid-review: the sheet sits above the lock screen, so
                // hide it — but keep the import queued for after unlock.
                suspendedImportForLock = true
                importQueue.insert(active, at: 0)
                activeImport = nil
            }
        }
        .onOpenURL { url in
            if let route = WidgetRoute(url: url) {
                pendingWidgetRoute = route
                openPendingWidgetRoute()
                return
            }
            guard url.scheme == "moneyiq", url.host == "import-share" else { return }
            let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let id = queryItems.first { $0.name == "id" }?.value.flatMap(UUID.init(uuidString:))
            if let text = queryItems.first(where: { $0.name == "text" })?.value, !text.isEmpty {
                enqueue(PendingShareImport(id: id ?? UUID(), text: text))
            }
            collectPendingImports()
        }
        .sheet(item: $activeImport, onDismiss: importSheetDismissed) { pending in
            SharedReceiptImportView(sharedText: pending.text)
        }
    }

    /// Never over the lock screen, sign-in, or onboarding.
    private var canPresentImports: Bool {
        guard !showSplash, let lockManager, !lockManager.isLocked,
              authManager?.currentAccount?.isOnboarded == true else { return false }
        return true
    }

    private func collectPendingImports() {
        ShareImportInbox.pendingImports().forEach(enqueue)
        presentNextImport()
    }

    private func openPendingWidgetRoute() {
        guard scenePhase == .active, canPresentImports,
              let route = pendingWidgetRoute else { return }
        pendingWidgetRoute = nil
        switch route {
        case .budget:
            selectedTab = .home
        case .addExpense:
            selectedTab = .home
            expenseActionRequest = .addExpense
        case .pasteExpense:
            selectedTab = .home
            expenseActionRequest = .pasteExpense
        case .screenshotExpense:
            selectedTab = .home
            expenseActionRequest = .screenshotExpense
        case .insights:
            selectedTab = .insights
        }
    }

    private func enqueue(_ pending: PendingShareImport) {
        guard !handledImportIDs.contains(pending.id),
              activeImport?.id != pending.id,
              !importQueue.contains(where: { $0.id == pending.id }) else { return }
        importQueue.append(pending)
    }

    private func presentNextImport() {
        guard activeImport == nil, canPresentImports, !importQueue.isEmpty else { return }
        let next = importQueue.removeFirst()
        presentedImportID = next.id
        activeImport = next
    }

    /// Saved or cancelled, either way it's been dealt with — drop it from the
    /// inbox so it doesn't come back, then move on to the next one. It stays
    /// in the inbox until now so a share isn't lost if the app is killed
    /// mid-review.
    private func importSheetDismissed() {
        guard !suspendedImportForLock else {
            suspendedImportForLock = false
            presentedImportID = nil
            return
        }
        if let id = presentedImportID {
            handledImportIDs.insert(id)
            ShareImportInbox.remove(id: id)
            presentedImportID = nil
        }
        Task { @MainActor in
            // Let the dismissal animation finish before presenting again.
            try? await Task.sleep(for: .milliseconds(450))
            presentNextImport()
        }
    }
}

#Preview {
    RootView()
        .modelContainer(PersistenceController.makeContainer(inMemory: true))
}
