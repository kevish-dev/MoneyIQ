import AppIntents
import Foundation
import SwiftData
#if os(iOS)
import WidgetKit
#endif

/// Accepts a bank debit SMS from a user-created Shortcuts Message automation.
/// Shortcuts passes the message text; MoneyIQ never reads the Messages inbox.
public struct ImportUPIPaymentIntent: AppIntent {
    public static let title: LocalizedStringResource = "Import UPI Debit"
    public static let description = IntentDescription("Save a UPI debit from a bank message, skipping uncertain or repeated messages.")

    @Parameter(title: "Bank message")
    public var message: String

    public init() {}

    public init(message: String) {
        self.message = message
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let candidate = UPIPaymentMessageParser.parse(message) else {
            return .result(dialog: "No clear UPI debit found. Nothing was added.")
        }

        let saved = try await MainActor.run { () throws -> Bool in
            let container = PersistenceController.makeContainer()
            let context = container.mainContext
            let transactions = try context.fetch(FetchDescriptor<ExpenseTransaction>())
            guard !UPIPaymentMessageParser.isDuplicate(candidate, in: transactions) else { return false }

            let category = candidate.payee.flatMap {
                MerchantCategoryMapping.category(forMerchant: $0, context: context)
            }
            context.insert(ExpenseTransaction(
                amount: candidate.amount,
                date: candidate.date,
                merchantName: candidate.payee,
                paymentMethod: .upi,
                isAutoImported: true,
                isBillLike: candidate.looksLikeBill,
                category: category,
                importFingerprint: candidate.fingerprint
            ))
            try context.save()

            #if os(iOS)
            if let currentSnapshot = WidgetSnapshotStore.load(),
               let updatedTransactions = try? context.fetch(FetchDescriptor<ExpenseTransaction>()),
               let budgets = try? context.fetch(FetchDescriptor<Budget>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])) {
                let snapshot = WidgetSnapshotBuilder.make(
                    currencyCode: currentSnapshot.currencyCode,
                    budget: budgets.first,
                    transactions: updatedTransactions
                )
                if WidgetSnapshotStore.save(snapshot) {
                    WidgetCenter.shared.reloadAllTimelines()
                }
            }
            #endif
            return true
        }

        let amount = candidate.amount.formatted(.currency(code: "INR"))
        let dialog: IntentDialog = saved ? "Added \(amount) to MoneyIQ." : "This UPI debit is already in MoneyIQ."
        return .result(dialog: dialog)
    }
}
