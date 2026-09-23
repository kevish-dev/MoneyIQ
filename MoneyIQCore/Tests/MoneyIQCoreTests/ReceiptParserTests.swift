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

    /// Exactly what Vision returns for the real Slice receipt card: the big
    /// centered "₹100" comes back as "·100", with no "Paid" on that line and
    /// no decimals, so none of the original patterns caught it and the
    /// review screen opened with the amount blank (Save disabled).
    @Test func extractsStandaloneRoundAmountWithMisreadCurrencySymbol() {
        let lines = [
            "PAID SECURELY ON", "slice", "PAYMENT SUCCESSFUL", "·100",
            "To Big Mama Canfectionery", "Q899636744@ybl", "19 Sep '26, 05:52 pm",
            "From slice CC", "xx6386", "RRN: 626224365150"
        ]
        #expect(ReceiptParser.extractAmount(from: lines) == Decimal(100))
        #expect(ReceiptParser.extractMerchant(from: lines) == "Big Mama Canfectionery")
    }

    @Test func doesNotTruncateAmountsWithoutThousandsSeparators() {
        #expect(ReceiptParser.extractAmount(from: ["Paid ₹1500 to Swiggy"]) == Decimal(1500))
        #expect(ReceiptParser.extractAmount(from: ["Rs.12000 debited from A/c XX1234"]) == Decimal(12000))
        #expect(ReceiptParser.extractAmount(from: ["Total 1500.00"]) == Decimal(string: "1500.00"))
    }

    @Test func handlesIndianDigitGrouping() {
        #expect(ReceiptParser.extractAmount(from: ["₹1,00,000.50"]) == Decimal(string: "100000.50"))
    }

    @Test func treatsHryvniaSignAsAMisreadRupee() {
        #expect(ReceiptParser.extractAmount(from: ["₴2,000.00"]) == Decimal(2000))
    }

    @Test func doesNotReadDatesPhoneNumbersOrWordsAsAmounts() {
        #expect(ReceiptParser.extractAmount(from: ["Date 19.09.2026"]) == nil)
        #expect(ReceiptParser.extractAmount(from: ["Working hours 5"]) == nil)
        #expect(ReceiptParser.extractAmount(from: ["+919876543210"]) == nil)
    }

    @Test func parsesTheSlicePaymentSharedAsText() {
        let result = ReceiptParser.parse(text: "PAYMENT SUCCESSFUL\n·100\nTo Big Mama Canfectionery\n19 Sep '26, 05:52 pm")
        #expect(result.amount == Decimal(100))
        #expect(result.merchantName == "Big Mama Canfectionery")
        #expect(result.date != nil)
    }

    /// Real Vision output for a Slice "Paid ₹80" screenshot: the top reading
    /// turned the ₹ into a 7, with the right reading ranked equally beside it.
    @Test func prefersTheAlternativeReadingWhenTheRupeeWasReadAsADigit() {
        let candidates: [(string: String, confidence: Float)] = [("Paid 780", 1), ("Paid ·80", 1), ("Paid 80", 1)]
        #expect(ReceiptParser.bestReading(of: candidates) == "Paid ·80")
    }

    @Test func keepsTheTopReadingWithoutAnEquallyConfidentSymbolAlternative() {
        #expect(ReceiptParser.bestReading(of: [("Paid 780", 1)]) == "Paid 780")
        #expect(ReceiptParser.bestReading(of: [("Paid 780", 1), ("Paid ·80", 0.3)]) == "Paid 780")
        #expect(ReceiptParser.bestReading(of: [("Total 1,250.00", 1), ("Total ·1,250.00", 1)]) == "Total 1,250.00")
        #expect(ReceiptParser.bestReading(of: []) == nil)
    }

    /// A screenshot's first OCR line is usually the status-bar clock; that's
    /// "now", not the payment's date, which appears further down.
    @Test func skipsTheStatusBarClockWhenFindingTheDate() throws {
        let date = try #require(ReceiptParser.extractDate(from: "11:21\nPaid ·2,000\nTo Mal Ramjibhai\n28 Jul '26, 12:03 am"))
        let components = Calendar.current.dateComponents([.month, .day], from: date)
        #expect(components.month == 7)
        #expect(components.day == 28)
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
