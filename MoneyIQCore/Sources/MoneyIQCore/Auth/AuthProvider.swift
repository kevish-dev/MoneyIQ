import Foundation

public struct AuthResult: Equatable, Sendable {
    public let provider: AuthProviderKind
    public let providerUserID: String
    public let email: String
    public let displayName: String?

    public init(provider: AuthProviderKind, providerUserID: String, email: String, displayName: String?) {
        self.provider = provider
        self.providerUserID = providerUserID
        self.email = email
        self.displayName = displayName
    }
}

public enum AuthError: Error, LocalizedError {
    case cancelled
    case missingConfiguration(String)
    case invalidCallback
    case network(underlying: Error)
    case unavailable(reason: String)

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Sign-in was cancelled."
        case .missingConfiguration(let detail):
            return "Sign-in isn't configured yet: \(detail)"
        case .invalidCallback:
            return "Sign-in failed: the provider returned an unexpected response."
        case .network(let underlying):
            return "Sign-in failed: \(underlying.localizedDescription)"
        case .unavailable(let reason):
            return reason
        }
    }
}

@MainActor
public protocol AuthProvider {
    var kind: AuthProviderKind { get }
    /// Whether this provider can actually be used right now (e.g. Apple's
    /// requires the paid Developer Program entitlement, Google/GitHub need
    /// OAuth client IDs configured).
    var isAvailable: Bool { get }
    func signIn() async throws -> AuthResult
}
