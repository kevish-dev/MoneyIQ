import Foundation
import SwiftData

/// The single unified identity a user has in the app, regardless of which
/// provider(s) they sign in with. Multiple `LinkedIdentity` records can point
/// at one `UserAccount` once accounts are linked by matching email.
@Model
public final class UserAccount {
    @Attribute(.unique) public var id: UUID
    public var firstName: String
    public var lastName: String
    public var email: String
    public var mobileNumber: String?
    public var age: Int?
    public var preferredCurrencyCode: String
    public var monthlyIncome: Decimal?
    public var createdAt: Date

    /// At most one of these is meaningfully set at a time — a photo takes
    /// priority over an emoji, which takes priority over the initials
    /// fallback (see `AvatarView`). Kept as two separate optionals rather
    /// than an enum since SwiftData models can't easily store enums with
    /// associated `Data`/`String` payloads.
    public var avatarImageData: Data? = nil
    public var avatarEmoji: String? = nil

    @Relationship(deleteRule: .cascade, inverse: \LinkedIdentity.account)
    public var linkedIdentities: [LinkedIdentity] = []

    public init(
        id: UUID = UUID(),
        firstName: String = "",
        lastName: String = "",
        email: String,
        mobileNumber: String? = nil,
        age: Int? = nil,
        preferredCurrencyCode: String = Locale.current.currency?.identifier ?? "USD",
        monthlyIncome: Decimal? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.email = email
        self.mobileNumber = mobileNumber
        self.age = age
        self.preferredCurrencyCode = preferredCurrencyCode
        self.monthlyIncome = monthlyIncome
        self.createdAt = createdAt
    }

    public var isOnboarded: Bool {
        !firstName.isEmpty && !lastName.isEmpty
    }
}
