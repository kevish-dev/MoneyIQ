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

    public static func parse(cgImage: CGImage) async throws -> ParsedReceipt {
        let lines = try await recognizeTextLines(in: cgImage)
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

    /// Deliberately the long-standing `VNRecognizeTextRequest`, run
    /// synchronously on a background queue, rather than the newer async
    /// `RecognizeTextRequest.perform(on:)`: on this project's real receipt
    /// images the async API was observed suspending forever (no CPU, no
    /// error, continuation never resumed), while this path read the same
    /// images in well under a second.
    static func recognizeTextLines(in cgImage: CGImage) async throws -> [String] {
        let image = SendableImage(cgImage: cgImage)
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                do {
                    try VNImageRequestHandler(cgImage: image.cgImage, options: [:]).perform([request])
                    let lines = (request.results ?? [])
                        .compactMap { observation in
                            bestReading(of: observation.topCandidates(5).map { ($0.string, $0.confidence) })
                        }
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    continuation.resume(returning: lines)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static let misreadRupeeSymbols = ["₹", "·", "•", "₴"]

    /// Vision sometimes reads the ₹ glyph as a digit — a real receipt's
    /// "Paid ₹80" came back as "Paid 780" — while listing the right reading
    /// ("Paid ·80") as an equally confident alternative. Prefer that
    /// alternative when it's the top reading with a ₹-like symbol exactly
    /// where the top reading has a 7 or 2.
    static func bestReading(of candidates: [(string: String, confidence: Float)]) -> String? {
        guard let top = candidates.first else { return nil }
        guard top.string.contains(where: { $0 == "7" || $0 == "2" }) else { return top.string }
        for alternative in candidates.dropFirst() where alternative.confidence >= top.confidence - 0.05 {
            for symbol in misreadRupeeSymbols where alternative.string.contains(symbol) {
                for digit in ["7", "2"] where alternative.string.replacingOccurrences(of: symbol, with: digit) == top.string {
                    return alternative.string
                }
            }
        }
        return top.string
    }

    /// `CGImage` is immutable, so handing one to the OCR queue is safe.
    private struct SendableImage: @unchecked Sendable {
        let cgImage: CGImage
    }

    /// Same heuristics as `parse(cgImage:)`, but for text handed off
    /// directly — e.g. from a UPI app's native iOS share sheet (Share
    /// Extension), which needs no OCR since the text is already real text,
    /// not a picture of text.
    public static func parse(text: String) -> ParsedReceipt {
        let lines = text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        return ParsedReceipt(
            amount: extractAmount(from: lines),
            merchantName: extractMerchant(from: lines),
            date: extractDate(from: text),
            looksLikeBill: detectBill(in: text),
            rawText: text
        )
    }

    // MARK: - Amount

    /// The number itself: comma-grouped, Indian or Western ("1,00,000",
    /// "1,250"), or a plain run of up to 7 digits ("1500"), with optional
    /// paise. Every pattern below ends in `(?![0-9])` so it can't stop
    /// partway through a longer number — the original patterns read
    /// "₹1500" as 150 and "1500.00" as 500.00.
    private static let amountNumber = #"(?:[0-9]{1,3}(?:,[0-9]{2,3})+|[0-9]{1,7})(?:\.[0-9]{1,2})?"#

    /// "₴" is here because Vision regularly misreads the ₹ glyph as the
    /// (visually similar) hryvnia sign. `\b` keeps "Rs" from matching inside
    /// words like "hours 5".
    private static let amountRegex = try! NSRegularExpression(
        pattern: #"(?:₹|₴|\bRs\.?|\bINR)\s?("# + amountNumber + #")(?![0-9])"#,
        options: [.caseInsensitive]
    )

    /// Many UPI apps' "Paid" line has no clean ₹ (e.g. "Paid ·2,000", the
    /// glyph misread as a stray symbol). This targets the word "paid"/
    /// "amount" specifically, rather than matching any number anywhere
    /// (which would false-positive on reference numbers), and allows 0-3
    /// characters between it and the number: a misread ₹, a colon, or
    /// whitespace.
    private static let paidLineAmountRegex = try! NSRegularExpression(
        pattern: #"\b(?:paid|amount)\D{0,3}("# + amountNumber + #")(?![0-9])"#,
        options: [.caseInsensitive]
    )

    /// A line that is nothing but a stray symbol and a number — how a big
    /// centered "₹100" usually comes back from OCR ("·100", "•100"). Slice's
    /// receipt card shows the amount exactly like this, with no "Paid" on
    /// the same line and no decimals, so none of the other patterns catch
    /// it. "+" is excluded so a bare "+91…" phone number never qualifies.
    private static let symbolPrefixedLineRegex = try! NSRegularExpression(
        pattern: #"^[^\p{L}\p{N}\s+]{1,2}\s?("# + amountNumber + #")(?:\s?/-)?$"#
    )

    /// Last resort: any "money-shaped" number — exactly 2 decimal places,
    /// which a transaction ID or phone number won't have. The lookarounds
    /// reject fragments of dates like "19.09.2026".
    private static let moneyShapedRegex = try! NSRegularExpression(
        pattern: #"(?<![0-9.,])((?:[0-9]{1,3}(?:,[0-9]{2,3})+|[0-9]{1,7})\.[0-9]{2})(?!\.?[0-9])"#
    )

    static func extractAmount(from lines: [String]) -> Decimal? {
        for regex in [amountRegex, paidLineAmountRegex, symbolPrefixedLineRegex, moneyShapedRegex] {
            if let value = firstMatch(of: regex, in: lines) {
                return value
            }
        }
        return nil
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

    // Deliberately no bare "paid " prefix — nearly every payment app's
    // header line reads "Paid ₹80" (amount, not a name), and "paid " would
    // match that before ever reaching the real "To <name>" line below it.
    // "paid to" alone covers the legitimate "Paid to Swiggy" phrasing.
    private static let merchantPrefixes = [
        "paid to", "payment to", "sent to", "to ", "received by"
    ]

    private static let ignoredLineFragments = [
        "successful", "transaction id", "upi ref", "reference no", "utr",
        "payment", "complete", "status", "amount", "bank", "wallet"
    ]

    /// True for candidates that are actually an amount, not a name (e.g. a
    /// prefix match landing on "₹80" or "2,000") — guards both extraction
    /// paths below so a currency-shaped string never gets returned as the
    /// merchant.
    private static func looksLikeAmount(_ candidate: String) -> Bool {
        let lowered = candidate.lowercased()
        if lowered.hasPrefix("₹") || lowered.hasPrefix("rs") || lowered.hasPrefix("inr") {
            return true
        }
        return Decimal(string: candidate.filter { !$0.isWhitespace }) != nil
    }

    static func extractMerchant(from lines: [String]) -> String? {
        for line in lines {
            let lowered = line.lowercased()
            for prefix in merchantPrefixes {
                if let range = lowered.range(of: prefix) {
                    let candidate = String(line[range.upperBound...])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !candidate.isEmpty, candidate.count <= 40, !looksLikeAmount(candidate) {
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
            guard !looksLikeAmount(trimmed) else { continue }
            guard !ignoredLineFragments.contains(where: lowered.contains) else { continue }
            return trimmed
        }
        return nil
    }

    // MARK: - Date

    /// A bare clock time like "11:21" — on a screenshot that's almost always
    /// the status bar, i.e. "now", not when the payment happened.
    private static let bareTimeRegex = try! NSRegularExpression(
        pattern: #"^\d{1,2}[:.]\d{2}(?:\s?[ap]\.?m\.?)?$"#,
        options: [.caseInsensitive]
    )

    static func extractDate(from rawText: String) -> Date? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else {
            return nil
        }
        let range = NSRange(rawText.startIndex..<rawText.endIndex, in: rawText)
        for match in detector.matches(in: rawText, range: range) {
            guard let matchRange = Range(match.range, in: rawText) else { continue }
            let matched = String(rawText[matchRange]).trimmingCharacters(in: .whitespaces)
            let matchedRange = NSRange(matched.startIndex..<matched.endIndex, in: matched)
            if bareTimeRegex.firstMatch(in: matched, range: matchedRange) != nil { continue }
            return match.date
        }
        return nil
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
