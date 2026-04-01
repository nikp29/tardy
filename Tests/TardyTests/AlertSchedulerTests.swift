import Testing
import Foundation
@testable import Tardy

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
}
