import SwiftUI
import SwiftData
import MoneyIQCore

/// The monthly budget card shown at the top of Home — this is also the only
/// place a `Budget` gets created, since Phase 1 never actually shipped a UI
/// for it despite having the data model.
struct BudgetCardView: View {
    let currencyCode: String

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Budget.createdAt, order: .reverse) private var budgets: [Budget]
    @Query private var transactions: [ExpenseTransaction]

    @State private var showingEditor = false

    private var activeBudget: Budget? { budgets.first }

    var body: some View {
        Group {
            if let budget = activeBudget {
                let progress = BudgetEngine.monthProgress(for: budget, transactions: transactions)
                Button {
                    showingEditor = true
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("This Month's Budget")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            if budget.rolloverEnabled && progress.rolloverFromLastMonth > 0 {
                                Label("+\(progress.rolloverFromLastMonth.formatted(.currency(code: currencyCode))) rolled over", systemImage: "arrow.triangle.2.circlepath")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.green)
                            }
                        }

                        ProgressView(value: progress.fractionUsed)
                            .tint(progress.fractionUsed >= 1 ? .red : .accentColor)

                        HStack {
                            Text("\(progress.spent.formatted(.currency(code: currencyCode))) spent")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(progress.remaining.formatted(.currency(code: currencyCode))) left of \(progress.effectiveCap.formatted(.currency(code: currencyCode)))")
                                .font(.caption)
                                .foregroundStyle(progress.remaining < 0 ? .red : .secondary)
                        }
                    }
                    .padding(14)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    showingEditor = true
                } label: {
                    Label("Set a monthly budget", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity)
                        .padding(14)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showingEditor) {
            BudgetEditView(budget: activeBudget, currencyCode: currencyCode)
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
            }
            .navigationTitle(budget == nil ? "Set Budget" : "Edit Budget")
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
        try? modelContext.save()
        dismiss()
    }
}
