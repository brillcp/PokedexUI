import AVFoundation

actor AudioPlayer {
    // MARK: Private properties
    private var player: AVPlayer?

    // MARK: - Public properties
    var isPlaying: Bool {
        guard let player else { return false }
        return player.timeControlStatus == .playing
    }

    // MARK: init
    init() {
        let shared = AVAudioSession.sharedInstance()
        try? shared.setCategory(.playback, mode: .default)
        try? shared.setActive(true)
    }
}

// MARK: - Public functions
extension AudioPlayer {
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
