import SwiftUI
import SwiftData
import MoneyIQCore

struct NetWorthView: View {
    let authManager: AuthManager

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \NetWorthAccount.createdAt) private var accounts: [NetWorthAccount]

    @State private var showingAddAccount = false

    private var currencyCode: String {
        authManager.currentAccount?.preferredCurrencyCode ?? "USD"
    }

    private var netWorth: Decimal {
        accounts.reduce(Decimal(0)) { $0 + $1.signedBalance }
    }

    private var assets: [NetWorthAccount] { accounts.filter { $0.kind == .asset } }
    private var liabilities: [NetWorthAccount] { accounts.filter { $0.kind == .liability } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Net Worth")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.8))
                        Text(netWorth, format: .currency(code: currencyCode))
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(AppTheme.Spacing.large)
                    .background(AppTheme.heroGradient, in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .padding(.vertical, AppTheme.Spacing.small)
                }

                if !assets.isEmpty {
                    Section("Assets") {
                        ForEach(assets) { account in
                            accountRow(account)
                        }
                        .onDelete { delete(assets, at: $0) }
                    }
                }

                if !liabilities.isEmpty {
                    Section("Liabilities") {
                        ForEach(liabilities) { account in
                            accountRow(account)
                        }
                        .onDelete { delete(liabilities, at: $0) }
                    }
                }

                if accounts.isEmpty {
                    ContentUnavailableIfNeeded()
                }
            }
            .navigationTitle("Net Worth")
            .compactListLayout()
            .toolbar {
                ToolbarItem {
                    Button {
                        showingAddAccount = true
                    } label: {
                        Label("Add Account", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddAccount) {
                AddNetWorthAccountView()
            }
        }
    }

    private func accountRow(_ account: NetWorthAccount) -> some View {
        HStack(spacing: 12) {
            IconBubble(
                systemName: account.systemIconName,
                tint: account.kind == .liability ? .red : AppTheme.accent,
                diameter: 34
            )
            Text(account.name)
            Spacer()
            Text(account.balance, format: .currency(code: account.currencyCode))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, AppTheme.Spacing.small)
    }

    private func delete(_ group: [NetWorthAccount], at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(group[index])
        }
        try? modelContext.save()
    }
}

private struct ContentUnavailableIfNeeded: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.pie")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("No accounts yet")
                .font(.headline)
            Text("Add a bank account, investment, or loan to start tracking your net worth.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .listRowBackground(Color.clear)
    }
}

private struct AddNetWorthAccountView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var kind: NetWorthAccountKind = .asset
    @State private var balanceText = ""
    @State private var icon = "banknote"

    private let iconChoices = ["banknote", "building.columns", "chart.line.uptrend.xyaxis", "house", "car", "creditcard"]

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name (e.g. Savings Account)", text: $name)
                Picker("Type", selection: $kind) {
                    Text("Asset").tag(NetWorthAccountKind.asset)
                    Text("Liability").tag(NetWorthAccountKind.liability)
                }
                .pickerStyle(.segmented)
                HStack {
                    Text("Balance")
                    Spacer()
                    TextField("0.00", text: $balanceText)
                        .multilineTextAlignment(.trailing)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                }
                Picker("Icon", selection: $icon) {
                    ForEach(iconChoices, id: \.self) { name in
                        Label(name, systemImage: name).tag(name)
                    }
                }
            }
            .navigationTitle("New Account")
            .compactFormLayout()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.isEmpty || Decimal(string: balanceText) == nil)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func save() {
        guard let balance = Decimal(string: balanceText) else { return }
        let account = NetWorthAccount(name: name, kind: kind, balance: balance, systemIconName: icon)
        modelContext.insert(account)
        try? modelContext.save()
        dismiss()
    }
}
