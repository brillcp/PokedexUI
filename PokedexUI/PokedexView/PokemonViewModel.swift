import SwiftUI

/// Protocol for Pokémon view models providing display-ready Pokémon data.
protocol PokemonViewModelProtocol {
    /// The Pokémon front sprite image.
    var frontSprite: String { get }
    /// The Pokémon back sprite image.
    var backSprite: String? { get }
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
    /// A boolean value that determine if the Pokémon is bookmarked.
    var isBookmarked: Bool { get set }

}

// MARK: -
/// ViewModel providing formatted and display-ready data for a single Pokémon.
@Observable
final class PokemonViewModel {
    @ObservationIgnored
    private(set) var statLookup: [String: Int]
    private(set) var pokemon: Pokemon

    // MARK: - Public properties
    var isBookmarked: Bool

    /// Initializes the ViewModel with Pokémon details.
    /// - Parameter pokemon: The detailed Pokémon model.
    init(pokemon: Pokemon) {
        self.pokemon = pokemon
        self.statLookup = Dictionary(uniqueKeysWithValues: pokemon.stats.map { ($0.stat.name, $0.baseStat) })
        self.isBookmarked = pokemon.isBookmarked
    }
}

// MARK: - Calculated PokemonViewModelProtocol properties
extension PokemonViewModel: PokemonViewModelProtocol {
    var id: Int { pokemon.id }
    var name: String { pokemon.capitalizedName }
    var frontSprite: String { pokemon.sprite.front }
    var backSprite: String? { pokemon.sprite.back }
    var height: String { pokemon.formattedHeight }
    var weight: String { pokemon.formattedWeight }
    var isLight: Bool { false }
    var types: String { pokemon.typeList }
    var abilities: String { pokemon.abilityList }
    var stats: [Stat] { pokemon.stats }
    var latestCry: String? { pokemon.cries.latest }
    var moves: String { pokemon.moveList }
}

// MARK: - Public PokemonViewModelProtocol functions
@MainActor
extension PokemonViewModel {
    func playBattleCry(_ urlString: String, audioPlayer: AudioPlayer) async {
        await audioPlayer.play(from: urlString)
    }
}

// MARK: - Equatable
extension PokemonViewModel: Equatable {
    static func == (lhs: PokemonViewModel, rhs: PokemonViewModel) -> Bool {
        lhs.id == rhs.id
    }
}
