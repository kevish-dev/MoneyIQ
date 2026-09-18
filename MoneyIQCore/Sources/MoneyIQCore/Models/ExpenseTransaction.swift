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

@Model
public final class ExpenseTransaction {
    @Attribute(.unique) public var id: UUID
    public var amount: Decimal
    public var date: Date
    public var note: String?
    public var merchantName: String?
    public var paymentMethod: PaymentMethod
    public var createdAt: Date

    /// Set when a screenshot/ML pipeline produced this transaction (Phase 3).
    /// Left false for manual entries.
    public var isAutoImported: Bool

    /// Heuristically flagged as a recurring bill (EMI, subscription, utility,
    /// etc.) at import time — Phase 3's "auto-detect bills."
    public var isBillLike: Bool

    public var category: ExpenseCategory?

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
        createdAt: Date = .now
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
        self.createdAt = createdAt
    }
}
