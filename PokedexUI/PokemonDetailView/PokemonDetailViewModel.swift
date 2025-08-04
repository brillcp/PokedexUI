import SwiftUI
import SwiftData

@MainActor
protocol PokemonDetailViewModelProtocol {
    var pokemon: PokemonViewModelProtocol { get }
    var isBookmarked: Bool { get }
    var isFlipped: Bool { get set }
    var frontSprite: Image? { get }
    var backSprite: Image? { get }
    var color: Color? { get }

    func loadSpritesAndColor(withSpriteLoader spriteLoader: SpriteLoader, imageColorAnalyzer: ImageColorAnalyzer) async
    func updateBookmarkStatus(from bookmarks: [Pokemon])
    func toggleBookmark(in context: ModelContext)
    func flipSprite(hapticFeedback: UIImpactFeedbackGenerator)
    func flipSpriteBack(hapticFeedback: UIImpactFeedbackGenerator)
    func playSound(with audioPlayer: AudioPlayer) async
}

@Observable
final class PokemonDetailViewModel {
    // MARK: Public Properties
    let pokemon: PokemonViewModelProtocol
    var isBookmarked = false
    var isFlipped = false
    var frontSprite: Image?
    var backSprite: Image?
    var color: Color?

    // MARK: - Initialization
    init(pokemon: PokemonViewModelProtocol) {
        self.pokemon = pokemon
    }
}

// MARK: - PokemonDetailViewModelProtocol
extension PokemonDetailViewModel: PokemonDetailViewModelProtocol {
    func updateBookmarkStatus(from bookmarks: [Pokemon]) {
        isBookmarked = bookmarks.contains(where: { $0.id == pokemon.id })
    }

    func loadSpritesAndColor(withSpriteLoader spriteLoader: SpriteLoader, imageColorAnalyzer: ImageColorAnalyzer) async {
        guard let image = await spriteLoader.spriteImage(from: pokemon.frontSprite),
              let uicolor = await imageColorAnalyzer.dominantColor(for: pokemon.id, image: image)
        else { return }

        color = Color(uiColor: uicolor)
        frontSprite = Image(uiImage: image)

        if let backSpriteURL = pokemon.backSprite,
           let backImage = await spriteLoader.spriteImage(from: backSpriteURL) {
            backSprite = Image(uiImage: backImage)
        }
    }

    func toggleBookmark(in context: ModelContext) {
        let id = pokemon.id
        let descriptor = FetchDescriptor<Pokemon>(predicate: #Predicate { $0.id == id })

        do {
            if let pokemonEntity = try context.fetch(descriptor).first {
                pokemonEntity.isBookmarked.toggle()
                isBookmarked = pokemonEntity.isBookmarked
                try context.save()
            }
        } catch {
            print("Failed to toggle bookmark: \(error)")
        }
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
