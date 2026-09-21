import Foundation

/// Pure math for freelance project tracking — kept separate from the
/// `@Model` types so it's trivial to unit test, same pattern as
/// `LedgerEngine`/`BudgetEngine`. Two independent totals live side by
/// side here: payments the client owes you (`installments`) and expenses
/// you fronted that the client owes you back (`reimbursements`).
public enum FreelanceProjectEngine {
    public static func totalReceived(_ installments: [PaymentInstallment]) -> Decimal {
        installments.filter(\.isReceived).reduce(Decimal(0)) { $0 + $1.amount }
    }

    public static func totalPending(_ installments: [PaymentInstallment]) -> Decimal {
        installments.filter { !$0.isReceived }.reduce(Decimal(0)) { $0 + $1.amount }
    }

    public static func allocatedTotal(_ installments: [PaymentInstallment]) -> Decimal {
        installments.reduce(Decimal(0)) { $0 + $1.amount }
    }

    /// How much of the project total hasn't been assigned to any
    /// installment yet — drives the "remaining to schedule" hint while
    /// building a flexible payment breakdown. Floored at 0 so over-quoting
    /// (installments summing past the total, e.g. because the quote
    /// changed) doesn't show as a negative "remaining."
    public static func unallocatedAmount(totalAmount: Decimal, installments: [PaymentInstallment]) -> Decimal {
        max(0, totalAmount - allocatedTotal(installments))
    }

    /// Fraction (0...1) of the project total that's actually been
    /// received — what the progress ring on the project's summary card
    /// renders.
    public static func progressFraction(totalAmount: Decimal, installments: [PaymentInstallment]) -> Double {
        guard totalAmount > 0 else { return 0 }
        let fraction = NSDecimalNumber(decimal: totalReceived(installments) / totalAmount).doubleValue
        return min(max(fraction, 0), 1)
    }

    public static func totalReimbursed(_ reimbursements: [ProjectReimbursement]) -> Decimal {
        reimbursements.reduce(Decimal(0)) { $0 + $1.amount }
    }

    public static func totalRecovered(_ reimbursements: [ProjectReimbursement]) -> Decimal {
        reimbursements.filter(\.isRecovered).reduce(Decimal(0)) { $0 + $1.amount }
    }

    /// Money fronted for the project that the client hasn't paid back yet —
    /// the number that answers "how much should I still ask the client to
    /// reimburse me?"
    public static func outstandingReimbursements(_ reimbursements: [ProjectReimbursement]) -> Decimal {
        reimbursements.filter { !$0.isRecovered }.reduce(Decimal(0)) { $0 + $1.amount }
    }

    /// Converts a percentage-of-total entry (e.g. "30% advance" on a
    /// ₹1,00,000 project) into a currency amount, rounded to 2 decimal
    /// places. Lets a user quote a payment breakdown like "30/40/30" without
    /// doing the arithmetic themselves; each installment is converted
    /// independently; the three don't need to be forced to sum to exactly
    /// the total to the last paisa, since the amount (not the percentage)
    /// stays the editable source of truth afterward.
    public static func amount(forPercentage percentage: Decimal, ofTotal total: Decimal) -> Decimal {
        let raw = total * percentage / 100
        let handler = NSDecimalNumberHandler(
            roundingMode: .plain, scale: 2, raiseOnExactness: false,
            raiseOnOverflow: false, raiseOnUnderflow: false, raiseOnDivideByZero: false
        )
        return NSDecimalNumber(decimal: raw).rounding(accordingToBehavior: handler) as Decimal
    }
}
