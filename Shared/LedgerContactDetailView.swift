import SwiftUI
import SwiftData
import MoneyIQCore

struct LedgerContactDetailView: View {
    @Bindable var contact: LedgerContact
    let currencyCode: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showingAddEntry = false
    @State private var settlementDraft: SettlementDraft?
    @State private var editingEntry: LedgerEntry?
    @State private var showingRename = false
    @State private var showingDeleteContact = false
    @State private var deletingEntry: LedgerEntry?
    @State private var saveError: String?
    @State private var searchText = ""
    @State private var isSearchExpanded = false
    @FocusState private var isSearchFocused: Bool
    @State private var sortOption: EntrySortOption = .dateDescending
    @State private var directionFilter: EntryDirectionFilter = .all

    private enum EntrySortOption: String, CaseIterable, Identifiable {
        case dateDescending = "Newest first"
        case dateAscending = "Oldest first"
        case amountDescending = "Amount: high to low"
        case amountAscending = "Amount: low to high"
        var id: String { rawValue }
    }

    private enum EntryDirectionFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case iPaid = "I paid"
        case theyPaid = "They paid"
        case settlementsOnly = "Settlements"
        var id: String { rawValue }
    }

    private var displayedEntries: [LedgerEntry] {
        var result = contact.entries
        let query = searchText.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            result = result.filter { $0.note?.localizedCaseInsensitiveContains(query) == true }
        }
        switch directionFilter {
        case .all: break
        case .iPaid: result = result.filter { $0.direction == .iPaid }
        case .theyPaid: result = result.filter { $0.direction == .theyPaid }
        case .settlementsOnly: result = result.filter(\.isSettlement)
        }
        switch sortOption {
        case .dateDescending: result.sort { $0.date > $1.date }
        case .dateAscending: result.sort { $0.date < $1.date }
        case .amountDescending: result.sort { $0.amount > $1.amount }
        case .amountAscending: result.sort { $0.amount < $1.amount }
        }
        return result
    }

    private var net: Decimal { LedgerEngine.netBalance(for: contact.entries) }
    private var settlementSuggestion: (amount: Decimal, direction: LedgerDirection)? {
        LedgerEngine.settlementSuggestion(for: contact.entries)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                personHeading
                    .padding(.bottom, 20)
                if isSearchExpanded { searchField.padding(.bottom, 18) }
                balanceHero
                    .padding(.bottom, 18)
                quickActions
                    .padding(.bottom, 30)
                historySection
            }
            .frame(maxWidth: 720)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 34)
            .frame(maxWidth: .infinity)
        }
        .background(SplitDesign.paper.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: AppTheme.trailingToolbarPlacement) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isSearchExpanded.toggle()
                        if !isSearchExpanded { searchText = "" }
                    }
                    isSearchFocused = isSearchExpanded
                } label: {
                    Image(systemName: isSearchExpanded ? "xmark" : "magnifyingglass")
                }
                .accessibilityLabel(isSearchExpanded ? "Close search" : "Search history")
            }
            ToolbarItem(placement: AppTheme.trailingToolbarPlacement) {
                Menu {
                    Picker("Sort history", selection: $sortOption) {
                        ForEach(EntrySortOption.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                } label: { Image(systemName: "arrow.up.arrow.down") }
                    .accessibilityLabel("Sort history")
            }
            ToolbarItem(placement: AppTheme.trailingToolbarPlacement) {
                Menu {
                    Button { showingRename = true } label: {
                        Label("Rename person", systemImage: "pencil")
                    }
                    Button(role: .destructive) { showingDeleteContact = true } label: {
                        Label("Delete person", systemImage: "trash")
                    }
                } label: { Image(systemName: "ellipsis") }
                    .accessibilityLabel("Person options")
            }
        }
        .sheet(isPresented: $showingAddEntry) {
            LedgerEntryEditorView(contact: contact, currencyCode: currencyCode)
        }
        .sheet(item: $settlementDraft) { draft in
            LedgerEntryEditorView(
                contact: contact,
                currencyCode: currencyCode,
                prefillAmount: draft.amount,
                prefillDirection: draft.direction,
                startsAsSettlement: true
            )
        }
        .sheet(item: $editingEntry) { entry in
            LedgerEntryEditorView(contact: contact, currencyCode: currencyCode, entry: entry)
        }
        .sheet(isPresented: $showingRename) { RenameContactView(contact: contact) }
        .alert("Delete entry?", isPresented: Binding(
            get: { deletingEntry != nil }, set: { if !$0 { deletingEntry = nil } }
        ), presenting: deletingEntry) { entry in
            Button("Delete", role: .destructive) { delete(entry) }
            Button("Cancel", role: .cancel) { deletingEntry = nil }
        } message: { _ in
            Text("This changes the balance and cannot be undone.")
        }
        .alert("Delete \(contact.name)?", isPresented: $showingDeleteContact) {
            Button("Delete", role: .destructive) { deleteContact() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This also deletes the entire history with them. This can't be undone.")
        }
        .alert("Couldn't save", isPresented: Binding(
            get: { saveError != nil }, set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: { Text(saveError ?? "Please try again.") }
    }

    private var personHeading: some View {
        HStack(spacing: 14) {
            SplitAvatar(name: contact.name, colorHex: contact.colorHex, size: 58)
            VStack(alignment: .leading, spacing: 4) {
                Text("BALANCE WITH")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(AppTheme.emberRed)
                Text(contact.name)
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .foregroundStyle(SplitDesign.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search notes", text: $searchText)
                .focused($isSearchFocused)
                .textInputAutocapitalization(.never)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 15)
        .frame(height: 48)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
    }

    private var balanceHero: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("CURRENT BALANCE")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.3)
                    .foregroundStyle(.white.opacity(0.71))
                Spacer()
                Image(systemName: net == 0 ? "checkmark.seal.fill" : "arrow.left.arrow.right")
                    .foregroundStyle(.white.opacity(0.78))
            }
            Text(SplitDesign.money(abs(net), code: currencyCode))
                .font(.system(size: 39, weight: .bold, design: .rounded))
                .tracking(-1)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
                .padding(.top, 6)
            Text(net > 0 ? "\(contact.name) owes you" : net < 0 ? "You owe \(contact.name)" : "All settled up")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.82))
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.heroGradient, in: RoundedRectangle(cornerRadius: 27, style: .continuous))
        .shadow(color: AppTheme.emberRed.opacity(0.2), radius: 18, y: 10)
    }

    private var quickActions: some View {
        HStack(spacing: 10) {
            Button { showingAddEntry = true } label: {
                Label("Add entry", systemImage: "plus")
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
            }
            .buttonStyle(SplitPrimaryButtonStyle())
            .accessibilityIdentifier("split.addEntry")

            if let suggestion = settlementSuggestion {
                Button {
                    settlementDraft = SettlementDraft(amount: suggestion.amount, direction: suggestion.direction)
                } label: {
                    Label("Settle up", systemImage: "checkmark.circle")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.emberRed)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(SplitDesign.card, in: RoundedRectangle(cornerRadius: 17))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("split.settleUp")
            }
        }
    }

    private var historySection: some View {
        let rows = displayedEntries
        return VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .firstTextBaseline) {
                Text("History")
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundStyle(SplitDesign.ink)
                Spacer()
                Text("\(contact.entries.count) entries")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(SplitDesign.muted)
            }

            if !contact.entries.isEmpty { filterChips }

            if contact.entries.isEmpty {
                VStack(alignment: .leading, spacing: 9) {
                    Image(systemName: "text.book.closed")
                        .font(.system(size: 23, weight: .medium))
                        .foregroundStyle(AppTheme.emberRed)
                        .frame(width: 46, height: 46)
                        .background(AppTheme.emberRed.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                    Text("Nothing recorded yet")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SplitDesign.ink)
                    Text("Add what either of you paid to see the balance change here.")
                        .font(.caption)
                        .foregroundStyle(SplitDesign.muted)
                    Button("Add the first entry") { showingAddEntry = true }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.emberRed)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .background(SplitDesign.card, in: RoundedRectangle(cornerRadius: 21))
            } else if rows.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No matching entries")
                        .font(.subheadline.weight(.semibold))
                    Text("Try another note or direction filter.")
                        .font(.caption)
                        .foregroundStyle(SplitDesign.muted)
                    Button("Show all history") {
                        searchText = ""
                        directionFilter = .all
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.emberRed)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .background(SplitDesign.card, in: RoundedRectangle(cornerRadius: 21))
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { entry in
                        if entry.id != rows.first?.id {
                            Rectangle()
                                .fill(Color.black.opacity(0.06))
                                .frame(height: 1)
                                .padding(.leading, 66)
                        }
                        Button { editingEntry = entry } label: {
                            EntryRow(entry: entry, currencyCode: currencyCode)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens entry for editing")
                        .contextMenu {
                            Button { editingEntry = entry } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            Button(role: .destructive) { deletingEntry = entry } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.horizontal, 15)
                .background(SplitDesign.card, in: RoundedRectangle(cornerRadius: 21, style: .continuous))
            }
        }
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(EntryDirectionFilter.allCases) { option in
                    Button { withAnimation(.easeInOut(duration: 0.18)) { directionFilter = option } } label: {
                        Text(option.rawValue)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(directionFilter == option ? .white : SplitDesign.muted)
                            .padding(.horizontal, 13)
                            .frame(height: 40)
                            .background(directionFilter == option ? AppTheme.emberRed : SplitDesign.card, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func delete(_ entry: LedgerEntry) {
        entry.contact?.markActivity()
        modelContext.delete(entry)
        do { try modelContext.save() }
        catch { saveError = error.localizedDescription }
        deletingEntry = nil
    }

    private func deleteContact() {
        modelContext.delete(contact)
        do { try modelContext.save(); dismiss() }
        catch { saveError = error.localizedDescription }
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

    private var directionText: String {
        entry.direction == .iPaid ? "You paid" : "They paid"
    }

    private var amountText: String {
        (entry.direction == .iPaid ? "+" : "−") + SplitDesign.money(entry.amount, code: currencyCode)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entry.isSettlement ? "checkmark" : entry.direction == .iPaid ? "arrow.up.right" : "arrow.down.left")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(entry.direction == .iPaid ? SplitDesign.receive : SplitDesign.pay)
                .frame(width: 42, height: 42)
                .background((entry.direction == .iPaid ? SplitDesign.receive : SplitDesign.pay).opacity(0.1), in: RoundedRectangle(cornerRadius: 13))

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.note?.isEmpty == false ? entry.note! : entry.isSettlement ? "Settlement" : directionText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SplitDesign.ink)
                    .lineLimit(1)
                Text(directionText)
                    .font(.caption2)
                    .foregroundStyle(SplitDesign.muted)
                Text(entry.date.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                    .font(.caption2)
                    .foregroundStyle(SplitDesign.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 3) {
                Text(amountText)
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(SplitDesign.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if entry.isSettlement {
                    Text("SETTLEMENT")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(0.7)
                        .foregroundStyle(AppTheme.emberRed)
                }
            }
        }
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }
}

private struct LedgerEntryEditorView: View {
    let contact: LedgerContact
    let currencyCode: String
    let entry: LedgerEntry?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var amountText: String
    @State private var direction: LedgerDirection
    @State private var note: String
    @State private var date: Date
    @State private var isSettlement: Bool
    @State private var saveError: String?

    init(
        contact: LedgerContact,
        currencyCode: String,
        entry: LedgerEntry? = nil,
        prefillAmount: Decimal? = nil,
        prefillDirection: LedgerDirection? = nil,
        startsAsSettlement: Bool = false
    ) {
        self.contact = contact
        self.currencyCode = currencyCode
        self.entry = entry
        _amountText = State(initialValue: (entry?.amount ?? prefillAmount).map { NSDecimalNumber(decimal: $0).stringValue } ?? "")
        _direction = State(initialValue: entry?.direction ?? prefillDirection ?? .iPaid)
        _note = State(initialValue: entry?.note ?? "")
        _date = State(initialValue: entry?.date ?? .now)
        _isSettlement = State(initialValue: entry?.isSettlement ?? startsAsSettlement)
    }

    private var amount: Decimal? {
        guard let value = Decimal(string: amountText), value > 0 else { return nil }
        return value
    }

    private var projectedBalance: Decimal? {
        guard let amount else { return nil }
        let before = LedgerEngine.netBalance(for: contact.entries) - (entry?.signedAmount ?? 0)
        return before + (direction == .iPaid ? amount : -amount)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    SplitSheetHeader(
                        eyebrow: entry == nil ? (isSettlement ? "Settle a balance" : "New history") : "Update history",
                        title: entry == nil ? (isSettlement ? "Settle up" : "Add an entry") : "Edit entry",
                        message: "Record money that moved between you and \(contact.name).",
                        symbol: isSettlement ? "checkmark.circle" : "arrow.left.arrow.right"
                    )

                    amountCard
                    directionCard
                    balancePreview
                    detailsCard
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
                Button(entry == nil ? (isSettlement ? "Record settlement" : "Add entry") : "Save changes", action: save)
                    .buttonStyle(SplitPrimaryButtonStyle())
                    .disabled(amount == nil)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.regularMaterial)
            }
            .alert("Couldn't save entry", isPresented: Binding(
                get: { saveError != nil }, set: { if !$0 { saveError = nil } }
            )) {
                Button("OK", role: .cancel) { saveError = nil }
            } message: { Text(saveError ?? "Please try again.") }
        }
    }

    private var amountCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            fieldLabel("AMOUNT")
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text(currencyCode)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.emberRed)
                TextField("0.00", text: $amountText)
                    .font(.system(size: 31, weight: .bold, design: .rounded))
                    .keyboardType(.decimalPad)
                    .foregroundStyle(SplitDesign.ink)
                    .accessibilityLabel("Amount")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SplitDesign.card, in: RoundedRectangle(cornerRadius: 20))
    }

    private var directionCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            fieldLabel("WHO PAID?")
            HStack(spacing: 9) {
                directionChoice(.iPaid, title: "I paid", symbol: "arrow.up.right")
                directionChoice(.theyPaid, title: "They paid", symbol: "arrow.down.left")
            }
            Text(direction == .iPaid
                 ? "Money went from you to \(contact.name)."
                 : "Money came from \(contact.name) to you.")
                .font(.caption)
                .foregroundStyle(SplitDesign.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SplitDesign.card, in: RoundedRectangle(cornerRadius: 20))
    }

    private func directionChoice(_ value: LedgerDirection, title: String, symbol: String) -> some View {
        Button { direction = value } label: {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                Text(title)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(direction == value ? .white : SplitDesign.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 43)
            .background(direction == value ? AppTheme.emberRed : SplitDesign.paper, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(direction == value ? .isSelected : [])
    }

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("WHAT FOR?")
                TextField("Borrowed cash, dinner, shopping…", text: $note)
                    .font(.subheadline)
                    .textInputAutocapitalization(.sentences)
            }
            Rectangle().fill(Color.black.opacity(0.07)).frame(height: 1)
            DatePicker("WHEN", selection: $date, displayedComponents: [.date, .hourAndMinute])
                .font(.subheadline.weight(.medium))
            Rectangle().fill(Color.black.opacity(0.07)).frame(height: 1)
            Toggle("Mark as a settlement", isOn: $isSettlement)
                .font(.subheadline.weight(.medium))
                .tint(AppTheme.emberRed)
        }
        .padding(18)
        .background(SplitDesign.card, in: RoundedRectangle(cornerRadius: 20))
    }

    private var balancePreview: some View {
        VStack(alignment: .leading, spacing: 5) {
            fieldLabel("BALANCE AFTER THIS ENTRY")
            if let projectedBalance {
                Text(SplitDesign.money(abs(projectedBalance), code: currencyCode))
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .foregroundStyle(SplitDesign.ink)
                Text(SplitDesign.balanceDescription(projectedBalance, name: contact.name))
                    .font(.caption)
                    .foregroundStyle(projectedBalance > 0 ? SplitDesign.receive : projectedBalance < 0 ? SplitDesign.pay : SplitDesign.muted)
            } else {
                Text("Enter an amount to preview the balance.")
                    .font(.subheadline)
                    .foregroundStyle(SplitDesign.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(AppTheme.emberRed.opacity(0.07), in: RoundedRectangle(cornerRadius: 20))
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .tracking(1.1)
            .foregroundStyle(SplitDesign.muted)
    }

    private func save() {
        guard let amount else { return }
        if let entry {
            entry.amount = amount
            entry.direction = direction
            entry.note = note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note.trimmingCharacters(in: .whitespacesAndNewlines)
            entry.date = date
            entry.isSettlement = isSettlement
        } else {
            let newEntry = LedgerEntry(
                amount: amount,
                direction: direction,
                note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note.trimmingCharacters(in: .whitespacesAndNewlines),
                date: date,
                isSettlement: isSettlement,
                contact: contact
            )
            modelContext.insert(newEntry)
        }
        contact.markActivity()
        do { try modelContext.save(); dismiss() }
        catch { saveError = error.localizedDescription }
    }
}

struct RenameContactView: View {
    @Bindable var contact: LedgerContact

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var saveError: String?

    init(contact: LedgerContact) {
        self.contact = contact
        _name = State(initialValue: contact.name)
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    SplitSheetHeader(
                        eyebrow: "Person details",
                        title: "Rename person",
                        message: "The balance and history stay with this person.",
                        symbol: "pencil"
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
                Button("Save name", action: save)
                    .buttonStyle(SplitPrimaryButtonStyle())
                    .disabled(trimmedName.isEmpty)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.regularMaterial)
            }
            .alert("Couldn't rename person", isPresented: Binding(
                get: { saveError != nil }, set: { if !$0 { saveError = nil } }
            )) {
                Button("OK", role: .cancel) { saveError = nil }
            } message: { Text(saveError ?? "Please try again.") }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        contact.name = trimmedName
        do { try modelContext.save(); dismiss() }
        catch { saveError = error.localizedDescription }
    }
}
