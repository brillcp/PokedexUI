import SwiftUI
import BattleKit

/// One-shot helper that pulls sprite images for both combatants, extracts
/// dominant colors, and writes them onto the animator's per-side cues so
/// HP bars and hit flashes tint to match each Pokemon.
@MainActor
struct SpriteColorResolver {
    let spriteLoader: SpriteLoading
    let imageColorAnalyzer: ImageColorAnalyzing

    func resolve(
        player: PokemonViewModel,
        opponent: PokemonViewModel,
        animator: BattleAnimator
    ) async {
        async let playerImage   = spriteLoader.spriteImage(from: player.frontSprite)
        async let opponentImage = spriteLoader.spriteImage(from: opponent.frontSprite)
        let (pImg, oImg) = await (playerImage, opponentImage)
        if let pImg, let color = await imageColorAnalyzer.dominantColor(for: player.id, image: pImg) {
            animator.mutateCues(.player) { $0.color = color }
        }
        if let oImg, let color = await imageColorAnalyzer.dominantColor(for: opponent.id, image: oImg) {
            animator.mutateCues(.opponent) { $0.color = color }
        }
    }
}
