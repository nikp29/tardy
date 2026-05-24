import Testing
import Foundation
@testable import Tardy

@Suite("EventCoordinator near-term polling")
struct EventCoordinatorTests {
    @Test("polls every 30s when an event is within 5 minutes")
    func tightWhenImminent() {
        let next = Date().addingTimeInterval(120)
        #expect(EventCoordinator.nearTermPollInterval(nextStart: next, now: Date()) == 30)
    }
    @Test("no near-term poll when next event is far away")
    func looseWhenFar() {
        let next = Date().addingTimeInterval(3600)
        #expect(EventCoordinator.nearTermPollInterval(nextStart: next, now: Date()) == nil)
    }
    @Test("no near-term poll when there is no upcoming event")
    func noneWhenEmpty() {
        #expect(EventCoordinator.nearTermPollInterval(nextStart: nil, now: Date()) == nil)
    }
}
