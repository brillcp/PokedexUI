import SwiftUI

/// Protocol for Pokémon view models providing display-ready Pokémon data.
protocol PokemonViewModelProtocol {
    /// The Pokémon front sprite image.
    var frontImage: UIImage? { get }
    /// The Pokémon back sprite image.
    var backImage: UIImage? { get }
    /// The dominant color extracted from the image.
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
    private let audioStreamer: AudioPlayer
    private let imageLoader: ImageLoader
    private let pokemon: Pokemon

    // MARK: - Public properties
    var frontImage: UIImage?
    var backImage: UIImage?
    var color: Color?

    /// Initializes the ViewModel with Pokémon details and an optional image loader.
    /// - Parameters:
    ///   - pokemon: The detailed Pokémon model.
    ///   - imageLoader: The loader for sprite images.
    ///   - audioStreamer: The audio player to play the pokemon battle cry.
    init(
        pokemon: Pokemon,
        imageLoader: ImageLoader = .init(),
        audioStreamer: AudioPlayer = .init()
    ) {
        self.audioStreamer = audioStreamer
        self.imageLoader = imageLoader
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
        frontImage = await imageLoader.loadImage(from: pokemon.sprite.front)
        color = Color(uiColor: frontImage?.dominantColor ?? .darkGray)
        backImage = await imageLoader.loadImage(from: pokemon.sprite.back)
    }

    @MainActor
    func playBattleCry(_ urlString: String) async {
        await audioStreamer.play(from: urlString)
    }
}

// MARK: - Equatable
extension PokemonViewModel: Equatable {
    static func == (lhs: PokemonViewModel, rhs: PokemonViewModel) -> Bool {
        lhs.id == rhs.id
    }
}
