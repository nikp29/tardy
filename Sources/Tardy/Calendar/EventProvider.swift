import Foundation

/// A source of calendar events (EventKit, Google, …).
protocol EventProvider: AnyObject {
    var kind: EventSourceKind { get }
    /// Whether this provider should currently contribute events.
    var isEnabled: Bool { get }
    /// Called by the provider when its underlying data changes and the
    /// coordinator should re-poll immediately (e.g. EventKit store changed).
    var onChange: (() -> Void)? { get set }
    /// Begin observing changes / acquiring access. Idempotent.
    func start()
    /// Fetch events overlapping [start, end].
    func fetchEvents(start: Date, end: Date) async -> [UpcomingEvent]
}

protocol EventCoordinatorDelegate: AnyObject {
    func eventCoordinator(
        _ coordinator: EventCoordinator,
        didUpdateEvents events: [UpcomingEvent],
        forceReschedule: Bool
    )
}
