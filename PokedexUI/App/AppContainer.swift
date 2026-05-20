import SwiftUI

/// Process-wide composition root for dependency injection.
@MainActor
final class AppContainer {
    let pokemonService:   PokemonServiceProtocol
    let evolutionService: EvolutionServiceProtocol
    let itemService:      ItemServiceProtocol

    let typeChart:          TypeChartLoader
    let movePrefetcher:     MovePrefetching
    let spriteLoader:       SpriteLoading
    let imageColorAnalyzer: ImageColorAnalyzing
    let audioPlayer:        AudioPlaying
    let battleAI:           BattleAIServiceProtocol

    init(
        pokemonService:     PokemonServiceProtocol   = PokemonService(),
        evolutionService:   EvolutionServiceProtocol = EvolutionService(),
        itemService:        ItemServiceProtocol      = ItemService(),
        typeChart:          TypeChartLoader          = TypeChartLoader(),
        movePrefetcher:     MovePrefetching           = MovePrefetcher(),
        spriteLoader:       SpriteLoading             = SpriteLoader(),
        imageColorAnalyzer: ImageColorAnalyzing       = ImageColorAnalyzer(),
        audioPlayer:        AudioPlaying              = AudioPlayer(),
        battleAI:           BattleAIServiceProtocol  = BattleAIService()
    ) {
        self.pokemonService     = pokemonService
        self.evolutionService   = evolutionService
        self.itemService        = itemService
        self.movePrefetcher     = movePrefetcher
        self.spriteLoader       = spriteLoader
        self.imageColorAnalyzer = imageColorAnalyzer
        self.audioPlayer        = audioPlayer
        self.battleAI           = battleAI
        self.typeChart          = typeChart
    }

    static let live = AppContainer()
}
