import SwiftUI
import SwiftData

/// Detail view model. Full `Pokemon` data is available from the grid, so
/// stats, types, moves, and sprites render on frame 1. Back sprite,
/// evolution chain, and the type chart for the weakness grid load
/// asynchronously through this view model rather than the view reading
/// them off `AppContainer` directly.
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
    /// The shared type chart used by `WeaknessGridView`. The VM owns this
    /// reference so the view never needs to touch `AppContainer` itself.
    var typeChart: TypeChartLoader { get }

    /// Resolve the front sprite UIImage and dominant color.
    func loadSpritesAndColor() async
    /// Fetch the evolution chain (SwiftData-cache-first, network on miss).
    func loadEvolutionChain(context: ModelContext) async
    /// Ensure the shared type chart is loaded; safe to call from every
    /// detail-view appearance because `warmUp` is idempotent.
    func loadTypeChartIfNeeded(modelContainer: ModelContainer) async
    /// Toggle the `isBookmarked` flag on the underlying summary row.
    func toggleBookmark(in context: ModelContext)
    /// Play the latest cry through the audio player.
    func playCry() async
}

// MARK: - Implementation

/// Live implementation of `PokemonDetailViewModelProtocol`. Full Pokemon
/// data renders on frame 1. Back sprite + evolution chain + type chart
/// load async; the VM owns every service it consumes so the view doesn't
/// reach into `AppContainer`.
@Observable
final class PokemonDetailViewModel {
    var pokemon: PokemonViewModel
    var isLoadingDetails: Bool = false
    var isBookmarked: Bool
    var sprite: Image?
    var color: Color?
    var evolutionStages: [EvolutionChain.Stage] = []

    let typeChart: TypeChartLoader

    private let evolutionService: EvolutionServiceProtocol
    private let spriteLoader: SpriteLoader
    private let imageColorAnalyzer: ImageColorAnalyzer
    private let audioPlayer: AudioPlayer

    init(summary: Pokemon, container: AppContainer) {
        self.isBookmarked = summary.isBookmarked
        self.pokemon = PokemonViewModel(pokemon: summary)
        self.typeChart = container.typeChart
        self.evolutionService = container.evolutionService
        self.spriteLoader = container.spriteLoader
        self.imageColorAnalyzer = container.imageColorAnalyzer
        self.audioPlayer = container.audioPlayer
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
    func loadSpritesAndColor() async {
        guard let image = await spriteLoader.spriteImage(from: pokemon.frontSprite) else { return }
        sprite = Image(uiImage: image)
        if color == nil,
           let uicolor = await imageColorAnalyzer.dominantColor(for: pokemon.id, image: image) {
            color = Color(uiColor: uicolor)
        }
    }

    func loadTypeChartIfNeeded(modelContainer: ModelContainer) async {
        await typeChart.warmUp(modelContainer: modelContainer)
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

    func playCry() async {
        guard let cryURL = pokemon.latestCry else { return }
        await audioPlayer.play(from: cryURL)
    }
}
