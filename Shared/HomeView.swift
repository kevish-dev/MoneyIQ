import SwiftUI
import SwiftData
import MoneyIQCore

struct HomeView: View {
    let authManager: AuthManager
    let settings: AppSettingsStore

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ExpenseTransaction.date, order: .reverse) private var transactions: [ExpenseTransaction]
    @Query private var categories: [ExpenseCategory]
    @Query(sort: \Budget.createdAt, order: .reverse) private var budgets: [Budget]

    @State private var showingAddTransaction = false
    @State private var showingScreenshotImport = false
    @State private var editingTransaction: ExpenseTransaction?
    #if os(iOS)
    @State private var liveActivityManager = BudgetLiveActivityManager()
    #endif

    var body: some View {
        NavigationStack {
            List {
                if let account = authManager.currentAccount {
                    // Not wrapped in a `Section` on purpose — an empty-header
                    // Section here was rendering a thin divider line above
                    // the budget card in plain list style.
                    BudgetCardView(
                        currencyCode: account.preferredCurrencyCode,
                        onAddExpenseManually: { showingAddTransaction = true },
                        onAddExpenseFromScreenshot: { showingScreenshotImport = true }
                    )
                    .listRowInsets(EdgeInsets(
                        top: AppTheme.Spacing.small,
                        leading: AppTheme.Spacing.large,
                        bottom: AppTheme.Spacing.small,
                        trailing: AppTheme.Spacing.large
                    ))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }

                Section("Recent transactions") {
                    if transactions.isEmpty {
                        Text("No transactions yet.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(transactions) { transaction in
                        HStack(spacing: 12) {
                            IconBubble(systemName: transaction.category?.systemIconName ?? "creditcard")

                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(transaction.merchantName ?? transaction.category?.name ?? "Uncategorized")
                                        .font(.subheadline.weight(.medium))
                                    if transaction.isAutoImported {
                                        Image(systemName: "text.viewfinder")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    if transaction.editedAt != nil {
                                        Image(systemName: "pencil.circle.fill")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    if transaction.isBillLike {
                                        Text("Bill")
                                            .font(.caption2.weight(.semibold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(AppTheme.accent.opacity(0.18), in: Capsule())
                                            .foregroundStyle(AppTheme.accent)
                                    }
                                }
                                Text(relativeTimeText(for: transaction.date))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let note = transaction.note {
                                    Text(note).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text("-\(transaction.amount, format: .currency(code: account?.preferredCurrencyCode ?? "USD"))")
                                .font(.subheadline.weight(.semibold))
                        }
                        .padding(.vertical, AppTheme.Spacing.small)
                        // No whole-row .onTapGesture here on purpose: a
                        // full-row tap gesture competes with List's own
                        // swipe-to-delete recognizer and was blocking swipe
                        // actions entirely. Edit now lives only in the
                        // swipe actions below (tap the row to edit isn't
                        // available anymore — swipe left instead).
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                deleteTransaction(transaction)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button {
                                editingTransaction = transaction
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(AppTheme.accent)
                        }
                    }
                }
            }
            .navigationTitle("MoneyIQ")
            .compactListLayout()
            // The toolbar "Add" menu was removed — there's now a single
            // entry point for starting a new transaction: the "Add Expense"
            // button on the budget card, which itself presents the same
            // "Enter Manually" / "From Screenshot" choice as a menu.
            .sheet(item: $editingTransaction) { transaction in
                EditTransactionView(transaction: transaction, categories: categories)
            }
            .sheet(isPresented: $showingAddTransaction) {
                AddTransactionView(categories: categories)
            }
            .sheet(isPresented: $showingScreenshotImport) {
                ScreenshotImportView(categories: categories)
            }
            #if os(iOS)
            // Keeps the Lock Screen / Dynamic Island Live Activity in sync
            // with real budget data whenever it changes — opt-in via
            // Settings, since showing anything outside the app shouldn't be
            // the default just because a budget exists.
            .task(id: liveActivitySyncKey) {
                guard settings.isBudgetLiveActivityEnabled else {
                    if liveActivityManager.isActive {
                        await liveActivityManager.end()
                    }
                    return
                }
                guard let budget = budgets.first, let account = authManager.currentAccount else { return }
                let progress = BudgetEngine.monthProgress(for: budget, transactions: transactions)
                if liveActivityManager.isActive {
                    await liveActivityManager.update(
                        spent: progress.spent,
                        cap: progress.effectiveCap,
                        currencyCode: account.preferredCurrencyCode
                    )
                } else {
                    liveActivityManager.start(
                        spent: progress.spent,
                        cap: progress.effectiveCap,
                        currencyCode: account.preferredCurrencyCode
                    )
                }
            }
            #endif
        }
    }

    #if os(iOS)
    private var liveActivitySyncKey: String {
        "\(settings.isBudgetLiveActivityEnabled)-\(budgets.first?.id.uuidString ?? "none")-\(transactions.count)"
    }
    #endif

    private var account: UserAccount? { authManager.currentAccount }

    private func deleteTransaction(_ transaction: ExpenseTransaction) {
        modelContext.delete(transaction)
        do {
            try modelContext.save()
        } catch {
            // Surface real save failures instead of silently swallowing
            // them (a bare `try?` here previously made delete look like it
            // "didn't work" with no clue why).
            print("MoneyIQ: failed to delete transaction: \(error)")
        }
    }

    /// "Today, 9:42 AM" for today's transactions, otherwise a short date —
    /// matches the design reference's transaction-row timestamp style.
    private func relativeTimeText(for date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return "Today, \(date.formatted(.dateTime.hour().minute()))"
        } else if Calendar.current.isDateInYesterday(date) {
            return "Yesterday, \(date.formatted(.dateTime.hour().minute()))"
        }
        return date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }
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
                DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                TextField("Note", text: $note)
            }
            .navigationTitle("Add Transaction")
            .compactFormLayout()
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

private struct EditTransactionView: View {
    let transaction: ExpenseTransaction
    let categories: [ExpenseCategory]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var amountText: String
    @State private var note: String
    @State private var selectedCategory: ExpenseCategory?
    @State private var paymentMethod: PaymentMethod
    @State private var date: Date

    init(transaction: ExpenseTransaction, categories: [ExpenseCategory]) {
        self.transaction = transaction
        self.categories = categories
        _amountText = State(initialValue: NSDecimalNumber(decimal: transaction.amount).stringValue)
        _note = State(initialValue: transaction.note ?? "")
        _selectedCategory = State(initialValue: transaction.category)
        _paymentMethod = State(initialValue: transaction.paymentMethod)
        _date = State(initialValue: transaction.date)
    }

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
                DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                TextField("Note", text: $note)
            }
            .navigationTitle("Edit Transaction")
            .compactFormLayout()
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
        transaction.amount = amount
        transaction.date = date
        transaction.note = note.isEmpty ? nil : note
        transaction.paymentMethod = paymentMethod
        transaction.category = selectedCategory
        transaction.editedAt = .now
        do {
            try modelContext.save()
        } catch {
            print("MoneyIQ: failed to save edited transaction: \(error)")
        }
        dismiss()
    }
}
