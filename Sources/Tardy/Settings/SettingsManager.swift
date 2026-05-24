import Foundation

final class SettingsManager {
    static let validLeadTimes: [Int] = [0, 15, 30, 60]
    private static let leadTimeKey = "alertLeadTimeSeconds"
    private static let alertSoundKey = "alertSound"
    private static let launchOnLoginKey = "launchOnLogin"
    private static let googleEnabledKey = "googleCalendarEnabled"

    private let defaults: UserDefaults

    var leadTimeSeconds: Int {
        get {
            // If the key has never been written, default to 60s.
            // `defaults.integer(forKey:)` returns 0 for both "unset" and "explicitly 0",
            // so we must probe `object(forKey:)` to distinguish them.
            guard let raw = defaults.object(forKey: Self.leadTimeKey) as? Int else {
                return 60
            }
            return Self.validLeadTimes.contains(raw) ? raw : 60
        }
        set {
            if Self.validLeadTimes.contains(newValue) {
                defaults.set(newValue, forKey: Self.leadTimeKey)
            }
        }
    }

    var alertSound: AlertSound {
        get {
            guard let raw = defaults.string(forKey: Self.alertSoundKey),
                  let sound = AlertSound(rawValue: raw) else {
                return .crystal
            }
            return sound
        }
        set {
            defaults.set(newValue.rawValue, forKey: Self.alertSoundKey)
        }
    }

    var launchOnLogin: Bool {
        get {
            if defaults.object(forKey: Self.launchOnLoginKey) == nil {
                return true
            }
            return defaults.bool(forKey: Self.launchOnLoginKey)
        }
        set {
            defaults.set(newValue, forKey: Self.launchOnLoginKey)
        }
    }

    var googleCalendarEnabled: Bool {
        get { defaults.bool(forKey: Self.googleEnabledKey) } // defaults to false
        set { defaults.set(newValue, forKey: Self.googleEnabledKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }
}
