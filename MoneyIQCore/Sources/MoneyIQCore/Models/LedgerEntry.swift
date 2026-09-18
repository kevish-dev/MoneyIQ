import Foundation
import SwiftData

/// Which way the money moved. Everything else — "I borrowed," "I paid for
/// their shopping," "settling up" — is just one of these two directions
/// plus a note; the running balance falls out of summing them, no separate
/// borrow/lend/settle math needed. See `LedgerEngine`.
public enum LedgerDirection: String, Codable, CaseIterable {
    /// You handed them money (a loan to them, covering their expense, or you
    /// paying back what you owed them).
    case iPaid
    /// They handed you money (a loan to you, or them paying back what they
    /// owed you).
    case theyPaid
}

@Model
public final class LedgerEntry {
    @Attribute(.unique) public var id: UUID
    public var amount: Decimal
    public var direction: LedgerDirection
    public var note: String?
    public var date: Date
    /// Cosmetic only (doesn't change the math) — lets the UI label an entry
    /// "Settled up" instead of "You paid," so the history reads like an
    /// audit trail rather than just a flat transaction list.
    public var isSettlement: Bool
    public var createdAt: Date

    public var contact: LedgerContact?

    public init(
        id: UUID = UUID(),
        amount: Decimal,
        direction: LedgerDirection,
        note: String? = nil,
        date: Date = .now,
        isSettlement: Bool = false,
        contact: LedgerContact? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.amount = amount
        self.direction = direction
        self.note = note
        self.date = date
        self.isSettlement = isSettlement
        self.contact = contact
        self.createdAt = createdAt
    }

    /// Signed from *your* perspective: positive means this entry increased
    /// how much they owe you; negative means it increased how much you owe
    /// them.
    public var signedAmount: Decimal {
        direction == .iPaid ? amount : -amount
    }
}
