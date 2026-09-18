import Foundation
import SwiftData

/// A single overall monthly spending cap (Phase 1). Rollover (Phase 5) adds
/// a `rolloverEnabled` toggle later; left out here since it isn't needed yet.
@Model
public final class Budget {
    @Attribute(.unique) public var id: UUID
    public var monthlyCapAmount: Decimal
    public var currencyCode: String
    public var effectiveFrom: Date
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        monthlyCapAmount: Decimal,
        currencyCode: String,
        effectiveFrom: Date = .now,
        createdAt: Date = .now
    ) {
        self.id = id
        self.monthlyCapAmount = monthlyCapAmount
        self.currencyCode = currencyCode
        self.effectiveFrom = effectiveFrom
        self.createdAt = createdAt
    }
}
