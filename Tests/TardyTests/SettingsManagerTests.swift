import Testing
@testable import Tardy

@Suite("SettingsManager")
struct SettingsManagerTests {
    @Test("default lead time is 60 seconds")
    func defaultLeadTime() {
        let defaults = UserDefaults(suiteName: "test-settings-\(UUID().uuidString)")!
        let manager = SettingsManager(defaults: defaults)
        #expect(manager.leadTimeSeconds == 60)
    }

    @Test("persists lead time")
    func persistLeadTime() {
        let suite = "test-settings-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let manager = SettingsManager(defaults: defaults)
        manager.leadTimeSeconds = 15

        let manager2 = SettingsManager(defaults: defaults)
        #expect(manager2.leadTimeSeconds == 15)
    }

    @Test("only allows valid lead times")
    func validLeadTimes() {
        let defaults = UserDefaults(suiteName: "test-settings-\(UUID().uuidString)")!
        let manager = SettingsManager(defaults: defaults)
        manager.leadTimeSeconds = 99
        #expect(manager.leadTimeSeconds == 60)
    }
}
