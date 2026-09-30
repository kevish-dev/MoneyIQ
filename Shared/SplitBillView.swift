import SwiftUI
import SwiftData
import MoneyIQCore

/// "Split a Bill": you paid the full amount for a group (e.g. dinner), and
/// this divides it equally among everyone who was there, creating one
/// `LedgerEntry` per selected person for their share — each entry means
/// "I paid this on their behalf," so it correctly shows up as them owing
/// you that share.
struct SplitBillView: View {
    let currencyCode: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \LedgerContact.createdAt, order: .reverse) private var contacts: [LedgerContact]

    @State private var totalText = ""
    @State private var note = ""
    @State private var date = Date.now
    @State private var selectedContactIDs: Set<PersistentIdentifier> = []
    @State private var showingAddPerson = false

    private var total: Decimal? {
        guard let value = Decimal(string: totalText), value > 0 else { return nil }
        return value
    }

    /// Includes you (the payer) as one of the people splitting the bill.
    private var participantCount: Int { selectedContactIDs.count + 1 }

    private var shareAmount: Decimal? {
        guard let total, participantCount > 1 else { return nil }
        return LedgerEngine.splitEqually(total: total, participantCount: participantCount).first
    }

    private var canSave: Bool {
        total != nil && !selectedContactIDs.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Total bill")
                        Spacer()
                        TextField("0.00", text: $totalText)
                            .multilineTextAlignment(.trailing)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                    }
                    DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    TextField("What for? (e.g. Dinner)", text: $note)
                } footer: {
                    Text("You paid the full amount. Pick who was splitting it with you below.")
                }

                Section("Split with") {
                    if contacts.isEmpty {
                        Text("No one here yet — add a person to split with.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(contacts) { contact in
                        Button {
                            toggle(contact)
                        } label: {
                            HStack {
                                Text(contact.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selectedContactIDs.contains(contact.id) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(AppTheme.accent)
                                } else {
                                    Image(systemName: "circle")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    Button {
                        showingAddPerson = true
                    } label: {
                        Label("Add New Person", systemImage: "person.badge.plus")
                    }
                }

                if let shareAmount {
                    Section {
                        HStack {
                            Text("\(participantCount) people total (including you)")
                            Spacer()
                            Text("\(shareAmount.formatted(.currency(code: currencyCode))) each")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Split a Bill")
            .compactFormLayout()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showingAddPerson) {
                AddSplitParticipantView { newContact in
                    selectedContactIDs.insert(newContact.id)
                }
            }
        }
    }

    private func toggle(_ contact: LedgerContact) {
        if selectedContactIDs.contains(contact.id) {
            selectedContactIDs.remove(contact.id)
        } else {
            selectedContactIDs.insert(contact.id)
        }
    }

    private func save() {
        guard let total else { return }
        let selectedContacts = contacts.filter { selectedContactIDs.contains($0.id) }
        guard !selectedContacts.isEmpty else { return }

        let shares = LedgerEngine.splitEqually(total: total, participantCount: participantCount)
        // Your own share (the payer's) is the last one — you already covered
        // it out of pocket, so only the other participants' shares become
        // entries.
        for (contact, share) in zip(selectedContacts, shares) {
            let entry = LedgerEntry(
                amount: share,
                direction: .iPaid,
                note: note.isEmpty ? nil : note,
                date: date,
                isSettlement: false,
                contact: contact
            )
            modelContext.insert(entry)
            contact.markActivity()
        }
        do {
            try modelContext.save()
        } catch {
            print("MoneyIQ: failed to save split bill entries: \(error)")
        }
        dismiss()
    }
}

/// Quick inline "add a new person" sheet used from within the bill-split
/// flow — mirrors `LedgerView`'s `AddContactView` but hands the newly
/// created contact back to the caller so it can be auto-selected.
private struct AddSplitParticipantView: View {
    let onCreate: (LedgerContact) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
            }
            .navigationTitle("New Person")
            .compactFormLayout()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let contact = LedgerContact(name: name.trimmingCharacters(in: .whitespaces))
                        modelContext.insert(contact)
                        try? modelContext.save()
                        onCreate(contact)
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
