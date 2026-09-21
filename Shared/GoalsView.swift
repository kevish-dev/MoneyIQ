import SwiftUI
import SwiftData
import MoneyIQCore

struct GoalsView: View {
    let authManager: AuthManager
    let settings: AppSettingsStore
    let notifications: NotificationScheduler
    let lockManager: AppLockManager

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
            .compactListLayout()
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    ProfileMenuButton(authManager: authManager, settings: settings, notifications: notifications, lockManager: lockManager)
                }
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
            IconBubble(systemName: goal.systemIconName, tint: goal.isComplete ? .green : AppTheme.accent)

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
        .padding(.vertical, AppTheme.Spacing.small)
    }
}

private struct GoalDetailView: View {
    @Bindable var goal: SavingsGoal
    let currencyCode: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showingContribute = false
    @State private var showingEditGoal = false
    @State private var editingContribution: SavingsContribution?

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
                        VStack(alignment: .leading, spacing: 2) {
                            Text(contribution.date, format: .dateTime.month().day().year().hour().minute())
                            if let note = contribution.note {
                                Text(note).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(contribution.amount, format: .currency(code: currencyCode))
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            delete(contribution)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button {
                            editingContribution = contribution
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(AppTheme.accent)
                    }
                }
            }
        }
        .navigationTitle(goal.name)
        .compactListLayout()
        .toolbar {
            ToolbarItem {
                Button {
                    showingEditGoal = true
                } label: {
                    Label("Edit Goal", systemImage: "pencil")
                }
            }
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
        .sheet(isPresented: $showingEditGoal) {
            EditGoalView(goal: goal, onDeleted: { dismiss() })
        }
        .sheet(item: $editingContribution) { contribution in
            EditContributionView(goal: goal, contribution: contribution)
        }
    }

    private func delete(_ contribution: SavingsContribution) {
        goal.savedAmount -= contribution.amount
        modelContext.delete(contribution)
        do {
            try modelContext.save()
        } catch {
            print("MoneyIQ: failed to delete contribution: \(error)")
        }
    }
}

private struct AddContributionView: View {
    let goal: SavingsGoal

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var amountText = ""
    @State private var note = ""
    @State private var date = Date.now

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
                DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                TextField("Note (optional)", text: $note)
            }
            .navigationTitle("Add Funds")
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
        let contribution = SavingsContribution(amount: amount, date: date, note: note.isEmpty ? nil : note, goal: goal)
        modelContext.insert(contribution)
        goal.savedAmount += amount
        do {
            try modelContext.save()
        } catch {
            print("MoneyIQ: failed to save contribution: \(error)")
        }
        dismiss()
    }
}

private struct EditContributionView: View {
    let goal: SavingsGoal
    let contribution: SavingsContribution

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var amountText: String
    @State private var note: String
    @State private var date: Date

    init(goal: SavingsGoal, contribution: SavingsContribution) {
        self.goal = goal
        self.contribution = contribution
        _amountText = State(initialValue: NSDecimalNumber(decimal: contribution.amount).stringValue)
        _note = State(initialValue: contribution.note ?? "")
        _date = State(initialValue: contribution.date)
    }

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
                DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                TextField("Note (optional)", text: $note)
            }
            .navigationTitle("Edit Contribution")
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
        // `savedAmount` is a running total, not re-summed from contributions
        // (see SavingsGoal's doc comment) — adjust it by the delta rather
        // than just overwriting the contribution's amount.
        let delta = amount - contribution.amount
        contribution.amount = amount
        contribution.date = date
        contribution.note = note.isEmpty ? nil : note
        goal.savedAmount += delta
        do {
            try modelContext.save()
        } catch {
            print("MoneyIQ: failed to save edited contribution: \(error)")
        }
        dismiss()
    }
}

private struct EditGoalView: View {
    @Bindable var goal: SavingsGoal
    let onDeleted: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var targetText: String
    @State private var targetDate: Date
    @State private var icon: String

    private let iconChoices = ["target", "airplane", "house", "car", "graduationcap", "heart", "gift"]

    init(goal: SavingsGoal, onDeleted: @escaping () -> Void) {
        self.goal = goal
        self.onDeleted = onDeleted
        _name = State(initialValue: goal.name)
        _targetText = State(initialValue: NSDecimalNumber(decimal: goal.targetAmount).stringValue)
        _targetDate = State(initialValue: goal.targetDate)
        _icon = State(initialValue: goal.systemIconName)
    }

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

                Section {
                    Button("Delete Goal", role: .destructive) { deleteGoal() }
                }
            }
            .navigationTitle("Edit Goal")
            .compactFormLayout()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || Decimal(string: targetText) == nil)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func save() {
        guard let target = Decimal(string: targetText) else { return }
        goal.name = name.trimmingCharacters(in: .whitespaces)
        goal.targetAmount = target
        goal.targetDate = targetDate
        goal.systemIconName = icon
        do {
            try modelContext.save()
        } catch {
            print("MoneyIQ: failed to save edited goal: \(error)")
        }
        dismiss()
    }

    private func deleteGoal() {
        modelContext.delete(goal)
        do {
            try modelContext.save()
        } catch {
            print("MoneyIQ: failed to delete goal: \(error)")
        }
        dismiss()
        onDeleted()
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
            .compactFormLayout()
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
