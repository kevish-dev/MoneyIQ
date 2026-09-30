import Testing
import Foundation
@testable import MoneyIQCore

@MainActor
struct LedgerEngineTests {
    @Test func emptyLedgerIsSettled() {
        #expect(LedgerEngine.balanceState(for: []) == .settled)
    }

    @Test func borrowingMeansYouOweThem() {
        let borrowed = LedgerEntry(amount: 20000, direction: .theyPaid, note: "Borrowed for rent")
        #expect(LedgerEngine.netBalance(for: [borrowed]) == -20000)
        #expect(LedgerEngine.balanceState(for: [borrowed]) == .youOweThem(20000))
    }

    /// The user's own worked example: borrow 20,000, then pay 2,000 for
    /// their shopping, net should be "you owe them 18,000."
    @Test func borrowThenPayOnTheirBehalfNetsCorrectly() {
        let borrowed = LedgerEntry(amount: 20000, direction: .theyPaid, note: "Borrowed for rent")
        let paidForShopping = LedgerEntry(amount: 2000, direction: .iPaid, note: "His shopping")

        let entries = [borrowed, paidForShopping]
        #expect(LedgerEngine.netBalance(for: entries) == -18000)
        #expect(LedgerEngine.balanceState(for: entries) == .youOweThem(18000))
    }

    @Test func settlementSuggestionZeroesOutWhenYouOweThem() {
        let entries = [LedgerEntry(amount: 18000, direction: .theyPaid)]
        let suggestion = LedgerEngine.settlementSuggestion(for: entries)
        #expect(suggestion?.amount == 18000)
        #expect(suggestion?.direction == .iPaid)

        // Applying the suggested settlement should zero the balance.
        let settled = entries + [LedgerEntry(amount: suggestion!.amount, direction: suggestion!.direction, isSettlement: true)]
        #expect(LedgerEngine.balanceState(for: settled) == .settled)
    }

    @Test func settlementSuggestionZeroesOutWhenTheyOweYou() {
        let entries = [LedgerEntry(amount: 500, direction: .iPaid)]
        let suggestion = LedgerEngine.settlementSuggestion(for: entries)
        #expect(suggestion?.amount == 500)
        #expect(suggestion?.direction == .theyPaid)
    }

    @Test func noSettlementSuggestedWhenAlreadySettled() {
        let entries = [
            LedgerEntry(amount: 100, direction: .iPaid),
            LedgerEntry(amount: 100, direction: .theyPaid)
        ]
        #expect(LedgerEngine.settlementSuggestion(for: entries) == nil)
    }

    /// Full worked scenario: borrow, pay for shopping, settle up, then a
    /// fresh borrow starts a new cycle from zero.
    @Test func fullCycleThroughSettlementAndBeyond() {
        var entries: [LedgerEntry] = []
        entries.append(LedgerEntry(amount: 20000, direction: .theyPaid, note: "Borrowed"))
        entries.append(LedgerEntry(amount: 2000, direction: .iPaid, note: "His shopping"))
        #expect(LedgerEngine.balanceState(for: entries) == .youOweThem(18000))

        let settlement = LedgerEngine.settlementSuggestion(for: entries)!
        entries.append(LedgerEntry(amount: settlement.amount, direction: settlement.direction, isSettlement: true))
        #expect(LedgerEngine.balanceState(for: entries) == .settled)

        entries.append(LedgerEntry(amount: 500, direction: .theyPaid, note: "New borrow"))
        #expect(LedgerEngine.balanceState(for: entries) == .youOweThem(500))
    }

    @Test func partialSettlementLeavesRemainder() {
        var entries = [LedgerEntry(amount: 18000, direction: .theyPaid)]
        entries.append(LedgerEntry(amount: 10000, direction: .iPaid, isSettlement: true))
        #expect(LedgerEngine.balanceState(for: entries) == .youOweThem(8000))
    }

    @Test func splitEquallyDividesEvenly() {
        #expect(LedgerEngine.splitEqually(total: 2000, participantCount: 4) == [500, 500, 500, 500])
    }

    /// ₹100 ÷ 3 doesn't divide evenly in paise — shares should still sum to
    /// exactly the total, with the remainder distributed one paisa at a
    /// time to the first shares.
    @Test func splitEquallyDistributesRemainderExactly() {
        let shares = LedgerEngine.splitEqually(total: 100, participantCount: 3)
        #expect(shares == [Decimal(string: "33.34")!, Decimal(string: "33.33")!, Decimal(string: "33.33")!])
        #expect(shares.reduce(0, +) == 100)
    }

    @Test func splitEquallyWithOneParticipantReturnsWholeTotal() {
        #expect(LedgerEngine.splitEqually(total: 500, participantCount: 1) == [500])
    }

    @Test func splitEquallyWithZeroOrNegativeInputsReturnsEmpty() {
        #expect(LedgerEngine.splitEqually(total: 0, participantCount: 4).isEmpty)
        #expect(LedgerEngine.splitEqually(total: -100, participantCount: 4).isEmpty)
        #expect(LedgerEngine.splitEqually(total: 100, participantCount: 0).isEmpty)
    }
}

@MainActor
struct LedgerLastActivityTests {
    @Test func explicitActivityStampWinsOverOlderEntries() {
        let old = Date(timeIntervalSince1970: 1_000)
        let contact = LedgerContact(name: "Asha", createdAt: old)
        contact.entries = [LedgerEntry(amount: 10, direction: .iPaid, createdAt: old)]
        let edited = Date(timeIntervalSince1970: 5_000)
        contact.markActivity(at: edited)
        #expect(LedgerEngine.lastActivity(for: contact) == edited)
    }

    @Test func fallsBackToNewestEntryForContactsWithoutAStamp() {
        let contact = LedgerContact(name: "Ravi", createdAt: Date(timeIntervalSince1970: 1_000))
        let newest = Date(timeIntervalSince1970: 9_000)
        contact.entries = [
            LedgerEntry(amount: 10, direction: .iPaid, createdAt: Date(timeIntervalSince1970: 2_000)),
            LedgerEntry(amount: 5, direction: .theyPaid, createdAt: newest)
        ]
        #expect(LedgerEngine.lastActivity(for: contact) == newest)
    }
}
