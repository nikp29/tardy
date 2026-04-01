import Foundation

final class SettingsManager {
    static let validLeadTimes: [Int] = [0, 15, 30, 60]
    private static let leadTimeKey = "alertLeadTimeSeconds"
    private static let alertSoundKey = "alertSound"
    private static let launchOnLoginKey = "launchOnLogin"

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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }
}
