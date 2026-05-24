import Foundation

/// Public OAuth client ID for the Apple-platform client. Not a secret:
/// it appears in the consent URL and is safe to ship (PKCE secures the flow).
/// Project: tardy-app-55642 (iOS OAuth client, bundle com.nikp29.tardy).
enum GoogleOAuthConfig {
    static let clientID = "321723434454-cdfv8p0ue662dgms5cbq35gm1n6fagqo.apps.googleusercontent.com"
    static let scopes = ["https://www.googleapis.com/auth/calendar.readonly"]

    /// Reverse-client-ID URL scheme used as the OAuth redirect.
    static var redirectScheme: String {
        "com.googleusercontent.apps." + clientID
            .replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
    }
}
