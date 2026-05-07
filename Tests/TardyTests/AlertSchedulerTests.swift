import Testing
import Foundation
@testable import Tardy

/// Tiny thread-safe counter for use across threads in tests.
final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = 0
    var value: Int {
        lock.lock(); defer { lock.unlock() }
        return _value
    }
    func increment() {
        lock.lock(); defer { lock.unlock() }
        _value += 1
    }
}

@Suite("AlertScheduler")
struct AlertSchedulerTests {

    private func makeEvent(
        id: String = "e1",
        title: String = "Test",
        startDate: Date = Date().addingTimeInterval(120),
        endDate: Date? = nil
    ) -> UpcomingEvent {
        UpcomingEvent(
            id: id,
            title: title,
            startDate: startDate,
            endDate: endDate ?? startDate.addingTimeInterval(1800),
            location: nil,
            conferenceURL: nil,
            phoneNumber: nil,
            notes: nil
        )
    }

    @Test("schedules timer for future event")
    func scheduleFutureEvent() {
        let settings = SettingsManager(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        settings.leadTimeSeconds = 60
        var firedEvents: [UpcomingEvent] = []
        let scheduler = AlertScheduler(settings: settings) { event in firedEvents.append(event) }

        let event = makeEvent(startDate: Date().addingTimeInterval(120))
        scheduler.updateEvents([event])

        #expect(scheduler.scheduledEventIDs.contains("e1"))
    }

    @Test("fires immediately for event within lead time window but not started")
    func firesImmediatelyForImminentEvent() async throws {
        let settings = SettingsManager(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        settings.leadTimeSeconds = 60
        var firedEvents: [UpcomingEvent] = []
        let scheduler = AlertScheduler(settings: settings) { event in firedEvents.append(event) }

        let event = makeEvent(startDate: Date().addingTimeInterval(10))
        scheduler.updateEvents([event])

        try await Task.sleep(for: .milliseconds(200))
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        #expect(firedEvents.count == 1)
    }

    @Test("skips event that already started beyond grace period")
    func skipsStartedEvent() {
        let settings = SettingsManager(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        settings.leadTimeSeconds = 0
        var firedEvents: [UpcomingEvent] = []
        let scheduler = AlertScheduler(settings: settings) { event in firedEvents.append(event) }

        let event = makeEvent(startDate: Date().addingTimeInterval(-30))
        scheduler.updateEvents([event])

        #expect(scheduler.scheduledEventIDs.isEmpty)
    }

    @Test("fires within grace period for 0s lead time")
    func gracePeriod() async throws {
        let settings = SettingsManager(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        settings.leadTimeSeconds = 0
        var firedEvents: [UpcomingEvent] = []
        let scheduler = AlertScheduler(settings: settings) { event in firedEvents.append(event) }

        let event = makeEvent(startDate: Date().addingTimeInterval(-3))
        scheduler.updateEvents([event])

        try await Task.sleep(for: .milliseconds(200))
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        #expect(firedEvents.count == 1)
    }

    @Test("cancels timer for removed event")
    func cancelsRemovedEvent() {
        let settings = SettingsManager(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        settings.leadTimeSeconds = 60
        var firedEvents: [UpcomingEvent] = []
        let scheduler = AlertScheduler(settings: settings) { event in firedEvents.append(event) }

        let event = makeEvent(startDate: Date().addingTimeInterval(120))
        scheduler.updateEvents([event])
        #expect(scheduler.scheduledEventIDs.contains("e1"))

        scheduler.updateEvents([])
        #expect(scheduler.scheduledEventIDs.isEmpty)
    }

    @Test("reschedules timer when event time changes")
    func reschedulesChangedEvent() {
        let settings = SettingsManager(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        settings.leadTimeSeconds = 60
        var firedEvents: [UpcomingEvent] = []
        let scheduler = AlertScheduler(settings: settings) { event in firedEvents.append(event) }

        let event1 = makeEvent(startDate: Date().addingTimeInterval(120))
        scheduler.updateEvents([event1])

        let event2 = makeEvent(startDate: Date().addingTimeInterval(300))
        scheduler.updateEvents([event2])

        #expect(scheduler.scheduledEventIDs.contains("e1"))
    }

    @Test("snooze always fires even after event started")
    func snoozeFiresAfterStart() async throws {
        let settings = SettingsManager(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        settings.leadTimeSeconds = 60
        var firedEvents: [UpcomingEvent] = []
        let scheduler = AlertScheduler(settings: settings) { event in firedEvents.append(event) }

        let event = makeEvent(startDate: Date().addingTimeInterval(-600))
        scheduler.snooze(event: event, duration: 0.1)

        try await Task.sleep(for: .milliseconds(300))
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        #expect(firedEvents.count == 1)
    }

    @Test("timer scheduled from a background thread still fires (proves it's attached to RunLoop.main)")
    func firesWhenScheduledOffMain() async throws {
        // Real-world case: EKEventStoreChanged notifications and similar can deliver
        // on background threads. `Timer.scheduledTimer(...)` attaches to the *current*
        // thread's run loop, which on a background thread is not running and never
        // ticks — so the alert never fires. Explicitly adding to RunLoop.main fixes it.
        let settings = SettingsManager(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        settings.leadTimeSeconds = 60
        let firedCount = LockedCounter()
        let scheduler = AlertScheduler(settings: settings) { _ in firedCount.increment() }

        let event = makeEvent(startDate: Date().addingTimeInterval(10))
        await Task.detached {
            // Definitely not on main here.
            scheduler.updateEvents([event])
        }.value

        try await Task.sleep(for: .milliseconds(200))
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        #expect(firedCount.value == 1, "Timer scheduled from a background thread must still fire")
    }

    @Test("forceReschedule recomputes timers even when event hasn't changed (wake from sleep)")
    func forceRescheduleAfterWake() {
        // Simulates wake-from-sleep: the kernel timer drifted while asleep, so the
        // pre-existing Timer instance will fire late. updateEvents normally skips
        // rescheduling when an event hasn't changed; we need an explicit way to
        // force a recompute against current wall-clock time.
        let settings = SettingsManager(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        settings.leadTimeSeconds = 60
        let scheduler = AlertScheduler(settings: settings) { _ in }

        let event = makeEvent(startDate: Date().addingTimeInterval(600))
        scheduler.updateEvents([event])
        #expect(scheduler.scheduledEventIDs.contains("e1"))

        // Capture current timer and confirm forceReschedule swaps it out.
        let before = ObjectIdentifier(scheduler.timerForTesting(eventID: "e1")!)
        scheduler.updateEvents([event], forceReschedule: true)
        let after = ObjectIdentifier(scheduler.timerForTesting(eventID: "e1")!)
        #expect(before != after, "Timer must be replaced when forceReschedule=true")
    }
}
