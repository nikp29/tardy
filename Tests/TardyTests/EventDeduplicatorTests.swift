import Testing
import Foundation
@testable import Tardy

@Suite("EventDeduplicator")
struct EventDeduplicatorTests {
    private func ev(
        id: String, title: String = "Standup",
        start: Date = Date(timeIntervalSince1970: 1_000_000),
        source: EventSourceKind = .eventKit, iCalUID: String? = nil,
        conferenceURL: URL? = nil
    ) -> UpcomingEvent {
        UpcomingEvent(id: id, title: title, startDate: start,
            endDate: start.addingTimeInterval(1800), location: nil,
            conferenceURL: conferenceURL, phoneNumber: nil, notes: nil,
            source: source, iCalUID: iCalUID)
    }

    @Test("merges disjoint events and sorts by start")
    func mergesDisjoint() {
        let a = ev(id: "a", start: Date(timeIntervalSince1970: 200))
        let b = ev(id: "b", start: Date(timeIntervalSince1970: 100))
        let out = EventDeduplicator.merge([[a], [b]])
        #expect(out.map(\.id) == ["b", "a"])
    }

    @Test("dedupes by matching iCalUID, preferring Google")
    func dedupesByICalUID() {
        let ek = ev(id: "ek", source: .eventKit, iCalUID: "uid-1")
        let g = ev(id: "g", source: .google, iCalUID: "uid-1",
                   conferenceURL: URL(string: "https://meet.google.com/xyz"))
        let out = EventDeduplicator.merge([[ek], [g]])
        #expect(out.count == 1)
        #expect(out.first?.source == .google)
        #expect(out.first?.conferenceURL?.absoluteString == "https://meet.google.com/xyz")
    }

    @Test("dedupes by (start, normalized title) when no iCalUID")
    func dedupesByStartTitle() {
        let start = Date(timeIntervalSince1970: 500)
        let ek = ev(id: "ek", title: "Team Sync ", start: start, source: .eventKit)
        let g = ev(id: "g", title: "team sync", start: start, source: .google)
        let out = EventDeduplicator.merge([[ek], [g]])
        #expect(out.count == 1)
        #expect(out.first?.source == .google)
    }

    @Test("does not dedupe different events at same time")
    func keepsDistinct() {
        let start = Date(timeIntervalSince1970: 500)
        let a = ev(id: "a", title: "Sync", start: start)
        let b = ev(id: "b", title: "1:1", start: start)
        let out = EventDeduplicator.merge([[a], [b]])
        #expect(out.count == 2)
    }
}
