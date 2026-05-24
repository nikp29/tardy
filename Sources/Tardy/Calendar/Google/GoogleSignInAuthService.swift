import AppKit
import Foundation
import GoogleSignIn

/// Concrete `GoogleAuthProviding` backed by the GoogleSignIn SDK. The SDK owns
/// the OAuth/PKCE flow, Keychain token storage, and refresh.
final class GoogleSignInAuthService: GoogleAuthProviding {
    static let shared = GoogleSignInAuthService()

    private var signIn: GIDSignIn { GIDSignIn.sharedInstance }

    init() {
        signIn.configuration = GIDConfiguration(clientID: GoogleOAuthConfig.clientID)
    }

    var isSignedIn: Bool { signIn.currentUser != nil }
    var accountEmail: String? { signIn.currentUser?.profile?.email }

    func restorePreviousSignIn() async {
        guard signIn.hasPreviousSignIn() else { return }
        _ = try? await signIn.restorePreviousSignIn()
    }

    @MainActor
    func signIn(presenting anchor: NSWindow) async throws {
        do {
            try await signIn.signIn(
                withPresenting: anchor,
                hint: nil,
                additionalScopes: GoogleOAuthConfig.scopes
            )
        } catch {
            if (error as NSError).code == GIDSignInError.canceled.rawValue {
                throw GoogleAuthError.cancelled
            }
            throw error
        }
    }

    func validAccessToken() async throws -> String {
        guard let user = signIn.currentUser else { throw GoogleAuthError.needsReauth }
        do {
            let refreshed = try await user.refreshTokensIfNeeded()
            return refreshed.accessToken.tokenString
        } catch {
            throw GoogleAuthError.needsReauth
        }
    }

    func signOut() {
        signIn.signOut()
    }
}
