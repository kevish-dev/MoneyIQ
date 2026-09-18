import Foundation

@MainActor
public final class GoogleAuthProvider: AuthProvider {
    public let kind: AuthProviderKind = .google
    private let runner = WebAuthSessionRunner()

    public init() {}

    public var isAvailable: Bool { OAuthConfig.google != nil }

    public func signIn() async throws -> AuthResult {
        guard let config = OAuthConfig.google else {
            throw AuthError.missingConfiguration("Add MIQ_GOOGLE_CLIENT_ID / MIQ_GOOGLE_REDIRECT_URI to Info.plist.")
        }
        guard let redirectComponents = URLComponents(string: config.redirectURI),
              let scheme = redirectComponents.scheme else {
            throw AuthError.missingConfiguration("MIQ_GOOGLE_REDIRECT_URI must be a valid URL with a custom scheme.")
        }

        let verifier = PKCE.makeVerifier()
        let challenge = PKCE.challenge(for: verifier)

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: config.clientID),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]

        let callbackURL = try await runner.run(url: components.url!, callbackURLScheme: scheme)
        guard let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value else {
            throw AuthError.invalidCallback
        }

        let tokens = try await exchangeCode(code, verifier: verifier, config: config)
        let profile = try await fetchProfile(accessToken: tokens.accessToken)

        KeychainStore.set(tokens.accessToken, forKey: "google.accessToken")
        if let refreshToken = tokens.refreshToken {
            KeychainStore.set(refreshToken, forKey: "google.refreshToken")
        }

        return AuthResult(
            provider: .google,
            providerUserID: profile.sub,
            email: profile.email,
            displayName: profile.name
        )
    }

    private struct TokenResponse: Decodable {
        let accessToken: String
        let refreshToken: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
        }
    }

    private func exchangeCode(_ code: String, verifier: String, config: OAuthConfig.ProviderConfig) async throws -> TokenResponse {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyParams = [
            "client_id": config.clientID,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": config.redirectURI
        ]
        request.httpBody = bodyParams
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    private struct GoogleProfile: Decodable {
        let sub: String
        let email: String
        let name: String?
    }

    private func fetchProfile(accessToken: String) async throws -> GoogleProfile {
        var request = URLRequest(url: URL(string: "https://openidconnect.googleapis.com/v1/userinfo")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(GoogleProfile.self, from: data)
    }
}
