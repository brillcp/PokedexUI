import SwiftUI
import SwiftData

/// Pokemon detail view model protocol.
@MainActor
protocol PokemonDetailViewModelProtocol {
    var pokemon: PokemonViewModel { get }
    var isLoadingDetails: Bool { get }
    var isBookmarked: Bool { get }
    var sprite: Image? { get }
    var color: Color? { get }
    var evolutionStages: [EvolutionChain.Stage] { get }
    var typeChart: TypeChartLoader { get }

    /// Load front sprite image and extract dominant color.
    func loadSpritesAndColor() async
    /// Fetch evolution chain from cache or network.
    func loadEvolutionChain(context: ModelContext) async
    /// Ensure type chart is loaded for weakness grid.
    func loadTypeChartIfNeeded(modelContainer: ModelContainer) async
    /// Toggle bookmark on disk.
    func toggleBookmark(in context: ModelContext)
    /// Play the pokemon's cry audio.
    func playCry() async
}

/// Live implementation of `PokemonDetailViewModelProtocol`.
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
    private let spriteLoader: SpriteLoading
    private let imageColorAnalyzer: ImageColorAnalyzing
    private let audioPlayer: AudioPlaying

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

extension PokemonDetailViewModel: PokemonDetailViewModelProtocol {
    func loadEvolutionChain(context: ModelContext) async {
        guard evolutionStages.isEmpty,
              let chainId = pokemon.evolutionChainId
        else { return }
        guard let chain = try? await evolutionService.requestChain(id: "\(chainId)") else { return }
        evolutionStages = chain.stages
    }

    func loadSpritesAndColor() async {
        guard let image = await spriteLoader.spriteImage(from: pokemon.frontSprite) else { return }
        sprite = Image(uiImage: image)
        if color == nil, let color = await imageColorAnalyzer.dominantColor(for: pokemon.id, image: image) {
            self.color = color
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
