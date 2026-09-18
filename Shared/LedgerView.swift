import SwiftUI
import SwiftData
import MoneyIQCore

/// Person-to-person IOU tracking — "me and my friend paying each other's
/// bills." Separate from your own budget/net worth: this is money that
/// moves between you and someone else, not your own spending.
struct LedgerView: View {
    let authManager: AuthManager

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LedgerContact.createdAt, order: .reverse) private var contacts: [LedgerContact]

    @State private var showingAddContact = false

    private var currencyCode: String {
        authManager.currentAccount?.preferredCurrencyCode ?? "USD"
    }

    var body: some View {
        NavigationStack {
            List {
                if contacts.isEmpty {
                    emptyState
                } else {
                    ForEach(contacts) { contact in
                        NavigationLink {
                            LedgerContactDetailView(contact: contact, currencyCode: currencyCode)
                        } label: {
                            ContactRow(contact: contact, currencyCode: currencyCode)
                        }
                    }
                    .onDelete(perform: delete)
                }
            }
            .navigationTitle("Split")
            .toolbar {
                ToolbarItem {
                    Button {
                        showingAddContact = true
                    } label: {
                        Label("Add Person", systemImage: "person.badge.plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddContact) {
                AddContactView()
            }
        }
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

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(contacts[index])
        }
        try? modelContext.save()
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
                .frame(width: 40, height: 40)
                .overlay {
                    Text(initials)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(contact.name).font(.subheadline.weight(.medium))
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(statusColor)
            }
            Spacer()
        }
        .padding(.vertical, 4)
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
