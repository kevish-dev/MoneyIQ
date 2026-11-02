import SwiftUI
import SwiftData
import MoneyIQCore

/// The payer keeps one share; each selected person gets a ledger entry for
/// the exact amount they owe. The preview uses the same split as save().
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
    @State private var saveError: String?

    private var total: Decimal? {
        guard let value = Decimal(string: totalText), value > 0 else { return nil }
        return value
    }

    private var selectedContacts: [LedgerContact] {
        contacts.filter { selectedContactIDs.contains($0.id) }
    }

    private var shares: [Decimal] {
        guard let total, !selectedContacts.isEmpty else { return [] }
        return LedgerEngine.splitEqually(total: total, participantCount: selectedContacts.count + 1)
    }

    private var canSave: Bool { total != nil && !selectedContacts.isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    SplitSheetHeader(
                        eyebrow: "Group payment",
                        title: "Split a bill",
                        message: "You paid the full bill. Pick who shared it with you; your own share stays out of the ledger.",
                        symbol: "person.3.fill"
                    )
                    amountCard
                    detailsCard
                    peoplePicker
                    splitPreview
                }
                .frame(maxWidth: 560)
                .padding(20)
                .frame(maxWidth: .infinity)
            }
            .background(SplitDesign.paper.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                Button("Record split", action: save)
                    .buttonStyle(SplitPrimaryButtonStyle())
                    .disabled(!canSave)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.regularMaterial)
            }
            .sheet(isPresented: $showingAddPerson) {
                AddSplitParticipantView { newContact in
                    selectedContactIDs.insert(newContact.id)
                }
            }
            .alert("Couldn't record split", isPresented: Binding(
                get: { saveError != nil }, set: { if !$0 { saveError = nil } }
            )) {
                Button("OK", role: .cancel) { saveError = nil }
            } message: { Text(saveError ?? "Please try again.") }
        }
    }

    private var amountCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("TOTAL BILL")
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text(currencyCode)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.emberRed)
                TextField("0.00", text: $totalText)
                    .font(.system(size: 31, weight: .bold, design: .rounded))
                    .keyboardType(.decimalPad)
                    .foregroundStyle(SplitDesign.ink)
                    .accessibilityLabel("Total bill")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SplitDesign.card, in: RoundedRectangle(cornerRadius: 20))
    }

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("WHAT WAS IT FOR?")
                TextField("Dinner, tickets, groceries…", text: $note)
                    .font(.subheadline)
                    .textInputAutocapitalization(.sentences)
            }
            Rectangle().fill(Color.black.opacity(0.07)).frame(height: 1)
            DatePicker("WHEN", selection: $date, displayedComponents: [.date, .hourAndMinute])
                .font(.subheadline.weight(.medium))
        }
        .padding(18)
        .background(SplitDesign.card, in: RoundedRectangle(cornerRadius: 20))
    }

    private var peoplePicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Split with")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(SplitDesign.ink)
                Spacer()
                Button { showingAddPerson = true } label: {
                    Label("Add person", systemImage: "plus")
                        .font(.caption.weight(.semibold))
                }
                .tint(AppTheme.emberRed)
            }
            if contacts.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No people yet")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SplitDesign.ink)
                    Text("Add someone above to split this bill with them.")
                        .font(.caption)
                        .foregroundStyle(SplitDesign.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(SplitDesign.card, in: RoundedRectangle(cornerRadius: 20))
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(contacts) { contact in
                        if contact.id != contacts.first?.id {
                            Rectangle().fill(Color.black.opacity(0.06)).frame(height: 1).padding(.leading, 66)
                        }
                        Button { toggle(contact) } label: {
                            HStack(spacing: 11) {
                                SplitAvatar(name: contact.name, colorHex: contact.colorHex, size: 39)
                                Text(contact.name)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(SplitDesign.ink)
                                    .lineLimit(1)
                                Spacer()
                                Image(systemName: selectedContactIDs.contains(contact.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(selectedContactIDs.contains(contact.id) ? AppTheme.emberRed : SplitDesign.muted.opacity(0.55))
                            }
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selectedContactIDs.contains(contact.id) ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 15)
                .background(SplitDesign.card, in: RoundedRectangle(cornerRadius: 20))
            }
        }
    }

    private var splitPreview: some View {
        let people = selectedContacts
        let portions = shares
        return VStack(alignment: .leading, spacing: 11) {
            sectionLabel("SPLIT PREVIEW")
            if let total, !portions.isEmpty {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(people.count + 1) people, including you")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SplitDesign.ink)
                    Spacer(minLength: 6)
                    Text(SplitDesign.money(total, code: currencyCode))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(SplitDesign.ink)
                }
                Rectangle().fill(Color.black.opacity(0.07)).frame(height: 1)
                ForEach(Array(people.indices), id: \.self) { index in
                    HStack {
                        Text(people[index].name)
                        Spacer()
                        Text(SplitDesign.money(portions[index], code: currencyCode))
                            .fontWeight(.semibold)
                    }
                    .font(.subheadline)
                    .foregroundStyle(SplitDesign.ink)
                }
                HStack {
                    Text("Your share")
                    Spacer()
                    Text(SplitDesign.money(portions.last ?? 0, code: currencyCode))
                        .fontWeight(.semibold)
                }
                .font(.subheadline)
                .foregroundStyle(SplitDesign.muted)
                Text("Only the selected people's shares become balances owed to you.")
                    .font(.caption)
                    .foregroundStyle(SplitDesign.muted)
                    .padding(.top, 2)
            } else {
                Text("Enter a total and choose at least one person to see their exact shares.")
                    .font(.subheadline)
                    .foregroundStyle(SplitDesign.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(AppTheme.emberRed.opacity(0.07), in: RoundedRectangle(cornerRadius: 20))
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .tracking(1.1)
            .foregroundStyle(SplitDesign.muted)
    }

    private func toggle(_ contact: LedgerContact) {
        if selectedContactIDs.contains(contact.id) { selectedContactIDs.remove(contact.id) }
        else { selectedContactIDs.insert(contact.id) }
    }

    private func save() {
        let people = selectedContacts
        let portions = shares
        guard total != nil, !people.isEmpty, portions.count == people.count + 1 else { return }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        for (contact, share) in zip(people, portions) {
            modelContext.insert(LedgerEntry(
                amount: share,
                direction: .iPaid,
                note: trimmedNote.isEmpty ? nil : trimmedNote,
                date: date,
                isSettlement: false,
                contact: contact
            ))
            contact.markActivity()
        }
        do { try modelContext.save(); dismiss() }
        catch { saveError = error.localizedDescription }
    }
}

private struct AddSplitParticipantView: View {
    let onCreate: (LedgerContact) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var saveError: String?

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    SplitSheetHeader(
                        eyebrow: "Split participant",
                        title: "Add a person",
                        message: "They'll be selected for this bill and available for future balances.",
                        symbol: "person.badge.plus"
                    )
                    VStack(alignment: .leading, spacing: 8) {
                        Text("NAME")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .tracking(1)
                            .foregroundStyle(SplitDesign.muted)
                        TextField("Full name", text: $name)
                            .font(.system(size: 19, weight: .medium, design: .rounded))
                            .textContentType(.name)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.done)
                            .onSubmit(save)
                    }
                    .padding(18)
                    .background(SplitDesign.card, in: RoundedRectangle(cornerRadius: 20))
                }
                .frame(maxWidth: 560)
                .padding(20)
                .frame(maxWidth: .infinity)
            }
            .background(SplitDesign.paper.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                Button("Add person", action: save)
                    .buttonStyle(SplitPrimaryButtonStyle())
                    .disabled(trimmedName.isEmpty)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.regularMaterial)
            }
            .alert("Couldn't save person", isPresented: Binding(
                get: { saveError != nil }, set: { if !$0 { saveError = nil } }
            )) {
                Button("OK", role: .cancel) { saveError = nil }
            } message: { Text(saveError ?? "Please try again.") }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        let contact = LedgerContact(name: trimmedName)
        modelContext.insert(contact)
        do {
            try modelContext.save()
            onCreate(contact)
            dismiss()
        } catch { saveError = error.localizedDescription }
    }
}
