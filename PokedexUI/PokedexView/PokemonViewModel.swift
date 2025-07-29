import SwiftUI

/// Protocol for Pokémon view models providing display-ready Pokémon data.
protocol PokemonViewModelProtocol {
    /// The Pokémon front sprite image.
    var frontSprite: UIImage? { get }
    /// The Pokémon back sprite image.
    var backSprite: UIImage? { get }
    /// The dominant color extracted from the sprite.
    var color: Color? { get }
    /// Indicates if the color is light for UI adjustments.
    var isLight: Bool { get }
    /// Types associated with the Pokémon.
    var types: String { get }
    /// Abilities associated with the Pokémon.
    var abilities: String { get }
    /// Display-ready Pokémon name.
    var name: String { get }
    /// Statistics for the Pokémon.
    var stats: [Stat] { get }
    /// Main moves for the Pokémon (first 20, comma-separated).
    var moves: String { get }
    /// Pokémon height, formatted for display.
    var height: String { get }
    /// Pokémon weight, formatted for display.
    var weight: String { get }
    /// Unique Pokémon identifier.
    var id: Int { get }
    /// The battle cry of the pokemon.
    var latestCry: String? { get }

    /// Loads the sprite image asynchronously and updates color.
    func loadSprite() async
    /// Play the battle cry of the pokemon.
    func playBattleCry(_ urlString: String) async
}

// MARK: -
/// ViewModel providing formatted and display-ready data for a single Pokémon.
@Observable
final class PokemonViewModel {
    // MARK: Private properties
    private let spriteLoader: SpriteLoader
    private let audioPlayer: AudioPlayer
    private let pokemon: Pokemon

    // MARK: - Public properties
    var frontSprite: UIImage?
    var backSprite: UIImage?
    var color: Color?

    /// Initializes the ViewModel with Pokémon details, a sprite loader and a audio player.
    /// - Parameters:
    ///   - pokemon: The detailed Pokémon model.
    ///   - spriteLoader: The loader for sprite images.
    ///   - audioPlayer: The audio player to play the pokemon battle cry.
    init(
        pokemon: Pokemon,
        spriteLoader: SpriteLoader = .init(),
        audioPlayer: AudioPlayer = .init()
    ) {
        self.audioPlayer = audioPlayer
        self.spriteLoader = spriteLoader
        self.pokemon = pokemon
    }
}

// MARK: - Calculated PokemonViewModelProtocol properties
extension PokemonViewModel: PokemonViewModelProtocol {
    var id: Int { pokemon.id }
    var name: String { pokemon.capitalizedName }
    var height: String { pokemon.formattedHeight }
    var weight: String { pokemon.formattedWeight }
    var isLight: Bool { color?.isLight ?? false }
    var types: String { pokemon.typeList }
    var abilities: String { pokemon.abilityList }
    var stats: [Stat] { pokemon.stats }
    var latestCry: String? { pokemon.cries.latest }
    var moves: String { pokemon.moveList }
}

// MARK: - Public PokemonViewModelProtocol functions
extension PokemonViewModel {
    @MainActor
    func loadSprite() async {
        frontSprite = await spriteLoader.loadSprite(from: pokemon.sprite.front)
        color = Color(uiColor: frontSprite?.dominantColor ?? .darkGray)
        backSprite = await spriteLoader.loadSprite(from: pokemon.sprite.back)
    }

    @MainActor
    func playBattleCry(_ urlString: String) async {
        await audioPlayer.play(from: urlString)
    }
}

// MARK: - Equatable
extension PokemonViewModel: Equatable {
    static func == (lhs: PokemonViewModel, rhs: PokemonViewModel) -> Bool {
        lhs.id == rhs.id
    }
}
