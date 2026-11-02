import AppIntents
import SwiftData
import Foundation
#if os(iOS)
import WidgetKit
#endif

/// "Log ₹200 for lunch" from the PRD's Phase 6 example. This runs in the
/// main app's own process (it's a plain `AppIntent` in the app target, not a
/// separate App Intents Extension), so it opens the same on-disk SwiftData
/// store the app itself uses — no App Groups needed. After saving, it also
/// refreshes the aggregate snapshot used by Home and Lock Screen widgets.
public struct LogExpenseIntent: AppIntent {
    public static let title: LocalizedStringResource = "Log Expense"
    public static let description = IntentDescription("Add a new expense to MoneyIQ.")

    @Parameter(title: "Amount")
    public var amount: Double

    @Parameter(title: "For", default: nil)
    public var note: String?

    public init() {}

    public init(amount: Double, note: String?) {
        self.amount = amount
        self.note = note
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let capturedAmount = amount
        let capturedNote = note

        try await MainActor.run {
            let container = PersistenceController.makeContainer()
            let context = container.mainContext
            let transaction = ExpenseTransaction(
                amount: Decimal(capturedAmount),
                note: capturedNote,
                paymentMethod: .other
            )
            context.insert(transaction)
            try context.save()
            #if os(iOS)
            if let currentSnapshot = WidgetSnapshotStore.load(),
               let transactions = try? context.fetch(FetchDescriptor<ExpenseTransaction>()),
               let budgets = try? context.fetch(FetchDescriptor<Budget>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])) {
                let snapshot = WidgetSnapshotBuilder.make(
                    currencyCode: currentSnapshot.currencyCode,
                    budget: budgets.first,
                    transactions: transactions
                )
                if WidgetSnapshotStore.save(snapshot) {
                    WidgetCenter.shared.reloadAllTimelines()
                }
            }
            #endif
        }

        let dialog: IntentDialog = note.map { "Logged \(amount.formatted()) for \($0)." } ?? "Logged \(amount.formatted())."
        return .result(dialog: dialog)
    }
}

public struct MoneyIQShortcuts: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogExpenseIntent(),
            phrases: [
                // \.$amount can't be embedded here — AppShortcut phrase
                // parameters only support AppEntity/AppEnum types, not raw
                // Double. Siri still prompts for the amount conversationally
                // since it's a required, non-optional parameter.
                "Log an expense in \(.applicationName)",
                "Log a transaction in \(.applicationName)",
                "Add a transaction in \(.applicationName)"
            ],
            shortTitle: "Log Expense",
            systemImageName: "creditcard"
        )
        AppShortcut(
            intent: ImportUPIPaymentIntent(),
            phrases: [
                "Import a UPI debit in \(.applicationName)"
            ],
            shortTitle: "Import UPI Debit",
            systemImageName: "arrow.down.doc"
        )
    }
}
