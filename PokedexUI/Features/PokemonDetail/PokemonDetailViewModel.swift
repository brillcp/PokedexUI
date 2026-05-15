import SwiftUI
import SwiftData

/// Detail view model. Backed by a lightweight `PokemonSummary` for the header
/// (always available) and an optional `PokemonViewModelProtocol` for the rest
/// (set after the lazy hydration call returns).
@MainActor
protocol PokemonDetailViewModelProtocol {
    /// Always present — drives the sprite + title before any network call lands.
    var summary: PokemonSummary { get }
    /// `nil` until the lazy fetch resolves. The detail body fades in once set.
    var pokemon: PokemonViewModelProtocol? { get }
    /// True while the hydration network call is in-flight.
    var isLoadingDetails: Bool { get }
    /// Bookmark flag mirrors the `PokemonSummary.isBookmarked` on disk.
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

    /// Fetch full pokemon detail (cache-first via SwiftData, then network).
    func loadFullDetails(context: ModelContext) async
    /// Resolve the front sprite UIImage and (if not seeded from
    /// `summary.colorHex` in init) the dominant color from it.
    func loadSpritesAndColor(withSpriteLoader spriteLoader: SpriteLoader,
                             imageColorAnalyzer: ImageColorAnalyzer) async
    /// Resolve the back sprite UIImage once `pokemon` is hydrated.
    func loadBackSprite(withSpriteLoader spriteLoader: SpriteLoader) async
    /// Fetch the evolution chain via the API (no-op if absent or already loaded).
    func loadEvolutionChain() async
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

@Observable
final class PokemonDetailViewModel {
    let summary: PokemonSummary
    var pokemon: PokemonViewModelProtocol?
    var isLoadingDetails: Bool = true
    var isBookmarked: Bool
    var isFlipped: Bool = false
    var frontSprite: Image?
    var backSprite: Image?
    var color: Color?
    var evolutionStages: [EvolutionChain.Stage] = []

    private let pokemonService:   PokemonServiceProtocol
    private let evolutionService: EvolutionServiceProtocol

    init(
        summary: PokemonSummary,
        pokemonService:   PokemonServiceProtocol   = PokemonService(),
        evolutionService: EvolutionServiceProtocol = EvolutionService.shared
    ) {
        self.summary = summary
        self.isBookmarked = summary.isBookmarked
        self.pokemonService = pokemonService
        self.evolutionService = evolutionService
        // Seed the gradient color from the persisted hex if we've already
        // analyzed this sprite once. Frame-1 background instead of black-flash
        // while the image color analyzer crunches.
        if let hex = summary.colorHex {
            self.color = Color(hex: hex)
        }
    }
}

// MARK: - PokemonDetailViewModelProtocol

extension PokemonDetailViewModel: PokemonDetailViewModelProtocol {
    /// Cache-first hydration. Returns early when already loaded so re-entering
    /// the detail view is instant.
    func loadFullDetails(context: ModelContext) async {
        guard pokemon == nil else { return }
        isLoadingDetails = true
        defer { isLoadingDetails = false }

        // 1. Cache: look up `Pokemon` by id in SwiftData.
        let id = summary.id
        let descriptor = FetchDescriptor<Pokemon>(predicate: #Predicate { $0.id == id })
        if let cached = try? context.fetch(descriptor).first {
            pokemon = PokemonViewModel(pokemon: cached)
            return
        }

        // 2. Network: pull species + variety pokemon, merge, persist for next time.
        do {
            let fetched = try await pokemonService.requestFullPokemon(id: id)
            context.insert(fetched)
            try? context.save()
            pokemon = PokemonViewModel(pokemon: fetched)
        } catch {
            print("Detail load failed for #\(id): \(error)")
        }
    }

    func loadEvolutionChain() async {
        guard evolutionStages.isEmpty,
              let chainId = pokemon?.evolutionChainId
        else { return }
        do {
            let chain = try await evolutionService.requestChain(id: chainId)
            evolutionStages = chain.stages
        } catch {
            print("Evolution chain failed for \(summary.name): \(error)")
        }
    }

    /// Front sprite + dominant color. The color is normally seeded in `init`
    /// from `summary.colorHex` (filled by `SpriteColorPrefetcher` at app
    /// start), so this call usually just loads the sprite image. On the rare
    /// case the prefetcher hasn't reached this pokemon yet, the analyzer runs
    /// to display a color in this session — the prefetcher persists it later.
    func loadSpritesAndColor(withSpriteLoader spriteLoader: SpriteLoader,
                             imageColorAnalyzer: ImageColorAnalyzer) async {
        guard let image = await spriteLoader.spriteImage(from: summary.frontSprite) else { return }
        frontSprite = Image(uiImage: image)
        if color == nil,
           let uicolor = await imageColorAnalyzer.dominantColor(for: summary.id, image: image) {
            color = Color(uiColor: uicolor)
        }
    }

    /// Back sprite loads separately: the URL only exists on the full `Pokemon`
    /// row, so this runs after `loadFullDetails` resolves. View triggers it
    /// via a `.task(id: pokemon?.id)` once hydration lands.
    func loadBackSprite(withSpriteLoader spriteLoader: SpriteLoader) async {
        guard backSprite == nil,
              let backURL = pokemon?.backSprite,
              let backImage = await spriteLoader.spriteImage(from: backURL)
        else { return }
        backSprite = Image(uiImage: backImage)
    }

    func toggleBookmark(in context: ModelContext) {
        summary.isBookmarked.toggle()
        isBookmarked = summary.isBookmarked
        try? context.save()
    }

    func playSound(with audioPlayer: AudioPlayer) async {
        guard let cryURL = pokemon?.latestCry else { return }
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
