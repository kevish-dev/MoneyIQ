import Foundation
import SwiftData

public enum NetWorthAccountKind: String, Codable, CaseIterable {
    case asset
    case liability
}

/// Phase 4's net worth tracker: a standalone accounts/assets model, kept
/// deliberately independent of `ExpenseTransaction` per the PRD note that
/// this "should follow core app stability" rather than being derived from
/// transaction history.
@Model
public final class NetWorthAccount {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var kind: NetWorthAccountKind
    public var balance: Decimal
    public var currencyCode: String
    public var systemIconName: String
    public var updatedAt: Date
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        kind: NetWorthAccountKind,
        balance: Decimal,
        currencyCode: String = Locale.current.currency?.identifier ?? "USD",
        systemIconName: String = "banknote",
        updatedAt: Date = .now,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.balance = balance
        self.currencyCode = currencyCode
        self.systemIconName = systemIconName
        self.updatedAt = updatedAt
        self.createdAt = createdAt
    }

    /// Assets contribute positively, liabilities negatively.
    public var signedBalance: Decimal {
        kind == .asset ? balance : -balance
    }
}
