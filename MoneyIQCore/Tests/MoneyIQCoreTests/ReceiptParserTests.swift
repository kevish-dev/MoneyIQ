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

    /// A round-number "Paid" line with no decimal at all (e.g. Google Pay's
    /// "Paid ₹2,000") — Vision often misreads the ₹ as a stray middle dot,
    /// and there's no decimal for `moneyShapedRegex` to key off, so this
    /// needs the "paid"-keyword-scoped fallback specifically.
    @Test func extractsRoundAmountFromPaidLineWithMisreadCurrencySymbol() {
        let lines = ["12:03 1", "•I LTE 21", "Paid ·2,000", "To Mal Ramjibhai", "28 Jul '26, 12:03 am"]
        #expect(ReceiptParser.extractAmount(from: lines) == Decimal(2000))
    }

    @Test func extractsMerchantAfterPaidToPrefix() {
        let lines = ["Payment successful", "Paid to Swiggy Bangalore", "₹450"]
        #expect(ReceiptParser.extractMerchant(from: lines) == "Swiggy Bangalore")
    }

    @Test func fallsBackToPlausibleLineWhenNoPrefixMatches() {
        let lines = ["₹450", "Reliance Digital", "UPI Ref No 998877"]
        #expect(ReceiptParser.extractMerchant(from: lines) == "Reliance Digital")
    }

    /// Reproduces a real screenshot (Slice app) where a bare "Paid ₹80"
    /// header line was matching the "paid " merchant prefix before the
    /// actual "To <name>" line was ever reached, returning "₹80" as the
    /// "merchant" instead of the payee's name.
    @Test func doesNotMistakeThePaidAmountHeaderForTheMerchant() {
        let lines = ["Paid ₹80", "To Mr Khuswant Rajpurohit", "18 Sep '26, 09:45 pm"]
        #expect(ReceiptParser.extractMerchant(from: lines) == "Mr Khuswant Rajpurohit")
    }

    @Test func detectsBillKeywords() {
        #expect(ReceiptParser.detectBill(in: "Electricity Bill Payment\n₹1200") == true)
        #expect(ReceiptParser.detectBill(in: "Paid to Swiggy\n₹450") == false)
    }

    /// `parse(text:)` is the entry point for shared text (Share Extension),
    /// not OCR — same heuristics, no Vision step.
    @Test func parsesSharedTextTheSameWayAsOCRLines() {
        let shared = "Payment successful\nPaid to Swiggy Bangalore\n₹450"
        let result = ReceiptParser.parse(text: shared)
        #expect(result.amount == Decimal(450))
        #expect(result.merchantName == "Swiggy Bangalore")
    }

    @Test func normalizesMerchantKeysConsistently() {
        #expect(MerchantCategoryMapping.normalize("Swiggy") == MerchantCategoryMapping.normalize("SWIGGY*ORDER".replacingOccurrences(of: "*ORDER", with: "")))
        #expect(MerchantCategoryMapping.normalize("  Swiggy  ") == "swiggy")
    }
}
