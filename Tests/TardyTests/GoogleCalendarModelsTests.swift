import Testing
import Foundation
@testable import Tardy

@Suite("GoogleCalendarModels")
struct GoogleCalendarModelsTests {
    @Test("decodes a timed event with conferenceData and attendees")
    func decodesTimedEvent() throws {
        let json = """
        {
          "items": [{
            "id": "evt1",
            "iCalUID": "uid-1@google.com",
            "status": "confirmed",
            "summary": "Standup",
            "location": "HQ",
            "description": "notes here",
            "hangoutLink": "https://meet.google.com/abc-defg-hij",
            "start": {"dateTime": "2026-05-25T10:00:00-04:00", "timeZone": "America/New_York"},
            "end": {"dateTime": "2026-05-25T10:30:00-04:00", "timeZone": "America/New_York"},
            "conferenceData": {"entryPoints": [
              {"entryPointType": "video", "uri": "https://meet.google.com/abc-defg-hij"},
              {"entryPointType": "phone", "uri": "tel:+1-555-555-5555", "label": "+1 555-555-5555"}
            ]},
            "attendees": [{"self": true, "responseStatus": "accepted"}]
          }],
          "nextSyncToken": "TOKEN123"
        }
        """.data(using: .utf8)!
        let resp = try GoogleCalendarModels.decoder.decode(GoogleEventsResponse.self, from: json)
        #expect(resp.nextSyncToken == "TOKEN123")
        let e = try #require(resp.items.first)
        #expect(e.iCalUID == "uid-1@google.com")
        #expect(e.start.dateTime != nil)
        #expect(e.start.date == nil)
        #expect(e.conferenceData?.entryPoints?.first?.entryPointType == "video")
        #expect(e.attendees?.first?.selfAttendee == true)
    }

    @Test("decodes an all-day event (date, no dateTime)")
    func decodesAllDay() throws {
        let json = """
        {"items":[{"id":"d1","status":"confirmed","summary":"Holiday",
          "start":{"date":"2026-05-25"},"end":{"date":"2026-05-26"}}]}
        """.data(using: .utf8)!
        let resp = try GoogleCalendarModels.decoder.decode(GoogleEventsResponse.self, from: json)
        let e = try #require(resp.items.first)
        #expect(e.start.dateTime == nil)
        #expect(e.start.date == "2026-05-25")
    }

    @Test("decodes calendar list")
    func decodesCalendarList() throws {
        let json = """
        {"items":[{"id":"primary"},{"id":"team@group.calendar.google.com"}]}
        """.data(using: .utf8)!
        let resp = try GoogleCalendarModels.decoder.decode(GoogleCalendarListResponse.self, from: json)
        #expect(resp.items.map(\.id) == ["primary", "team@group.calendar.google.com"])
    }
}
