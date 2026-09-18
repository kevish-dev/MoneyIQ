import Foundation
import SwiftData

/// A single overall monthly spending cap. `rolloverEnabled` (Phase 5) lets
/// last month's unused amount carry into this month's effective cap — see
/// `BudgetEngine.effectiveCap`.
@Model
public final class Budget {
    @Attribute(.unique) public var id: UUID
    public var monthlyCapAmount: Decimal
    public var currencyCode: String
    public var rolloverEnabled: Bool
    public var effectiveFrom: Date
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        monthlyCapAmount: Decimal,
        currencyCode: String,
        rolloverEnabled: Bool = false,
        effectiveFrom: Date = .now,
        createdAt: Date = .now
    ) {
        self.id = id
        self.monthlyCapAmount = monthlyCapAmount
        self.currencyCode = currencyCode
        self.rolloverEnabled = rolloverEnabled
        self.effectiveFrom = effectiveFrom
        self.createdAt = createdAt
    }
}
