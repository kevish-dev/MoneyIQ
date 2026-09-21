import SwiftUI
import SwiftData
import MoneyIQCore

struct LedgerContactDetailView: View {
    @Bindable var contact: LedgerContact
    let currencyCode: String

    @Environment(\.modelContext) private var modelContext
    @State private var showingAddEntry = false
    @State private var settlementDraft: SettlementDraft?
    @State private var editingEntry: LedgerEntry?
    @State private var showingRename = false

    private var sortedEntries: [LedgerEntry] {
        contact.entries.sorted { $0.date > $1.date }
    }

    private var state: LedgerEngine.BalanceState {
        LedgerEngine.balanceState(for: contact.entries)
    }

    private var settlementSuggestion: (amount: Decimal, direction: LedgerDirection)? {
        LedgerEngine.settlementSuggestion(for: contact.entries)
    }

    var body: some View {
        List {
            balanceHeader
                .listRowInsets(EdgeInsets(
                    top: AppTheme.Spacing.small,
                    leading: AppTheme.Spacing.large,
                    bottom: AppTheme.Spacing.small,
                    trailing: AppTheme.Spacing.large
                ))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

            Section("History") {
                if sortedEntries.isEmpty {
                    Text("No transactions yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(sortedEntries) { entry in
                    EntryRow(entry: entry, currencyCode: currencyCode)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                delete(entry)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button {
                                editingEntry = entry
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(AppTheme.accent)
                        }
                }
            }
        }
        .navigationTitle(contact.name)
        .compactListLayout()
        .toolbar {
            ToolbarItem {
                Button {
                    showingRename = true
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
            }
        }
        .sheet(isPresented: $showingAddEntry) {
            AddLedgerEntryView(contact: contact, currencyCode: currencyCode, isSettlement: false)
        }
        .sheet(item: $settlementDraft) { draft in
            AddLedgerEntryView(
                contact: contact,
                currencyCode: currencyCode,
                isSettlement: true,
                prefillAmount: draft.amount,
                prefillDirection: draft.direction
            )
        }
        .sheet(item: $editingEntry) { entry in
            EditLedgerEntryView(entry: entry, currencyCode: currencyCode)
        }
        .sheet(isPresented: $showingRename) {
            RenameContactView(contact: contact)
        }
    }

    private var balanceHeader: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            switch state {
            case .theyOweYou(let amount):
                Text("\(contact.name) owes you")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.75))
                Text(amount, format: .currency(code: currencyCode))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            case .youOweThem(let amount):
                Text("You owe \(contact.name)")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.75))
                Text(amount, format: .currency(code: currencyCode))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            case .settled:
                Label("All settled up", systemImage: "checkmark.seal.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
            }

            HStack(spacing: AppTheme.Spacing.medium) {
                Button {
                    showingAddEntry = true
                } label: {
                    Label("Add Transaction", systemImage: "plus")
                        .labelStyle(.titleAndIcon)
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppTheme.Spacing.medium)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white.opacity(0.25))
                .foregroundStyle(.white)

                if let suggestion = settlementSuggestion {
                    Button {
                        settlementDraft = SettlementDraft(amount: suggestion.amount, direction: suggestion.direction)
                    } label: {
                        Label("Settle Up", systemImage: "checkmark.circle")
                            .labelStyle(.titleAndIcon)
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, AppTheme.Spacing.medium)
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                    .foregroundStyle(.white)
                }
            }
        }
        .padding(AppTheme.Spacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.heroGradient, in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
        .shadow(color: AppTheme.emberRed.opacity(0.3), radius: 16, y: 10)
    }

    private func delete(_ entry: LedgerEntry) {
        modelContext.delete(entry)
        do {
            try modelContext.save()
        } catch {
            print("MoneyIQ: failed to delete ledger entry: \(error)")
        }
    }
}

private struct SettlementDraft: Identifiable {
    let id = UUID()
    let amount: Decimal
    let direction: LedgerDirection
}

private struct EntryRow: View {
    let entry: LedgerEntry
    let currencyCode: String

    var body: some View {
        HStack(spacing: 12) {
            IconBubble(
                systemName: entry.isSettlement
                    ? "checkmark.circle.fill"
                    : (entry.direction == .theyPaid ? "arrow.down.circle.fill" : "arrow.up.circle.fill"),
                tint: entry.direction == .theyPaid ? .red : .green
            )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.note?.isEmpty == false ? entry.note! : defaultLabel)
                        .font(.subheadline.weight(.medium))
                    if entry.isSettlement {
                        Text("Settled")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppTheme.accent.opacity(0.15), in: Capsule())
                            .foregroundStyle(AppTheme.accent)
                    }
                }
                Text(relativeTimeText(for: entry.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(signedAmountText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(entry.direction == .theyPaid ? .red : .green)
        }
        .padding(.vertical, AppTheme.Spacing.small)
    }

    private var defaultLabel: String {
        entry.direction == .iPaid ? "You paid" : "They paid"
    }

    private var signedAmountText: String {
        let formatted = entry.amount.formatted(.currency(code: currencyCode))
        return entry.direction == .theyPaid ? "-\(formatted)" : "+\(formatted)"
    }

    /// "Today, 9:42 AM" for today's entries, otherwise a short date + time —
    /// matches the same pattern used for the Home transaction list.
    private func relativeTimeText(for date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return "Today, \(date.formatted(.dateTime.hour().minute()))"
        } else if Calendar.current.isDateInYesterday(date) {
            return "Yesterday, \(date.formatted(.dateTime.hour().minute()))"
        }
        return date.formatted(.dateTime.month(.abbreviated).day().year().hour().minute())
    }
}

private struct AddLedgerEntryView: View {
    let contact: LedgerContact
    let currencyCode: String
    let isSettlement: Bool
    var prefillAmount: Decimal?
    var prefillDirection: LedgerDirection?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var amountText: String
    @State private var direction: LedgerDirection
    @State private var note = ""
    @State private var date = Date.now

    init(contact: LedgerContact, currencyCode: String, isSettlement: Bool, prefillAmount: Decimal? = nil, prefillDirection: LedgerDirection? = nil) {
        self.contact = contact
        self.currencyCode = currencyCode
        self.isSettlement = isSettlement
        self.prefillAmount = prefillAmount
        self.prefillDirection = prefillDirection
        _amountText = State(initialValue: prefillAmount.map { "\($0)" } ?? "")
        _direction = State(initialValue: prefillDirection ?? .iPaid)
    }

    var body: some View {
        NavigationStack {
            Form {
                if isSettlement {
                    Section {
                        Label(
                            direction == .iPaid
                                ? "You paid \(contact.name) to settle up"
                                : "\(contact.name) paid you to settle up",
                            systemImage: "checkmark.circle.fill"
                        )
                        .foregroundStyle(AppTheme.accent)
                    }
                }

                Section {
                    Picker("Direction", selection: $direction) {
                        Text("I paid").tag(LedgerDirection.iPaid)
                        Text("They paid").tag(LedgerDirection.theyPaid)
                    }
                    .pickerStyle(.segmented)

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
                    TextField(isSettlement ? "Note (optional)" : "What for? (e.g. Borrowed cash, Shopping)", text: $note)
                }
            }
            .navigationTitle(isSettlement ? "Settle Up" : "Add Transaction")
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
        let entry = LedgerEntry(
            amount: amount,
            direction: direction,
            note: note.isEmpty ? nil : note,
            date: date,
            isSettlement: isSettlement,
            contact: contact
        )
        modelContext.insert(entry)
        do {
            try modelContext.save()
        } catch {
            print("MoneyIQ: failed to save ledger entry: \(error)")
        }
        dismiss()
    }
}

private struct EditLedgerEntryView: View {
    let entry: LedgerEntry
    let currencyCode: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var amountText: String
    @State private var direction: LedgerDirection
    @State private var note: String
    @State private var date: Date
    @State private var isSettlement: Bool

    init(entry: LedgerEntry, currencyCode: String) {
        self.entry = entry
        self.currencyCode = currencyCode
        _amountText = State(initialValue: NSDecimalNumber(decimal: entry.amount).stringValue)
        _direction = State(initialValue: entry.direction)
        _note = State(initialValue: entry.note ?? "")
        _date = State(initialValue: entry.date)
        _isSettlement = State(initialValue: entry.isSettlement)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Direction", selection: $direction) {
                        Text("I paid").tag(LedgerDirection.iPaid)
                        Text("They paid").tag(LedgerDirection.theyPaid)
                    }
                    .pickerStyle(.segmented)

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
                    TextField("What for? (e.g. Borrowed cash, Shopping)", text: $note)
                }

                Section {
                    Toggle("Counts as a settlement", isOn: $isSettlement)
                } footer: {
                    Text("Shows a \u{201C}Settled\u{201D} badge instead of listing it as a regular transaction.")
                }
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
        entry.amount = amount
        entry.direction = direction
        entry.note = note.isEmpty ? nil : note
        entry.date = date
        entry.isSettlement = isSettlement
        do {
            try modelContext.save()
        } catch {
            print("MoneyIQ: failed to save edited ledger entry: \(error)")
        }
        dismiss()
    }
}

private struct RenameContactView: View {
    @Bindable var contact: LedgerContact

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name: String

    init(contact: LedgerContact) {
        self.contact = contact
        _name = State(initialValue: contact.name)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
            }
            .navigationTitle("Rename Person")
            .compactFormLayout()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        contact.name = name.trimmingCharacters(in: .whitespaces)
                        do {
                            try modelContext.save()
                        } catch {
                            print("MoneyIQ: failed to rename contact: \(error)")
                        }
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
