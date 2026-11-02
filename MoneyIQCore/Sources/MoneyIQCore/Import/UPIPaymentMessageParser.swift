import Foundation
import CryptoKit

public struct UPIPaymentMessage: Sendable {
    public let amount: Decimal
    public let date: Date
    public let payee: String?
    public let looksLikeBill: Bool
    public let fingerprint: String
}

/// A deliberately strict parser for bank debit messages passed in by a
/// Shortcuts Message automation. An app-open event alone has no payment data.
public enum UPIPaymentMessageParser {
    private static let upi = regex(#"\b(?:upi|vpa)\b"#)
    private static let debit = regex(#"\b(?:debited|spent|paid|sent)\b"#)
    private static let unsafeStatus = regex(#"\b(?:credited|refunded|refund|reversed|reversal|failed|declined|unsuccessful|pending|mandate|request)\b"#)
    private static let currency = regex(#"(?:₹|\bRs\.?|\bINR)\s*([0-9]{1,3}(?:,[0-9]{2,3})+|[0-9]{1,9})(?:\.([0-9]{1,2}))?(?![0-9])"#)
    private static let amountContextLabel = regex(#"\b(?:balance|bal|avl|available|amount|amt|paid|debited|spent|sent)\b"#)
    private static let reference = regex(#"\b(?:upi\s*(?:ref(?:erence)?\s*(?:no\.?|number|id)?|id)|utr|rrn|txn\s*id)\s*[:#./-]?\s*([a-z0-9]{8,30})\b"#)
    private static let payee = regex(#"\b(?:to|towards|at)\s+([a-z][a-z0-9 .&@_-]{1,48})"#)

    public static func parse(_ text: String, receivedAt: Date = .now) -> UPIPaymentMessage? {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard upi.firstMatch(in: text, range: range) != nil,
              unsafeStatus.firstMatch(in: text, range: range) == nil,
              let debitMatch = debit.firstMatch(in: text, range: range) else { return nil }

        // Bank messages often contain both the debit and the available
        // balance. Use the currency amount closest to the debit verb.
        let amountMatch = currency.matches(in: text, range: range)
            .filter { !isBalanceAmount($0, in: text) }
            .min { distance($0.range, to: debitMatch.range) < distance($1.range, to: debitMatch.range) }
        guard let amountMatch,
              distance(amountMatch.range, to: debitMatch.range) <= 80,
              let wholeRange = Range(amountMatch.range(at: 1), in: text) else { return nil }
        let whole = text[wholeRange].replacingOccurrences(of: ",", with: "")
        let fraction = Range(amountMatch.range(at: 2), in: text).map { String(text[$0]) } ?? ""
        let numeric = fraction.isEmpty ? whole : "\(whole).\(fraction)"
        guard let amount = Decimal(string: numeric, locale: Locale(identifier: "en_IN")), amount > 0 else { return nil }

        let parsedReceipt = ReceiptParser.parse(text: text)
        let identifier = reference.firstMatch(in: text, range: range)
            .flatMap { Range($0.range(at: 1), in: text) }
            .map { "ref:\(text[$0].lowercased())" }
        let normalizedText = text.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let source = identifier ?? "text:\(normalizedText)"
        let fingerprint = SHA256.hash(data: Data(source.utf8))
            .map { String(format: "%02x", $0) }.joined()

        return UPIPaymentMessage(
            amount: amount,
            date: parsedReceipt.date ?? receivedAt,
            payee: extractPayee(from: text, range: range),
            looksLikeBill: parsedReceipt.looksLikeBill,
            fingerprint: fingerprint
        )
    }

    public static func isDuplicate(_ candidate: UPIPaymentMessage, in transactions: [ExpenseTransaction]) -> Bool {
        transactions.contains { $0.importFingerprint == candidate.fingerprint }
    }

    private static func extractPayee(from text: String, range: NSRange) -> String? {
        guard let match = payee.firstMatch(in: text, range: range),
              let valueRange = Range(match.range(at: 1), in: text) else { return nil }
        var name = String(text[valueRange])
        for delimiter in [" via ", " on ", " upi", " ref", " utr", " from ", " avl", " balance", " by "] {
            if let found = name.range(of: delimiter, options: .caseInsensitive) {
                name = String(name[..<found.lowerBound])
            }
        }
        name = name.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard (2...40).contains(name.count),
              !name.lowercased().hasPrefix("your "),
              !name.lowercased().hasPrefix("a/c"),
              !["upi", "vpa"].contains(name.lowercased()) else { return nil }
        return name
    }

    private static func isBalanceAmount(_ match: NSTextCheckingResult, in text: String) -> Bool {
        let nsText = text as NSString
        let start = max(0, match.range.location - 28)
        let prefix = nsText.substring(with: NSRange(location: start, length: match.range.location - start))
        let range = NSRange(prefix.startIndex..<prefix.endIndex, in: prefix)
        guard let lastLabel = amountContextLabel.matches(in: prefix, range: range).last,
              let labelRange = Range(lastLabel.range, in: prefix) else { return false }
        return ["balance", "bal", "avl", "available"].contains(prefix[labelRange].lowercased())
    }

    private static func distance(_ a: NSRange, to b: NSRange) -> Int {
        if NSMaxRange(a) < b.location { return b.location - NSMaxRange(a) }
        if NSMaxRange(b) < a.location { return a.location - NSMaxRange(b) }
        return 0
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }
}
