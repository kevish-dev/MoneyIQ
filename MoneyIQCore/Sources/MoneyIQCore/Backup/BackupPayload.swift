import Foundation

/// A full, self-contained snapshot of everything MoneyIQ stores locally —
/// exported to a single JSON file so a user can carry their data across an
/// uninstall/reinstall (there's no backend/CloudKit sync yet, see
/// `PersistenceController`). Each nested type mirrors a `@Model` one-to-one,
/// with relationships flattened to the related object's `UUID` so the whole
/// graph round-trips through plain `Codable` without SwiftData involved.
public struct BackupPayload: Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var exportedAt: Date

    public var userAccounts: [UserAccountDTO]
    public var linkedIdentities: [LinkedIdentityDTO]
    public var expenseCategories: [ExpenseCategoryDTO]
    public var expenseTransactions: [ExpenseTransactionDTO]
    public var budgets: [BudgetDTO]
    public var reminderItems: [ReminderItemDTO]
    public var merchantCategoryMappings: [MerchantCategoryMappingDTO]
    public var netWorthAccounts: [NetWorthAccountDTO]
    public var savingsGoals: [SavingsGoalDTO]
    public var savingsContributions: [SavingsContributionDTO]
    public var ledgerContacts: [LedgerContactDTO]
    public var ledgerEntries: [LedgerEntryDTO]
    public var freelanceProjects: [FreelanceProjectDTO]
    public var paymentInstallments: [PaymentInstallmentDTO]
    public var projectReimbursements: [ProjectReimbursementDTO]

    public init(
        schemaVersion: Int = BackupPayload.currentSchemaVersion,
        exportedAt: Date = .now,
        userAccounts: [UserAccountDTO] = [],
        linkedIdentities: [LinkedIdentityDTO] = [],
        expenseCategories: [ExpenseCategoryDTO] = [],
        expenseTransactions: [ExpenseTransactionDTO] = [],
        budgets: [BudgetDTO] = [],
        reminderItems: [ReminderItemDTO] = [],
        merchantCategoryMappings: [MerchantCategoryMappingDTO] = [],
        netWorthAccounts: [NetWorthAccountDTO] = [],
        savingsGoals: [SavingsGoalDTO] = [],
        savingsContributions: [SavingsContributionDTO] = [],
        ledgerContacts: [LedgerContactDTO] = [],
        ledgerEntries: [LedgerEntryDTO] = [],
        freelanceProjects: [FreelanceProjectDTO] = [],
        paymentInstallments: [PaymentInstallmentDTO] = [],
        projectReimbursements: [ProjectReimbursementDTO] = []
    ) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.userAccounts = userAccounts
        self.linkedIdentities = linkedIdentities
        self.expenseCategories = expenseCategories
        self.expenseTransactions = expenseTransactions
        self.budgets = budgets
        self.reminderItems = reminderItems
        self.merchantCategoryMappings = merchantCategoryMappings
        self.netWorthAccounts = netWorthAccounts
        self.savingsGoals = savingsGoals
        self.savingsContributions = savingsContributions
        self.ledgerContacts = ledgerContacts
        self.ledgerEntries = ledgerEntries
        self.freelanceProjects = freelanceProjects
        self.paymentInstallments = paymentInstallments
        self.projectReimbursements = projectReimbursements
    }

    /// Total record count across every entity — used for the "X records"
    /// summary shown before a restore overwrites existing data.
    public var totalRecordCount: Int {
        userAccounts.count + linkedIdentities.count + expenseCategories.count
            + expenseTransactions.count + budgets.count + reminderItems.count
            + merchantCategoryMappings.count + netWorthAccounts.count + savingsGoals.count
            + savingsContributions.count + ledgerContacts.count + ledgerEntries.count
            + freelanceProjects.count + paymentInstallments.count + projectReimbursements.count
    }
}

public struct UserAccountDTO: Codable {
    public var id: UUID
    public var firstName: String
    public var lastName: String
    public var email: String
    public var mobileNumber: String?
    public var age: Int?
    public var preferredCurrencyCode: String
    public var monthlyIncome: Decimal?
    public var avatarImageData: Data?
    public var avatarEmoji: String?
    public var createdAt: Date
}

public struct LinkedIdentityDTO: Codable {
    public var id: UUID
    public var provider: AuthProviderKind
    public var providerUserID: String
    public var email: String
    public var displayName: String?
    public var linkedAt: Date
    public var accountID: UUID?
}

public struct ExpenseCategoryDTO: Codable {
    public var id: UUID
    public var name: String
    public var systemIconName: String
    public var isDefault: Bool
    public var createdAt: Date
}

public struct ExpenseTransactionDTO: Codable {
    public var id: UUID
    public var amount: Decimal
    public var date: Date
    public var note: String?
    public var merchantName: String?
    public var paymentMethod: PaymentMethod
    public var isAutoImported: Bool
    public var isBillLike: Bool
    public var categoryID: UUID?
    public var createdAt: Date
    public var editedAt: Date?
}

public struct BudgetDTO: Codable {
    public var id: UUID
    public var monthlyCapAmount: Decimal
    public var currencyCode: String
    public var rolloverEnabled: Bool
    public var effectiveFrom: Date
    public var createdAt: Date
}

public struct ReminderItemDTO: Codable {
    public var id: UUID
    public var title: String
    public var amount: Decimal?
    public var frequency: ReminderFrequency
    public var time: Date
    public var isEnabled: Bool
    public var createdAt: Date
}

public struct MerchantCategoryMappingDTO: Codable {
    public var merchantKey: String
    public var categoryID: UUID?
    public var updatedAt: Date
}

public struct NetWorthAccountDTO: Codable {
    public var id: UUID
    public var name: String
    public var kind: NetWorthAccountKind
    public var balance: Decimal
    public var currencyCode: String
    public var systemIconName: String
    public var updatedAt: Date
    public var createdAt: Date
}

public struct SavingsGoalDTO: Codable {
    public var id: UUID
    public var name: String
    public var targetAmount: Decimal
    public var targetDate: Date
    public var savedAmount: Decimal
    public var currencyCode: String
    public var systemIconName: String
    public var createdAt: Date
}

public struct SavingsContributionDTO: Codable {
    public var id: UUID
    public var amount: Decimal
    public var date: Date
    public var note: String?
    public var goalID: UUID?
}

public struct LedgerContactDTO: Codable {
    public var id: UUID
    public var name: String
    public var colorHex: String
    public var createdAt: Date
    /// Optional so older backups still decode.
    public var lastActivityAt: Date?
}

public struct LedgerEntryDTO: Codable {
    public var id: UUID
    public var amount: Decimal
    public var direction: LedgerDirection
    public var note: String?
    public var date: Date
    public var isSettlement: Bool
    public var createdAt: Date
    public var contactID: UUID?
}

public struct FreelanceProjectDTO: Codable {
    public var id: UUID
    public var name: String
    public var clientName: String?
    public var totalAmount: Decimal
    public var currencyCode: String
    public var notes: String?
    public var createdAt: Date
}

public struct PaymentInstallmentDTO: Codable {
    public var id: UUID
    public var label: String
    public var amount: Decimal
    public var percentage: Decimal?
    public var dueDate: Date?
    public var isReceived: Bool
    public var receivedDate: Date?
    public var note: String?
    public var createdAt: Date
    public var projectID: UUID?
}

public struct ProjectReimbursementDTO: Codable {
    public var id: UUID
    public var title: String
    public var amount: Decimal
    public var date: Date
    public var isRecovered: Bool
    public var recoveredDate: Date?
    public var note: String?
    public var createdAt: Date
    public var projectID: UUID?
}
