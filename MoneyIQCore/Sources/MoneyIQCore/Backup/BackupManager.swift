import Foundation
import SwiftData

/// Exports every locally-stored model into a single JSON file, and restores
/// from one — the whole answer to "back up my data so I can move it to a
/// reinstall." No backend involved: the file is just handed to the system
/// share sheet / file picker, so the user decides where it lives (Files,
/// iCloud Drive, AirDrop, email, ...).
@MainActor
public enum BackupManager {
    public enum BackupError: LocalizedError {
        case encodingFailed
        case decodingFailed(Error)
        case incompatibleSchemaVersion(Int)

        public var errorDescription: String? {
            switch self {
            case .encodingFailed:
                "Couldn't prepare your data for export."
            case .decodingFailed:
                "That file doesn't look like a MoneyIQ backup."
            case .incompatibleSchemaVersion(let version):
                "This backup was made with a newer version of MoneyIQ (schema \(version)) and can't be restored here."
            }
        }
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    // MARK: - Export

    public static func exportData(context: ModelContext) throws -> Data {
        let payload = try buildPayload(context: context)
        do {
            return try encoder.encode(payload)
        } catch {
            throw BackupError.encodingFailed
        }
    }

    /// A filename like "MoneyIQ Backup 2026-09-22.json" for the export sheet.
    public static func suggestedFilename(date: Date = .now) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "MoneyIQ Backup \(formatter.string(from: date)).json"
    }

    private static func buildPayload(context: ModelContext) throws -> BackupPayload {
        let userAccounts = try context.fetch(FetchDescriptor<UserAccount>())
        let linkedIdentities = try context.fetch(FetchDescriptor<LinkedIdentity>())
        let expenseCategories = try context.fetch(FetchDescriptor<ExpenseCategory>())
        let expenseTransactions = try context.fetch(FetchDescriptor<ExpenseTransaction>())
        let budgets = try context.fetch(FetchDescriptor<Budget>())
        let reminderItems = try context.fetch(FetchDescriptor<ReminderItem>())
        let merchantCategoryMappings = try context.fetch(FetchDescriptor<MerchantCategoryMapping>())
        let netWorthAccounts = try context.fetch(FetchDescriptor<NetWorthAccount>())
        let savingsGoals = try context.fetch(FetchDescriptor<SavingsGoal>())
        let savingsContributions = try context.fetch(FetchDescriptor<SavingsContribution>())
        let ledgerContacts = try context.fetch(FetchDescriptor<LedgerContact>())
        let ledgerEntries = try context.fetch(FetchDescriptor<LedgerEntry>())
        let freelanceProjects = try context.fetch(FetchDescriptor<FreelanceProject>())
        let paymentInstallments = try context.fetch(FetchDescriptor<PaymentInstallment>())
        let projectReimbursements = try context.fetch(FetchDescriptor<ProjectReimbursement>())

        return BackupPayload(
            userAccounts: userAccounts.map {
                UserAccountDTO(
                    id: $0.id, firstName: $0.firstName, lastName: $0.lastName, email: $0.email,
                    mobileNumber: $0.mobileNumber, age: $0.age, preferredCurrencyCode: $0.preferredCurrencyCode,
                    monthlyIncome: $0.monthlyIncome, avatarImageData: $0.avatarImageData,
                    avatarEmoji: $0.avatarEmoji, createdAt: $0.createdAt
                )
            },
            linkedIdentities: linkedIdentities.map {
                LinkedIdentityDTO(
                    id: $0.id, provider: $0.provider, providerUserID: $0.providerUserID, email: $0.email,
                    displayName: $0.displayName, linkedAt: $0.linkedAt, accountID: $0.account?.id
                )
            },
            expenseCategories: expenseCategories.map {
                ExpenseCategoryDTO(
                    id: $0.id, name: $0.name, systemIconName: $0.systemIconName,
                    isDefault: $0.isDefault, createdAt: $0.createdAt
                )
            },
            expenseTransactions: expenseTransactions.map {
                ExpenseTransactionDTO(
                    id: $0.id, amount: $0.amount, date: $0.date, note: $0.note, merchantName: $0.merchantName,
                    paymentMethod: $0.paymentMethod, isAutoImported: $0.isAutoImported, isBillLike: $0.isBillLike,
                    categoryID: $0.category?.id, createdAt: $0.createdAt, editedAt: $0.editedAt,
                    importFingerprint: $0.importFingerprint
                )
            },
            budgets: budgets.map {
                BudgetDTO(
                    id: $0.id, monthlyCapAmount: $0.monthlyCapAmount, currencyCode: $0.currencyCode,
                    rolloverEnabled: $0.rolloverEnabled, effectiveFrom: $0.effectiveFrom, createdAt: $0.createdAt
                )
            },
            reminderItems: reminderItems.map {
                ReminderItemDTO(
                    id: $0.id, title: $0.title, amount: $0.amount, frequency: $0.frequency,
                    time: $0.time, isEnabled: $0.isEnabled, createdAt: $0.createdAt
                )
            },
            merchantCategoryMappings: merchantCategoryMappings.map {
                MerchantCategoryMappingDTO(merchantKey: $0.merchantKey, categoryID: $0.category?.id, updatedAt: $0.updatedAt)
            },
            netWorthAccounts: netWorthAccounts.map {
                NetWorthAccountDTO(
                    id: $0.id, name: $0.name, kind: $0.kind, balance: $0.balance, currencyCode: $0.currencyCode,
                    systemIconName: $0.systemIconName, updatedAt: $0.updatedAt, createdAt: $0.createdAt
                )
            },
            savingsGoals: savingsGoals.map {
                SavingsGoalDTO(
                    id: $0.id, name: $0.name, targetAmount: $0.targetAmount, targetDate: $0.targetDate,
                    savedAmount: $0.savedAmount, currencyCode: $0.currencyCode,
                    systemIconName: $0.systemIconName, createdAt: $0.createdAt
                )
            },
            savingsContributions: savingsContributions.map {
                SavingsContributionDTO(id: $0.id, amount: $0.amount, date: $0.date, note: $0.note, goalID: $0.goal?.id)
            },
            ledgerContacts: ledgerContacts.map {
                LedgerContactDTO(id: $0.id, name: $0.name, colorHex: $0.colorHex, createdAt: $0.createdAt, lastActivityAt: $0.lastActivityAt)
            },
            ledgerEntries: ledgerEntries.map {
                LedgerEntryDTO(
                    id: $0.id, amount: $0.amount, direction: $0.direction, note: $0.note, date: $0.date,
                    isSettlement: $0.isSettlement, createdAt: $0.createdAt, contactID: $0.contact?.id
                )
            },
            freelanceProjects: freelanceProjects.map {
                FreelanceProjectDTO(
                    id: $0.id, name: $0.name, clientName: $0.clientName, totalAmount: $0.totalAmount,
                    currencyCode: $0.currencyCode, notes: $0.notes, createdAt: $0.createdAt
                )
            },
            paymentInstallments: paymentInstallments.map {
                PaymentInstallmentDTO(
                    id: $0.id, label: $0.label, amount: $0.amount, percentage: $0.percentage, dueDate: $0.dueDate,
                    isReceived: $0.isReceived, receivedDate: $0.receivedDate, note: $0.note,
                    createdAt: $0.createdAt, projectID: $0.project?.id
                )
            },
            projectReimbursements: projectReimbursements.map {
                ProjectReimbursementDTO(
                    id: $0.id, title: $0.title, amount: $0.amount, date: $0.date, isRecovered: $0.isRecovered,
                    recoveredDate: $0.recoveredDate, note: $0.note, createdAt: $0.createdAt, projectID: $0.project?.id
                )
            }
        )
    }

    // MARK: - Restore

    /// Replaces everything currently in the store with the contents of
    /// `data`. This is a full restore, not a merge — the expected use case
    /// is a fresh reinstall with an empty store, and merging two histories
    /// unambiguously isn't something a "restore" should try to guess at.
    @discardableResult
    public static func restore(from data: Data, context: ModelContext) throws -> BackupPayload {
        let payload: BackupPayload
        do {
            payload = try decoder.decode(BackupPayload.self, from: data)
        } catch {
            throw BackupError.decodingFailed(error)
        }
        guard payload.schemaVersion <= BackupPayload.currentSchemaVersion else {
            throw BackupError.incompatibleSchemaVersion(payload.schemaVersion)
        }

        try eraseAllData(context: context)

        var categoriesByID: [UUID: ExpenseCategory] = [:]
        for dto in payload.expenseCategories {
            let category = ExpenseCategory(id: dto.id, name: dto.name, systemIconName: dto.systemIconName, isDefault: dto.isDefault, createdAt: dto.createdAt)
            context.insert(category)
            categoriesByID[dto.id] = category
        }

        var accountsByID: [UUID: UserAccount] = [:]
        for dto in payload.userAccounts {
            let account = UserAccount(
                id: dto.id, firstName: dto.firstName, lastName: dto.lastName, email: dto.email,
                mobileNumber: dto.mobileNumber, age: dto.age, preferredCurrencyCode: dto.preferredCurrencyCode,
                monthlyIncome: dto.monthlyIncome, createdAt: dto.createdAt
            )
            account.avatarImageData = dto.avatarImageData
            account.avatarEmoji = dto.avatarEmoji
            context.insert(account)
            accountsByID[dto.id] = account
        }

        for dto in payload.linkedIdentities {
            let identity = LinkedIdentity(
                id: dto.id, provider: dto.provider, providerUserID: dto.providerUserID,
                email: dto.email, displayName: dto.displayName, linkedAt: dto.linkedAt
            )
            identity.account = dto.accountID.flatMap { accountsByID[$0] }
            context.insert(identity)
        }

        for dto in payload.expenseTransactions {
            let transaction = ExpenseTransaction(
                id: dto.id, amount: dto.amount, date: dto.date, note: dto.note, merchantName: dto.merchantName,
                paymentMethod: dto.paymentMethod, isAutoImported: dto.isAutoImported, isBillLike: dto.isBillLike,
                category: dto.categoryID.flatMap { categoriesByID[$0] }, createdAt: dto.createdAt,
                editedAt: dto.editedAt, importFingerprint: dto.importFingerprint
            )
            context.insert(transaction)
        }

        for dto in payload.budgets {
            context.insert(Budget(
                id: dto.id, monthlyCapAmount: dto.monthlyCapAmount, currencyCode: dto.currencyCode,
                rolloverEnabled: dto.rolloverEnabled, effectiveFrom: dto.effectiveFrom, createdAt: dto.createdAt
            ))
        }

        for dto in payload.reminderItems {
            context.insert(ReminderItem(
                id: dto.id, title: dto.title, amount: dto.amount, frequency: dto.frequency,
                time: dto.time, isEnabled: dto.isEnabled, createdAt: dto.createdAt
            ))
        }

        for dto in payload.merchantCategoryMappings {
            context.insert(MerchantCategoryMapping(
                merchantKey: dto.merchantKey, category: dto.categoryID.flatMap { categoriesByID[$0] }, updatedAt: dto.updatedAt
            ))
        }

        for dto in payload.netWorthAccounts {
            context.insert(NetWorthAccount(
                id: dto.id, name: dto.name, kind: dto.kind, balance: dto.balance, currencyCode: dto.currencyCode,
                systemIconName: dto.systemIconName, updatedAt: dto.updatedAt, createdAt: dto.createdAt
            ))
        }

        var goalsByID: [UUID: SavingsGoal] = [:]
        for dto in payload.savingsGoals {
            let goal = SavingsGoal(
                id: dto.id, name: dto.name, targetAmount: dto.targetAmount, targetDate: dto.targetDate,
                savedAmount: dto.savedAmount, currencyCode: dto.currencyCode,
                systemIconName: dto.systemIconName, createdAt: dto.createdAt
            )
            context.insert(goal)
            goalsByID[dto.id] = goal
        }

        for dto in payload.savingsContributions {
            context.insert(SavingsContribution(
                id: dto.id, amount: dto.amount, date: dto.date, note: dto.note,
                goal: dto.goalID.flatMap { goalsByID[$0] }
            ))
        }

        var contactsByID: [UUID: LedgerContact] = [:]
        for dto in payload.ledgerContacts {
            let contact = LedgerContact(id: dto.id, name: dto.name, colorHex: dto.colorHex, createdAt: dto.createdAt, lastActivityAt: dto.lastActivityAt)
            context.insert(contact)
            contactsByID[dto.id] = contact
        }

        for dto in payload.ledgerEntries {
            context.insert(LedgerEntry(
                id: dto.id, amount: dto.amount, direction: dto.direction, note: dto.note, date: dto.date,
                isSettlement: dto.isSettlement, contact: dto.contactID.flatMap { contactsByID[$0] }, createdAt: dto.createdAt
            ))
        }

        var projectsByID: [UUID: FreelanceProject] = [:]
        for dto in payload.freelanceProjects {
            let project = FreelanceProject(
                id: dto.id, name: dto.name, clientName: dto.clientName, totalAmount: dto.totalAmount,
                currencyCode: dto.currencyCode, notes: dto.notes, createdAt: dto.createdAt
            )
            context.insert(project)
            projectsByID[dto.id] = project
        }

        for dto in payload.paymentInstallments {
            context.insert(PaymentInstallment(
                id: dto.id, label: dto.label, amount: dto.amount, percentage: dto.percentage, dueDate: dto.dueDate,
                isReceived: dto.isReceived, receivedDate: dto.receivedDate, note: dto.note,
                project: dto.projectID.flatMap { projectsByID[$0] }, createdAt: dto.createdAt
            ))
        }

        for dto in payload.projectReimbursements {
            context.insert(ProjectReimbursement(
                id: dto.id, title: dto.title, amount: dto.amount, date: dto.date, isRecovered: dto.isRecovered,
                recoveredDate: dto.recoveredDate, note: dto.note,
                project: dto.projectID.flatMap { projectsByID[$0] }, createdAt: dto.createdAt
            ))
        }

        try context.save()
        return payload
    }

    private static func eraseAllData(context: ModelContext) throws {
        try context.delete(model: ProjectReimbursement.self)
        try context.delete(model: PaymentInstallment.self)
        try context.delete(model: FreelanceProject.self)
        try context.delete(model: LedgerEntry.self)
        try context.delete(model: LedgerContact.self)
        try context.delete(model: SavingsContribution.self)
        try context.delete(model: SavingsGoal.self)
        try context.delete(model: NetWorthAccount.self)
        try context.delete(model: MerchantCategoryMapping.self)
        try context.delete(model: ReminderItem.self)
        try context.delete(model: Budget.self)
        try context.delete(model: ExpenseTransaction.self)
        try context.delete(model: ExpenseCategory.self)
        try context.delete(model: LinkedIdentity.self)
        try context.delete(model: UserAccount.self)
        try context.save()
    }
}
