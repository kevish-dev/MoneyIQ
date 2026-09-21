import SwiftUI
import SwiftData
import MoneyIQCore

/// The monthly budget card shown at the top of Home — this is also the only
/// place a `Budget` gets created, since Phase 1 never actually shipped a UI
/// for it despite having the data model.
struct BudgetCardView: View {
    let currencyCode: String
    /// Both are optional so previews/tests that don't need the sheet
    /// wiring can omit them, but Home passes both — this button is the
    /// single entry point for starting a new transaction (the old toolbar
    /// menu on Home was removed in favor of this one).
    var onAddExpenseManually: (() -> Void)?
    var onAddExpenseFromScreenshot: (() -> Void)?

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Budget.createdAt, order: .reverse) private var budgets: [Budget]
    @Query private var transactions: [ExpenseTransaction]

    @State private var showingEditor = false

    private var activeBudget: Budget? { budgets.first }

    var body: some View {
        Group {
            if let budget = activeBudget {
                let progress = BudgetEngine.monthProgress(for: budget, transactions: transactions)
                VStack(spacing: 14) {
                    Button {
                        showingEditor = true
                    } label: {
                        heroContent(budget: budget, progress: progress)
                    }
                    .buttonStyle(.plain)

                    quickActions
                }
            } else {
                Button {
                    showingEditor = true
                } label: {
                    Label("Set a monthly budget", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity)
                        .padding(AppTheme.Spacing.large)
                        .foregroundStyle(.white)
                        .background(AppTheme.heroGradient, in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showingEditor) {
            BudgetEditView(budget: activeBudget, currencyCode: currencyCode)
        }
    }

    private func heroContent(budget: Budget, progress: BudgetEngine.MonthProgress) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("This Month's Budget")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                if budget.rolloverEnabled && progress.rolloverFromLastMonth > 0 {
                    Label("+\(progress.rolloverFromLastMonth.formatted(.currency(code: currencyCode))) rolled over", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Remaining")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                Text(progress.remaining, format: .currency(code: currencyCode))
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }

            HStack(spacing: 6) {
                Image(systemName: progress.fractionUsed >= 1 ? "arrow.up.right" : "chart.pie.fill")
                    .font(.caption2.weight(.bold))
                Text("\(Int((progress.fractionUsed * 100).rounded()))% of \(progress.effectiveCap.formatted(.currency(code: currencyCode))) used")
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, AppTheme.Spacing.medium)
            .padding(.vertical, AppTheme.Spacing.small)
            .background(AppTheme.pillBackgroundOnHero, in: Capsule())

            ProgressView(value: min(progress.fractionUsed, 1))
                .tint(.white)
                .background(Color.white.opacity(0.2), in: Capsule())

            HStack {
                Text("\(progress.spent.formatted(.currency(code: currencyCode))) spent")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
                Spacer()
                Text("of \(progress.effectiveCap.formatted(.currency(code: currencyCode))) cap")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
        .padding(AppTheme.Spacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.heroGradient, in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
        .shadow(color: AppTheme.emberRed.opacity(0.3), radius: 16, y: 10)
    }

    private var quickActions: some View {
        HStack(spacing: AppTheme.Spacing.medium) {
            Button {
                showingEditor = true
            } label: {
                Label("Edit Budget", systemImage: "slider.horizontal.3")
                    .labelStyle(.titleAndIcon)
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.Spacing.medium)
            }
            .buttonStyle(.bordered)
            .tint(AppTheme.accent)

            Menu {
                Button {
                    onAddExpenseManually?()
                } label: {
                    Label("Enter Manually", systemImage: "square.and.pencil")
                }
                Button {
                    onAddExpenseFromScreenshot?()
                } label: {
                    Label("From Screenshot", systemImage: "text.viewfinder")
                }
            } label: {
                Label("Add Expense", systemImage: "plus")
                    .labelStyle(.titleAndIcon)
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.Spacing.medium)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.accent)
        }
    }
}

private struct BudgetEditView: View {
    let budget: Budget?
    let currencyCode: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var capText: String
    @State private var rolloverEnabled: Bool

    init(budget: Budget?, currencyCode: String) {
        self.budget = budget
        self.currencyCode = currencyCode
        _capText = State(initialValue: budget.map { "\($0.monthlyCapAmount)" } ?? "")
        _rolloverEnabled = State(initialValue: budget?.rolloverEnabled ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                HStack {
                    Text("Monthly cap")
                    Spacer()
                    TextField("0.00", text: $capText)
                        .multilineTextAlignment(.trailing)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                }
                Toggle("Roll over unused budget", isOn: $rolloverEnabled)
                Text("If you spend less than your cap this month, the leftover adds to next month's budget. Overspending never carries forward.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if budget != nil {
                    Section {
                        Button("Delete Budget", role: .destructive) { deleteBudget() }
                    }
                }
            }
            .navigationTitle(budget == nil ? "Set Budget" : "Edit Budget")
            .compactFormLayout()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(Decimal(string: capText) == nil)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func save() {
        guard let cap = Decimal(string: capText) else { return }
        if let budget {
            budget.monthlyCapAmount = cap
            budget.rolloverEnabled = rolloverEnabled
        } else {
            let newBudget = Budget(monthlyCapAmount: cap, currencyCode: currencyCode, rolloverEnabled: rolloverEnabled)
            modelContext.insert(newBudget)
        }
        do {
            try modelContext.save()
        } catch {
            print("MoneyIQ: failed to save budget: \(error)")
        }
        dismiss()
    }

    private func deleteBudget() {
        guard let budget else { return }
        modelContext.delete(budget)
        do {
            try modelContext.save()
        } catch {
            print("MoneyIQ: failed to delete budget: \(error)")
        }
        dismiss()
    }
}
