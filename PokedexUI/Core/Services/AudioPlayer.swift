import AVFoundation

/// Audio playback for pokemon cries. Shared via `AppContainer.audioPlayer`.
protocol AudioPlaying: Sendable {
    /// Whether audio is currently playing.
    var isPlaying: Bool { get async }
    /// Play audio from a URL string, stopping any current playback.
    func play(from url: String) async
    /// Stop playback and reset to the beginning.
    func stop() async
}

actor AudioPlayer: AudioPlaying {
    private var player: AVPlayer?

    var isPlaying: Bool {
        guard let player else { return false }
        return player.timeControlStatus == .playing
    }

    init() {
        let shared = AVAudioSession.sharedInstance()
        try? shared.setCategory(.playback, mode: .default)
        try? shared.setActive(true)
    }

    func play(from url: String) {
        guard let url = URL(string: url) else { return }

        if isPlaying {
            stop()
        }

        let playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)
        player?.play()
    }

    func stop() {
        player?.pause()
        player?.seek(to: .zero)
    }
}
