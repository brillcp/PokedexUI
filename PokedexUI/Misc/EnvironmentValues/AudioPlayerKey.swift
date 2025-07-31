import SwiftUI

private struct AudioPlayerKey: EnvironmentKey {
    static let defaultValue: AudioPlayer = AudioPlayer()
}

extension EnvironmentValues {
    var audioPlayer: AudioPlayer {
        get { self[AudioPlayerKey.self] }
        set { self[AudioPlayerKey.self] = newValue }
    }
}
