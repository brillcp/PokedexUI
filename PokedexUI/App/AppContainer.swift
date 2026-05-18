import SwiftUI

/// Process-wide composition root. Owns the concrete dependencies the app
/// needs and hands them to views + viewmodels through a single environment
/// entry. Tests and previews swap in a custom container to inject mocks
/// without touching call sites.
///
/// This is the single answer to the **Dependency Inversion** + **easy
/// testing** claims in the README: every layer below `App/` depends on
/// abstractions (protocols) and gets them via the container, never via
/// `static let shared` lookups.
@MainActor
final class AppContainer {
    // MARK: - Networking-backed services

    let pokemonService:   PokemonServiceProtocol
    let moveService:      MoveServiceProtocol
    let typeService:      TypeServiceProtocol
    let evolutionService: EvolutionServiceProtocol
    let itemService:      ItemServiceProtocol

    // MARK: - Long-lived workers

    let typeChart:          TypeChartLoader
    let movePrefetcher:     MovePrefetcher
    let spriteLoader:       SpriteLoader
    let imageColorAnalyzer: ImageColorAnalyzer
    let audioPlayer:        AudioPlayer
    let battleAI:           BattleAIServiceProtocol

    init(
        pokemonService:     PokemonServiceProtocol   = PokemonService(),
        moveService:        MoveServiceProtocol      = MoveService(),
        typeService:        TypeServiceProtocol      = TypeService(),
        evolutionService:   EvolutionServiceProtocol = EvolutionService(),
        itemService:        ItemServiceProtocol      = ItemService(),
        typeChart:          TypeChartLoader          = TypeChartLoader(),
        movePrefetcher:     MovePrefetcher           = MovePrefetcher(),
        spriteLoader:       SpriteLoader             = SpriteLoader(),
        imageColorAnalyzer: ImageColorAnalyzer       = ImageColorAnalyzer(),
        audioPlayer:        AudioPlayer              = AudioPlayer(),
        battleAI:           BattleAIServiceProtocol  = BattleAIService()
    ) {
        self.pokemonService     = pokemonService
        self.moveService        = moveService
        self.typeService        = typeService
        self.evolutionService   = evolutionService
        self.itemService        = itemService
        self.movePrefetcher     = movePrefetcher
        self.spriteLoader       = spriteLoader
        self.imageColorAnalyzer = imageColorAnalyzer
        self.audioPlayer        = audioPlayer
        self.battleAI           = battleAI
        self.typeChart          = typeChart
    }

    /// The default container used by the live app. Resolved lazily on first
    /// access; views never construct their own. Tests pass a different
    /// container into `.environment(\.container, …)`.
    static let live = AppContainer()
}
