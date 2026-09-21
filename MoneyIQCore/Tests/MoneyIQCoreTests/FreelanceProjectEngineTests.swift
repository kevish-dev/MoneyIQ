import Testing
import Foundation
@testable import MoneyIQCore

@MainActor
struct FreelanceProjectEngineTests {
    @Test func totalReceivedOnlyCountsReceivedInstallments() {
        let installments = [
            PaymentInstallment(label: "Advance", amount: 30000, isReceived: true),
            PaymentInstallment(label: "Final", amount: 70000, isReceived: false)
        ]
        #expect(FreelanceProjectEngine.totalReceived(installments) == 30000)
        #expect(FreelanceProjectEngine.totalPending(installments) == 70000)
        #expect(FreelanceProjectEngine.allocatedTotal(installments) == 100000)
    }

    @Test func unallocatedAmountFloorsAtZero() {
        let installments = [PaymentInstallment(label: "Advance", amount: 30000)]
        #expect(FreelanceProjectEngine.unallocatedAmount(totalAmount: 100000, installments: installments) == 70000)
        // Over-allocated (quote changed after installments were already
        // set up) shouldn't read as a negative "remaining."
        let overAllocated = [PaymentInstallment(label: "A", amount: 60000), PaymentInstallment(label: "B", amount: 60000)]
        #expect(FreelanceProjectEngine.unallocatedAmount(totalAmount: 100000, installments: overAllocated) == 0)
    }

    @Test func progressFractionReflectsReceivedShare() {
        let installments = [
            PaymentInstallment(label: "Advance", amount: 30000, isReceived: true),
            PaymentInstallment(label: "Final", amount: 70000, isReceived: false)
        ]
        #expect(FreelanceProjectEngine.progressFraction(totalAmount: 100000, installments: installments) == 0.3)
    }

    @Test func progressFractionIsZeroWhenTotalIsZero() {
        #expect(FreelanceProjectEngine.progressFraction(totalAmount: 0, installments: []) == 0)
    }

    @Test func reimbursementTotalsSplitByRecoveredStatus() {
        let reimbursements = [
            ProjectReimbursement(title: "Domain", amount: 1200, isRecovered: true),
            ProjectReimbursement(title: "VPS", amount: 800, isRecovered: false)
        ]
        #expect(FreelanceProjectEngine.totalReimbursed(reimbursements) == 2000)
        #expect(FreelanceProjectEngine.totalRecovered(reimbursements) == 1200)
        #expect(FreelanceProjectEngine.outstandingReimbursements(reimbursements) == 800)
    }

    @Test func amountForPercentageMatchesTheUsersWorkedExample() {
        // The user's own example: a ₹1,00,000 project split 30/40/30.
        #expect(FreelanceProjectEngine.amount(forPercentage: 30, ofTotal: 100000) == 30000)
        #expect(FreelanceProjectEngine.amount(forPercentage: 40, ofTotal: 100000) == 40000)
    }

    @Test func amountForPercentageRoundsToTwoDecimalPlaces() {
        #expect(FreelanceProjectEngine.amount(forPercentage: Decimal(string: "33.333")!, ofTotal: 100) == Decimal(string: "33.33")!)
    }
}
