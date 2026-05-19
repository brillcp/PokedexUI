import SwiftUI
import SwiftData

/// Detail view model. Full `Pokemon` data is available from the grid, so
/// stats, types, moves, and sprites render on frame 1. Back sprite and
/// evolution chain load asynchronously.
@MainActor
protocol PokemonDetailViewModelProtocol {
    /// View-ready wrapper around `summary`. Set in init (never nil after init).
    var pokemon: PokemonViewModel { get }
    /// Always false after init (kept for animation compatibility).
    var isLoadingDetails: Bool { get }
    /// Bookmark flag mirrors `Pokemon.isBookmarked` on disk.
    var isBookmarked: Bool { get }
    /// Cached front sprite image, if loaded.
    var sprite: Image? { get }
    /// Dominant color extracted from the front sprite.
    var color: Color? { get }
    /// Linear evolution chain. Empty until `loadEvolutionChain` runs.
    var evolutionStages: [EvolutionChain.Stage] { get }

    /// Resolve the front sprite UIImage and dominant color.
    func loadSpritesAndColor(withSpriteLoader spriteLoader: SpriteLoader,
                             imageColorAnalyzer: ImageColorAnalyzer) async
    /// Fetch the evolution chain (SwiftData-cache-first, network on miss).
    func loadEvolutionChain(context: ModelContext) async
    /// Toggle the `isBookmarked` flag on the underlying summary row.
    func toggleBookmark(in context: ModelContext)
    /// Play the latest cry through the supplied audio player.
    func playCry(with audioPlayer: AudioPlayer) async
}

// MARK: - Implementation

/// Live implementation of `PokemonDetailViewModelProtocol`. Full Pokemon
/// data renders on frame 1. Back sprite and evolution chain load async.
@Observable
final class PokemonDetailViewModel {
    var pokemon: PokemonViewModel
    var isLoadingDetails: Bool = false
    var isBookmarked: Bool
    var sprite: Image?
    var color: Color?
    var evolutionStages: [EvolutionChain.Stage] = []

    private let evolutionService: EvolutionServiceProtocol

    init(
        summary: Pokemon,
        evolutionService: EvolutionServiceProtocol
    ) {
        self.isBookmarked = summary.isBookmarked
        self.evolutionService = evolutionService
        self.pokemon = PokemonViewModel(pokemon: summary)
    }
}

// MARK: - PokemonDetailViewModelProtocol

extension PokemonDetailViewModel: PokemonDetailViewModelProtocol {
    func loadEvolutionChain(context: ModelContext) async {
        guard evolutionStages.isEmpty,
              let chainId = pokemon.evolutionChainId
        else { return }
        guard let chain = try? await evolutionService.requestChain(id: "\(chainId)") else { return }
        evolutionStages = chain.stages
    }

    /// Front sprite + dominant color. Cached `colorHex` seeds `init`;
    /// otherwise the analyzer runs on first detail view open.
    func loadSpritesAndColor(withSpriteLoader spriteLoader: SpriteLoader,
                             imageColorAnalyzer: ImageColorAnalyzer) async {
        guard let image = await spriteLoader.spriteImage(from: pokemon.frontSprite) else { return }
        sprite = Image(uiImage: image)
        if color == nil,
           let uicolor = await imageColorAnalyzer.dominantColor(for: pokemon.id, image: image) {
            color = Color(uiColor: uicolor)
        }
    }

    func toggleBookmark(in context: ModelContext) {
        let id = pokemon.id
        let descriptor = FetchDescriptor<Pokemon>(predicate: #Predicate { $0.id == id })
        guard let model = try? context.fetch(descriptor).first else { return }
        model.isBookmarked.toggle()
        pokemon.isBookmarked = model.isBookmarked
        isBookmarked = model.isBookmarked
        try? context.save()
    }

    func playCry(with audioPlayer: AudioPlayer) async {
        guard let cryURL = pokemon.latestCry else { return }
        await audioPlayer.play(from: cryURL)
    }
}
