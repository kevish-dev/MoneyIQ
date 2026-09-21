import Testing
import Foundation
import SwiftData
@testable import MoneyIQCore

@MainActor
struct BackupManagerTests {
    @Test func exportThenRestoreRoundTripsEveryEntity() throws {
        let sourceContainer = PersistenceController.makeContainer(inMemory: true)
        let sourceContext = sourceContainer.mainContext

        let category = ExpenseCategory(name: "Food", systemIconName: "fork.knife", isDefault: true)
        sourceContext.insert(category)

        let account = UserAccount(firstName: "Ada", lastName: "Lovelace", email: "ada@example.com")
        sourceContext.insert(account)

        let identity = LinkedIdentity(provider: .google, providerUserID: "g-1", email: "ada@example.com")
        identity.account = account
        sourceContext.insert(identity)

        let transaction = ExpenseTransaction(amount: 499, note: "Lunch", merchantName: "Cafe", category: category)
        sourceContext.insert(transaction)

        let budget = Budget(monthlyCapAmount: 20000, currencyCode: "INR")
        sourceContext.insert(budget)

        let reminder = ReminderItem(title: "Rent", amount: 15000)
        sourceContext.insert(reminder)

        MerchantCategoryMapping.remember(merchant: "Cafe", category: category, context: sourceContext)

        let netWorthAccount = NetWorthAccount(name: "Savings", kind: .asset, balance: 50000)
        sourceContext.insert(netWorthAccount)

        let goal = SavingsGoal(name: "Trip", targetAmount: 100000, targetDate: .now)
        sourceContext.insert(goal)
        let contribution = SavingsContribution(amount: 5000, goal: goal)
        sourceContext.insert(contribution)

        let contact = LedgerContact(name: "Sam")
        sourceContext.insert(contact)
        let entry = LedgerEntry(amount: 500, direction: .iPaid, note: "Dinner split", contact: contact)
        sourceContext.insert(entry)

        try sourceContext.save()

        let data = try BackupManager.exportData(context: sourceContext)

        let destinationContainer = PersistenceController.makeContainer(inMemory: true)
        let destinationContext = destinationContainer.mainContext
        // Pre-existing data in the destination store should be wiped by the
        // restore, exactly like restoring onto a real device that already
        // has (different) data on it.
        destinationContext.insert(ExpenseCategory(name: "Stale", isDefault: false))
        try destinationContext.save()

        let payload = try BackupManager.restore(from: data, context: destinationContext)
        #expect(payload.totalRecordCount == 12)

        let restoredCategories = try destinationContext.fetch(FetchDescriptor<ExpenseCategory>())
        #expect(restoredCategories.count == 1)
        #expect(restoredCategories.first?.name == "Food")

        let restoredTransactions = try destinationContext.fetch(FetchDescriptor<ExpenseTransaction>())
        #expect(restoredTransactions.first?.amount == 499)
        #expect(restoredTransactions.first?.category?.name == "Food")

        let restoredIdentities = try destinationContext.fetch(FetchDescriptor<LinkedIdentity>())
        #expect(restoredIdentities.first?.account?.email == "ada@example.com")

        let restoredMappings = try destinationContext.fetch(FetchDescriptor<MerchantCategoryMapping>())
        #expect(restoredMappings.first?.category?.name == "Food")

        let restoredGoals = try destinationContext.fetch(FetchDescriptor<SavingsGoal>())
        #expect(restoredGoals.first?.contributions.count == 1)

        let restoredContacts = try destinationContext.fetch(FetchDescriptor<LedgerContact>())
        #expect(restoredContacts.first?.entries.first?.amount == 500)
    }

    @Test func restoreRejectsGarbageData() {
        let container = PersistenceController.makeContainer(inMemory: true)
        let garbage = Data("not a backup".utf8)
        #expect(throws: BackupManager.BackupError.self) {
            try BackupManager.restore(from: garbage, context: container.mainContext)
        }
    }
}
