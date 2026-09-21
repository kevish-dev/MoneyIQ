import SwiftUI
import SwiftData
import MoneyIQCore

struct HomeView: View {
    let authManager: AuthManager
    let settings: AppSettingsStore
    let notifications: NotificationScheduler
    let lockManager: AppLockManager

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ExpenseTransaction.date, order: .reverse) private var transactions: [ExpenseTransaction]
    @Query private var categories: [ExpenseCategory]
    @Query(sort: \Budget.createdAt, order: .reverse) private var budgets: [Budget]
    @Query(sort: \SavingsGoal.targetDate) private var goals: [SavingsGoal]

    @State private var showingAddTransaction = false
    @State private var showingScreenshotImport = false
    @State private var editingTransaction: ExpenseTransaction?
    @State private var deletingTransaction: ExpenseTransaction?
    @State private var searchText = ""
    @State private var sortOption: TransactionSortOption = .dateDescending
    @State private var categoryFilter: ExpenseCategory?
    @State private var billsOnly = false
    #if os(iOS)
    @State private var liveActivityManager = BudgetLiveActivityManager()
    #endif

    private enum TransactionSortOption: String, CaseIterable, Identifiable {
        case dateDescending = "Newest first"
        case dateAscending = "Oldest first"
        case amountDescending = "Amount: high to low"
        case amountAscending = "Amount: low to high"

        var id: String { rawValue }
    }

    /// `transactions` (the raw `@Query`) filtered by search text/category/
    /// bills-only, then sorted per `sortOption` — the `@Query`'s own sort
    /// (newest first) is just the default before any of this is applied.
    private var displayedTransactions: [ExpenseTransaction] {
        var result = transactions

        if let categoryFilter {
            result = result.filter { $0.category?.id == categoryFilter.id }
        }
        if billsOnly {
            result = result.filter { $0.isBillLike }
        }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            result = result.filter { transaction in
                transaction.merchantName?.localizedCaseInsensitiveContains(query) == true
                    || transaction.category?.name.localizedCaseInsensitiveContains(query) == true
                    || transaction.note?.localizedCaseInsensitiveContains(query) == true
            }
        }

        switch sortOption {
        case .dateDescending: result.sort { $0.date > $1.date }
        case .dateAscending: result.sort { $0.date < $1.date }
        case .amountDescending: result.sort { $0.amount > $1.amount }
        case .amountAscending: result.sort { $0.amount < $1.amount }
        }
        return result
    }

    private var isFiltering: Bool {
        categoryFilter != nil || billsOnly
    }

    /// Extracted so the category filter Menu's button labels aren't
    /// each an inline if/else — that was pushing the surrounding Menu
    /// expression past the type-checker's time budget.
    @ViewBuilder
    private func categoryMenuLabel(name: String, isSelected: Bool) -> some View {
        if isSelected {
            Label(name, systemImage: "checkmark")
        } else {
            Text(name)
        }
    }

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
                    } else if displayedTransactions.isEmpty {
                        Text("No transactions match your search/filters.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(displayedTransactions) { transaction in
                        TransactionRow(
                            transaction: transaction,
                            currencyCode: account?.preferredCurrencyCode ?? "USD",
                            onEdit: { editingTransaction = transaction },
                            onDelete: { deletingTransaction = transaction }
                        )
                    }
                }
            }
            .navigationTitle("MoneyIQ")
            .compactListLayout()
            .alert(
                "Delete Transaction?",
                isPresented: Binding(
                    get: { deletingTransaction != nil },
                    set: { if !$0 { deletingTransaction = nil } }
                ),
                presenting: deletingTransaction
            ) { transaction in
                Button("Delete", role: .destructive) { deleteTransaction(transaction) }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("This can't be undone.")
            }
            .searchable(text: $searchText, prompt: "Search transactions")
            // The toolbar "Add" menu was removed — there's now a single
            // entry point for starting a new transaction: the "Add Expense"
            // button on the budget card, which itself presents the same
            // "Enter Manually" / "From Screenshot" choice as a menu.
            .toolbar {
                ToolbarItem(placement: AppTheme.trailingToolbarPlacement) {
                    ProfileMenuButton(authManager: authManager, settings: settings, notifications: notifications, lockManager: lockManager)
                }
                ToolbarItem(placement: AppTheme.trailingToolbarPlacement) {
                    Menu {
                        Picker("Sort", selection: $sortOption) {
                            ForEach(TransactionSortOption.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }

                        Menu("Category") {
                            Button {
                                categoryFilter = nil
                            } label: {
                                categoryMenuLabel(name: "All categories", isSelected: categoryFilter == nil)
                            }
                            ForEach(categories) { category in
                                Button {
                                    categoryFilter = category
                                } label: {
                                    categoryMenuLabel(name: category.name, isSelected: categoryFilter?.id == category.id)
                                }
                            }
                        }

                        Toggle(isOn: $billsOnly) {
                            Label("Bills only", systemImage: "doc.text")
                        }
                    } label: {
                        Image(systemName: isFiltering
                            ? "line.3.horizontal.decrease.circle.fill"
                            : "line.3.horizontal.decrease.circle")
                    }
                }
            }
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
                let pace = BudgetEngine.dailyPace(remaining: progress.remaining)
                let nearestGoal = goals.first { !$0.isComplete }

                let state = BudgetActivityAttributes.ContentState(
                    spent: progress.spent,
                    cap: progress.effectiveCap,
                    currencyCode: account.preferredCurrencyCode,
                    showOnLockScreen: settings.isBudgetLockScreenEnabled,
                    showOnDynamicIsland: settings.isBudgetDynamicIslandEnabled,
                    lockScreenKind: settings.lockScreenContentKind,
                    dynamicIslandKind: settings.dynamicIslandContentKind,
                    goalName: nearestGoal?.name,
                    goalSaved: nearestGoal?.savedAmount ?? 0,
                    goalTarget: nearestGoal?.targetAmount ?? 0,
                    recommendedDailySpend: pace.recommendedDailySpend,
                    daysRemainingInMonth: pace.daysRemaining
                )
                if liveActivityManager.isActive {
                    await liveActivityManager.update(state: state)
                } else {
                    liveActivityManager.start(state: state)
                }
            }
            #endif
        }
    }

    #if os(iOS)
    private var liveActivitySyncKey: String {
        "\(settings.isBudgetLockScreenEnabled)-\(settings.isBudgetDynamicIslandEnabled)-\(settings.lockScreenContentKind.rawValue)-\(settings.dynamicIslandContentKind.rawValue)-\(budgets.first?.id.uuidString ?? "none")-\(transactions.count)-\(goals.count)"
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

}

/// Pulled out of `HomeView.body` as its own view — the whole List was one
/// enormous expression that the type-checker choked on ("unable to
/// type-check this expression in reasonable time"); a real view struct
/// avoids feeding it as one inline closure.
private struct TransactionRow: View {
    let transaction: ExpenseTransaction
    let currencyCode: String
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
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
                Text(relativeTimeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let note = transaction.note {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(amountText)
                .font(.subheadline.weight(.semibold))
        }
        .padding(.vertical, AppTheme.Spacing.small)
        .contentShape(Rectangle())
        // Hold-to-edit/delete instead of swipe — consistent with Split and
        // Goals, and more discoverable than a hidden swipe gesture.
        .contextMenu {
            Button(action: onEdit) {
                Label("Edit", systemImage: "pencil")
            }
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var amountText: String {
        "-" + transaction.amount.formatted(.currency(code: currencyCode))
    }

    /// "Today, 9:42 AM" for today's transactions, otherwise a short date —
    /// matches the design reference's transaction-row timestamp style.
    private var relativeTimeText: String {
        let date = transaction.date
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
    @State private var merchantName = ""
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
                TextField("Paid to (merchant, person, etc.)", text: $merchantName)
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
            merchantName: merchantName.isEmpty ? nil : merchantName,
            paymentMethod: paymentMethod,
            category: selectedCategory
        )
        modelContext.insert(transaction)
        do {
            try modelContext.save()
        } catch {
            print("MoneyIQ: failed to save transaction: \(error)")
        }
        dismiss()
    }
}

private struct EditTransactionView: View {
    let transaction: ExpenseTransaction
    let categories: [ExpenseCategory]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var amountText: String
    @State private var merchantName: String
    @State private var note: String
    @State private var selectedCategory: ExpenseCategory?
    @State private var paymentMethod: PaymentMethod
    @State private var date: Date

    init(transaction: ExpenseTransaction, categories: [ExpenseCategory]) {
        self.transaction = transaction
        self.categories = categories
        _amountText = State(initialValue: NSDecimalNumber(decimal: transaction.amount).stringValue)
        _merchantName = State(initialValue: transaction.merchantName ?? "")
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
                TextField("Paid to (merchant, person, etc.)", text: $merchantName)
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
        transaction.merchantName = merchantName.isEmpty ? nil : merchantName
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
