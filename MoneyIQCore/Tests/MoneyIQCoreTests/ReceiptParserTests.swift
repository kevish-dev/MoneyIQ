import Testing
import Foundation
@testable import MoneyIQCore

struct ReceiptParserTests {
    @Test func extractsAmountWithRupeeSymbol() {
        let lines = ["Payment successful", "₹1,250.50", "Paid to Swiggy"]
        #expect(ReceiptParser.extractAmount(from: lines) == Decimal(string: "1250.50"))
    }

    @Test func extractsAmountWithRsPrefix() {
        let lines = ["Rs. 499", "Transaction ID 12345"]
        #expect(ReceiptParser.extractAmount(from: lines) == Decimal(499))
    }

    /// Vision commonly misreads the ₹ glyph as a stray symbol — falls back
    /// to any decimal-shaped number rather than returning nothing.
    @Test func fallsBackToMoneyShapedNumberWhenCurrencySymbolIsMisread() {
        let lines = ["Payment Successful", "·1,249.00", "Paid to Swiggy Bangalore", "UPI Ref No 402918273645"]
        #expect(ReceiptParser.extractAmount(from: lines) == Decimal(string: "1249.00"))
    }

    @Test func ignoresLongIntegerIDsWithoutDecimals() {
        let lines = ["UPI Ref No 402918273645"]
        #expect(ReceiptParser.extractAmount(from: lines) == nil)
    }

    @Test func extractsMerchantAfterPaidToPrefix() {
        let lines = ["Payment successful", "Paid to Swiggy Bangalore", "₹450"]
        #expect(ReceiptParser.extractMerchant(from: lines) == "Swiggy Bangalore")
    }

    @Test func fallsBackToPlausibleLineWhenNoPrefixMatches() {
        let lines = ["₹450", "Reliance Digital", "UPI Ref No 998877"]
        #expect(ReceiptParser.extractMerchant(from: lines) == "Reliance Digital")
    }

    @Test func detectsBillKeywords() {
        #expect(ReceiptParser.detectBill(in: "Electricity Bill Payment\n₹1200") == true)
        #expect(ReceiptParser.detectBill(in: "Paid to Swiggy\n₹450") == false)
    }

    @Test func normalizesMerchantKeysConsistently() {
        #expect(MerchantCategoryMapping.normalize("Swiggy") == MerchantCategoryMapping.normalize("SWIGGY*ORDER".replacingOccurrences(of: "*ORDER", with: "")))
        #expect(MerchantCategoryMapping.normalize("  Swiggy  ") == "swiggy")
    }
}
