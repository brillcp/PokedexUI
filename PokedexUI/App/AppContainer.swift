import SwiftUI

/// Process-wide composition root for dependency injection. Constructed
/// once at app launch and exposed via `Environment(\.container)`. The
/// `static let live` instance wires real implementations; tests and
/// previews can call `init(...)` directly and pass mocks per parameter
/// without restating the others.
@MainActor
final class AppContainer {
    let pokemonService:   PokemonServiceProtocol
    let evolutionService: EvolutionServiceProtocol
    let itemService:      ItemServiceProtocol

    let spriteLoader:       SpriteLoading
    let imageColorAnalyzer: ImageColorAnalyzing
    let audioPlayer:        AudioPlaying
    let battleAI:           BattleAIServiceProtocol
    let multipeerService:   MultipeerService

    init(
        pokemonService:     PokemonServiceProtocol   = PokemonService(),
        evolutionService:   EvolutionServiceProtocol = EvolutionService(),
        itemService:        ItemServiceProtocol      = ItemService(),
        spriteLoader:       SpriteLoading            = SpriteLoader(),
        imageColorAnalyzer: ImageColorAnalyzing      = ImageColorAnalyzer(),
        audioPlayer:        AudioPlaying             = AudioPlayer(),
        battleAI:           BattleAIServiceProtocol  = BattleAIService(),
        multipeerService:   MultipeerService
    ) {
        self.pokemonService     = pokemonService
        self.evolutionService   = evolutionService
        self.itemService        = itemService
        self.spriteLoader       = spriteLoader
        self.imageColorAnalyzer = imageColorAnalyzer
        self.audioPlayer        = audioPlayer
        self.battleAI           = battleAI
        self.multipeerService   = multipeerService
    }

    /// Production composition. Reached via `Environment(\.container)`;
    /// also used by Previews to keep the tree close to the live wiring.
    static let live = AppContainer(multipeerService: MultipeerService())
}
