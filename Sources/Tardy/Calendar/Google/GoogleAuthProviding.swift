import AppKit
import Foundation

enum GoogleAuthError: Error, Equatable {
    case needsReauth
    case cancelled
    case notConfigured
}

/// Abstraction over Google auth so providers and tests don't depend on the SDK.
/// The concrete `GoogleSignInAuthService` (which imports GoogleSignIn) conforms
/// to this; tests substitute a fake.
protocol GoogleAuthProviding: AnyObject {
    var isSignedIn: Bool { get }
    var accountEmail: String? { get }
    /// Restore a prior session at launch (no UI). Safe to call when signed out.
    func restorePreviousSignIn() async
    /// Interactive sign-in. `anchor` is the presenting window for the consent UI.
    func signIn(presenting anchor: NSWindow) async throws
    /// A currently-valid access token, refreshing if needed.
    /// Throws `.needsReauth` if the session can't be refreshed.
    func validAccessToken() async throws -> String
    func signOut()
}
