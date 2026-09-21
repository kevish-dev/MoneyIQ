import SwiftUI
import SwiftData
import MoneyIQCore

/// Person-to-person IOU tracking — "me and my friend paying each other's
/// bills." Separate from your own budget/net worth: this is money that
/// moves between you and someone else, not your own spending.
struct LedgerView: View {
    let authManager: AuthManager
    let settings: AppSettingsStore
    let notifications: NotificationScheduler
    let lockManager: AppLockManager

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LedgerContact.createdAt, order: .reverse) private var contacts: [LedgerContact]

    @State private var showingAddContact = false
    @State private var showingSplitBill = false
    @State private var renamingContact: LedgerContact?
    @State private var contactsPendingDelete: [LedgerContact]?
    @State private var searchText = ""
    @State private var sortOption: ContactSortOption = .recentlyAdded
    @State private var balanceFilter: BalanceFilter = .all

    private enum ContactSortOption: String, CaseIterable, Identifiable {
        case recentlyAdded = "Recently added"
        case nameAscending = "Name: A to Z"
        case nameDescending = "Name: Z to A"
        case balanceDescending = "Balance: owed to you first"
        case balanceAscending = "Balance: you owe first"

        var id: String { rawValue }
    }

    private enum BalanceFilter: String, CaseIterable, Identifiable {
        case all = "Everyone"
        case theyOweYou = "Owes you"
        case youOweThem = "You owe"
        case settled = "Settled up"

        var id: String { rawValue }
    }

    private var currencyCode: String {
        authManager.currentAccount?.preferredCurrencyCode ?? "USD"
    }

    /// `contacts` filtered by search text/balance state, then sorted per
    /// `sortOption`.
    private var displayedContacts: [LedgerContact] {
        var result = contacts

        let query = searchText.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            result = result.filter { $0.name.localizedCaseInsensitiveContains(query) }
        }

        if balanceFilter != .all {
            result = result.filter { contact in
                switch (balanceFilter, LedgerEngine.balanceState(for: contact.entries)) {
                case (.theyOweYou, .theyOweYou): true
                case (.youOweThem, .youOweThem): true
                case (.settled, .settled): true
                default: false
                }
            }
        }

        switch sortOption {
        case .recentlyAdded:
            result.sort { $0.createdAt > $1.createdAt }
        case .nameAscending:
            result.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .nameDescending:
            result.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedDescending }
        case .balanceDescending:
            result.sort { LedgerEngine.netBalance(for: $0.entries) > LedgerEngine.netBalance(for: $1.entries) }
        case .balanceAscending:
            result.sort { LedgerEngine.netBalance(for: $0.entries) < LedgerEngine.netBalance(for: $1.entries) }
        }
        return result
    }

    private var isFiltering: Bool { balanceFilter != .all }

    private var overallSummary: (owedToYou: Decimal, youOwe: Decimal) {
        var owedToYou = Decimal(0)
        var youOwe = Decimal(0)
        for contact in contacts {
            let net = LedgerEngine.netBalance(for: contact.entries)
            if net > 0 {
                owedToYou += net
            } else if net < 0 {
                youOwe += -net
            }
        }
        return (owedToYou, youOwe)
    }

    var body: some View {
        NavigationStack {
            List {
                if contacts.isEmpty {
                    emptyState
                } else {
                    summaryHeader
                        .listRowInsets(EdgeInsets(
                            top: AppTheme.Spacing.small,
                            leading: AppTheme.Spacing.large,
                            bottom: AppTheme.Spacing.small,
                            trailing: AppTheme.Spacing.large
                        ))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)

                    Section("People") {
                        if displayedContacts.isEmpty {
                            Text("No one matches your search/filters.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(displayedContacts) { contact in
                            NavigationLink {
                                LedgerContactDetailView(contact: contact, currencyCode: currencyCode)
                            } label: {
                                ContactRow(contact: contact, currencyCode: currencyCode)
                            }
                            .contextMenu {
                                Button {
                                    renamingContact = contact
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    contactsPendingDelete = [contact]
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                        .onDelete { offsets in
                            contactsPendingDelete = offsets.map { displayedContacts[$0] }
                        }
                    }
                }
            }
            .navigationTitle("Split")
            .compactListLayout()
            .searchable(text: $searchText, prompt: "Search people")
            .toolbar {
                ToolbarItem(placement: AppTheme.trailingToolbarPlacement) {
                    ProfileMenuButton(authManager: authManager, settings: settings, notifications: notifications, lockManager: lockManager)
                }
                ToolbarItem(placement: AppTheme.trailingToolbarPlacement) {
                    Menu {
                        Picker("Sort", selection: $sortOption) {
                            ForEach(ContactSortOption.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        Picker("Filter", selection: $balanceFilter) {
                            ForEach(BalanceFilter.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                    } label: {
                        Image(systemName: isFiltering
                            ? "line.3.horizontal.decrease.circle.fill"
                            : "line.3.horizontal.decrease.circle")
                    }
                }
                ToolbarItem {
                    Menu {
                        Button {
                            showingAddContact = true
                        } label: {
                            Label("Add Person", systemImage: "person.badge.plus")
                        }
                        Button {
                            showingSplitBill = true
                        } label: {
                            Label("Split a Bill", systemImage: "person.3.sequence")
                        }
                        .disabled(contacts.isEmpty)
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddContact) {
                AddContactView()
            }
            .sheet(isPresented: $showingSplitBill) {
                SplitBillView(currencyCode: currencyCode)
            }
            .sheet(item: $renamingContact) { contact in
                RenameContactView(contact: contact)
            }
            .alert(
                "Delete \(contactsPendingDelete?.count == 1 ? (contactsPendingDelete?.first?.name ?? "Person") : "\(contactsPendingDelete?.count ?? 0) People")?",
                isPresented: Binding(
                    get: { contactsPendingDelete != nil },
                    set: { if !$0 { contactsPendingDelete = nil } }
                )
            ) {
                Button("Delete", role: .destructive) {
                    for contact in contactsPendingDelete ?? [] {
                        deleteContact(contact)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This also deletes their entire transaction history with you. This can't be undone.")
            }
        }
    }

    private var summaryHeader: some View {
        let net = overallSummary.owedToYou - overallSummary.youOwe
        return VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            Text(net >= 0 ? "Overall, you're owed" : "Overall, you owe")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.75))
            Text(abs(net), format: .currency(code: currencyCode))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            HStack(spacing: AppTheme.Spacing.medium) {
                summaryChip(label: "Owed to you", amount: overallSummary.owedToYou, tint: .green)
                summaryChip(label: "You owe", amount: overallSummary.youOwe, tint: .red)
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
        .background(AppTheme.pillBackgroundOnHero, in: Capsule())
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.2")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("No one here yet")
                .font(.headline)
            Text("Add a friend to start tracking who owes who — borrowed cash, paying for each other's stuff, and settling up.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .listRowBackground(Color.clear)
    }

    private func deleteContact(_ contact: LedgerContact) {
        modelContext.delete(contact)
        do {
            try modelContext.save()
        } catch {
            print("MoneyIQ: failed to delete contact: \(error)")
        }
    }
}

private struct ContactRow: View {
    let contact: LedgerContact
    let currencyCode: String

    private var state: LedgerEngine.BalanceState {
        LedgerEngine.balanceState(for: contact.entries)
    }

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(hex: contact.colorHex))
                .frame(width: 44, height: 44)
                .overlay {
                    Text(initials)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .shadow(color: Color(hex: contact.colorHex).opacity(0.35), radius: 6, y: 3)

            VStack(alignment: .leading, spacing: 2) {
                Text(contact.name).font(.subheadline.weight(.medium))
                HStack(spacing: 4) {
                    Circle().fill(statusColor).frame(width: 6, height: 6)
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(statusColor)
                }
            }
            Spacer()
        }
        .padding(.vertical, AppTheme.Spacing.xs)
    }

    private var initials: String {
        let parts = contact.name.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }

    private var statusText: String {
        switch state {
        case .theyOweYou(let amount): "Owes you \(amount.formatted(.currency(code: currencyCode)))"
        case .youOweThem(let amount): "You owe \(amount.formatted(.currency(code: currencyCode)))"
        case .settled: "Settled up"
        }
    }

    private var statusColor: Color {
        switch state {
        case .theyOweYou: .green
        case .youOweThem: .red
        case .settled: .secondary
        }
    }
}

private struct AddContactView: View {
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
                        let contact = LedgerContact(name: name)
                        modelContext.insert(contact)
                        try? modelContext.save()
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

extension Color {
    init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
