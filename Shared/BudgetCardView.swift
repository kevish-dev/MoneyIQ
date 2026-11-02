import SwiftUI
import SwiftData
import MoneyIQCore

/// Monthly spending hero. Tapping it opens the budget editor, whether or not
/// a cap has been set yet. Expense actions live separately in HomeView.
struct BudgetCardView: View {
    let currencyCode: String

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Budget.createdAt, order: .reverse) private var budgets: [Budget]
    @Query private var transactions: [ExpenseTransaction]

    @State private var showingEditor = false

    private var activeBudget: Budget? { budgets.first }

    var body: some View {
        Button { showingEditor = true } label: {
            heroContent
                .padding(22)
                .background(AppTheme.heroGradient, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .stroke(.white.opacity(0.1), lineWidth: 24)
                        .frame(width: 178, height: 178)
                        .offset(x: 72, y: -88)
                        .allowsHitTesting(false)
                }
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .shadow(color: AppTheme.emberRed.opacity(0.22), radius: 20, y: 11)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens monthly budget settings")
        .sheet(isPresented: $showingEditor) {
            BudgetEditView(budget: activeBudget, currencyCode: currencyCode)
        }
    }

    private var heroContent: some View {
        let progress = activeBudget.map { BudgetEngine.monthProgress(for: $0, transactions: transactions) }
        let spent = progress?.spent ?? BudgetEngine.totalSpent(transactions: transactions, inMonthContaining: .now)

        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(Date.now.formatted(.dateTime.month(.wide)).uppercased() + "  /  SPENDING")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.78))
                Spacer()
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(.white.opacity(0.16), in: Circle())
                    .accessibilityHidden(true)
            }

            Text(spent, format: .currency(code: currencyCode).precision(.fractionLength(0)))
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .tracking(-1.5)
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .minimumScaleFactor(0.55)
                .lineLimit(1)
                .padding(.top, 13)
            Text("Spent this month")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.76))
                .padding(.top, 1)

            if let progress {
                let isOver = progress.remaining < 0
                ProgressView(value: min(progress.fractionUsed, 1))
                    .tint(.white)
                    .background(.white.opacity(0.24), in: Capsule())
                    .padding(.top, 20)

                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(isOver ? "OVER BUDGET BY" : "LEFT TO SPEND")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .tracking(1)
                            .foregroundStyle(.white.opacity(0.7))
                        Text(abs(progress.remaining), format: .currency(code: currencyCode).precision(.fractionLength(0)))
                            .font(.system(size: 21, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                    }
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("MONTHLY CAP")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .tracking(1)
                            .foregroundStyle(.white.opacity(0.7))
                        Text(progress.effectiveCap, format: .currency(code: currencyCode).precision(.fractionLength(0)))
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                    }
                }
                .padding(.top, 13)
                if let budget = activeBudget, budget.rolloverEnabled && progress.rolloverFromLastMonth > 0 {
                    Label("\(progress.rolloverFromLastMonth.formatted(.currency(code: currencyCode))) carried over", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.82))
                        .padding(.top, 11)
                }
            } else {
                HStack(spacing: 7) {
                    Image(systemName: "plus.circle.fill")
                    Text("Set a monthly budget")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.top, 23)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BudgetEditView: View {
    let budget: Budget?
    let currencyCode: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var capText: String
    @State private var rolloverEnabled: Bool
    @State private var showingDeleteConfirmation = false

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
                        .keyboardType(.decimalPad)
                }
                Toggle("Roll over unused budget", isOn: $rolloverEnabled)
                Text("If you spend less than your cap this month, the leftover adds to next month's budget. Overspending never carries forward.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if budget != nil {
                    Section {
                        Button("Delete Budget", role: .destructive) { showingDeleteConfirmation = true }
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
            .alert("Delete Budget?", isPresented: $showingDeleteConfirmation) {
                Button("Delete", role: .destructive) { deleteBudget() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This can't be undone. You'll need to set a new monthly budget from scratch.")
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
