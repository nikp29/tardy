import AppKit
import EventKit
import Foundation

protocol CalendarServiceDelegate: AnyObject {
    func calendarService(_ service: CalendarService, didUpdateEvents events: [UpcomingEvent])
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
        fetchAndNotify()
    }

    @objc private func timezoneOrDayChanged(_ notification: Notification) {
        midnightTimer?.invalidate()
        midnightTimer = nil
        scheduleMidnightRollover()
        fetchAndNotify()
    }

    // MARK: - Polling

    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.fetchAndNotify()
        }
    }

    // MARK: - Midnight rollover

    private func scheduleMidnightRollover() {
        let calendar = Calendar.current
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()),
              let midnight = calendar.dateInterval(of: .day, for: tomorrow)?.start else { return }

        let interval = midnight.timeIntervalSinceNow
        midnightTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.fetchAndNotify()
            self?.scheduleMidnightRollover()
        }
    }

    // MARK: - Fetching

    func fetchAndNotify() {
        store.refreshSourcesIfNecessary()
        let events = fetchTodayEvents()
        currentEvents = events
        delegate?.calendarService(self, didUpdateEvents: events)
    }

    private func fetchTodayEvents() -> [UpcomingEvent] {
        let calendar = Calendar.current
        let now = Date()
        let endOfDay = calendar.dateInterval(of: .day, for: now)?.end ?? now.addingTimeInterval(86400)

        let predicate = store.predicateForEvents(withStart: now, end: endOfDay, calendars: nil)
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
