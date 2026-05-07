import Foundation

final class AlertScheduler {
    private let settings: SettingsManager
    private let onAlert: (UpcomingEvent) -> Void
    private var timers: [String: Timer] = [:]
    private var knownEvents: [String: UpcomingEvent] = [:]

    var scheduledEventIDs: Set<String> {
        Set(timers.keys)
    }

    init(settings: SettingsManager, onAlert: @escaping (UpcomingEvent) -> Void) {
        self.settings = settings
        self.onAlert = onAlert
    }

    func updateEvents(_ events: [UpcomingEvent], forceReschedule: Bool = false) {
        // Use last-wins to handle duplicate event IDs from EventKit
        let newEventsByID = Dictionary(events.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })

        // Cancel timers for removed events
        for id in timers.keys where newEventsByID[id] == nil {
            timers[id]?.invalidate()
            timers.removeValue(forKey: id)
        }

        // Schedule or reschedule timers
        for event in events {
            if !forceReschedule,
               let existing = knownEvents[event.id],
               !existing.hasChanged(comparedTo: event) {
                continue
            }
            scheduleTimer(for: event)
        }

        knownEvents = newEventsByID
    }

    /// Test-only accessor for verifying scheduled timer identity.
    func timerForTesting(eventID: String) -> Timer? {
        timers[eventID]
    }

    func snooze(event: UpcomingEvent, duration: TimeInterval = 120) {
        let timer = makeMainRunLoopTimer(after: duration) { [weak self] in
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

        // If the meeting has already ended, drop the alert entirely. We still
        // fire for events that are ongoing (started but not yet ended), e.g.
        // when the app launches mid-meeting or wakes from sleep mid-meeting.
        if Date() >= event.endDate {
            timers.removeValue(forKey: event.id)
            return
        }

        let now = Date()
        let leadTime = TimeInterval(settings.leadTimeSeconds)
        let fireDate = event.startDate.addingTimeInterval(-leadTime)
        let delay = max(0.01, fireDate.timeIntervalSince(now))

        let timer = makeMainRunLoopTimer(after: delay) { [weak self] in
            guard let self else { return }
            // Re-check at fire time. The timer may have been delayed (sleep,
            // blocked run loop, etc.) past the meeting's endDate; in that
            // case the alert is no longer useful — suppress it.
            if Date() < event.endDate {
                self.onAlert(event)
            }
            self.timers.removeValue(forKey: event.id)
        }
        timers[event.id] = timer
    }

    /// Creates a one-shot Timer attached to RunLoop.main in `.common` mode.
    ///
    /// Why this matters:
    /// 1. `Timer.scheduledTimer(...)` attaches to the *current* thread's run loop.
    ///    On a background thread there is no running run loop, so the timer
    ///    silently never fires. This caused intermittent missed notifications.
    /// 2. The default mode (`.default`) is *not* active while AppKit modal tracking
    ///    is in progress (e.g. while the user has the menu bar menu open).
    ///    `.common` is the meta-mode that includes `.default`, `.eventTracking`,
    ///    and `.modalPanel`, so the timer fires regardless of UI state.
    private func makeMainRunLoopTimer(
        after delay: TimeInterval,
        action: @escaping () -> Void
    ) -> Timer {
        let timer = Timer(timeInterval: delay, repeats: false) { _ in action() }
        // tolerance helps the OS coalesce timers; for a one-minute lead time,
        // 100ms tolerance is imperceptible and reduces wake load.
        timer.tolerance = min(0.1, delay / 10)
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }
}
