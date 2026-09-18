import SwiftUI
import SwiftData
import MoneyIQCore

struct GoalsView: View {
    let authManager: AuthManager

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavingsGoal.targetDate) private var goals: [SavingsGoal]

    @State private var showingAddGoal = false

    private var currencyCode: String {
        authManager.currentAccount?.preferredCurrencyCode ?? "USD"
    }

    var body: some View {
        NavigationStack {
            List {
                if goals.isEmpty {
                    emptyState
                } else {
                    ForEach(goals) { goal in
                        NavigationLink {
                            GoalDetailView(goal: goal, currencyCode: currencyCode)
                        } label: {
                            GoalRow(goal: goal, currencyCode: currencyCode)
                        }
                    }
                    .onDelete(perform: delete)
                }
            }
            .navigationTitle("Goals")
            .toolbar {
                ToolbarItem {
                    Button {
                        showingAddGoal = true
                    } label: {
                        Label("Add Goal", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddGoal) {
                AddGoalView(currencyCode: currencyCode)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "target")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("No savings goals yet")
                .font(.headline)
            Text("Set a target — like \"Save ₹50,000 for a trip by December\" — and track your progress.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .listRowBackground(Color.clear)
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(goals[index])
        }
        try? modelContext.save()
    }
}

private struct GoalRow: View {
    let goal: SavingsGoal
    let currencyCode: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: goal.systemIconName)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 6) {
                Text(goal.name).font(.subheadline.weight(.medium))
                ProgressView(value: goal.progressFraction)
                    .tint(goal.isComplete ? .green : .accentColor)
                HStack {
                    Text("\(goal.savedAmount.formatted(.currency(code: currencyCode))) of \(goal.targetAmount.formatted(.currency(code: currencyCode)))")
                    Spacer()
                    Text(goal.targetDate, format: .dateTime.month(.abbreviated).year())
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct GoalDetailView: View {
    @Bindable var goal: SavingsGoal
    let currencyCode: String

    @Environment(\.modelContext) private var modelContext
    @State private var showingContribute = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text(goal.savedAmount, format: .currency(code: currencyCode))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                    Text("of \(goal.targetAmount.formatted(.currency(code: currencyCode))) goal")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ProgressView(value: goal.progressFraction)
                        .tint(goal.isComplete ? .green : .accentColor)

                    if !goal.isComplete {
                        Text("Save \(goal.suggestedMonthlyContribution().formatted(.currency(code: currencyCode)))/month to hit your goal by \(goal.targetDate.formatted(.dateTime.month(.wide).year()))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Label("Goal reached!", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    }
                }
                .padding(.vertical, 8)
            }

            Section("Contributions") {
                if goal.contributions.isEmpty {
                    Text("No contributions yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(goal.contributions.sorted { $0.date > $1.date }) { contribution in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(contribution.date, format: .dateTime.month().day().year())
                            if let note = contribution.note {
                                Text(note).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(contribution.amount, format: .currency(code: currencyCode))
                    }
                }
            }
        }
        .navigationTitle(goal.name)
        .toolbar {
            ToolbarItem {
                Button {
                    showingContribute = true
                } label: {
                    Label("Add Funds", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingContribute) {
            AddContributionView(goal: goal)
        }
    }
}

private struct AddContributionView: View {
    let goal: SavingsGoal

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var amountText = ""
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                HStack {
                    Text("Amount")
                    Spacer()
                    TextField("0.00", text: $amountText)
                        .multilineTextAlignment(.trailing)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                }
                TextField("Note (optional)", text: $note)
            }
            .navigationTitle("Add Funds")
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
        let contribution = SavingsContribution(amount: amount, note: note.isEmpty ? nil : note, goal: goal)
        modelContext.insert(contribution)
        goal.savedAmount += amount
        try? modelContext.save()
        dismiss()
    }
}

private struct AddGoalView: View {
    let currencyCode: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var targetText = ""
    @State private var targetDate = Calendar.current.date(byAdding: .month, value: 6, to: .now) ?? .now
    @State private var icon = "target"

    private let iconChoices = ["target", "airplane", "house", "car", "graduationcap", "heart", "gift"]

    var body: some View {
        NavigationStack {
            Form {
                TextField("Goal name (e.g. Trip to Goa)", text: $name)
                HStack {
                    Text("Target amount")
                    Spacer()
                    TextField("0.00", text: $targetText)
                        .multilineTextAlignment(.trailing)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                }
                DatePicker("Target date", selection: $targetDate, displayedComponents: .date)
                Picker("Icon", selection: $icon) {
                    ForEach(iconChoices, id: \.self) { name in
                        Label(name, systemImage: name).tag(name)
                    }
                }
            }
            .navigationTitle("New Goal")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.isEmpty || Decimal(string: targetText) == nil)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func save() {
        guard let target = Decimal(string: targetText) else { return }
        let goal = SavingsGoal(name: name, targetAmount: target, targetDate: targetDate, currencyCode: currencyCode, systemIconName: icon)
        modelContext.insert(goal)
        try? modelContext.save()
        dismiss()
    }
}
