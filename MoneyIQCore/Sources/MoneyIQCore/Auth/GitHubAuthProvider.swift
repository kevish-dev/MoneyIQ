import Foundation

@MainActor
public final class GitHubAuthProvider: AuthProvider {
    public let kind: AuthProviderKind = .github
    private let runner = WebAuthSessionRunner()

    public init() {}

    public var isAvailable: Bool { OAuthConfig.github != nil }

    /// GitHub OAuth Apps support PKCE (no client secret needed in the native
    /// app) as long as "Enable PKCE" style support is available for your app;
    /// see SETUP notes. This deliberately avoids embedding a client secret,
    /// which would otherwise be extractable from the app binary.
    public func signIn() async throws -> AuthResult {
        guard let config = OAuthConfig.github else {
            throw AuthError.missingConfiguration("Add MIQ_GITHUB_CLIENT_ID / MIQ_GITHUB_REDIRECT_URI to Info.plist.")
        }
        guard let redirectComponents = URLComponents(string: config.redirectURI),
              let scheme = redirectComponents.scheme else {
            throw AuthError.missingConfiguration("MIQ_GITHUB_REDIRECT_URI must be a valid URL with a custom scheme.")
        }

        let verifier = PKCE.makeVerifier()
        let challenge = PKCE.challenge(for: verifier)
        let state = UUID().uuidString

        var components = URLComponents(string: "https://github.com/login/oauth/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: config.clientID),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI),
            URLQueryItem(name: "scope", value: "read:user user:email"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]

        let callbackURL = try await runner.run(url: components.url!, callbackURLScheme: scheme)
        let callbackItems = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems
        guard let code = callbackItems?.first(where: { $0.name == "code" })?.value,
              callbackItems?.first(where: { $0.name == "state" })?.value == state else {
            throw AuthError.invalidCallback
        }

        let accessToken = try await exchangeCode(code, verifier: verifier, config: config)
        let profile = try await fetchProfile(accessToken: accessToken)
        let email = try await fetchPrimaryEmail(accessToken: accessToken) ?? profile.email ?? ""

        KeychainStore.set(accessToken, forKey: "github.accessToken")

        return AuthResult(
            provider: .github,
            providerUserID: String(profile.id),
            email: email,
            displayName: profile.name ?? profile.login
        )
    }

    private struct TokenResponse: Decodable {
        let accessToken: String
        enum CodingKeys: String, CodingKey { case accessToken = "access_token" }
    }

    private func exchangeCode(_ code: String, verifier: String, config: OAuthConfig.ProviderConfig) async throws -> String {
        var request = URLRequest(url: URL(string: "https://github.com/login/oauth/access_token")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyParams = [
            "client_id": config.clientID,
            "code": code,
            "code_verifier": verifier,
            "redirect_uri": config.redirectURI
        ]
        request.httpBody = bodyParams
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(TokenResponse.self, from: data).accessToken
    }

    private struct GitHubProfile: Decodable {
        let id: Int
        let login: String
        let name: String?
        let email: String?
    }

    private func fetchProfile(accessToken: String) async throws -> GitHubProfile {
        var request = URLRequest(url: URL(string: "https://api.github.com/user")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(GitHubProfile.self, from: data)
    }

    private struct GitHubEmail: Decodable {
        let email: String
        let primary: Bool
        let verified: Bool
    }

    private func fetchPrimaryEmail(accessToken: String) async throws -> String? {
        var request = URLRequest(url: URL(string: "https://api.github.com/user/emails")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, _) = try await URLSession.shared.data(for: request)
        let emails = try JSONDecoder().decode([GitHubEmail].self, from: data)
        return emails.first(where: { $0.primary && $0.verified })?.email ?? emails.first?.email
    }
}
