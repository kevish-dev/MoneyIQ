import Testing
import SwiftData
@testable import MoneyIQCore

@MainActor
struct PersistenceControllerTests {
    @Test func seedsDefaultCategoriesOnce() throws {
        let container = PersistenceController.makeContainer(inMemory: true)
        let context = container.mainContext

        PersistenceController.seedDefaultCategoriesIfNeeded(context: context)
        PersistenceController.seedDefaultCategoriesIfNeeded(context: context)

        let categories = try context.fetch(FetchDescriptor<ExpenseCategory>())
        #expect(categories.count == ExpenseCategory.defaults.count)
    }
}
