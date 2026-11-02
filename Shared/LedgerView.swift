import SwiftUI
import SwiftData
import MoneyIQCore

/// Shared balances stay separate from the personal expense budget.
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
    @State private var isSearchExpanded = false
    @FocusState private var isSearchFocused: Bool
    @State private var sortOption: ContactSortOption = .recentlyUpdated
    @State private var balanceFilter: BalanceFilter = .all

    private enum ContactSortOption: String, CaseIterable, Identifiable {
        case recentlyUpdated = "Recently updated"
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
        case settled = "Settled"

        var id: String { rawValue }
    }

    private var currencyCode: String {
        authManager.currentAccount?.preferredCurrencyCode ?? "USD"
    }

    private var displayedContacts: [LedgerContact] {
        var result = contacts
        let query = searchText.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            result = result.filter { $0.name.localizedCaseInsensitiveContains(query) }
        }
        if balanceFilter != .all {
            result = result.filter { contact in
                switch (balanceFilter, LedgerEngine.balanceState(for: contact.entries)) {
                case (.theyOweYou, .theyOweYou), (.youOweThem, .youOweThem), (.settled, .settled): true
                default: false
                }
            }
        }
        switch sortOption {
        case .recentlyUpdated:
            result.sort { LedgerEngine.lastActivity(for: $0) > LedgerEngine.lastActivity(for: $1) }
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

    private var overallSummary: (owedToYou: Decimal, youOwe: Decimal) {
        var owedToYou = Decimal(0)
        var youOwe = Decimal(0)
        for contact in contacts {
            let net = LedgerEngine.netBalance(for: contact.entries)
            if net > 0 { owedToYou += net }
            if net < 0 { youOwe -= net }
        }
        return (owedToYou, youOwe)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    heading
                        .padding(.bottom, 21)
                    if isSearchExpanded { searchField.padding(.bottom, 18) }
                    if !contacts.isEmpty {
                        summaryHeader
                            .padding(.bottom, 24)
                    }
                    quickActions
                        .padding(.bottom, 29)
                    peopleSection
                }
                .frame(maxWidth: 720)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity)
            }
            .background(SplitDesign.paper.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text("M")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(AppTheme.accentText)
                        .accessibilityLabel("MoneyIQ Split")
                }
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
                    .accessibilityLabel(isSearchExpanded ? "Close search" : "Search people")
                }
                ToolbarItem(placement: AppTheme.trailingToolbarPlacement) {
                    Menu {
                        Picker("Sort people", selection: $sortOption) {
                            ForEach(ContactSortOption.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    .accessibilityLabel("Sort people")
                }
                ToolbarItem(placement: AppTheme.trailingToolbarPlacement) {
                    ProfileMenuButton(authManager: authManager, settings: settings, notifications: notifications, lockManager: lockManager)
                }
            }
            .sheet(isPresented: $showingAddContact) { AddContactView() }
            .sheet(isPresented: $showingSplitBill) { SplitBillView(currencyCode: currencyCode) }
            .sheet(item: $renamingContact) { contact in RenameContactView(contact: contact) }
            .alert(
                "Delete \(contactsPendingDelete?.count == 1 ? (contactsPendingDelete?.first?.name ?? "Person") : "\(contactsPendingDelete?.count ?? 0) People")?",
                isPresented: Binding(
                    get: { contactsPendingDelete != nil },
                    set: { if !$0 { contactsPendingDelete = nil } }
                )
            ) {
                Button("Delete", role: .destructive) {
                    for contact in contactsPendingDelete ?? [] { deleteContact(contact) }
                    contactsPendingDelete = nil
                }
                Button("Cancel", role: .cancel) { contactsPendingDelete = nil }
            } message: {
                Text("This also deletes the entire history with them. This can't be undone.")
            }
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("SHARED MONEY")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(1.4)
                .foregroundStyle(AppTheme.accentText)
            Text("Split")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .tracking(-0.9)
                .foregroundStyle(SplitDesign.ink)
            Text("Every balance, person by person.")
                .font(.subheadline)
                .foregroundStyle(SplitDesign.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search people", text: $searchText)
                .focused($isSearchFocused)
                .textInputAutocapitalization(.never)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 15)
        .frame(height: 48)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private var summaryHeader: some View {
        let summary = overallSummary
        let net = summary.owedToYou - summary.youOwe
        return VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("OPEN BALANCES")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.3)
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.83))
            }

            HStack(alignment: .top, spacing: 12) {
                summaryAmount("YOU'LL RECEIVE", amount: summary.owedToYou)
                Rectangle()
                    .fill(.white.opacity(0.19))
                    .frame(width: 1, height: 55)
                summaryAmount("YOU OWE", amount: summary.youOwe)
            }

            Text(net == 0 ? "Balances are even overall" : net > 0
                 ? "Net \(SplitDesign.money(net, code: currencyCode)) to receive"
                 : "Net \(SplitDesign.money(-net, code: currencyCode)) to pay")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.82))
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.heroGradient, in: RoundedRectangle(cornerRadius: 27, style: .continuous))
        .shadow(color: AppTheme.emberRed.opacity(0.2), radius: 18, y: 10)
    }

    private func summaryAmount(_ title: String, amount: Decimal) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.69))
            Text(SplitDesign.money(amount, code: currencyCode))
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var quickActions: some View {
        HStack(spacing: 11) {
            Button { showingAddContact = true } label: {
                actionContent("Add person", subtitle: "Start a balance", symbol: "person.badge.plus", filled: true)
            }
            .accessibilityIdentifier("split.addPerson")
            Button { showingSplitBill = true } label: {
                actionContent("Split a bill", subtitle: "Share a payment", symbol: "person.3.fill", filled: false)
            }
            .accessibilityIdentifier("split.splitBill")
        }
        .buttonStyle(SplitTileButtonStyle())
    }

    private func actionContent(_ title: String, subtitle: String, symbol: String, filled: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 36, height: 36)
                .background(filled ? .white.opacity(0.17) : AppTheme.emberRed.opacity(0.1), in: RoundedRectangle(cornerRadius: 11))
            Spacer(minLength: 8)
            Text(title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(filled ? .white.opacity(0.77) : SplitDesign.muted)
                .lineLimit(1)
                .padding(.top, 2)
        }
        .foregroundStyle(filled ? .white : SplitDesign.ink)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .padding(15)
        .background(filled ? AppTheme.emberRed : SplitDesign.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var peopleSection: some View {
        let rows = displayedContacts
        return VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .firstTextBaseline) {
                Text("People")
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundStyle(SplitDesign.ink)
                Spacer()
                Text("\(contacts.count) total")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(SplitDesign.muted)
            }

            if !contacts.isEmpty { filterChips }

            if contacts.isEmpty {
                emptyState
            } else if rows.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No matching people")
                        .font(.subheadline.weight(.semibold))
                    Text("Try another search or balance filter.")
                        .font(.caption)
                        .foregroundStyle(SplitDesign.muted)
                    Button("Show everyone") {
                        searchText = ""
                        balanceFilter = .all
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.accentText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .background(SplitDesign.card, in: RoundedRectangle(cornerRadius: 21))
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { contact in
                        if contact.id != rows.first?.id {
                            Rectangle()
                                .fill(AppTheme.separator)
                                .frame(height: 1)
                                .padding(.leading, 74)
                        }
                        NavigationLink {
                            LedgerContactDetailView(contact: contact, currencyCode: currencyCode)
                        } label: {
                            ContactRow(contact: contact, currencyCode: currencyCode)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button { renamingContact = contact } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            Button(role: .destructive) { contactsPendingDelete = [contact] } label: {
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
                ForEach(BalanceFilter.allCases) { option in
                    Button { withAnimation(.easeInOut(duration: 0.18)) { balanceFilter = option } } label: {
                        Text(option.rawValue)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(balanceFilter == option ? .white : SplitDesign.muted)
                            .padding(.horizontal, 13)
                            .frame(height: 40)
                            .background(balanceFilter == option ? AppTheme.emberRed : SplitDesign.card, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .contentMargins(.trailing, 3)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: "person.2.crop.square.stack")
                .font(.system(size: 23, weight: .medium))
                .foregroundStyle(AppTheme.accentText)
                .frame(width: 46, height: 46)
                .background(AppTheme.emberRed.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
            Text("No shared balances yet")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SplitDesign.ink)
            Text("Add a person to track money you pay for each other. Split bills and settlements will appear here.")
                .font(.caption)
                .foregroundStyle(SplitDesign.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(SplitDesign.card, in: RoundedRectangle(cornerRadius: 21))
    }

    private func deleteContact(_ contact: LedgerContact) {
        modelContext.delete(contact)
        do { try modelContext.save() }
        catch { print("MoneyIQ: failed to delete contact: \(error)") }
    }
}

private struct SplitTileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

private struct ContactRow: View {
    let contact: LedgerContact
    let currencyCode: String

    private var net: Decimal { LedgerEngine.netBalance(for: contact.entries) }

    var body: some View {
        HStack(spacing: 12) {
            SplitAvatar(name: contact.name, colorHex: contact.colorHex, size: 45)
            VStack(alignment: .leading, spacing: 4) {
                Text(contact.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SplitDesign.ink)
                    .lineLimit(1)
                Text(net > 0 ? "Owes you" : net < 0 ? "You owe" : "Settled up")
                    .font(.caption)
                    .foregroundStyle(net > 0 ? SplitDesign.receive : net < 0 ? SplitDesign.pay : SplitDesign.muted)
            }
            Spacer(minLength: 6)
            if net == 0 {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(SplitDesign.receive)
            } else {
                Text(SplitDesign.money(abs(net), code: currencyCode))
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(SplitDesign.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 13)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(net == 0 ? "\(contact.name), settled up"
            : net > 0 ? "\(contact.name) owes you \(SplitDesign.money(net, code: currencyCode))"
            : "You owe \(contact.name) \(SplitDesign.money(-net, code: currencyCode))")
    }
}

private struct AddContactView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var saveError: String?
    @FocusState private var nameFocused: Bool

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    SplitSheetHeader(
                        eyebrow: "New balance",
                        title: "Add a person",
                        message: "Keep what you pay for each other in one clear history.",
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
                            .focused($nameFocused)
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
        modelContext.insert(LedgerContact(name: trimmedName))
        do { try modelContext.save(); dismiss() }
        catch { saveError = error.localizedDescription }
    }
}
