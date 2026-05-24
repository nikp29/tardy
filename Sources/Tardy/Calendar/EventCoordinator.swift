import AppKit
import Foundation

final class EventCoordinator {
    /// Rolling fetch window. 26h covers the midnight boundary and delayed
    /// rollovers (see prior CalendarService notes).
    static let fetchWindowSeconds: TimeInterval = 26 * 3600

    private let providers: [EventProvider]
    private var pollTimer: Timer?
    private var midnightTimer: Timer?

    weak var delegate: EventCoordinatorDelegate?

    init(providers: [EventProvider]) {
        self.providers = providers
        for p in providers {
            p.onChange = { [weak self] in self?.refresh() }
        }
    }

    func start() {
        providers.forEach { $0.start() }
        subscribeToSystemNotifications()
        startPolling()
        scheduleMidnightRollover()
        refresh()
    }

    func stop() {
        pollTimer?.invalidate(); pollTimer = nil
        midnightTimer?.invalidate(); midnightTimer = nil
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    /// Public entry point used by poll-on-open and connect/disconnect.
    func refresh(forceReschedule: Bool = false) {
        let now = Date()
        let end = now.addingTimeInterval(Self.fetchWindowSeconds)
        Task { [weak self] in
            guard let self else { return }
            var groups: [[UpcomingEvent]] = []
            for provider in self.providers where provider.isEnabled {
                groups.append(await provider.fetchEvents(start: now, end: end))
            }
            let merged = EventDeduplicator.merge(groups)
            await MainActor.run {
                self.delegate?.eventCoordinator(self, didUpdateEvents: merged, forceReschedule: forceReschedule)
            }
        }
    }

    // MARK: - System notifications

    private func subscribeToSystemNotifications() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(timezoneOrDayChanged), name: .NSSystemTimeZoneDidChange, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(timezoneOrDayChanged), name: .NSCalendarDayChanged, object: nil)
    }

    @objc private func didWake(_ n: Notification) { refresh(forceReschedule: true) }

    @objc private func timezoneOrDayChanged(_ n: Notification) {
        midnightTimer?.invalidate(); midnightTimer = nil
        scheduleMidnightRollover()
        refresh(forceReschedule: true)
    }

    // MARK: - Timers

    private func startPolling() {
        let timer = Timer(timeInterval: 300, repeats: true) { [weak self] _ in self?.refresh() }
        timer.tolerance = 30
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func scheduleMidnightRollover() {
        let cal = Calendar.current
        guard let tomorrow = cal.date(byAdding: .day, value: 1, to: Date()),
              let midnight = cal.dateInterval(of: .day, for: tomorrow)?.start else { return }
        let interval = max(1, midnight.timeIntervalSinceNow)
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            self?.refresh(forceReschedule: true)
            self?.scheduleMidnightRollover()
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        midnightTimer = timer
    }
}
