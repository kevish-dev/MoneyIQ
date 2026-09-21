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
    @State private var hasAppeared = false
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

    /// Profile + filter icons, floating directly on the gradient (not in the
    /// system nav bar) — the nav bar is hidden on Home so the hero card can
    /// bleed behind the status bar/Dynamic Island; `.safeAreaPadding(.top)`
    /// keeps this row itself clear of the notch even though its container
    /// extends further up.
    private var topBar: some View {
        HStack {
            ProfileMenuButton(authManager: authManager, settings: settings, notifications: notifications, lockManager: lockManager)
            Spacer()
            filterMenu
        }
        .safeAreaPadding(.top)
        .padding(.top, AppTheme.Spacing.small)
    }

    private var filterMenu: some View {
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
                    if categoryFilter == nil {
                        Label("All categories", systemImage: "checkmark")
                    } else {
                        Text("All categories")
                    }
                }
                ForEach(categories) { category in
                    Button {
                        categoryFilter = category
                    } label: {
                        if categoryFilter?.id == category.id {
                            Label(category.name, systemImage: "checkmark")
                        } else {
                            Text(category.name)
                        }
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
                .font(.title2)
                .foregroundStyle(.white)
                .padding(8)
                .background(.white.opacity(0.18), in: Circle())
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    ZStack(alignment: .top) {
                        if let account = authManager.currentAccount {
                            BudgetCardView(
                                currencyCode: account.preferredCurrencyCode,
                                fullBleedTop: true,
                                onAddExpenseManually: { showingAddTransaction = true },
                                onAddExpenseFromScreenshot: { showingScreenshotImport = true }
                            )
                        }
                        topBar
                    }
                    .padding(.horizontal, AppTheme.Spacing.large)
                    .padding(.bottom, AppTheme.Spacing.small)
                    // Minimal load-in: the hero settles into place first...
                    .opacity(hasAppeared ? 1 : 0)
                    .offset(y: hasAppeared ? 0 : -10)
                    .animation(.easeOut(duration: 0.4), value: hasAppeared)
                    .scrollTransition { content, phase in
                        content
                            .opacity(phase.isIdentity ? 1 : 0.85)
                            .scaleEffect(phase.isIdentity ? 1 : 0.97, anchor: .top)
                    }

                    VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                        // A custom field instead of `.searchable` on
                        // purpose — `.searchable` reserves its own
                        // always-visible slot right below the nav bar,
                        // which blocked the hero card above from bleeding
                        // behind the status bar/Dynamic Island.
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)
                            TextField("Search transactions", text: $searchText)
                            if !searchText.isEmpty {
                                Button {
                                    searchText = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.horizontal, AppTheme.Spacing.medium)
                        .padding(.vertical, AppTheme.Spacing.small)
                        .background(.thinMaterial, in: Capsule())
                        .padding(.top, AppTheme.Spacing.medium)

                        Text("Recent transactions")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, AppTheme.Spacing.xs)

                        if transactions.isEmpty {
                            Text("No transactions yet.")
                                .foregroundStyle(.secondary)
                        } else if displayedTransactions.isEmpty {
                            Text("No transactions match your search/filters.")
                                .foregroundStyle(.secondary)
                        }

                        ForEach(displayedTransactions) { transaction in
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
                            .contentShape(Rectangle())
                            // Hold-to-edit/delete instead of swipe — consistent
                            // with Split and Goals, and more discoverable than
                            // a hidden swipe gesture.
                            .contextMenu {
                                Button {
                                    editingTransaction = transaction
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    deletingTransaction = transaction
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .scrollTransition { content, phase in
                                content
                                    .opacity(phase.isIdentity ? 1 : 0.5)
                                    .scaleEffect(phase.isIdentity ? 1 : 0.98)
                                    .offset(y: phase.isIdentity ? 0 : (phase.value < 0 ? -6 : 6))
                            }
                            if transaction.id != displayedTransactions.last?.id {
                                Divider()
                            }
                        }
                        .animation(.easeInOut(duration: 0.25), value: displayedTransactions.map(\.id))
                    }
                    .padding(.horizontal, AppTheme.Spacing.large)
                    .padding(.bottom, AppTheme.Spacing.large)
                    // ...then the transaction list settles in just after.
                    .opacity(hasAppeared ? 1 : 0)
                    .offset(y: hasAppeared ? 0 : 14)
                    .animation(.easeOut(duration: 0.45).delay(0.1), value: hasAppeared)
                }
            }
            .scrollClipDisabled()
            .onAppear {
                hasAppeared = true
            }
            .navigationTitle("")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            #endif
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
