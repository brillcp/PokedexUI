import SwiftUI
import SwiftData

/// Detail view model. Backed by a lightweight `PokemonSummary` for the header
/// (always available) and an optional `PokemonViewModelProtocol` for the rest
/// (set after the lazy hydration call returns).
@MainActor
protocol PokemonDetailViewModelProtocol {
    /// Always present: drives the sprite + title before any network call lands.
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

    /// Fetch full pokemon detail (cache-first via SwiftData, then network),
    /// then load the back sprite Image. Both land before `pokemon` is
    /// published so the body fades in with the flip button already armed.
    func loadFullDetails(context: ModelContext, spriteLoader: SpriteLoader) async
    /// Resolve the front sprite UIImage and (if not seeded from
    /// `summary.colorHex` in init) the dominant color from it.
    func loadSpritesAndColor(withSpriteLoader spriteLoader: SpriteLoader,
                             imageColorAnalyzer: ImageColorAnalyzer) async
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

/// Live implementation of `PokemonDetailViewModelProtocol`. Owns the lazy
/// hydration of the full `Pokemon` row, back-sprite Image, dominant color
/// fallback, evolution chain, and the bookmark toggle.
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
    /// Cache-first hydration. Loads the full `Pokemon` row, then sequentially
    /// loads the back sprite image, then publishes both atomically by setting
    /// `pokemon` last, so SwiftUI sees a single state transition and the
    /// detail body + flip button fade in together. Returns early when already
    /// loaded so re-entering the detail view is instant.
    func loadFullDetails(context: ModelContext, spriteLoader: SpriteLoader) async {
        guard pokemon == nil else { return }
        isLoadingDetails = true
        defer { isLoadingDetails = false }

        // 1. Cache lookup, falling back to network on miss.
        let id = summary.id
        let descriptor = FetchDescriptor<Pokemon>(predicate: #Predicate { $0.id == id })
        let fetched: Pokemon
        if let cached = try? context.fetch(descriptor).first {
            fetched = cached
        } else {
            do {
                fetched = try await pokemonService.requestFullPokemon(id: id)
                context.insert(fetched)
                try? context.save()
            } catch {
                print("Detail load failed for #\(id): \(error)")
                return
            }
        }

        // 2. Load the back sprite Image up-front so the flip button is armed
        // the moment the body becomes visible. The front sprite is loaded on
        // a parallel `.task`; that path already started before this method.
        let viewModelForVM = PokemonViewModel(pokemon: fetched)
        if let backURL = viewModelForVM.backSprite,
           let backImage = await spriteLoader.spriteImage(from: backURL) {
            self.backSprite = Image(uiImage: backImage)
        }

        // 3. Publish atomically: a single setter flips SwiftUI body to the
        // "loaded" branch with everything (back sprite, color, content) ready.
        self.pokemon = viewModelForVM
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
    /// to display a color in this session; the prefetcher persists it later.
    func loadSpritesAndColor(withSpriteLoader spriteLoader: SpriteLoader,
                             imageColorAnalyzer: ImageColorAnalyzer) async {
        guard let image = await spriteLoader.spriteImage(from: summary.frontSprite) else { return }
        frontSprite = Image(uiImage: image)
        if color == nil,
           let uicolor = await imageColorAnalyzer.dominantColor(for: summary.id, image: image) {
            color = Color(uiColor: uicolor)
        }
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
