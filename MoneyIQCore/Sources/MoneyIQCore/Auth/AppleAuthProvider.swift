import AuthenticationServices

/// Sign in with Apple. The logic is fully implemented, but `isAvailable`
/// stays `false` (and the UI hides the button) until the app has the
/// "Sign in with Apple" capability, which needs the paid Apple Developer
/// Program (see PRD dependency table). Flip `Self.isEnabledByBuild` once
/// enrolled and the capability is added in Xcode.
@MainActor
public final class AppleAuthProvider: NSObject, AuthProvider {
    public let kind: AuthProviderKind = .apple

    /// Flip this to `true` once the Apple Developer Program membership is
    /// active and the "Sign in with Apple" capability has been added to both
    /// app targets in Xcode's Signing & Capabilities tab.
    public static var isEnabledByBuild = false

    public var isAvailable: Bool { Self.isEnabledByBuild }

    public override init() {
        super.init()
    }

    public func signIn() async throws -> AuthResult {
        guard isAvailable else {
            throw AuthError.unavailable(reason: "Sign in with Apple requires the paid Apple Developer Program membership. See SETUP.md.")
        }

        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]

        return try await withCheckedThrowingContinuation { continuation in
            let delegate = AppleSignInDelegate(continuation: continuation)
            self.activeDelegate = delegate
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = delegate
            controller.presentationContextProvider = delegate
            controller.performRequests()
        }
    }

    // Keeps the delegate alive for the duration of the async call.
    private var activeDelegate: AppleSignInDelegate?
}

private final class AppleSignInDelegate: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private let continuation: CheckedContinuation<AuthResult, Error>

    init(continuation: CheckedContinuation<AuthResult, Error>) {
        self.continuation = continuation
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            continuation.resume(throwing: AuthError.invalidCallback)
            return
        }
        let email = credential.email ?? "\(credential.user)@privaterelay.appleid.com"
        let displayName = [credential.fullName?.givenName, credential.fullName?.familyName]
            .compactMap { $0 }
            .joined(separator: " ")

        continuation.resume(returning: AuthResult(
            provider: .apple,
            providerUserID: credential.user,
            email: email,
            displayName: displayName.isEmpty ? nil : displayName
        ))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        if let authError = error as? ASAuthorizationError, authError.code == .canceled {
            continuation.resume(throwing: AuthError.cancelled)
        } else {
            continuation.resume(throwing: AuthError.network(underlying: error))
        }
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        #if os(iOS)
        return UIApplicationHelper.keyWindow ?? ASPresentationAnchor()
        #else
        return NSApplicationHelper.keyWindow ?? ASPresentationAnchor()
        #endif
    }
}
