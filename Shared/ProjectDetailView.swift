import SwiftUI
import SwiftData
import MoneyIQCore

struct ProjectDetailView: View {
    @Bindable var project: FreelanceProject

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var showingAddInstallment = false
    @State private var editingInstallment: PaymentInstallment?
    @State private var receivedDateEditTarget: PaymentInstallment?
    @State private var deletingInstallment: PaymentInstallment?
    @State private var showingAddReimbursement = false
    @State private var editingReimbursement: ProjectReimbursement?
    @State private var deletingReimbursement: ProjectReimbursement?
    @State private var showingEditProject = false

    private var currencyCode: String { project.currencyCode }

    private var installments: [PaymentInstallment] {
        project.installments.sorted { $0.createdAt < $1.createdAt }
    }

    private var reimbursements: [ProjectReimbursement] {
        project.reimbursements.sorted { $0.date > $1.date }
    }

    private var progress: Double {
        FreelanceProjectEngine.progressFraction(totalAmount: project.totalAmount, installments: project.installments)
    }

    private var received: Decimal { FreelanceProjectEngine.totalReceived(project.installments) }
    private var pending: Decimal { FreelanceProjectEngine.totalPending(project.installments) }
    private var unallocated: Decimal {
        FreelanceProjectEngine.unallocatedAmount(totalAmount: project.totalAmount, installments: project.installments)
    }

    private var totalReimbursed: Decimal { FreelanceProjectEngine.totalReimbursed(project.reimbursements) }
    private var outstandingReimbursements: Decimal { FreelanceProjectEngine.outstandingReimbursements(project.reimbursements) }

    private var projectFacts: [String] {
        [
            "Project: \(project.name)",
            "Client: \(project.clientName ?? "Not set")",
            "Quoted total: \(project.totalAmount.formatted(.currency(code: currencyCode)))",
            "Received: \(received.formatted(.currency(code: currencyCode)))",
            "Scheduled but pending: \(pending.formatted(.currency(code: currencyCode)))",
            "Not scheduled yet: \(unallocated.formatted(.currency(code: currencyCode)))",
            "Reimbursements still owed: \(outstandingReimbursements.formatted(.currency(code: currencyCode)))"
        ] + installments.prefix(8).map {
            "Installment \($0.label): \($0.amount.formatted(.currency(code: currencyCode))); \($0.isReceived ? "received" : "pending"); due \($0.dueDate?.formatted(date: .abbreviated, time: .omitted) ?? "not set")"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
            summaryHeader
            HStack(spacing: 10) {
                Button { showingAddInstallment = true } label: {
                    Label("Add payment", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                Button { showingAddReimbursement = true } label: {
                    Label("Log cost", systemImage: "arrow.uturn.backward")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
            }

            LocalIntelligenceCard(
                title: "Project brief",
                subtitle: "Ask about payments and money to recover",
                facts: projectFacts,
                suggestions: ["What is still owed?", "Which payment should I follow up on?"]
            )

            sectionHeading("PAYMENT INSTALLMENTS", count: installments.count) {
                showingAddInstallment = true
            }
                if installments.isEmpty {
                    emptySection("Set up an advance, milestone, or final payment to track what the client owes.")
                }
                ForEach(installments) { installment in
                    HStack(spacing: 4) {
                        InstallmentRow(installment: installment, currencyCode: currencyCode)
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                            .onTapGesture { receivedDateEditTarget = installment }
                        Button { editingInstallment = installment } label: {
                            Image(systemName: "pencil").frame(width: 34, height: 34)
                        }
                        .buttonStyle(.glass)
                        .accessibilityLabel("Edit \(installment.label)")
                    }
                    .padding(.horizontal, 12)
                    .glassEffect(.regular, in: .rect(cornerRadius: 18))
                    .contextMenu {
                            if installment.isReceived {
                                Button {
                                    toggleReceived(installment)
                                } label: {
                                    Label("Mark Pending", systemImage: "arrow.uturn.backward")
                                }
                            }
                            Button {
                                editingInstallment = installment
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                deletingInstallment = installment
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                    }
                }
                if unallocated > 0 {
                    Text("\(unallocated.formatted(.currency(code: currencyCode))) of the total isn't scheduled in any installment yet.")
                        .font(.caption).foregroundStyle(.secondary)
                }

            sectionHeading("REIMBURSEMENTS", count: reimbursements.count) {
                showingAddReimbursement = true
            }
                if reimbursements.isEmpty {
                    emptySection("Paid for a domain, tool, or travel? Log it here to track what the client owes back.")
                }
                ForEach(reimbursements) { reimbursement in
                    HStack(spacing: 4) {
                        ReimbursementRow(reimbursement: reimbursement, currencyCode: currencyCode)
                            .frame(maxWidth: .infinity)
                        Button { toggleRecovered(reimbursement) } label: {
                            Image(systemName: reimbursement.isRecovered ? "arrow.uturn.backward" : "checkmark")
                                .frame(width: 34, height: 34)
                        }
                        .buttonStyle(.glass)
                        .accessibilityLabel(reimbursement.isRecovered ? "Mark \(reimbursement.title) not recovered" : "Mark \(reimbursement.title) recovered")
                        Button { editingReimbursement = reimbursement } label: {
                            Image(systemName: "pencil").frame(width: 34, height: 34)
                        }
                        .buttonStyle(.glass)
                        .accessibilityLabel("Edit \(reimbursement.title)")
                    }
                    .padding(.horizontal, 12)
                    .glassEffect(.regular, in: .rect(cornerRadius: 18))
                    .contextMenu {
                            Button {
                                toggleRecovered(reimbursement)
                            } label: {
                                Label(reimbursement.isRecovered ? "Mark Not Recovered" : "Mark Recovered", systemImage: reimbursement.isRecovered ? "arrow.uturn.backward" : "checkmark.circle")
                            }
                            Button {
                                editingReimbursement = reimbursement
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                deletingReimbursement = reimbursement
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                    }
                }
                Text("Costs you fronted, tracked separately from the project quote.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 30)
        }
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem {
                Button {
                    showingEditProject = true
                } label: {
                    Label("Edit Project", systemImage: "pencil")
                }
            }
        }
        .sheet(isPresented: $showingAddInstallment) {
            AddInstallmentView(project: project)
        }
        .sheet(item: $editingInstallment) { installment in
            EditInstallmentView(project: project, installment: installment)
        }
        .sheet(item: $receivedDateEditTarget) { installment in
            InstallmentReceivedView(installment: installment)
        }
        .sheet(isPresented: $showingAddReimbursement) {
            AddReimbursementView(project: project)
        }
        .sheet(item: $editingReimbursement) { reimbursement in
            EditReimbursementView(reimbursement: reimbursement)
        }
        .sheet(isPresented: $showingEditProject) {
            EditProjectView(project: project, onDeleted: { dismiss() })
        }
        .alert(
            "Delete Installment?",
            isPresented: Binding(
                get: { deletingInstallment != nil },
                set: { if !$0 { deletingInstallment = nil } }
            ),
            presenting: deletingInstallment
        ) { installment in
            Button("Delete", role: .destructive) { delete(installment) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This can't be undone.")
        }
        .alert(
            "Delete Reimbursement?",
            isPresented: Binding(
                get: { deletingReimbursement != nil },
                set: { if !$0 { deletingReimbursement = nil } }
            ),
            presenting: deletingReimbursement
        ) { reimbursement in
            Button("Delete", role: .destructive) { delete(reimbursement) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This can't be undone.")
        }
    }

    private func sectionHeading(_ title: String, count: Int, add: @escaping () -> Void) -> some View {
        HStack {
            Text(title).tracking(1.4)
            Text("\(count)").foregroundStyle(AppTheme.accent)
            Spacer()
            Button(action: add) { Image(systemName: "plus") }
                .buttonStyle(.glass)
                .accessibilityLabel("Add \(title.lowercased())")
        }
        .font(.system(size: 11, weight: .bold, design: .rounded))
        .foregroundStyle(.secondary)
    }

    private func emptySection(_ message: String) -> some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }

    private var summaryHeader: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            if let clientName = project.clientName, !clientName.isEmpty {
                Text(clientName)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.75))
            }
            Text(project.totalAmount, format: .currency(code: currencyCode))
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            ProgressView(value: progress)
                .tint(.white)
                .background(Color.white.opacity(0.2), in: Capsule())

            HStack(spacing: 8) {
                summaryChip(label: "Received", amount: received, tint: .green)
                summaryChip(label: "Pending", amount: pending, tint: .white)
            }
            if outstandingReimbursements > 0 {
                summaryChip(label: "To recover", amount: outstandingReimbursements, tint: .orange)
            }
        }
        .padding(AppTheme.Spacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.heroGradient, in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
        .shadow(color: AppTheme.emberRed.opacity(0.3), radius: 16, y: 10)
    }

    private func summaryChip(label: String, amount: Decimal, tint: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(tint).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
                Text(amount, format: .currency(code: currencyCode))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.medium)
        .padding(.vertical, AppTheme.Spacing.small)
        .glassEffect(.regular.tint(.white.opacity(0.08)), in: .capsule)
    }

    private func toggleReceived(_ installment: PaymentInstallment) {
        installment.isReceived.toggle()
        installment.receivedDate = installment.isReceived ? .now : nil
        save()
    }

    private func toggleRecovered(_ reimbursement: ProjectReimbursement) {
        reimbursement.isRecovered.toggle()
        reimbursement.recoveredDate = reimbursement.isRecovered ? .now : nil
        save()
    }

    private func delete(_ installment: PaymentInstallment) {
        modelContext.delete(installment)
        save()
    }

    private func delete(_ reimbursement: ProjectReimbursement) {
        modelContext.delete(reimbursement)
        save()
    }

    private func save() {
        do {
            try modelContext.save()
        } catch {
            print("MoneyIQ: failed to save project change: \(error)")
        }
    }
}

private struct InstallmentRow: View {
    let installment: PaymentInstallment
    let currencyCode: String

    var body: some View {
        HStack(spacing: 12) {
            IconBubble(
                systemName: installment.isReceived ? "checkmark.circle.fill" : "clock",
                tint: installment.isReceived ? .green : AppTheme.accent
            )
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(installment.label).font(.subheadline.weight(.medium))
                    if let percentage = installment.percentage {
                        Text("(\(percentage.formatted())%)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if installment.isReceived {
                    Text(installment.receivedDate.map { "Received \($0.formatted(.dateTime.month().day().hour().minute()))" } ?? "Received")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let dueDate = installment.dueDate {
                    Text("Due \(dueDate.formatted(.dateTime.month().day()))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(installment.isReceived ? "Tap to correct receipt" : "Tap to mark received")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.accent)
            }
            Spacer()
            Text(installment.amount, format: .currency(code: currencyCode))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(installment.isReceived ? .green : .primary)
        }
        .padding(.vertical, AppTheme.Spacing.xs)
    }
}

private struct ReimbursementRow: View {
    let reimbursement: ProjectReimbursement
    let currencyCode: String

    var body: some View {
        HStack(spacing: 12) {
            IconBubble(
                systemName: reimbursement.isRecovered ? "checkmark.circle.fill" : "arrow.counterclockwise.circle",
                tint: reimbursement.isRecovered ? .green : .orange
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(reimbursement.title).font(.subheadline.weight(.medium))
                Text(reimbursement.isRecovered ? "Recovered" : "Not yet recovered")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(reimbursement.amount, format: .currency(code: currencyCode))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(reimbursement.isRecovered ? .green : .orange)
        }
        .padding(.vertical, AppTheme.Spacing.xs)
    }
}

// MARK: - Installments

private struct AddInstallmentView: View {
    let project: FreelanceProject

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var label = ""
    @State private var entryMode: InstallmentEntryMode = .percentage
    @State private var valueText = ""
    @State private var hasDueDate = false
    @State private var dueDate = Date.now
    @State private var note = ""

    private var computedAmount: Decimal? {
        guard let value = Decimal(string: valueText) else { return nil }
        switch entryMode {
        case .percentage:
            return FreelanceProjectEngine.amount(forPercentage: value, ofTotal: project.totalAmount)
        case .fixedAmount:
            return value
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                FinanceFormIntro(icon: "banknote", title: "Schedule a payment", detail: "Use a percentage or a fixed amount. The due date helps you know when to follow up.")
                    .listRowBackground(Color.clear)
                TextField("Label (e.g. Advance, Milestone 1)", text: $label)

                Section {
                    Picker("Entry", selection: $entryMode) {
                        Text("% of total").tag(InstallmentEntryMode.percentage)
                        Text("Fixed amount").tag(InstallmentEntryMode.fixedAmount)
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Text(entryMode == .percentage ? "Percentage" : "Amount")
                        Spacer()
                        TextField(entryMode == .percentage ? "0" : "0.00", text: $valueText)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                    }
                    if let computedAmount {
                        HStack {
                            Text("= \(computedAmount.formatted(.currency(code: project.currencyCode)))")
                                .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    let unallocated = FreelanceProjectEngine.unallocatedAmount(totalAmount: project.totalAmount, installments: project.installments)
                    Text("\(unallocated.formatted(.currency(code: project.currencyCode))) of the total isn't scheduled yet.")
                }

                Section {
                    Toggle("Due date", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("Due", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                    }
                    TextField("Note (optional)", text: $note)
                }
            }
            .navigationTitle("Add Installment")
            .compactFormLayout()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(label.trimmingCharacters(in: .whitespaces).isEmpty || !(computedAmount.map { $0 > 0 } ?? false))
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func save() {
        guard let amount = computedAmount, amount > 0, let rawValue = Decimal(string: valueText) else { return }
        let installment = PaymentInstallment(
            label: label.trimmingCharacters(in: .whitespaces),
            amount: amount,
            percentage: entryMode == .percentage ? rawValue : nil,
            dueDate: hasDueDate ? dueDate : nil,
            note: note.isEmpty ? nil : note,
            project: project
        )
        modelContext.insert(installment)
        do {
            try modelContext.save()
        } catch {
            print("MoneyIQ: failed to save installment: \(error)")
        }
        dismiss()
    }
}

private struct EditInstallmentView: View {
    let project: FreelanceProject
    @Bindable var installment: PaymentInstallment

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var label: String
    @State private var amountText: String
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var isReceived: Bool
    @State private var receivedDate: Date
    @State private var note: String

    init(project: FreelanceProject, installment: PaymentInstallment) {
        self.project = project
        self.installment = installment
        _label = State(initialValue: installment.label)
        _amountText = State(initialValue: NSDecimalNumber(decimal: installment.amount).stringValue)
        _hasDueDate = State(initialValue: installment.dueDate != nil)
        _dueDate = State(initialValue: installment.dueDate ?? .now)
        _isReceived = State(initialValue: installment.isReceived)
        _receivedDate = State(initialValue: installment.receivedDate ?? .now)
        _note = State(initialValue: installment.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                FinanceFormIntro(icon: "pencil", title: "Update this payment", detail: "Correct its amount, due time, or the exact date and time received.")
                    .listRowBackground(Color.clear)
                TextField("Label", text: $label)
                HStack {
                    Text("Amount")
                    Spacer()
                    TextField("0.00", text: $amountText)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                }
                Toggle("Due date", isOn: $hasDueDate)
                if hasDueDate {
                    DatePicker("Due", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                }
                Toggle("Received", isOn: $isReceived)
                if isReceived {
                    DatePicker("Received at", selection: $receivedDate, displayedComponents: [.date, .hourAndMinute])
                }
                TextField("Note (optional)", text: $note)
            }
            .navigationTitle("Edit Installment")
            .compactFormLayout()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(label.trimmingCharacters(in: .whitespaces).isEmpty || !(Decimal(string: amountText).map { $0 > 0 } ?? false))
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func save() {
        guard let amount = Decimal(string: amountText), amount > 0 else { return }
        installment.label = label.trimmingCharacters(in: .whitespaces)
        installment.amount = amount
        // A directly-edited amount may no longer match the originally
        // entered percentage, so drop it rather than show a stale figure.
        installment.percentage = nil
        installment.dueDate = hasDueDate ? dueDate : nil
        installment.isReceived = isReceived
        installment.receivedDate = isReceived ? receivedDate : nil
        installment.note = note.isEmpty ? nil : note
        do {
            try modelContext.save()
        } catch {
            print("MoneyIQ: failed to save edited installment: \(error)")
        }
        dismiss()
    }
}

private enum InstallmentEntryMode {
    case percentage
    case fixedAmount
}

/// Shown when tapping an installment row — marks it received (or, if
/// already received, lets the date and time be corrected) at a moment the
/// user picks rather than always silently stamping "now."
private struct InstallmentReceivedView: View {
    @Bindable var installment: PaymentInstallment

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var receivedDate: Date

    init(installment: PaymentInstallment) {
        self.installment = installment
        _receivedDate = State(initialValue: installment.receivedDate ?? .now)
    }

    var body: some View {
        NavigationStack {
            Form {
                FinanceFormIntro(icon: "checkmark.circle", title: installment.isReceived ? "Correct receipt time" : "Record when it arrived", detail: "Choose the actual date and time. You can change this later.")
                    .listRowBackground(Color.clear)
                Section {
                    LabeledContent(installment.label, value: installment.amount.formatted(.currency(code: installment.project?.currencyCode ?? "USD")))
                    DatePicker("Received at", selection: $receivedDate, displayedComponents: [.date, .hourAndMinute])
                }

                if installment.isReceived {
                    Section {
                        Button("Mark as Pending", role: .destructive) { markPending() }
                    }
                }
            }
            .navigationTitle(installment.isReceived ? "Edit Receipt" : "Mark Received")
            .compactFormLayout()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { markReceived() }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func markReceived() {
        installment.isReceived = true
        installment.receivedDate = receivedDate
        save()
    }

    private func markPending() {
        installment.isReceived = false
        installment.receivedDate = nil
        save()
    }

    private func save() {
        do {
            try modelContext.save()
        } catch {
            print("MoneyIQ: failed to save installment received date: \(error)")
        }
        dismiss()
    }
}

// MARK: - Reimbursements

private struct AddReimbursementView: View {
    let project: FreelanceProject

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var amountText = ""
    @State private var date = Date.now
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                FinanceFormIntro(icon: "arrow.uturn.backward", title: "Track a client cost", detail: "Keep money you fronted separate from the payment for your work.")
                    .listRowBackground(Color.clear)
                TextField("What did you pay for? (e.g. Domain, VPS)", text: $title)
                HStack {
                    Text("Amount")
                    Spacer()
                    TextField("0.00", text: $amountText)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                }
                DatePicker("Paid at", selection: $date, displayedComponents: [.date, .hourAndMinute])
                TextField("Note (optional)", text: $note)
            }
            .navigationTitle("Add Reimbursement")
            .compactFormLayout()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || !(Decimal(string: amountText).map { $0 > 0 } ?? false))
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func save() {
        guard let amount = Decimal(string: amountText), amount > 0 else { return }
        let reimbursement = ProjectReimbursement(
            title: title.trimmingCharacters(in: .whitespaces),
            amount: amount,
            date: date,
            note: note.isEmpty ? nil : note,
            project: project
        )
        modelContext.insert(reimbursement)
        do {
            try modelContext.save()
        } catch {
            print("MoneyIQ: failed to save reimbursement: \(error)")
        }
        dismiss()
    }
}

private struct EditReimbursementView: View {
    @Bindable var reimbursement: ProjectReimbursement

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var amountText: String
    @State private var date: Date
    @State private var isRecovered: Bool
    @State private var recoveredDate: Date
    @State private var note: String

    init(reimbursement: ProjectReimbursement) {
        self.reimbursement = reimbursement
        _title = State(initialValue: reimbursement.title)
        _amountText = State(initialValue: NSDecimalNumber(decimal: reimbursement.amount).stringValue)
        _date = State(initialValue: reimbursement.date)
        _isRecovered = State(initialValue: reimbursement.isRecovered)
        _recoveredDate = State(initialValue: reimbursement.recoveredDate ?? .now)
        _note = State(initialValue: reimbursement.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                FinanceFormIntro(icon: "pencil", title: "Update this cost", detail: "Correct the amount or when the client paid you back.")
                    .listRowBackground(Color.clear)
                TextField("Title", text: $title)
                HStack {
                    Text("Amount")
                    Spacer()
                    TextField("0.00", text: $amountText)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                }
                DatePicker("Paid at", selection: $date, displayedComponents: [.date, .hourAndMinute])
                Toggle("Recovered from client", isOn: $isRecovered)
                if isRecovered {
                    DatePicker("Recovered at", selection: $recoveredDate, displayedComponents: [.date, .hourAndMinute])
                }
                TextField("Note (optional)", text: $note)
            }
            .navigationTitle("Edit Reimbursement")
            .compactFormLayout()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || !(Decimal(string: amountText).map { $0 > 0 } ?? false))
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func save() {
        guard let amount = Decimal(string: amountText), amount > 0 else { return }
        reimbursement.title = title.trimmingCharacters(in: .whitespaces)
        reimbursement.amount = amount
        reimbursement.date = date
        reimbursement.recoveredDate = isRecovered ? recoveredDate : nil
        reimbursement.isRecovered = isRecovered
        reimbursement.note = note.isEmpty ? nil : note
        do {
            try modelContext.save()
        } catch {
            print("MoneyIQ: failed to save edited reimbursement: \(error)")
        }
        dismiss()
    }
}

// MARK: - Edit project

private struct EditProjectView: View {
    @Bindable var project: FreelanceProject
    let onDeleted: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var clientName: String
    @State private var totalText: String
    @State private var notes: String
    @State private var showingDeleteConfirmation = false

    init(project: FreelanceProject, onDeleted: @escaping () -> Void) {
        self.project = project
        self.onDeleted = onDeleted
        _name = State(initialValue: project.name)
        _clientName = State(initialValue: project.clientName ?? "")
        _totalText = State(initialValue: NSDecimalNumber(decimal: project.totalAmount).stringValue)
        _notes = State(initialValue: project.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                FinanceFormIntro(icon: "briefcase", title: "Refine the quote", detail: "Update the project details without changing its payment history.")
                    .listRowBackground(Color.clear)
                TextField("Project name", text: $name)
                TextField("Client name (optional)", text: $clientName)
                HStack {
                    Text("Total quoted")
                    Spacer()
                    TextField("0.00", text: $totalText)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                }
                TextField("Notes (optional)", text: $notes)

                Section {
                    Button("Delete Project", role: .destructive) { showingDeleteConfirmation = true }
                }
            }
            .navigationTitle("Edit Project")
            .compactFormLayout()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || !(Decimal(string: totalText).map { $0 > 0 } ?? false))
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Delete Project?", isPresented: $showingDeleteConfirmation) {
                Button("Delete", role: .destructive) { deleteProject() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This also deletes all its installments and reimbursements. This can't be undone.")
            }
        }
    }

    private func save() {
        guard let total = Decimal(string: totalText), total > 0 else { return }
        project.name = name.trimmingCharacters(in: .whitespaces)
        project.clientName = clientName.trimmingCharacters(in: .whitespaces).isEmpty ? nil : clientName
        project.totalAmount = total
        project.notes = notes.isEmpty ? nil : notes
        do {
            try modelContext.save()
        } catch {
            print("MoneyIQ: failed to save edited project: \(error)")
        }
        dismiss()
    }

    private func deleteProject() {
        modelContext.delete(project)
        do {
            try modelContext.save()
        } catch {
            print("MoneyIQ: failed to delete project: \(error)")
        }
        dismiss()
        onDeleted()
    }
}
