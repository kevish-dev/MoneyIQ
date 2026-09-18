import Foundation
import SwiftData

/// Remembers which category a merchant was last filed under, so future
/// screenshots from the same merchant auto-categorize themselves. This is
/// the whole of "merchant-based auto-categorization" from the PRD — no ML
/// needed, just a learned lookup table that improves as the user corrects it.
@Model
public final class MerchantCategoryMapping {
    @Attribute(.unique) public var merchantKey: String
    public var category: ExpenseCategory?
    public var updatedAt: Date

    public init(merchantKey: String, category: ExpenseCategory?, updatedAt: Date = .now) {
        self.merchantKey = merchantKey
        self.category = category
        self.updatedAt = updatedAt
    }

    /// Normalizes a raw merchant string into a stable lookup key (case/
    /// whitespace/punctuation-insensitive) so "Swiggy", "SWIGGY*ORDER",
    /// and "swiggy  " all map to the same merchant.
    public static func normalize(_ rawName: String) -> String {
        rawName
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    @MainActor
    public static func category(forMerchant rawName: String, context: ModelContext) -> ExpenseCategory? {
        let key = normalize(rawName)
        guard !key.isEmpty else { return nil }
        let descriptor = FetchDescriptor<MerchantCategoryMapping>(predicate: #Predicate { $0.merchantKey == key })
        return (try? context.fetch(descriptor))?.first?.category
    }

    /// Called whenever the user confirms (or corrects) a category for a
    /// merchant — this is the "learning" half of auto-categorization.
    @MainActor
    public static func remember(merchant rawName: String, category: ExpenseCategory, context: ModelContext) {
        let key = normalize(rawName)
        guard !key.isEmpty else { return }
        let descriptor = FetchDescriptor<MerchantCategoryMapping>(predicate: #Predicate { $0.merchantKey == key })
        if let existing = try? context.fetch(descriptor).first {
            existing.category = category
            existing.updatedAt = .now
        } else {
            context.insert(MerchantCategoryMapping(merchantKey: key, category: category))
        }
        try? context.save()
    }
}
