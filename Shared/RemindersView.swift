import SwiftUI
import SwiftData
import MoneyIQCore

struct RemindersView: View {
    let authManager: AuthManager
    @Bindable var notifications: NotificationScheduler

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ReminderItem.time) private var reminders: [ReminderItem]
    @Query(sort: \ExpenseTransaction.date) private var transactions: [ExpenseTransaction]

    @State private var showingAddReminder = false
    @State private var prefill: ReminderDraft?
    @State private var permissionDeniedAlert = false

    private var currencyCode: String {
        authManager.currentAccount?.preferredCurrencyCode ?? "USD"
    }

    /// Detected recurring subscriptions (Phase 4, built on Phase 3's
    /// merchant tracking) that don't already have a reminder — "benefits
    /// from Auto-Detect Bills for suggesting reminders" per the PRD.
    private var suggestions: [InsightsEngine.SubscriptionCandidate] {
        let existingTitles = Set(reminders.map { $0.title.lowercased() })
        return InsightsEngine.recurringSubscriptions(in: transactions)
            .filter { !existingTitles.contains($0.merchantName.lowercased()) }
    }

    var body: some View {
        List {
            if !suggestions.isEmpty {
                Section {
                    ForEach(suggestions) { suggestion in
                        Button {
                            prefill = ReminderDraft(
                                title: suggestion.merchantName,
                                amount: suggestion.averageAmount,
                                frequency: .monthly,
                                time: suggestion.expectedNextDate
                            )
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(suggestion.merchantName)
                                        .foregroundStyle(.primary)
                                    Text("Repeats ~monthly, expected \(suggestion.expectedNextDate.formatted(.dateTime.month().day()))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                } header: {
                    Text("Suggested")
                } footer: {
                    Text("Detected from your recurring transactions.")
                }
            }

            Section {
                if reminders.isEmpty {
                    Text("No reminders yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(reminders) { reminder in
                    ReminderRow(
                        reminder: reminder,
                        currencyCode: currencyCode,
                        onToggle: { toggle(reminder) }
                    )
                }
                .onDelete(perform: delete)
            } header: {
                Text("Your Reminders")
            }
        }
        .navigationTitle("Reminders")
        .compactListLayout()
        .toolbar {
            ToolbarItem {
                Button {
                    prefill = ReminderDraft()
                } label: {
                    Label("Add Reminder", systemImage: "plus")
                }
            }
        }
        .sheet(item: $prefill) { draft in
            AddReminderView(draft: draft, onSave: save)
        }
        .alert("Notifications are off", isPresented: $permissionDeniedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Turn on notifications for MoneyIQ in Settings to get reminder alerts.")
        }
    }

    private func toggle(_ reminder: ReminderItem) {
        Task {
            if reminder.isEnabled {
                reminder.isEnabled = false
                notifications.cancelReminder(reminder)
                try? modelContext.save()
            } else {
                let granted = await notifications.requestPermissionIfNeeded()
                guard granted else {
                    permissionDeniedAlert = true
                    return
                }
                reminder.isEnabled = true
                try? modelContext.save()
                notifications.scheduleReminder(reminder, currencyCode: currencyCode)
            }
        }
    }

    private func save(_ draft: ReminderDraft) {
        Task {
            let granted = await notifications.requestPermissionIfNeeded()
            let reminder = ReminderItem(
                title: draft.title,
                amount: draft.amount,
                frequency: draft.frequency,
                time: draft.time,
                isEnabled: granted
            )
            modelContext.insert(reminder)
            try? modelContext.save()
            if granted {
                notifications.scheduleReminder(reminder, currencyCode: currencyCode)
            } else {
                permissionDeniedAlert = true
            }
            prefill = nil
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            let reminder = reminders[index]
            notifications.cancelReminder(reminder)
            modelContext.delete(reminder)
        }
        try? modelContext.save()
    }
}

private struct ReminderRow: View {
    let reminder: ReminderItem
    let currencyCode: String
    let onToggle: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(reminder.title)
                HStack(spacing: 6) {
                    Text(frequencyLabel)
                    if let amount = reminder.amount {
                        Text("·").foregroundStyle(.tertiary)
                        Text(amount, format: .currency(code: currencyCode))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { reminder.isEnabled }, set: { _ in onToggle() }))
                .labelsHidden()
        }
    }

    private var frequencyLabel: String {
        switch reminder.frequency {
        case .once: reminder.time.formatted(.dateTime.month().day().year())
        case .daily: "Daily at \(reminder.time.formatted(.dateTime.hour().minute()))"
        case .weekly: "Weekly, \(reminder.time.formatted(.dateTime.weekday(.wide))) at \(reminder.time.formatted(.dateTime.hour().minute()))"
        case .monthly: "Monthly on the \(reminder.time.formatted(.dateTime.day()))"
        }
    }
}

/// A pending new/prefilled reminder, driving the add sheet — `Identifiable`
/// so `.sheet(item:)` can key off it and `showingAddReminder`-style boolean
/// juggling isn't needed for both the "+" button and suggestion taps.
private struct ReminderDraft: Identifiable {
    let id = UUID()
    var title: String = ""
    var amount: Decimal?
    var frequency: ReminderFrequency = .monthly
    var time: Date = .now
}

private struct AddReminderView: View {
    let draft: ReminderDraft
    let onSave: (ReminderDraft) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var amountText: String
    @State private var frequency: ReminderFrequency
    @State private var time: Date

    init(draft: ReminderDraft, onSave: @escaping (ReminderDraft) -> Void) {
        self.draft = draft
        self.onSave = onSave
        _title = State(initialValue: draft.title)
        _amountText = State(initialValue: draft.amount.map { "\($0)" } ?? "")
        _frequency = State(initialValue: draft.frequency)
        _time = State(initialValue: draft.time)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title (e.g. Rent)", text: $title)
                HStack {
                    Text("Amount (optional)")
                    Spacer()
                    TextField("0.00", text: $amountText)
                        .multilineTextAlignment(.trailing)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                }
                Picker("Repeats", selection: $frequency) {
                    Text("Once").tag(ReminderFrequency.once)
                    Text("Daily").tag(ReminderFrequency.daily)
                    Text("Weekly").tag(ReminderFrequency.weekly)
                    Text("Monthly").tag(ReminderFrequency.monthly)
                }
                DatePicker(
                    frequency == .daily ? "Time" : "Date & Time",
                    selection: $time,
                    displayedComponents: frequency == .daily ? [.hourAndMinute] : [.date, .hourAndMinute]
                )
            }
            .navigationTitle("New Reminder")
            .compactFormLayout()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(ReminderDraft(title: title, amount: Decimal(string: amountText), frequency: frequency, time: time))
                    }
                    .disabled(title.isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
