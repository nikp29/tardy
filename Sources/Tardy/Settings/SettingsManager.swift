import Foundation

final class SettingsManager {
    static let validLeadTimes: [Int] = [0, 15, 30, 60]
    private static let leadTimeKey = "alertLeadTimeSeconds"

    private let defaults: UserDefaults

    var leadTimeSeconds: Int {
        get {
            let value = defaults.integer(forKey: Self.leadTimeKey)
            return Self.validLeadTimes.contains(value) ? value : 60
        }
        set {
            if Self.validLeadTimes.contains(newValue) {
                defaults.set(newValue, forKey: Self.leadTimeKey)
            }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }
}
