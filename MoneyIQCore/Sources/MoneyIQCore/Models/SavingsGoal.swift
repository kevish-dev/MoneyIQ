import Foundation
import SwiftData

/// Phase 5's goal-based savings ("Save ₹50k for trip by Dec"). Progress is
/// tracked by `savedAmount`, bumped whenever the user logs a
/// `SavingsContribution` — kept as its own running total rather than summed
/// on read, so it stays correct even as history grows.
@Model
public final class SavingsGoal {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var targetAmount: Decimal
    public var targetDate: Date
    public var savedAmount: Decimal
    public var currencyCode: String
    public var systemIconName: String
    public var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \SavingsContribution.goal)
    public var contributions: [SavingsContribution] = []

    public init(
        id: UUID = UUID(),
        name: String,
        targetAmount: Decimal,
        targetDate: Date,
        savedAmount: Decimal = 0,
        currencyCode: String = Locale.current.currency?.identifier ?? "USD",
        systemIconName: String = "target",
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.targetAmount = targetAmount
        self.targetDate = targetDate
        self.savedAmount = savedAmount
        self.currencyCode = currencyCode
        self.systemIconName = systemIconName
        self.createdAt = createdAt
    }

    public var progressFraction: Double {
        guard targetAmount > 0 else { return 0 }
        let fraction = NSDecimalNumber(decimal: savedAmount / targetAmount).doubleValue
        return min(max(fraction, 0), 1)
    }

    public var remainingAmount: Decimal {
        max(0, targetAmount - savedAmount)
    }

    public var isComplete: Bool {
        savedAmount >= targetAmount
    }

    /// Whole calendar months between now and the target date, floored at 1
    /// so a goal due this month doesn't divide by zero.
    public func monthsRemaining(calendar: Calendar = .current, now: Date = .now) -> Int {
        let months = calendar.dateComponents([.month], from: now, to: targetDate).month ?? 0
        return max(months, 1)
    }

    /// How much the user would need to save each remaining month to hit the
    /// goal on time, given what's saved so far.
    public func suggestedMonthlyContribution(calendar: Calendar = .current, now: Date = .now) -> Decimal {
        remainingAmount / Decimal(monthsRemaining(calendar: calendar, now: now))
    }
}

@Model
public final class SavingsContribution {
    @Attribute(.unique) public var id: UUID
    public var amount: Decimal
    public var date: Date
    public var note: String?

    public var goal: SavingsGoal?

    public init(id: UUID = UUID(), amount: Decimal, date: Date = .now, note: String? = nil, goal: SavingsGoal? = nil) {
        self.id = id
        self.amount = amount
        self.date = date
        self.note = note
        self.goal = goal
    }
}
