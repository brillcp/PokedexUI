import SwiftUI

// MARK: - Setup side effects (entrance, sprite colors, winner cry)

extension BattleViewModel {
    /// Resolve each combatant's dominant sprite color in parallel. The
    /// `ImageColorAnalyzer` caches by pokemon id, so a detail view that
    /// already opened the same pokemon makes this a cache hit. Colors land
    /// on the animator's per-side cue bundle and tint the pokemon's name
    /// in the log.
    func loadSpriteColors() async {
        async let playerImage   = spriteLoader.spriteImage(from: playerPokemon.frontSprite)
        async let opponentImage = spriteLoader.spriteImage(from: opponentPokemon.frontSprite)
        let (pImg, oImg) = await (playerImage, opponentImage)
        if let pImg, let color = await imageColorAnalyzer.dominantColor(for: playerPokemon.id, image: pImg) {
            animator.mutateCues(.player) { $0.color = color }
        }
        if let oImg, let color = await imageColorAnalyzer.dominantColor(for: opponentPokemon.id, image: oImg) {
            animator.mutateCues(.opponent) { $0.color = color }
        }
    }

    /// Animate sprites in from off-stage and play the opponent's cry so the
    /// battle opens with a recognisable audio beat.
    func playEntrance() async {
        await animator.playEntrance()
        if let cry = opponentPokemon.latestCry {
            await audioPlayer.play(from: cry)
        }
    }

    /// Play the winning side's cry after a short beat so it lands on top
    /// of the celebration tilt rather than the final hit's SFX.
    func playWinnerCry() async {
        guard let winner else { return }
        let cry = winner == .player ? playerPokemon.latestCry : opponentPokemon.latestCry
        guard let cry else { return }
        try? await Task.sleep(for: .milliseconds(350))
        await audioPlayer.play(from: cry)
    }
}
