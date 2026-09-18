import Foundation

/// Reads OAuth client settings from the app's Info.plist so the package
/// itself never hardcodes secrets. Each app target supplies these via its
/// own Info.plist (see MoneyIQConfig.xcconfig / README for the exact keys).
public enum OAuthConfig {
    public struct ProviderConfig {
        public let clientID: String
        public let redirectURI: String
    }

    public static var google: ProviderConfig? {
        config(clientIDKey: "MIQ_GOOGLE_CLIENT_ID", redirectKey: "MIQ_GOOGLE_REDIRECT_URI")
    }

    public static var github: ProviderConfig? {
        config(clientIDKey: "MIQ_GITHUB_CLIENT_ID", redirectKey: "MIQ_GITHUB_REDIRECT_URI")
    }

    private static func config(clientIDKey: String, redirectKey: String) -> ProviderConfig? {
        guard
            let clientID = Bundle.main.object(forInfoDictionaryKey: clientIDKey) as? String,
            !clientID.isEmpty,
            let redirectURI = Bundle.main.object(forInfoDictionaryKey: redirectKey) as? String,
            !redirectURI.isEmpty
        else {
            return nil
        }
        return ProviderConfig(clientID: clientID, redirectURI: redirectURI)
    }
}
