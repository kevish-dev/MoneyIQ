import SwiftUI
import SwiftData
import WidgetKit
import MoneyIQCore

/// Publishes aggregate spending whenever the app's data changes. Mounted
/// above the tabs so edits in any section refresh Home and Lock widgets.
struct WidgetSnapshotBridge: View {
    let account: UserAccount?

    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Budget.createdAt, order: .reverse) private var budgets: [Budget]
    @Query private var transactions: [ExpenseTransaction]

    private var content: WidgetSnapshot? {
        guard let account, account.isOnboarded else { return nil }
        var snapshot = WidgetSnapshotBuilder.make(
            currencyCode: account.preferredCurrencyCode,
            budget: budgets.first,
            transactions: transactions
        )
        // A changing clock must not restart the task on every redraw.
        snapshot.refreshedAt = .distantPast
        return snapshot
    }

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .task(id: content) { publish(content) }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { publish(content) }
            }
    }

    private func publish(_ content: WidgetSnapshot?) {
        guard var content else {
            WidgetSnapshotStore.clear()
            WidgetCenter.shared.reloadAllTimelines()
            return
        }
        content.refreshedAt = .now
        if WidgetSnapshotStore.save(content) {
            WidgetCenter.shared.reloadAllTimelines()
        } else {
            print("MoneyIQ: unable to publish widget spending snapshot")
        }
    }
}
