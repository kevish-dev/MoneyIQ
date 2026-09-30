import SwiftUI
import SwiftData
import MoneyIQCore

/// Review screen for a payment brought in from another app — shared via the
/// Share Extension (delivered through `ShareImportInbox` / the
/// `moneyiq://import-share` URL, see `RootView`) or pasted from the
/// clipboard. Parses the text with the same heuristics as screenshot
/// import, and nothing is saved until the user confirms it.
struct SharedReceiptImportView: View {
    let sharedText: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var categories: [ExpenseCategory]

    var body: some View {
        NavigationStack {
            ReviewParsedTransactionView(
                parsed: ReceiptParser.parse(text: sharedText),
                categories: categories,
                onSave: { save(from: $0) },
                onCancel: { dismiss() }
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func save(from draft: ReviewParsedTransactionView.Draft) {
        let transaction = ExpenseTransaction(
            amount: draft.amount,
            date: draft.date,
            note: draft.note.isEmpty ? nil : draft.note,
            merchantName: draft.merchantName.isEmpty ? nil : draft.merchantName,
            paymentMethod: .upi,
            isAutoImported: true,
            isBillLike: draft.isBillLike,
            category: draft.category,
            direction: draft.direction
        )
        modelContext.insert(transaction)

        if draft.direction == .expense, let category = draft.category, !draft.merchantName.isEmpty {
            MerchantCategoryMapping.remember(merchant: draft.merchantName, category: category, context: modelContext)
        }

        do {
            try modelContext.save()
        } catch {
            print("MoneyIQ: failed to save shared transaction: \(error)")
        }
        dismiss()
    }
}
