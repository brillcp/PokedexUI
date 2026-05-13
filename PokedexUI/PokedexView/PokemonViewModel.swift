import SwiftUI

/// Protocol for Pokémon view models providing display-ready Pokémon data.
protocol PokemonViewModelProtocol {
    /// The Pokémon front sprite image.
    var frontSprite: String { get }
    /// The Pokémon back sprite image.
    var backSprite: String? { get }
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
    /// Precomputed, normalized text used for search matching.
    var searchHaystack: String { get }
    /// Display-ready habitat name, if available.
    var habitat: String? { get }
    /// English Pokédex flavor text, if available.
    var flavorText: String? { get }
}

// MARK: -
/// ViewModel providing formatted and display-ready data for a single Pokémon.
struct PokemonViewModel {
    private(set) var statLookup: [String: Int]
    private(set) var pokemon: Pokemon
    let id: Int
    let name: String
    let frontSprite: String
    let searchHaystack: String

    // MARK: - Public properties
    var isBookmarked: Bool

    /// Initializes the ViewModel with Pokémon details.
    /// - Parameter pokemon: The detailed Pokémon model.
    init(pokemon: Pokemon) {
        self.pokemon = pokemon
        self.statLookup = Dictionary(uniqueKeysWithValues: pokemon.stats.map { ($0.stat.name, $0.baseStat) })
        self.isBookmarked = pokemon.isBookmarked
        self.id = pokemon.id
        self.name = pokemon.name.capitalized
        self.frontSprite = pokemon.sprite.front
        let typeNames = pokemon.types.map { $0.type.name }.joined(separator: " ")
        self.searchHaystack = "\(pokemon.name) \(typeNames)".normalize
    }
}

// MARK: - Calculated PokemonViewModelProtocol properties
extension PokemonViewModel: PokemonViewModelProtocol {
    var backSprite: String? { pokemon.sprite.back }
    var height: String { "\(Double(pokemon.height) / 10.0) m" }
    var weight: String { "\(Double(pokemon.weight) / 10.0) kg" }
    var latestCry: String? { pokemon.cries.latest }
    var stats: [Stat] { pokemon.stats }

    var types: String {
        pokemon.types.map { $0.type }.joinedCapitalizedNames
    }
    var abilities: String {
        pokemon.abilities.map { $0.ability }.joinedCapitalizedNames
    }
    var moves: String {
        pokemon.moves.map { $0.move }.joinedCapitalizedNames
    }
    var habitat: String? {
        pokemon.habitat?.capitalized
    }
    var flavorText: String? {
        pokemon.flavorText
    }
}

// MARK: - Equatable / Hashable
extension PokemonViewModel: Hashable {
    static func == (lhs: PokemonViewModel, rhs: PokemonViewModel) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Array helper functions
private protocol NameProvidable {
    var name: String { get }
}

private extension Array where Element: NameProvidable {
    var joinedCapitalizedNames: String {
        map { $0.name.capitalized }.joined(separator: ", ")
    }
}

extension APIItem: NameProvidable {}
