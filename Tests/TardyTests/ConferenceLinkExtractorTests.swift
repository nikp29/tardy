import Testing
import Foundation
@testable import Tardy

@Suite("ConferenceLinkExtractor")
struct ConferenceLinkExtractorTests {

    // MARK: - Video URL extraction

    @Test("extracts Zoom URL from event URL field")
    func zoomFromURL() {
        let result = ConferenceLinkExtractor.extract(
            url: URL(string: "https://zoom.us/j/123456789"),
            notes: nil,
            location: nil
        )
        #expect(result == .videoCall(URL(string: "https://zoom.us/j/123456789")!, provider: "Zoom"))
    }

    @Test("extracts Google Meet from notes")
    func meetFromNotes() {
        let notes = "Join at https://meet.google.com/abc-defg-hij for standup"
        let result = ConferenceLinkExtractor.extract(url: nil, notes: notes, location: nil)
        #expect(result == .videoCall(URL(string: "https://meet.google.com/abc-defg-hij")!, provider: "Google Meet"))
    }

    @Test("extracts Teams URL from location")
    func teamsFromLocation() {
        let location = "https://teams.microsoft.com/l/meetup-join/abc123"
        let result = ConferenceLinkExtractor.extract(url: nil, notes: nil, location: location)
        #expect(result == .videoCall(URL(string: "https://teams.microsoft.com/l/meetup-join/abc123")!, provider: "Teams"))
    }

    @Test("extracts Webex URL")
    func webex() {
        let notes = "Meeting: https://acme.webex.com/meet/jsmith"
        let result = ConferenceLinkExtractor.extract(url: nil, notes: notes, location: nil)
        #expect(result == .videoCall(URL(string: "https://acme.webex.com/meet/jsmith")!, provider: "Webex"))
    }

    @Test("ignores non-conference URL in url field, falls through to notes")
    func nonConferenceURLIgnored() {
        let notes = "Agenda: https://meet.google.com/xyz-abcd-efg"
        let result = ConferenceLinkExtractor.extract(
            url: URL(string: "https://docs.google.com/document/d/abc"),
            notes: notes,
            location: nil
        )
        #expect(result == .videoCall(URL(string: "https://meet.google.com/xyz-abcd-efg")!, provider: "Google Meet"))
    }

    // MARK: - Phone number extraction

    @Test("extracts phone number when no video URL")
    func phoneNumber() {
        let notes = "Dial in: +1-555-123-4567 PIN: 1234"
        let result = ConferenceLinkExtractor.extract(url: nil, notes: notes, location: nil)
        #expect(result == .phone("+1-555-123-4567"))
    }

    @Test("extracts phone with parens format")
    func phoneParens() {
        let notes = "Call (555) 123-4567 to join"
        let result = ConferenceLinkExtractor.extract(url: nil, notes: notes, location: nil)
        #expect(result == .phone("(555) 123-4567"))
    }

    @Test("prefers video URL over phone number")
    func videoOverPhone() {
        let notes = "Join https://zoom.us/j/999 or call +1-555-000-0000"
        let result = ConferenceLinkExtractor.extract(url: nil, notes: notes, location: nil)
        if case .videoCall(let url, _) = result {
            #expect(url.absoluteString == "https://zoom.us/j/999")
        } else {
            Issue.record("Expected videoCall, got \(String(describing: result))")
        }
    }

    // MARK: - Notes fallback

    @Test("returns notes when no video URL or phone")
    func notesFallback() {
        let notes = "Meet in the lobby"
        let result = ConferenceLinkExtractor.extract(url: nil, notes: notes, location: nil)
        #expect(result == .notes("Meet in the lobby"))
    }

    @Test("returns nil when nothing available")
    func nothingAvailable() {
        let result = ConferenceLinkExtractor.extract(url: nil, notes: nil, location: nil)
        #expect(result == nil)
    }
}
