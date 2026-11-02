import Foundation
import Testing
@testable import MoneyIQCore

struct UPIPaymentMessageParserTests {
    @Test func importsDebitAmountRatherThanAvailableBalance() {
        let message = "UPI: INR 125.50 debited from A/c XX1234 to Cafe Mocha on 02 Nov 2026. Avl Bal INR 9,000.00. UPI Ref No 123456789012"
        let parsed = UPIPaymentMessageParser.parse(message)
        #expect(parsed?.amount == Decimal(string: "125.50"))
        #expect(parsed?.payee == "Cafe Mocha")
        #expect(parsed?.fingerprint.count == 64)
    }

    @Test func rejectsCreditsFailuresAndMessagesWithoutUPI() {
        #expect(UPIPaymentMessageParser.parse("INR 80 credited to your account via UPI Ref 123456789012") == nil)
        #expect(UPIPaymentMessageParser.parse("UPI payment of INR 80 failed and was reversed") == nil)
        #expect(UPIPaymentMessageParser.parse("INR 80 debited from your account to Cafe Mocha") == nil)
        #expect(UPIPaymentMessageParser.parse("UPI payment request of INR 80 pending") == nil)
    }

    @Test func ignoresBalanceEvenWhenItIsCloserToDebitWord() {
        let message = "UPI debited from a/c. Avl Bal INR 900. Amount INR 75 to Corner Shop"
        #expect(UPIPaymentMessageParser.parse(message)?.amount == 75)
    }

    @Test func sameReferenceIsIdempotentAcrossMessageFormats() {
        let first = UPIPaymentMessageParser.parse("INR 80 paid via UPI to Cafe. UPI Ref No 123456789012")!
        let second = UPIPaymentMessageParser.parse("UPI Ref No 123456789012: INR 80 debited to Cafe")!
        #expect(first.fingerprint == second.fingerprint)
        let saved = ExpenseTransaction(amount: 80, importFingerprint: first.fingerprint)
        #expect(UPIPaymentMessageParser.isDuplicate(second, in: [saved]))
    }

    @Test func repeatedSameTextIsIdempotentWithoutReference() {
        let text = "UPI INR 40 debited to Corner Shop"
        let first = UPIPaymentMessageParser.parse(text)!
        let second = UPIPaymentMessageParser.parse("  UPI   INR 40 debited to Corner Shop  ")!
        #expect(first.fingerprint == second.fingerprint)
    }
}
