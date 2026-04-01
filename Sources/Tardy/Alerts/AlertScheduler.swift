import Foundation

final class AlertScheduler {
    private let settings: SettingsManager
    private let onAlert: (UpcomingEvent) -> Void
    private var timers: [String: Timer] = [:]
    private var knownEvents: [String: UpcomingEvent] = [:]

    static let gracePeriod: TimeInterval = 5.0

    var scheduledEventIDs: Set<String> {
        Set(timers.keys)
    }

    init(settings: SettingsManager, onAlert: @escaping (UpcomingEvent) -> Void) {
        self.settings = settings
        self.onAlert = onAlert
    }

    func updateEvents(_ events: [UpcomingEvent]) {
        // Use last-wins to handle duplicate event IDs from EventKit
        let newEventsByID = Dictionary(events.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })

        // Cancel timers for removed events
        for id in timers.keys where newEventsByID[id] == nil {
            timers[id]?.invalidate()
            timers.removeValue(forKey: id)
        }

        // Schedule or reschedule timers
        for event in events {
            if let existing = knownEvents[event.id], !existing.hasChanged(comparedTo: event) {
                continue
            }
            scheduleTimer(for: event)
        }

        knownEvents = newEventsByID
    }

    func snooze(event: UpcomingEvent, duration: TimeInterval = 120) {
        let timer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.onAlert(event)
        }
        timers["snooze-\(event.id)-\(Date().timeIntervalSince1970)"] = timer
    }

    func cancelAll() {
        timers.values.forEach { $0.invalidate() }
        timers.removeAll()
        knownEvents.removeAll()
    }

    private func scheduleTimer(for event: UpcomingEvent) {
        timers[event.id]?.invalidate()

        let now = Date()
        let leadTime = TimeInterval(settings.leadTimeSeconds)
        let fireDate = event.startDate.addingTimeInterval(-leadTime)
        let timeSinceStart = now.timeIntervalSince(event.startDate)

        // Event already started beyond grace period — skip
        if timeSinceStart > Self.gracePeriod {
            timers.removeValue(forKey: event.id)
            return
        }

        let delay = fireDate.timeIntervalSince(now)

        if delay <= 0 {
            // Fire immediately (fire date already passed but event within grace period or not started)
            let timer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: false) { [weak self] _ in
                self?.onAlert(event)
                self?.timers.removeValue(forKey: event.id)
            }
            timers[event.id] = timer
        } else {
            let timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                self?.onAlert(event)
                self?.timers.removeValue(forKey: event.id)
            }
            timers[event.id] = timer
        }
    }
}
