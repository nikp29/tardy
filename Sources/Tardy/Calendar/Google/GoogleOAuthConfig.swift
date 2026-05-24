import Foundation

/// Public OAuth client ID for the Apple-platform client. Not a secret:
/// it appears in the consent URL and is safe to ship (PKCE secures the flow).
///
/// NOTE: `clientID` is a placeholder until the OAuth client is created in the
/// Google Cloud Console (plan Task 6). Replace it there, and mirror the value
/// + reverse-client-ID scheme into `scripts/build-app.sh` (plan Task 7).
enum GoogleOAuthConfig {
    static let clientID = "REPLACE_WITH_CLIENT_ID.apps.googleusercontent.com"
    static let scopes = ["https://www.googleapis.com/auth/calendar.readonly"]

    /// Reverse-client-ID URL scheme used as the OAuth redirect.
    static var redirectScheme: String {
        "com.googleusercontent.apps." + clientID
            .replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
    }
}
