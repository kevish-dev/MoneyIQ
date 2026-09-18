import Foundation

/// Pure balance math for the person-to-person IOU ledger — kept separate
/// from the `LedgerEntry` model itself so it's trivial to unit test.
public enum LedgerEngine {
    public enum BalanceState: Equatable {
        case theyOweYou(Decimal)
        case youOweThem(Decimal)
        case settled
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
}
