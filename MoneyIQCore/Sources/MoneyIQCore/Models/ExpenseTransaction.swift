import Foundation
import SwiftData

public enum PaymentMethod: String, Codable, CaseIterable {
    case cash
    case card
    case upi
    case bankTransfer
    case wallet
    case other
}

/// Whether money left your account (an expense) or came into it (income,
/// a refund, someone paying you back). Income is recorded alongside
/// expenses but never counts toward spending, budgets, or insights.
public enum TransactionDirection: String, Codable, CaseIterable, Sendable {
    case expense
    case income
}

@Model
public final class ExpenseTransaction {
    @Attribute(.unique) public var id: UUID
    public var amount: Decimal
    public var date: Date
    public var note: String?
    public var merchantName: String?
    public var paymentMethod: PaymentMethod
    public var createdAt: Date

    /// Set the first time this transaction is edited after creation; nil
    /// until then. Drives the "edited" indicator in the transaction list.
    public var editedAt: Date?

    /// Set when a screenshot/ML pipeline produced this transaction (Phase 3).
    /// Left false for manual entries.
    public var isAutoImported: Bool

    /// Heuristically flagged as a recurring bill (EMI, subscription, utility,
    /// etc.) at import time — Phase 3's "auto-detect bills."
    public var isBillLike: Bool

    public var category: ExpenseCategory?

    /// Stored as optional on purpose: rows from before income existed
    /// migrate in with nil here — SwiftData does *not* backfill a declared
    /// default into existing rows, and reading a nil into a non-optional
    /// enum crashes (verified against a real pre-income store). Read and
    /// write through `direction` instead.
    public var storedDirection: TransactionDirection?

    public var direction: TransactionDirection {
        get { storedDirection ?? .expense }
        set { storedDirection = newValue }
    }

    public var isIncome: Bool { direction == .income }

    public init(
        id: UUID = UUID(),
        amount: Decimal,
        date: Date = .now,
        note: String? = nil,
        merchantName: String? = nil,
        paymentMethod: PaymentMethod = .cash,
        isAutoImported: Bool = false,
        isBillLike: Bool = false,
        category: ExpenseCategory? = nil,
        direction: TransactionDirection = .expense,
        createdAt: Date = .now,
        editedAt: Date? = nil
    ) {
        self.id = id
        self.amount = amount
        self.date = date
        self.note = note
        self.merchantName = merchantName
        self.paymentMethod = paymentMethod
        self.isAutoImported = isAutoImported
        self.isBillLike = isBillLike
        self.category = category
        self.storedDirection = direction
        self.createdAt = createdAt
        self.editedAt = editedAt
    }
}

public extension Array where Element == ExpenseTransaction {
    /// Just the money-out rows — what every spending total, budget, and
    /// insight is computed from.
    var expensesOnly: [ExpenseTransaction] { filter { !$0.isIncome } }
}
