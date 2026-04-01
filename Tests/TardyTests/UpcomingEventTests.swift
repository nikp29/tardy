import Testing
import Foundation
@testable import Tardy

@Suite("UpcomingEvent")
struct UpcomingEventTests {
    @Test("creates from fields")
    func creation() {
        let start = Date()
        let event = UpcomingEvent(
            id: "abc-123",
            title: "Standup",
            startDate: start,
            endDate: start.addingTimeInterval(1800),
            location: "Room 5",
            conferenceURL: URL(string: "https://meet.google.com/abc-defg-hij"),
            phoneNumber: nil,
            notes: nil
        )
        #expect(event.id == "abc-123")
        #expect(event.title == "Standup")
        #expect(event.location == "Room 5")
        #expect(event.conferenceURL?.host?.contains("google") == true)
    }

    @Test("equality is based on id")
    func equality() {
        let now = Date()
        let a = UpcomingEvent(id: "1", title: "A", startDate: now, endDate: now, location: nil, conferenceURL: nil, phoneNumber: nil, notes: nil)
        let b = UpcomingEvent(id: "1", title: "B", startDate: now, endDate: now, location: nil, conferenceURL: nil, phoneNumber: nil, notes: nil)
        #expect(a == b)
    }

    @Test("detects changes via hasChanged")
    func hasChanged() {
        let now = Date()
        let a = UpcomingEvent(id: "1", title: "A", startDate: now, endDate: now, location: nil, conferenceURL: nil, phoneNumber: nil, notes: nil)
        let b = UpcomingEvent(id: "1", title: "A", startDate: now.addingTimeInterval(600), endDate: now, location: nil, conferenceURL: nil, phoneNumber: nil, notes: nil)
        #expect(a.hasChanged(comparedTo: b) == true)
    }
}
