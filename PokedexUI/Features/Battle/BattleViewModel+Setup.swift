import SwiftUI

extension BattleViewModel {
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

    func playEntrance() async {
        await animator.playEntrance()
        if let cry = opponentPokemon.latestCry {
            await audioPlayer.play(from: cry)
        }
    }

    func playWinnerCry() async {
        guard let winner else { return }
        let cry = winner == .player ? playerPokemon.latestCry : opponentPokemon.latestCry
        guard let cry else { return }
        try? await Task.sleep(for: .milliseconds(350))
        await audioPlayer.play(from: cry)
    }
}
