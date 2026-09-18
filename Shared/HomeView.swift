import SwiftUI
import SwiftData
import MoneyIQCore

struct HomeView: View {
    let authManager: AuthManager

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ExpenseTransaction.date, order: .reverse) private var transactions: [ExpenseTransaction]
    @Query private var categories: [ExpenseCategory]

    @State private var showingAddTransaction = false
    @State private var showingScreenshotImport = false

    var body: some View {
        NavigationStack {
            List {
                if let account = authManager.currentAccount {
                    Section {
                        Text("Hi, \(account.firstName)")
                            .font(.headline)
                        BudgetCardView(currencyCode: account.preferredCurrencyCode)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .padding(.vertical, 6)
                    }
                }

                Section("Recent transactions") {
                    if transactions.isEmpty {
                        Text("No transactions yet.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(transactions) { transaction in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(transaction.merchantName ?? transaction.category?.name ?? "Uncategorized")
                                    if transaction.isAutoImported {
                                        Image(systemName: "text.viewfinder")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    if transaction.isBillLike {
                                        Text("Bill")
                                            .font(.caption2.weight(.semibold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(.orange.opacity(0.18), in: Capsule())
                                            .foregroundStyle(.orange)
                                    }
                                }
                                if let category = transaction.category {
                                    Text(category.name)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if let note = transaction.note {
                                    Text(note).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(transaction.amount, format: .currency(code: account?.preferredCurrencyCode ?? "USD"))
                        }
                    }
                }
            }
            .navigationTitle("MoneyIQ")
            .toolbar {
                ToolbarItem {
                    Menu {
                        Button {
                            showingAddTransaction = true
                        } label: {
                            Label("Enter Manually", systemImage: "square.and.pencil")
                        }
                        Button {
                            showingScreenshotImport = true
                        } label: {
                            Label("From Screenshot", systemImage: "text.viewfinder")
                        }
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddTransaction) {
                AddTransactionView(categories: categories)
            }
            .sheet(isPresented: $showingScreenshotImport) {
                ScreenshotImportView(categories: categories)
            }
        }
    }

    private var account: UserAccount? { authManager.currentAccount }
}

private struct AddTransactionView: View {
    let categories: [ExpenseCategory]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var amountText = ""
    @State private var note = ""
    @State private var selectedCategory: ExpenseCategory?
    @State private var paymentMethod: PaymentMethod = .cash
    @State private var date = Date.now

    var body: some View {
        NavigationStack {
            Form {
                TextField("Amount", text: $amountText)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                Picker("Category", selection: $selectedCategory) {
                    Text("None").tag(ExpenseCategory?.none)
                    ForEach(categories) { category in
                        Text(category.name).tag(ExpenseCategory?.some(category))
                    }
                }
                Picker("Payment method", selection: $paymentMethod) {
                    ForEach(PaymentMethod.allCases, id: \.self) { method in
                        Text(method.rawValue.capitalized).tag(method)
                    }
                }
                DatePicker("Date", selection: $date, displayedComponents: .date)
                TextField("Note", text: $note)
            }
            .navigationTitle("Add Transaction")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(Decimal(string: amountText) == nil)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func save() {
        guard let amount = Decimal(string: amountText) else { return }
        let transaction = ExpenseTransaction(
            amount: amount,
            date: date,
            note: note.isEmpty ? nil : note,
            paymentMethod: paymentMethod,
            category: selectedCategory
        )
        modelContext.insert(transaction)
        try? modelContext.save()
        dismiss()
    }
}
