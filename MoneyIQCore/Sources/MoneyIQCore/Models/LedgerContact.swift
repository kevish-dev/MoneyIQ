import Foundation
import SwiftData

/// A person you lend to / borrow from outside of your own budget — "person A
/// and person B settling up," as opposed to `NetWorthAccount` (your own
/// assets/liabilities) or `ExpenseTransaction` (your own spending).
@Model
public final class LedgerContact {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var colorHex: String
    public var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \LedgerEntry.contact)
    public var entries: [LedgerEntry] = []

    public init(
        id: UUID = UUID(),
        name: String,
        colorHex: String = LedgerContact.randomColorHex(),
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.createdAt = createdAt
    }

    private static let palette = ["FF6B6B", "4ECDC4", "556FB5", "FFB84C", "9B5DE5", "00BBF9", "F15BB5", "845EC2"]
    public static func randomColorHex() -> String {
        palette.randomElement() ?? "556FB5"
    }
}
