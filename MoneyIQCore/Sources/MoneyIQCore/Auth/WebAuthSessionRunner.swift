import AuthenticationServices

/// Runs an `ASWebAuthenticationSession` and bridges its completion handler
/// into async/await. Shared by every provider that does browser-based OAuth
/// (Google, GitHub) since neither needs a paid Apple Developer Program
/// entitlement — just a custom URL scheme redirect.
@MainActor
final class WebAuthSessionRunner: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    func run(url: URL, callbackURLScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackURLScheme
            ) { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else if let error = error as? ASWebAuthenticationSessionError,
                          error.code == .canceledLogin {
                    continuation.resume(throwing: AuthError.cancelled)
                } else {
                    continuation.resume(throwing: error.map(AuthError.network) ?? AuthError.invalidCallback)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = true
            self.session = session
            session.start()
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(iOS)
        return UIApplicationHelper.keyWindow ?? ASPresentationAnchor()
        #else
        return NSApplicationHelper.keyWindow ?? ASPresentationAnchor()
        #endif
    }
}
