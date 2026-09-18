import Foundation
import SwiftData

@Model
public final class ExpenseCategory {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var systemIconName: String
    public var isDefault: Bool
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        systemIconName: String = "circle",
        isDefault: Bool = false,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.systemIconName = systemIconName
        self.isDefault = isDefault
        self.createdAt = createdAt
    }

    /// The eight default categories called out in the PRD. Call once at
    /// first launch (see `PersistenceController.seedDefaultCategoriesIfNeeded`).
    public static let defaults: [(name: String, icon: String)] = [
        ("Food", "fork.knife"),
        ("Travel", "airplane"),
        ("Rent", "house"),
        ("Health", "cross.case"),
        ("EMI/Bills", "doc.text"),
        ("Investment", "chart.line.uptrend.xyaxis"),
        ("Grocery Shopping", "cart"),
        ("Subscriptions", "arrow.triangle.2.circlepath")
    ]
}
