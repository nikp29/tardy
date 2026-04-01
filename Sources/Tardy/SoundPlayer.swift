import AVFoundation

enum AlertSound: String, CaseIterable {
    case crystal = "Crystal"
    case pulse = "Pulse"
    case deepBell = "DeepBell"

    var displayName: String {
        switch self {
        case .crystal: return "Crystal"
        case .pulse: return "Pulse"
        case .deepBell: return "Deep Bell"
        }
    }
}

final class SoundPlayer {
    private var player: AVAudioPlayer?

    func play(_ sound: AlertSound) {
        guard let url = Bundle.module.url(forResource: sound.rawValue, withExtension: "mp3", subdirectory: "Sounds") else {
            print("Tardy: Sound file not found: \(sound.rawValue).mp3")
            return
        }
        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.play()
        } catch {
            print("Tardy: Failed to play sound: \(error)")
        }
    }
}
