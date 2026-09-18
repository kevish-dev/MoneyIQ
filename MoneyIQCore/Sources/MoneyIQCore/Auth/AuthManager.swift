import Foundation
import SwiftData
import Observation

@MainActor
@Observable
public final class AuthManager {
    public private(set) var currentAccount: UserAccount?
    public private(set) var isSigningIn = false
    public private(set) var lastError: AuthError?

    private let modelContext: ModelContext
    private let providers: [AuthProviderKind: AuthProvider]
    private static let currentAccountIDKey = "com.moneyiq.currentAccountID"

    public init(modelContext: ModelContext, providers: [AuthProviderKind: AuthProvider]? = nil) {
        self.modelContext = modelContext
        self.providers = providers ?? [
            .apple: AppleAuthProvider(),
            .google: GoogleAuthProvider(),
            .github: GitHubAuthProvider()
        ]
        restoreSession()
    }

    public func isAvailable(_ kind: AuthProviderKind) -> Bool {
        providers[kind]?.isAvailable ?? false
    }

    public func signIn(with kind: AuthProviderKind) async {
        guard let provider = providers[kind] else { return }
        isSigningIn = true
        lastError = nil
        defer { isSigningIn = false }

        do {
            let result = try await provider.signIn()
            let account = try resolveAccount(for: result)
            currentAccount = account
            UserDefaults.standard.set(account.id.uuidString, forKey: Self.currentAccountIDKey)
        } catch let error as AuthError {
            lastError = error
        } catch {
            lastError = .network(underlying: error)
        }
    }

    public func signOut() {
        currentAccount = nil
        UserDefaults.standard.removeObject(forKey: Self.currentAccountIDKey)
    }

    private func restoreSession() {
        guard
            let idString = UserDefaults.standard.string(forKey: Self.currentAccountIDKey),
            let id = UUID(uuidString: idString)
        else { return }

        let descriptor = FetchDescriptor<UserAccount>(predicate: #Predicate { $0.id == id })
        currentAccount = try? modelContext.fetch(descriptor).first
    }

    /// Unifies identity across providers: a new sign-in links to an existing
    /// account whose email already matches, rather than creating a duplicate.
    private func resolveAccount(for result: AuthResult) throws -> UserAccount {
        let providerKind = result.provider
        let providerUserID = result.providerUserID

        let identityDescriptor = FetchDescriptor<LinkedIdentity>(
            predicate: #Predicate { $0.provider == providerKind && $0.providerUserID == providerUserID }
        )
        if let existingIdentity = try modelContext.fetch(identityDescriptor).first,
           let account = existingIdentity.account {
            return account
        }

        let email = result.email
        let accountDescriptor = FetchDescriptor<UserAccount>(predicate: #Predicate { $0.email == email })
        let account: UserAccount
        if let existingAccount = try modelContext.fetch(accountDescriptor).first {
            account = existingAccount
        } else {
            let nameParts = (result.displayName ?? "").split(separator: " ", maxSplits: 1).map(String.init)
            account = UserAccount(
                firstName: nameParts.first ?? "",
                lastName: nameParts.count > 1 ? nameParts[1] : "",
                email: email
            )
            modelContext.insert(account)
        }

        let identity = LinkedIdentity(
            provider: result.provider,
            providerUserID: result.providerUserID,
            email: result.email,
            displayName: result.displayName
        )
        identity.account = account
        modelContext.insert(identity)
        try modelContext.save()

        return account
    }
}
