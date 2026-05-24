import Foundation

enum EventDeduplicator {
    static func merge(_ groups: [[UpcomingEvent]]) -> [UpcomingEvent] {
        groups.flatMap { $0 } // replaced in Task 5
    }
}
