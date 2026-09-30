import SwiftUI
import MoneyIQCore

/// Confirmation screen after OCR parsing — nothing from a screenshot import
/// is saved until the user reviews it here, since heuristic parsing is
/// never going to be 100% right.
struct ReviewParsedTransactionView: View {
    struct Draft {
        var amount: Decimal
        var date: Date
        var merchantName: String
        var note: String
        var category: ExpenseCategory?
        var isBillLike: Bool
    }

    let parsed: ParsedReceipt
    let categories: [ExpenseCategory]
    let onSave: (Draft) -> Void
    let onCancel: () -> Void

    @Environment(\.modelContext) private var modelContext

    @State private var amountText: String
    @State private var date: Date
    @State private var merchantName: String
    @State private var note = ""
    @State private var selectedCategory: ExpenseCategory?
    @State private var isBillLike: Bool
    @State private var categoryWasAutoSuggested = false

    init(parsed: ParsedReceipt, categories: [ExpenseCategory], onSave: @escaping (Draft) -> Void, onCancel: @escaping () -> Void) {
        self.parsed = parsed
        self.categories = categories
        self.onSave = onSave
        self.onCancel = onCancel
        _amountText = State(initialValue: parsed.amount.map { "\($0)" } ?? "")
        _date = State(initialValue: parsed.date ?? .now)
        _merchantName = State(initialValue: parsed.merchantName ?? "")
        _isBillLike = State(initialValue: parsed.looksLikeBill)
    }

    var body: some View {
        Form {
            Section {
                Label("Detected from your screenshot — check it over before saving.", systemImage: "sparkles")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Details") {
                HStack {
                    Text("Amount")
                    Spacer()
                    TextField("0.00", text: $amountText)
                        .multilineTextAlignment(.trailing)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                }
                TextField("Merchant", text: $merchantName)
                DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
            }

            Section {
                Picker("Category", selection: $selectedCategory) {
                    Text("None").tag(ExpenseCategory?.none)
                    ForEach(categories) { category in
                        Text(category.name).tag(ExpenseCategory?.some(category))
                    }
                }
                if categoryWasAutoSuggested {
                    Label("Suggested from past transactions at this merchant", systemImage: "wand.and.stars")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle("This looks like a recurring bill", isOn: $isBillLike)
            }

            Section("Note") {
                TextField("Optional note", text: $note, axis: .vertical)
            }

            if !parsed.rawText.isEmpty {
                Section("Scanned text") {
                    Text(parsed.rawText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(6)
                }
            }
        }
        .navigationTitle("Review")
        .compactFormLayout()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(Decimal(string: amountText) == nil)
            }
        }
        .task {
            guard !merchantName.isEmpty else { return }
            if let suggested = MerchantCategoryMapping.category(forMerchant: merchantName, context: modelContext) {
                selectedCategory = suggested
                categoryWasAutoSuggested = true
            }
        }
    }

    private func save() {
        guard let amount = Decimal(string: amountText) else { return }
        onSave(
            Draft(
                amount: amount,
                date: date,
                merchantName: merchantName,
                note: note,
                category: selectedCategory,
                isBillLike: isBillLike
            )
        )
    }
}
