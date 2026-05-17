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
    /// Whether the sprite is flipped (showing the back view).
    var isFlipped: Bool { get set }
    /// Cached front sprite image, if loaded.
    var frontSprite: Image? { get }
    /// Cached back sprite image, if loaded.
    var backSprite: Image? { get }
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
    /// Flip to the back sprite, with a haptic.
    func flipSprite(hapticFeedback: UIImpactFeedbackGenerator)
    /// Flip back to the front sprite, with a haptic.
    func flipSpriteBack(hapticFeedback: UIImpactFeedbackGenerator)
    /// Play the latest cry through the supplied audio player.
    func playSound(with audioPlayer: AudioPlayer) async
}

// MARK: - Implementation

/// Live implementation of `PokemonDetailViewModelProtocol`. Full Pokemon
/// data renders on frame 1. Back sprite and evolution chain load async.
@Observable
final class PokemonDetailViewModel {
    var pokemon: PokemonViewModel
    var isLoadingDetails: Bool = false
    var isBookmarked: Bool
    var isFlipped: Bool = false
    var frontSprite: Image?
    var backSprite: Image?
    var color: Color?
    var evolutionStages: [EvolutionChain.Stage] = []

    private let evolutionService: EvolutionServiceProtocol

    init(
        summary: Pokemon,
        evolutionService: EvolutionServiceProtocol = EvolutionService.shared
    ) {
        self.isBookmarked = summary.isBookmarked
        self.evolutionService = evolutionService
        self.pokemon = PokemonViewModel(pokemon: summary)
//        if let hex = summary.colorHex {
//            self.color = Color(hex: hex)
//        }
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
        frontSprite = Image(uiImage: image)
        if color == nil,
           let uicolor = await imageColorAnalyzer.dominantColor(for: pokemon.id, image: image) {
            color = Color(uiColor: uicolor)
        }
    }

func toggleBookmark(in context: ModelContext) {
        pokemon.isBookmarked.toggle()
        isBookmarked = pokemon.isBookmarked
        try? context.save()
    }

    func playSound(with audioPlayer: AudioPlayer) async {
        guard let cryURL = pokemon.latestCry else { return }
        await audioPlayer.play(from: cryURL)
    }

    func flipSprite(hapticFeedback: UIImpactFeedbackGenerator) {
        guard !isFlipped else { return }
        isFlipped = true
        hapticFeedback.impactOccurred()
    }

    func flipSpriteBack(hapticFeedback: UIImpactFeedbackGenerator) {
        guard isFlipped else { return }
        isFlipped = false
        hapticFeedback.impactOccurred()
    }
}
