import Foundation
import Vision
import CoreGraphics

public struct ParsedReceipt: Sendable {
    public let amount: Decimal?
    public let merchantName: String?
    public let date: Date?
    public let looksLikeBill: Bool
    public let rawText: String
}

/// On-device screenshot parsing (Phase 3 of the PRD): OCRs a UPI/bank/wallet
/// payment screenshot with Vision and heuristically pulls out amount,
/// merchant, and date. Runs entirely on-device — the image is never
/// uploaded or persisted by this type.
public enum ReceiptParser {
    public enum ParseError: Error {
        case noTextFound
    }

    @MainActor
    public static func parse(cgImage: CGImage) async throws -> ParsedReceipt {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let observations = try await request.perform(on: cgImage)
        let lines = observations.compactMap { $0.topCandidates(1).first?.string }
        guard !lines.isEmpty else { throw ParseError.noTextFound }

        let rawText = lines.joined(separator: "\n")

        return ParsedReceipt(
            amount: extractAmount(from: lines),
            merchantName: extractMerchant(from: lines),
            date: extractDate(from: rawText),
            looksLikeBill: detectBill(in: rawText),
            rawText: rawText
        )
    }

    // MARK: - Amount

    private static let amountRegex = try! NSRegularExpression(
        pattern: #"(?:₹|Rs\.?|INR)\s?([0-9]{1,3}(?:,[0-9]{2,3})*(?:\.[0-9]{1,2})?)"#,
        options: [.caseInsensitive]
    )

    /// Vision frequently misreads the ₹ glyph as a stray symbol (·, •, a
    /// stray "Z", etc.) since it's small and unfamiliar to the text model.
    /// When no line has a clean currency prefix, fall back to the first
    /// "money-shaped" number instead — a decimal amount to exactly 2 places,
    /// which a transaction ID or phone number won't have.
    private static let moneyShapedRegex = try! NSRegularExpression(
        pattern: #"([0-9]{1,3}(?:,[0-9]{2,3})*\.[0-9]{2})\b"#
    )

    static func extractAmount(from lines: [String]) -> Decimal? {
        if let value = firstMatch(of: amountRegex, in: lines) {
            return value
        }
        return firstMatch(of: moneyShapedRegex, in: lines)
    }

    private static func firstMatch(of regex: NSRegularExpression, in lines: [String]) -> Decimal? {
        for line in lines {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let match = regex.firstMatch(in: line, range: range),
                  let group = Range(match.range(at: 1), in: line) else { continue }
            let numeric = line[group].replacingOccurrences(of: ",", with: "")
            if let value = Decimal(string: numeric) {
                return value
            }
        }
        return nil
    }

    // MARK: - Merchant

    private static let merchantPrefixes = [
        "paid to", "payment to", "sent to", "to ", "paid ", "received by"
    ]

    private static let ignoredLineFragments = [
        "successful", "transaction id", "upi ref", "reference no", "utr",
        "payment", "complete", "status", "amount", "bank", "wallet"
    ]

    static func extractMerchant(from lines: [String]) -> String? {
        for line in lines {
            let lowered = line.lowercased()
            for prefix in merchantPrefixes {
                if let range = lowered.range(of: prefix) {
                    let candidate = String(line[range.upperBound...])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !candidate.isEmpty, candidate.count <= 40 {
                        return candidate
                    }
                }
            }
        }

        // Fallback: the first line that isn't a number, date-ish, or one of
        // the generic boilerplate words every payment screenshot repeats.
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let lowered = trimmed.lowercased()
            guard trimmed.count >= 3, trimmed.count <= 40 else { continue }
            guard Decimal(string: trimmed.filter { !$0.isWhitespace }) == nil else { continue }
            guard !ignoredLineFragments.contains(where: lowered.contains) else { continue }
            guard !lowered.hasPrefix("₹"), !lowered.hasPrefix("rs") else { continue }
            return trimmed
        }
        return nil
    }

    // MARK: - Date

    static func extractDate(from rawText: String) -> Date? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else {
            return nil
        }
        let range = NSRange(rawText.startIndex..<rawText.endIndex, in: rawText)
        guard let match = detector.firstMatch(in: rawText, range: range) else { return nil }
        return match.date
    }

    // MARK: - Bill detection

    private static let billKeywords = [
        "bill", "emi", "recharge", "electricity", "broadband", "subscription",
        "premium due", "rent", "wifi", "gas bill", "water bill", "insurance"
    ]

    static func detectBill(in rawText: String) -> Bool {
        let lowered = rawText.lowercased()
        return billKeywords.contains { lowered.contains($0) }
    }
}
