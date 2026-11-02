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
    @State private var goalsPendingDelete: [SavingsGoal]?
    @State private var contributingGoal: SavingsGoal?

    private var currencyCode: String {
        authManager.currentAccount?.preferredCurrencyCode ?? "USD"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    goalsHeader
                    if goals.isEmpty {
                        emptyState
                    } else {
                        if let nextGoal = goals.filter({ !$0.isComplete }).min(by: { $0.targetDate < $1.targetDate }) {
                            nextGoalCard(nextGoal)
                        }
                        if goals.contains(where: { !$0.isComplete }) {
                            sectionTitle("IN PROGRESS", count: goals.filter { !$0.isComplete }.count)
                            ForEach(goals.filter { !$0.isComplete }) { goal in goalLink(goal) }
                        }
                        if goals.contains(where: \.isComplete) {
                            sectionTitle("COMPLETED", count: goals.filter(\.isComplete).count)
                            ForEach(goals.filter(\.isComplete)) { goal in goalLink(goal) }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    showingAddGoal = true
                } label: {
                    Label("New savings goal", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.glassProminent)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
            .navigationTitle("Goals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: AppTheme.trailingToolbarPlacement) {
                    ProfileMenuButton(authManager: authManager, settings: settings, notifications: notifications, lockManager: lockManager)
                }
            }
            .sheet(isPresented: $showingAddGoal) { AddGoalView(currencyCode: currencyCode) }
            .sheet(item: $contributingGoal) { goal in AddContributionView(goal: goal) }
            .alert(
                "Delete \(goalsPendingDelete?.first?.name ?? "Goal")?",
                isPresented: Binding(
                    get: { goalsPendingDelete != nil },
                    set: { if !$0 { goalsPendingDelete = nil } }
                )
            ) {
                Button("Delete", role: .destructive) {
                    for goal in goalsPendingDelete ?? [] { modelContext.delete(goal) }
                    try? modelContext.save()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This also deletes all its contributions. This can't be undone.")
            }
        }
    }

    private var goalsHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MAKE ROOM FOR WHAT'S NEXT")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.78))
            Text("Your goals,\nin motion.")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            HStack(spacing: 12) {
                Label("\(goals.filter { !$0.isComplete }.count) active", systemImage: "circle.dotted")
                Label("\(goals.filter(\.isComplete).count) reached", systemImage: "checkmark.seal")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background(AppTheme.heroGradient, in: RoundedRectangle(cornerRadius: 26))
    }

    private func nextGoalCard(_ goal: SavingsGoal) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("NEXT MILESTONE")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(AppTheme.accent)
            HStack {
                Text(goal.name).font(.title3.bold())
                Spacer()
                Text(goal.targetDate, format: .dateTime.month(.abbreviated).day())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text("\(goal.remainingAmount.formatted(.currency(code: goal.currencyCode))) to go")
                .font(.subheadline)
            HStack {
                Text("\(goal.suggestedMonthlyContribution().formatted(.currency(code: goal.currencyCode)))/month keeps you on track")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Button { contributingGoal = goal } label: {
                Label("Add funds", systemImage: "plus")
            }
            .buttonStyle(.glassProminent)
        }
        .padding(18)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    private func sectionTitle(_ title: String, count: Int) -> some View {
        HStack {
            Text(title).tracking(1.6)
            Spacer()
            Text("\(count)")
        }
        .font(.system(size: 11, weight: .bold, design: .rounded))
        .foregroundStyle(.secondary)
    }

    private func goalLink(_ goal: SavingsGoal) -> some View {
        NavigationLink {
            GoalDetailView(goal: goal, currencyCode: goal.currencyCode)
        } label: {
            GoalRow(goal: goal, currencyCode: goal.currencyCode)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { contributingGoal = goal } label: { Label("Add Funds", systemImage: "plus") }
            Button(role: .destructive) { goalsPendingDelete = [goal] } label: { Label("Delete", systemImage: "trash") }
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
        .padding(24)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
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
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
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
    @State private var deletingContribution: SavingsContribution?

    private var goalFacts: [String] {
        [
            "Goal: \(goal.name)",
            "Target: \(goal.targetAmount.formatted(.currency(code: currencyCode))) by \(goal.targetDate.formatted(date: .abbreviated, time: .omitted))",
            "Saved: \(goal.savedAmount.formatted(.currency(code: currencyCode)))",
            "Remaining: \(goal.remainingAmount.formatted(.currency(code: currencyCode)))",
            "Suggested monthly contribution: \(goal.suggestedMonthlyContribution().formatted(.currency(code: currencyCode)))",
            "Contributions: \(goal.contributions.count)"
        ] + goal.contributions.sorted { $0.date > $1.date }.prefix(5).map {
            "Contribution on \($0.date.formatted(date: .abbreviated, time: .omitted)): \($0.amount.formatted(.currency(code: currencyCode)))"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    Label(goal.name, systemImage: goal.systemIconName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                    Text(goal.savedAmount, format: .currency(code: currencyCode))
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("of \(goal.targetAmount.formatted(.currency(code: currencyCode))) saved")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                    ProgressView(value: goal.progressFraction)
                        .tint(.white)
                    Text(goal.isComplete ? "Goal reached" : "\(goal.remainingAmount.formatted(.currency(code: currencyCode))) left by \(goal.targetDate.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.heroGradient, in: RoundedRectangle(cornerRadius: 24))

                if !goal.isComplete {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("A steady way there").font(.headline)
                            Text("\(goal.suggestedMonthlyContribution().formatted(.currency(code: currencyCode))) each month")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "calendar.badge.clock").foregroundStyle(AppTheme.accent)
                    }
                    .padding(16)
                    .glassEffect(.regular, in: .rect(cornerRadius: 18))
                }

                LocalIntelligenceCard(
                    title: "Plan this goal",
                    subtitle: "Explore your pace with the on-device model",
                    facts: goalFacts,
                    suggestions: ["Am I on pace?", "What should I contribute next month?"]
                )

                HStack {
                    Text("CONTRIBUTIONS").tracking(1.5)
                    Spacer()
                    Text("\(goal.contributions.count)")
                }
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                if goal.contributions.isEmpty {
                    Text("Your contributions will appear here. Add the first one to start tracking progress.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassEffect(.regular, in: .rect(cornerRadius: 18))
                }
                ForEach(goal.contributions.sorted { $0.date > $1.date }) { contribution in
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.down.left")
                            .foregroundStyle(.green)
                            .frame(width: 34, height: 34)
                            .glassEffect(.regular, in: .circle)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(contribution.date, format: .dateTime.month().day().year().hour().minute())
                            if let note = contribution.note {
                                Text(note).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(contribution.amount, format: .currency(code: currencyCode)).fontWeight(.semibold)
                    }
                    .padding(14)
                    .glassEffect(.regular, in: .rect(cornerRadius: 18))
                    .onTapGesture { editingContribution = contribution }
                    .contextMenu {
                        Button {
                            editingContribution = contribution
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            deletingContribution = contribution
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 30)
        }
        .safeAreaInset(edge: .bottom) {
            Button { showingContribute = true } label: {
                Label("Add funds", systemImage: "plus")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.glassProminent)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .navigationTitle(goal.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem {
                Button {
                    showingEditGoal = true
                } label: {
                    Label("Edit Goal", systemImage: "pencil")
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
        .alert(
            "Delete Contribution?",
            isPresented: Binding(
                get: { deletingContribution != nil },
                set: { if !$0 { deletingContribution = nil } }
            ),
            presenting: deletingContribution
        ) { contribution in
            Button("Delete", role: .destructive) { delete(contribution) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This can't be undone.")
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
                        .keyboardType(.decimalPad)
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
                        .keyboardType(.decimalPad)
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
    @State private var showingDeleteConfirmation = false

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
                        .keyboardType(.decimalPad)
                }
                DatePicker("Target date", selection: $targetDate, displayedComponents: .date)
                Picker("Icon", selection: $icon) {
                    ForEach(iconChoices, id: \.self) { name in
                        Label(name, systemImage: name).tag(name)
                    }
                }

                Section {
                    Button("Delete Goal", role: .destructive) { showingDeleteConfirmation = true }
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
            .alert("Delete Goal?", isPresented: $showingDeleteConfirmation) {
                Button("Delete", role: .destructive) { deleteGoal() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This also deletes all its contributions. This can't be undone.")
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
                        .keyboardType(.decimalPad)
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
