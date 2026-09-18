import Foundation
import SwiftData

public enum AuthProviderKind: String, Codable, CaseIterable, Sendable {
    case apple
    case google
    case github
}

/// One provider-specific credential linked to a `UserAccount`. A single
/// account can accumulate several of these (e.g. sign in with Google first,
/// then link GitHub later) since both share the same email.
@Model
public final class LinkedIdentity {
    @Attribute(.unique) public var id: UUID
    public var provider: AuthProviderKind
    public var providerUserID: String
    public var email: String
    public var displayName: String?
    public var linkedAt: Date

    public var account: UserAccount?

    public init(
        id: UUID = UUID(),
        provider: AuthProviderKind,
        providerUserID: String,
        email: String,
        displayName: String? = nil,
        linkedAt: Date = .now
    ) {
        self.id = id
        self.provider = provider
        self.providerUserID = providerUserID
        self.email = email
        self.displayName = displayName
        self.linkedAt = linkedAt
    }
}
