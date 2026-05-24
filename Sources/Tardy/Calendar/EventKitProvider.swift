import AppKit
import EventKit
import Foundation

final class EventKitProvider: EventProvider {
    let kind: EventSourceKind = .eventKit
    var isEnabled: Bool { true } // EventKit is always available as a source
    var onChange: (() -> Void)?

    private let store = EKEventStore()
    private var accessGranted = false

    func start() {
        requestAccess { [weak self] granted in
            guard let self else { return }
            self.accessGranted = granted
            if !granted { print("Tardy: Calendar access denied") }
            NotificationCenter.default.addObserver(
                self, selector: #selector(self.storeChanged),
                name: .EKEventStoreChanged, object: self.store
            )
            self.onChange?()
        }
    }

    @objc private func storeChanged(_ note: Notification) {
        onChange?()
    }

    func fetchEvents(start: Date, end: Date) async -> [UpcomingEvent] {
        guard accessGranted else { return [] }
        store.refreshSourcesIfNecessary()
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let ekEvents = store.events(matching: predicate)

        let filtered = ekEvents.filter { event in
            if event.isAllDay { return false }
            if event.status == .canceled { return false }
            if let me = event.attendees?.first(where: { $0.isCurrentUser }),
               me.participantStatus == .declined { return false }
            return true
        }

        return filtered.map { event in
            let conferenceInfo = ConferenceLinkExtractor.extract(
                url: event.url, notes: event.notes, location: event.location
            )
            var conferenceURL: URL?
            var phoneNumber: String?
            var notes: String?
            switch conferenceInfo {
            case .videoCall(let url, _): conferenceURL = url
            case .phone(let number): phoneNumber = number
            case .notes(let text): notes = text
            case nil: break
            }
            return UpcomingEvent(
                id: event.eventIdentifier,
                title: event.title ?? "Untitled Event",
                startDate: event.startDate,
                endDate: event.endDate,
                location: event.location,
                conferenceURL: conferenceURL,
                phoneNumber: phoneNumber,
                notes: notes,
                source: .eventKit,
                iCalUID: event.calendarItemExternalIdentifier
            )
        }
    }

    private func requestAccess(completion: @escaping (Bool) -> Void) {
        if #available(macOS 14.0, *) {
            store.requestFullAccessToEvents { granted, _ in
                DispatchQueue.main.async { completion(granted) }
            }
        } else {
            store.requestAccess(to: .event) { granted, _ in
                DispatchQueue.main.async { completion(granted) }
            }
        }
    }
}
