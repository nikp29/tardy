import Foundation

/// Static OAuth configuration. The client ID is intentionally NOT stored here:
/// it is supplied at build time from `.env` (gitignored) into the app's
/// Info.plist (`GIDClientID`), which GoogleSignIn reads at runtime. The client
/// ID is a public identifier — it ships in the app bundle and appears in OAuth
/// URLs — not a secret; keeping it in `.env` just keeps it out of source.
enum GoogleOAuthConfig {
    /// Read-only Calendar scope requested in addition to GoogleSignIn's defaults.
    static let scopes = ["https://www.googleapis.com/auth/calendar.readonly"]
}
