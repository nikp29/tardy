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

    @Test("default alert sound is crystal")
    func defaultAlertSound() {
        let defaults = UserDefaults(suiteName: "test-settings-\(UUID().uuidString)")!
        let manager = SettingsManager(defaults: defaults)
        #expect(manager.alertSound == .crystal)
    }

    @Test("persists alert sound")
    func persistAlertSound() {
        let suite = "test-settings-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let manager = SettingsManager(defaults: defaults)
        manager.alertSound = .deepBell

        let manager2 = SettingsManager(defaults: defaults)
        #expect(manager2.alertSound == .deepBell)
    }

    @Test("default launch on login is true")
    func defaultLaunchOnLogin() {
        let defaults = UserDefaults(suiteName: "test-settings-\(UUID().uuidString)")!
        let manager = SettingsManager(defaults: defaults)
        #expect(manager.launchOnLogin == true)
    }

    @Test("persists launch on login")
    func persistLaunchOnLogin() {
        let suite = "test-settings-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let manager = SettingsManager(defaults: defaults)
        manager.launchOnLogin = false

        let manager2 = SettingsManager(defaults: defaults)
        #expect(manager2.launchOnLogin == false)
    }
}
