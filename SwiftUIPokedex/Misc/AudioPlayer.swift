import AVFoundation

/// An actor responsible for managing audio playback using AVFoundation.
actor AudioPlayer {
    // MARK: Private properties
    
    /// The AVFoundation player instance used to control audio playback.
    private var player: AVPlayer?

    // MARK: - Public properties
    
    /// A Boolean value indicating whether the audio player is currently playing.
    var isPlaying: Bool {
        guard let player else { return false }
        return player.timeControlStatus == .playing
    }

    // MARK: init
    
    /// Initializes a new audio player and configures the audio session for playback.
    init() {
        let shared = AVAudioSession.sharedInstance()
        try? shared.setCategory(.playback, mode: .default)
        try? shared.setActive(true)
    }
}

// MARK: - Public functions
extension AudioPlayer {
    /// Begins playback of audio from the specified URL string.
    ///
    /// If playback is already in progress, it stops the current audio before starting the new one.
    ///
    /// - Parameter url: A string representing the URL of the audio to play.
    func play(from url: String) {
        guard let url = URL(string: url) else { return }

        if isPlaying {
            stop()
        }

        let playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)
        player?.play()
    }

    /// Stops the current audio playback and resets the position to the beginning.
    func stop() {
        player?.pause()
        player?.seek(to: .zero)
    }
}

