import SwiftUI
import SwiftData
import MoneyIQCore

struct HomeView: View {
    let authManager: AuthManager
    let settings: AppSettingsStore
    let notifications: NotificationScheduler
    let lockManager: AppLockManager
    @Binding var expenseActionRequest: WidgetRoute?

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ExpenseTransaction.date, order: .reverse) private var transactions: [ExpenseTransaction]
    @Query private var categories: [ExpenseCategory]
    @Query(sort: \Budget.createdAt, order: .reverse) private var budgets: [Budget]
    @Query(sort: \SavingsGoal.targetDate) private var goals: [SavingsGoal]

    @State private var showingAddTransaction = false
    @State private var showingScreenshotImport = false
    @State private var autoPresentScreenshotPicker = false
    @State private var clipboardImportText: String?
    @State private var isReadingClipboard = false
    @State private var clipboardProblem: ClipboardProblem?
    @State private var editingTransaction: ExpenseTransaction?
    @State private var deletingTransaction: ExpenseTransaction?
    @State private var searchText = ""
    @State private var isSearchExpanded = false
    @FocusState private var isSearchFocused: Bool
    @State private var sortOption: TransactionSortOption = .dateDescending
    @State private var categoryFilter: ExpenseCategory?
    @State private var billsOnly = false
    @State private var liveActivityManager = BudgetLiveActivityManager()

    private enum TransactionSortOption: String, CaseIterable, Identifiable {
        case dateDescending = "Newest first"
        case dateAscending = "Oldest first"
        case amountDescending = "Amount: high to low"
        case amountAscending = "Amount: low to high"

        var id: String { rawValue }
    }

    /// Home is a "this month" view — earlier months live in Insights. The
    /// full `@Query` is still kept for the budget rollover/Live Activity
    /// math, which needs last month too.
    private var currentMonthTransactions: [ExpenseTransaction] {
        let calendar = Calendar.current
        let monthStart = calendar.startOfMonth(for: .now)
        guard let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) else { return [] }
        return transactions.filter { $0.date >= monthStart && $0.date < monthEnd }
    }

    /// `currentMonthTransactions` filtered by search text/category/
    /// bills-only, then sorted per `sortOption` — the `@Query`'s
    /// own sort (newest first) is just the default before any of this is
    /// applied.
    private var displayedTransactions: [ExpenseTransaction] {
        var result = currentMonthTransactions

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

    private var monthSectionTitle: String {
        Date.now.formatted(.dateTime.month(.wide).year())
    }

    private var homeSnapshot: WidgetSnapshot {
        WidgetSnapshotBuilder.make(
            currencyCode: account?.preferredCurrencyCode ?? "USD",
            budget: budgets.first,
            transactions: transactions
        )
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
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    homeHeader
                        .padding(.bottom, 21)

                    if isSearchExpanded {
                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)
                            TextField("Search transactions", text: $searchText)
                                .focused($isSearchFocused)
                                .submitLabel(.search)
                                .textInputAutocapitalization(.never)
                            if !searchText.isEmpty {
                                Button { searchText = "" } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .accessibilityLabel("Clear search")
                            }
                        }
                        .padding(.horizontal, 15)
                        .frame(height: 48)
                        .background(.white, in: RoundedRectangle(cornerRadius: 16))
                        .padding(.bottom, 18)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    BudgetCardView(currencyCode: account?.preferredCurrencyCode ?? "USD")
                        .padding(.bottom, 27)

                    quickActions
                        .padding(.bottom, 27)

                    atAGlance
                        .padding(.bottom, 28)

                    recentActivity
                }
                .frame(maxWidth: 720)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity)
            }
            .background(
                LinearGradient(
                    colors: [Color(red: 1, green: 0.973, blue: 0.946), Color(red: 0.985, green: 0.978, blue: 0.967)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
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
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text("M")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(AppTheme.emberRed)
                        .accessibilityLabel("MoneyIQ Home")
                }
                ToolbarItem(placement: AppTheme.trailingToolbarPlacement) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isSearchExpanded.toggle()
                            if !isSearchExpanded { searchText = "" }
                        }
                        isSearchFocused = isSearchExpanded
                    } label: {
                        Image(systemName: isSearchExpanded ? "xmark" : "magnifyingglass")
                    }
                    .accessibilityLabel(isSearchExpanded ? "Close search" : "Search transactions")
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
                ToolbarItem(placement: AppTheme.trailingToolbarPlacement) {
                    ProfileMenuButton(authManager: authManager, settings: settings, notifications: notifications, lockManager: lockManager)
                }
            }
            .sheet(item: $editingTransaction) { transaction in
                EditTransactionView(transaction: transaction, categories: categories)
            }
            .sheet(isPresented: $showingAddTransaction) {
                AddTransactionView(categories: categories)
            }
            .onAppear { handleRequestedExpenseAction() }
            .onChange(of: expenseActionRequest) { _, _ in handleRequestedExpenseAction() }
            .sheet(isPresented: $showingScreenshotImport) {
                ScreenshotImportView(categories: categories, autoPresentPicker: autoPresentScreenshotPicker)
            }
            .sheet(isPresented: Binding(
                get: { clipboardImportText != nil },
                set: { if !$0 { clipboardImportText = nil } }
            )) {
                if let clipboardImportText {
                    SharedReceiptImportView(sharedText: clipboardImportText)
                }
            }
            .alert(
                clipboardProblem?.title ?? "",
                isPresented: Binding(
                    get: { clipboardProblem != nil },
                    set: { if !$0 { clipboardProblem = nil } }
                ),
                presenting: clipboardProblem
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { problem in
                Text(problem.message)
            }
            .overlay {
                if isReadingClipboard {
                    ProgressView("Reading clipboard…")
                        .padding(AppTheme.Spacing.large)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppTheme.rowCornerRadius, style: .continuous))
                }
            }
            // Keeps the Lock Screen / Dynamic Island Live Activity in sync
            // with real budget data whenever it changes — opt-in via
            // Settings, since showing anything outside the app shouldn't be
            // the default just because a budget exists.
            .task(id: liveActivityState) {
                guard settings.isBudgetLiveActivityEnabled, let state = liveActivityState else {
                    if liveActivityManager.isActive {
                        await liveActivityManager.end()
                    }
                    return
                }
                if liveActivityManager.isActive {
                    await liveActivityManager.update(state: state)
                } else {
                    liveActivityManager.start(state: state)
                }
            }
        }
    }

    private var homeHeader: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()).uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(1.4)
                .foregroundStyle(AppTheme.emberRed)
            Text("\(greeting), \(account?.firstName ?? "there")")
                .font(.system(size: 29, weight: .bold, design: .rounded))
                .tracking(-0.7)
                .foregroundStyle(Color(red: 0.18, green: 0.15, blue: 0.15))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("Quick actions")
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.18, green: 0.15, blue: 0.15))

            Button { showingAddTransaction = true } label: {
                HStack(spacing: 13) {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .bold))
                        .frame(width: 39, height: 39)
                        .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Log an expense")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                        Text("Enter details manually")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .background(AppTheme.emberRed, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .buttonStyle(HomeActionPressStyle())
            .accessibilityIdentifier("home.logExpense")

            HStack(spacing: 11) {
                secondaryAction(
                    title: "Paste expense",
                    subtitle: "From clipboard",
                    symbol: "doc.on.clipboard.fill",
                    identifier: "home.pasteExpense"
                ) { pasteFromClipboard() }

                secondaryAction(
                    title: "Add screenshot",
                    subtitle: "Read a payment",
                    symbol: "photo.on.rectangle.angled",
                    identifier: "home.screenshotExpense"
                ) {
                    autoPresentScreenshotPicker = true
                    showingScreenshotImport = true
                }
            }
        }
    }

    private func secondaryAction(
        title: String,
        subtitle: String,
        symbol: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(AppTheme.emberRed)
                    .frame(width: 34, height: 34)
                    .background(AppTheme.emberRed.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
                Spacer(minLength: 8)
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.2, green: 0.16, blue: 0.16))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
            .padding(14)
            .background(.white.opacity(0.86), in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        }
        .buttonStyle(HomeActionPressStyle())
        .accessibilityIdentifier(identifier)
    }

    private var atAGlance: some View {
        let snapshot = homeSnapshot
        return VStack(alignment: .leading, spacing: 11) {
            Text("At a glance")
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.18, green: 0.15, blue: 0.15))

            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SPENT TODAY")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1)
                        .foregroundStyle(AppTheme.emberRed)
                    Text(snapshot.todaySpent, format: .currency(code: snapshot.currencyCode).precision(.fractionLength(0)))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.19, green: 0.16, blue: 0.16))
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                    Text("Your daily total")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Rectangle()
                    .fill(Color.black.opacity(0.07))
                    .frame(width: 1, height: 58)

                VStack(alignment: .leading, spacing: 4) {
                    Text("TOP CATEGORY")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1)
                        .foregroundStyle(AppTheme.emberRed)
                    Text(snapshot.topCategoryName ?? "No category yet")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.19, green: 0.16, blue: 0.16))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(snapshot.topCategoryName == nil
                         ? "This month"
                         : snapshot.topCategoryAmount.formatted(.currency(code: snapshot.currencyCode).precision(.fractionLength(0))) + " this month")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(18)
            .background(.white.opacity(0.86), in: RoundedRectangle(cornerRadius: 21, style: .continuous))
        }
    }

    private var recentActivity: some View {
        let rows = displayedTransactions
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recent activity")
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.18, green: 0.15, blue: 0.15))
                Spacer()
                Text(monthSectionTitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            if currentMonthTransactions.isEmpty {
                VStack(alignment: .leading, spacing: 9) {
                    Image(systemName: "receipt")
                        .font(.system(size: 23, weight: .light))
                        .foregroundStyle(AppTheme.emberRed)
                        .frame(width: 42, height: 42)
                        .background(AppTheme.emberRed.opacity(0.1), in: RoundedRectangle(cornerRadius: 13))
                    Text("Your month starts here")
                        .font(.subheadline.weight(.semibold))
                    Text("Add an expense to see your activity and budget progress.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Log your first expense") { showingAddTransaction = true }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.emberRed)
                        .padding(.top, 3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .background(.white.opacity(0.86), in: RoundedRectangle(cornerRadius: 21))
            } else if rows.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No matching expenses")
                        .font(.subheadline.weight(.semibold))
                    Text("Try a different search or clear the filters.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Clear search and filters") {
                        searchText = ""
                        categoryFilter = nil
                        billsOnly = false
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.emberRed)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .background(.white.opacity(0.86), in: RoundedRectangle(cornerRadius: 21))
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { transaction in
                        if transaction.id != rows.first?.id {
                            Rectangle()
                                .fill(Color.black.opacity(0.06))
                                .frame(height: 1)
                                .padding(.leading, 70)
                        }
                        TransactionRow(
                            transaction: transaction,
                            currencyCode: account?.preferredCurrencyCode ?? "USD",
                            onEdit: { editingTransaction = transaction },
                            onDelete: { deletingTransaction = transaction }
                        )
                    }
                }
                .padding(.horizontal, 15)
                .background(.white.opacity(0.86), in: RoundedRectangle(cornerRadius: 21, style: .continuous))
            }
        }
    }

    private var liveActivityState: BudgetActivityAttributes.ContentState? {
        guard let budget = budgets.first, let account = authManager.currentAccount else { return nil }
        let progress = BudgetEngine.monthProgress(for: budget, transactions: transactions)
        let pace = BudgetEngine.dailyPace(remaining: progress.remaining)
        let nearestGoal = goals.first { !$0.isComplete }
        return BudgetActivityAttributes.ContentState(
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
    }

    private var account: UserAccount? { authManager.currentAccount }

    private func handleRequestedExpenseAction() {
        guard let action = expenseActionRequest else { return }
        expenseActionRequest = nil
        switch action {
        case .addExpense:
            showingAddTransaction = true
        case .pasteExpense:
            pasteFromClipboard()
        case .screenshotExpense:
            autoPresentScreenshotPicker = true
            showingScreenshotImport = true
        case .budget, .insights:
            break
        }
    }

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

    /// Imports a payment the user copied from a UPI app — text, or a
    /// receipt image (see `ClipboardReceiptReader`), which takes a moment to
    /// OCR, hence the progress overlay.
    private func pasteFromClipboard() {
        guard !isReadingClipboard else { return }
        isReadingClipboard = true
        Task {
            let outcome = await ClipboardReceiptReader.read()
            isReadingClipboard = false
            switch outcome {
            case .found(let text): clipboardImportText = text
            case .empty: clipboardProblem = .empty
            case .notAllowed: clipboardProblem = .notAllowed
            case .noTextInImage: clipboardProblem = .noTextInImage
            }
        }
    }
}

private enum ClipboardProblem: Identifiable {
    case empty
    case notAllowed
    case noTextInImage

    var id: Self { self }

    var title: String {
        switch self {
        case .empty: "Nothing to import"
        case .notAllowed: "Paste wasn't allowed"
        case .noTextInImage: "Couldn't read the image"
        }
    }

    var message: String {
        switch self {
        case .empty:
            "Copy a payment receipt or message from a UPI app first, then try again."
        case .notAllowed:
            "Tap \u{201C}Allow Paste\u{201D} when iOS asks. To stop being asked, go to Settings › Apps › MoneyIQ › Paste from Other Apps and choose Allow."
        case .noTextInImage:
            "The copied image didn't contain any readable text. Try copying the receipt again, or use Add Expense › From Screenshot."
        }
    }
}

private struct HomeActionPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

/// A tappable activity row. The long-press menu keeps delete close by
/// without making it easy to trigger accidentally.
private struct TransactionRow: View {
    let transaction: ExpenseTransaction
    let currencyCode: String
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onEdit) {
            HStack(spacing: 12) {
                IconBubble(systemName: transaction.category?.systemIconName ?? "creditcard", tint: AppTheme.emberRed, diameter: 42)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(transaction.merchantName ?? transaction.category?.name ?? "Uncategorized")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color(red: 0.2, green: 0.16, blue: 0.16))
                            .lineLimit(1)
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
                    }
                    Text(relativeTimeText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let note = transaction.note, !note.isEmpty {
                        Text(note)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(amountText)
                        .font(.subheadline.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(Color(red: 0.2, green: 0.16, blue: 0.16))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if transaction.isBillLike {
                        Text("BILL")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .tracking(0.8)
                            .foregroundStyle(AppTheme.emberRed)
                    }
                }
            }
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens expense for editing")
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
                    .keyboardType(.decimalPad)
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
                    .keyboardType(.decimalPad)
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
