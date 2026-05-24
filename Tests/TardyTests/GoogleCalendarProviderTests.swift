import Testing
import Foundation
import AppKit
@testable import Tardy

final class FakeAuth: GoogleAuthProviding {
    var signedIn: Bool
    init(signedIn: Bool) { self.signedIn = signedIn }
    var isSignedIn: Bool { signedIn }
    var accountEmail: String? { signedIn ? "me@gmail.com" : nil }
    func restorePreviousSignIn() async {}
    func signIn(presenting anchor: NSWindow) async throws {}
    func validAccessToken() async throws -> String {
        if signedIn { return "token" }
        throw GoogleAuthError.needsReauth
    }
    func signOut() { signedIn = false }
}

struct StubHTTP: HTTPFetching {
    let routes: [(match: (URL) -> Bool, body: String)]
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let url = request.url!
        let body = routes.first { $0.match(url) }?.body ?? "{}"
        let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (body.data(using: .utf8)!, resp)
    }
}

@Suite("GoogleCalendarProvider")
struct GoogleCalendarProviderTests {
    @Test("returns empty and is disabled when signed out")
    func emptyWhenSignedOut() async {
        let provider = GoogleCalendarProvider(auth: FakeAuth(signedIn: false), http: StubHTTP(routes: []))
        provider.setEnabled(true)
        #expect(provider.isEnabled == false) // gated on sign-in
        let out = await provider.fetchEvents(start: Date(), end: Date().addingTimeInterval(3600))
        #expect(out.isEmpty)
    }

    @Test("fetches, maps, and filters events across calendars")
    func fetchesAndMaps() async {
        let calList = #"{"items":[{"id":"primary"}]}"#
        let events = """
        {"items":[
          {"id":"e1","status":"confirmed","summary":"Standup",
           "start":{"dateTime":"2026-05-25T10:00:00Z"},"end":{"dateTime":"2026-05-25T10:30:00Z"},
           "hangoutLink":"https://meet.google.com/abc"},
          {"id":"a1","status":"confirmed","summary":"Holiday","start":{"date":"2026-05-25"},"end":{"date":"2026-05-26"}}
        ]}
        """
        let http = StubHTTP(routes: [
            (match: { $0.path.hasSuffix("/calendarList") }, body: calList),
            (match: { $0.path.contains("/events") }, body: events),
        ])
        let provider = GoogleCalendarProvider(auth: FakeAuth(signedIn: true), http: http)
        provider.setEnabled(true)
        #expect(provider.isEnabled == true)
        // Window brackets the event's 2026-05-25T10:00:00Z start so the
        // provider's in-window prune keeps it.
        let out = await provider.fetchEvents(
            start: Date(timeIntervalSince1970: 1_779_699_600), // 2026-05-25T09:00:00Z
            end: Date(timeIntervalSince1970: 1_779_710_400))   // 2026-05-25T12:00:00Z
        #expect(out.map(\.id) == ["e1"]) // all-day filtered out
        #expect(out.first?.source == .google)
    }
}
