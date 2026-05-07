import AppKit
import EventKit
import Foundation

protocol CalendarServiceDelegate: AnyObject {
    func calendarService(
        _ service: CalendarService,
        didUpdateEvents events: [UpcomingEvent],
        forceReschedule: Bool
    )
}

final class CalendarService {
    private let store = EKEventStore()
    private var pollTimer: Timer?
    private var midnightTimer: Timer?
    private var currentEvents: [UpcomingEvent] = []

    weak var delegate: CalendarServiceDelegate?

    func start() {
        requestAccess { [weak self] granted in
            guard granted, let self else {
                print("Tardy: Calendar access denied")
                return
            }
            self.subscribeToChanges()
            self.startPolling()
            self.scheduleMidnightRollover()
            self.fetchAndNotify()
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        midnightTimer?.invalidate()
        midnightTimer = nil
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Access

    private func requestAccess(completion: @escaping (Bool) -> Void) {
        if #available(macOS 14.0, *) {
            store.requestFullAccessToEvents { granted, error in
                DispatchQueue.main.async { completion(granted) }
            }
        } else {
            store.requestAccess(to: .event) { granted, error in
                DispatchQueue.main.async { completion(granted) }
            }
        }
    }

    // MARK: - Change notifications

    private func subscribeToChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(storeChanged),
            name: .EKEventStoreChanged,
            object: store
        )
        // Re-fetch on wake from sleep so timers are recalculated
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(didWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        // Re-fetch when system timezone changes so day boundaries are recalculated
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(timezoneOrDayChanged),
            name: .NSSystemTimeZoneDidChange,
            object: nil
        )
        // Re-fetch on calendar day rollover for reliable midnight handling
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(timezoneOrDayChanged),
            name: .NSCalendarDayChanged,
            object: nil
        )
    }

    @objc private func storeChanged(_ notification: Notification) {
        fetchAndNotify()
    }

    @objc private func didWake(_ notification: Notification) {
        // Kernel-based timers don't advance during sleep, so any pre-existing
        // timer fire date may have drifted relative to wall-clock time.
        // Force a full recompute so timers are recreated against `Date()` now.
        fetchAndNotify(forceReschedule: true)
    }

    @objc private func timezoneOrDayChanged(_ notification: Notification) {
        midnightTimer?.invalidate()
        midnightTimer = nil
        scheduleMidnightRollover()
        // Day rollover and timezone changes can shift effective fire times
        // relative to wall clock; recompute everything.
        fetchAndNotify(forceReschedule: true)
    }

    // MARK: - Polling

    private func startPolling() {
        let timer = Timer(timeInterval: 300, repeats: true) { [weak self] _ in
            self?.fetchAndNotify()
        }
        timer.tolerance = 30
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    // MARK: - Midnight rollover

    private func scheduleMidnightRollover() {
        let calendar = Calendar.current
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()),
              let midnight = calendar.dateInterval(of: .day, for: tomorrow)?.start else { return }

        let interval = max(1, midnight.timeIntervalSinceNow)
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            self?.fetchAndNotify(forceReschedule: true)
            self?.scheduleMidnightRollover()
        }
        // Allow up to 5s of OS-level coalescing; midnight rollover doesn't need ms precision.
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        midnightTimer = timer
    }

    // MARK: - Fetching

    /// We fetch a rolling 26-hour window rather than just "the rest of today".
    /// Reasons:
    ///  * If the app launches at 11:55pm with a meeting at 12:05am, we still see it.
    ///  * If the midnight-rollover timer is delayed (sleeping Mac, busy run loop),
    ///    we already have tomorrow's first events scheduled.
    ///  * 26h (rather than 24h) gives a small safety margin around the boundary.
    static let fetchWindowSeconds: TimeInterval = 26 * 3600

    func fetchAndNotify(forceReschedule: Bool = false) {
        store.refreshSourcesIfNecessary()
        let events = fetchUpcomingEvents()
        currentEvents = events
        delegate?.calendarService(self, didUpdateEvents: events, forceReschedule: forceReschedule)
    }

    private func fetchUpcomingEvents() -> [UpcomingEvent] {
        let now = Date()
        let end = now.addingTimeInterval(Self.fetchWindowSeconds)

        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        let ekEvents = store.events(matching: predicate)

        let filtered = ekEvents.filter { event in
            // Skip all-day events (birthdays, holidays, etc.)
            if event.isAllDay { return false }
            // Skip cancelled events
            if event.status == .canceled { return false }
            // Skip declined events
            if let me = event.attendees?.first(where: { $0.isCurrentUser }),
               me.participantStatus == .declined {
                return false
            }
            return true
        }

        return filtered.map { event in
            let conferenceInfo = ConferenceLinkExtractor.extract(
                url: event.url,
                notes: event.notes,
                location: event.location
            )

            var conferenceURL: URL? = nil
            var phoneNumber: String? = nil
            var notes: String? = nil

            switch conferenceInfo {
            case .videoCall(let url, _):
                conferenceURL = url
            case .phone(let number):
                phoneNumber = number
            case .notes(let text):
                notes = text
            case nil:
                break
            }

            return UpcomingEvent(
                id: event.eventIdentifier,
                title: event.title ?? "Untitled Event",
                startDate: event.startDate,
                endDate: event.endDate,
                location: event.location,
                conferenceURL: conferenceURL,
                phoneNumber: phoneNumber,
                notes: notes
            )
        }
    }
}
