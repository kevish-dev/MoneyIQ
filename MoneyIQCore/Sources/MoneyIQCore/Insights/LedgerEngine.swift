import Foundation

/// Pure balance math for the person-to-person IOU ledger — kept separate
/// from the `LedgerEntry` model itself so it's trivial to unit test.
public enum LedgerEngine {
    public enum BalanceState: Equatable {
        case theyOweYou(Decimal)
        case youOweThem(Decimal)
        case settled
    }

    /// When anything last happened with this person: the explicit
    /// `lastActivityAt` stamp, their newest entry, or when they were added —
    /// whichever is latest. What Split's "Recently updated" sort orders by.
    public static func lastActivity(for contact: LedgerContact) -> Date {
        let newestEntry = contact.entries.map(\.createdAt).max() ?? .distantPast
        return max(contact.lastActivityAt ?? .distantPast, newestEntry, contact.createdAt)
    }

    /// Positive = they owe you; negative = you owe them; zero = settled.
    public static func netBalance(for entries: [LedgerEntry]) -> Decimal {
        entries.reduce(Decimal(0)) { $0 + $1.signedAmount }
    }

    public static func balanceState(for entries: [LedgerEntry]) -> BalanceState {
        let net = netBalance(for: entries)
        if net > 0 { return .theyOweYou(net) }
        if net < 0 { return .youOweThem(-net) }
        return .settled
    }

    /// The exact entry that would zero out the current balance — this is
    /// what "settle up" prefills, though the user can edit it down for a
    /// partial settlement.
    public static func settlementSuggestion(for entries: [LedgerEntry]) -> (amount: Decimal, direction: LedgerDirection)? {
        let net = netBalance(for: entries)
        guard net != 0 else { return nil }
        // If they owe you (net > 0), you settling means you receive money
        // from them, i.e. direction .theyPaid brings the balance back to 0.
        return net > 0 ? (net, .theyPaid) : (-net, .iPaid)
    }

    /// Splits `total` equally among `participantCount` people, rounded to
    /// the nearest paisa/cent, with any leftover remainder (a naive
    /// division like ₹100 ÷ 3 doesn't divide evenly) distributed one unit
    /// at a time to the first few shares — so the returned shares always
    /// sum to exactly `total`, never off by a fraction. Used by "Split a
    /// Bill": the caller keeps the last share for themselves (the payer)
    /// and creates one `LedgerEntry` per remaining share.
    public static func splitEqually(total: Decimal, participantCount: Int) -> [Decimal] {
        guard participantCount > 0, total > 0 else { return [] }

        let totalMinorUnits = NSDecimalNumber(decimal: total * 100)
            .rounding(accordingToBehavior: NSDecimalNumberHandler(
                roundingMode: .plain, scale: 0, raiseOnExactness: false,
                raiseOnOverflow: false, raiseOnUnderflow: false, raiseOnDivideByZero: false
            ))
            .int64Value
        let count = Int64(participantCount)
        let baseMinorUnits = totalMinorUnits / count
        let remainder = totalMinorUnits % count

        return (0..<participantCount).map { index in
            let minorUnits = baseMinorUnits + (Int64(index) < remainder ? 1 : 0)
            return Decimal(minorUnits) / 100
        }
    }
}
