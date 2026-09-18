import SwiftUI
import SwiftData
import MoneyIQCore

struct LedgerContactDetailView: View {
    @Bindable var contact: LedgerContact
    let currencyCode: String

    @Environment(\.modelContext) private var modelContext
    @State private var showingAddEntry = false
    @State private var settlementDraft: SettlementDraft?

    private var sortedEntries: [LedgerEntry] {
        contact.entries.sorted { $0.date > $1.date }
    }

    private var state: LedgerEngine.BalanceState {
        LedgerEngine.balanceState(for: contact.entries)
    }

    var body: some View {
        List {
            Section {
                balanceHeader
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section("History") {
                if sortedEntries.isEmpty {
                    Text("No transactions yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(sortedEntries) { entry in
                    EntryRow(entry: entry, currencyCode: currencyCode)
                }
                .onDelete(perform: delete)
            }
        }
        .navigationTitle(contact.name)
        .toolbar {
            ToolbarItem {
                Menu {
                    Button {
                        showingAddEntry = true
                    } label: {
                        Label("Add Transaction", systemImage: "plus")
                    }
                    if let suggestion = LedgerEngine.settlementSuggestion(for: contact.entries) {
                        Button {
                            settlementDraft = SettlementDraft(amount: suggestion.amount, direction: suggestion.direction)
                        } label: {
                            Label("Settle Up", systemImage: "checkmark.circle")
                        }
                    }
                } label: {
                    Label("Add", systemImage: "plus.circle")
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
    }

    private var balanceHeader: some View {
        VStack(spacing: 8) {
            switch state {
            case .theyOweYou(let amount):
                Text("\(contact.name) owes you").font(.subheadline).foregroundStyle(.secondary)
                Text(amount, format: .currency(code: currencyCode))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(.green)
            case .youOweThem(let amount):
                Text("You owe \(contact.name)").font(.subheadline).foregroundStyle(.secondary)
                Text(amount, format: .currency(code: currencyCode))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(.red)
            case .settled:
                Text("All settled up").font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            if let entry = sortedEntries[safe: index] {
                modelContext.delete(entry)
            }
        }
        try? modelContext.save()
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
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.note?.isEmpty == false ? entry.note! : defaultLabel)
                    if entry.isSettlement {
                        Text("Settled")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.blue.opacity(0.15), in: Capsule())
                            .foregroundStyle(.blue)
                    }
                }
                Text(entry.date, format: .dateTime.month().day().year())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(signedAmountText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(entry.direction == .theyPaid ? .red : .green)
        }
    }

    private var defaultLabel: String {
        entry.direction == .iPaid ? "You paid" : "They paid"
    }

    private var signedAmountText: String {
        let formatted = entry.amount.formatted(.currency(code: currencyCode))
        return entry.direction == .theyPaid ? "-\(formatted)" : "+\(formatted)"
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
                        .foregroundStyle(.blue)
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
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    TextField(isSettlement ? "Note (optional)" : "What for? (e.g. Borrowed cash, Shopping)", text: $note)
                }
            }
            .navigationTitle(isSettlement ? "Settle Up" : "Add Transaction")
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
        try? modelContext.save()
        dismiss()
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
