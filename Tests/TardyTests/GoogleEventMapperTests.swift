import Testing
import Foundation
@testable import Tardy

@Suite("GoogleEventMapper")
struct GoogleEventMapperTests {
    private func decode(_ json: String) throws -> GoogleEvent {
        let wrapped = "{\"items\":[\(json)]}".data(using: .utf8)!
        return try GoogleCalendarModels.decoder.decode(GoogleEventsResponse.self, from: wrapped).items[0]
    }

    @Test("maps a timed event and prefers video entryPoint for conference URL")
    func mapsTimedEvent() throws {
        let e = try decode("""
        {"id":"e1","iCalUID":"uid-1","status":"confirmed","summary":"Standup",
         "start":{"dateTime":"2026-05-25T10:00:00Z"},"end":{"dateTime":"2026-05-25T10:30:00Z"},
         "hangoutLink":"https://meet.google.com/zzz",
         "conferenceData":{"entryPoints":[{"entryPointType":"video","uri":"https://meet.google.com/abc"}]}}
        """)
        let m = try #require(GoogleEventMapper.map(e))
        #expect(m.id == "e1")
        #expect(m.title == "Standup")
        #expect(m.source == .google)
        #expect(m.iCalUID == "uid-1")
        #expect(m.conferenceURL?.absoluteString == "https://meet.google.com/abc")
    }

    @Test("falls back to hangoutLink when no video entryPoint")
    func fallsBackToHangoutLink() throws {
        let e = try decode("""
        {"id":"e2","status":"confirmed","summary":"Sync",
         "start":{"dateTime":"2026-05-25T10:00:00Z"},"end":{"dateTime":"2026-05-25T10:30:00Z"},
         "hangoutLink":"https://meet.google.com/zzz"}
        """)
        let m = try #require(GoogleEventMapper.map(e))
        #expect(m.conferenceURL?.absoluteString == "https://meet.google.com/zzz")
    }

    @Test("extracts phone entryPoint when no video")
    func extractsPhone() throws {
        let e = try decode("""
        {"id":"e3","status":"confirmed","summary":"Call",
         "start":{"dateTime":"2026-05-25T10:00:00Z"},"end":{"dateTime":"2026-05-25T10:30:00Z"},
         "conferenceData":{"entryPoints":[{"entryPointType":"phone","uri":"tel:+15555555555","label":"+1 555-555-5555"}]}}
        """)
        let m = try #require(GoogleEventMapper.map(e))
        #expect(m.conferenceURL == nil)
        #expect(m.phoneNumber == "+1 555-555-5555")
    }

    @Test("returns nil for all-day, cancelled, and declined events")
    func filtersOut() throws {
        let allDay = try decode("""
        {"id":"a","status":"confirmed","summary":"Holiday","start":{"date":"2026-05-25"},"end":{"date":"2026-05-26"}}
        """)
        let cancelled = try decode("""
        {"id":"c","status":"cancelled","summary":"X","start":{"dateTime":"2026-05-25T10:00:00Z"},"end":{"dateTime":"2026-05-25T10:30:00Z"}}
        """)
        let declined = try decode("""
        {"id":"d","status":"confirmed","summary":"Y","start":{"dateTime":"2026-05-25T10:00:00Z"},"end":{"dateTime":"2026-05-25T10:30:00Z"},
         "attendees":[{"self":true,"responseStatus":"declined"}]}
        """)
        #expect(GoogleEventMapper.map(allDay) == nil)
        #expect(GoogleEventMapper.map(cancelled) == nil)
        #expect(GoogleEventMapper.map(declined) == nil)
    }
}
