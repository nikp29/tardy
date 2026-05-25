import Foundation

enum EventDeduplicator {
    /// Merge events from multiple providers, removing duplicates that represent
    /// the same meeting. When duplicates are found, prefer the Google copy
    /// (richer structured conference data). Result is sorted by start date.
    static func merge(_ groups: [[UpcomingEvent]]) -> [UpcomingEvent] {
        var byKey: [String: UpcomingEvent] = [:]
        var order: [String] = []

        for event in groups.flatMap({ $0 }) {
            let key = dedupKey(for: event)
            if let existing = byKey[key] {
                byKey[key] = prefer(existing, event)
            } else {
                byKey[key] = event
                order.append(key)
            }
        }

        return order.compactMap { byKey[$0] }
            .sorted { $0.startDate < $1.startDate }
    }

    private static func dedupKey(for e: UpcomingEvent) -> String {
        if let uid = e.iCalUID, !uid.isEmpty { return "uid:\(uid)" }
        let title = e.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "st:\(e.startDate.timeIntervalSince1970):\(title)"
    }

    private static func prefer(_ a: UpcomingEvent, _ b: UpcomingEvent) -> UpcomingEvent {
        if a.source == .google { return a }
        if b.source == .google { return b }
        return a
    }
}
