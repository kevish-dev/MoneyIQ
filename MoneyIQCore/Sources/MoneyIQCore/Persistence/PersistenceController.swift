import Foundation
import SwiftData

@MainActor
public enum PersistenceController {
    public static let schema = Schema([
        UserAccount.self,
        LinkedIdentity.self,
        ExpenseCategory.self,
        ExpenseTransaction.self,
        Budget.self,
        ReminderItem.self,
        MerchantCategoryMapping.self
    ])

    /// Local-only store for now. `cloudKitDatabase: .none` is deliberate —
    /// CloudKit sync switches on once the paid Apple Developer Program
    /// membership is active (see PRD Phase 1/CloudKit dependency).
    public static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        let configuration = ModelConfiguration(
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    public static func seedDefaultCategoriesIfNeeded(context: ModelContext) {
        let descriptor = FetchDescriptor<ExpenseCategory>(predicate: #Predicate { $0.isDefault == true })
        let existingCount = (try? context.fetchCount(descriptor)) ?? 0
        guard existingCount == 0 else { return }

        for entry in ExpenseCategory.defaults {
            let category = ExpenseCategory(name: entry.name, systemIconName: entry.icon, isDefault: true)
            context.insert(category)
        }
        try? context.save()
    }
}
