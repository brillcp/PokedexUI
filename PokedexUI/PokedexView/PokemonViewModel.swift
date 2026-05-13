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
    /// "Mouse Pokémon", etc.
    var genus: String? { get }
    /// "generation-i" style name.
    var generationName: String? { get }
    /// `-1` genderless, else `0...8` (1/8 increments female).
    var genderRate: Int { get }
    /// PokeAPI capture rate (0–255). 255 = easiest.
    var captureRate: Int { get }
    /// Steps required to hatch: `(hatchCounter + 1) * 255`.
    var hatchSteps: Int { get }
    /// Egg group display names.
    var eggGroups: [String] { get }
    /// Evolution chain id (last path component) for lazy fetch.
    var evolutionChainId: String? { get }
    /// Sum of all six base stats.
    var baseStatTotal: Int { get }
    /// Lowercase type names (e.g. `["fire", "flying"]`) for effectiveness lookup.
    var typeNames: [String] { get }
    /// `true` when this pokemon is flagged legendary or mythical.
    var isLegendary: Bool { get }
    var isMythical: Bool { get }
}

// MARK: -
/// ViewModel providing formatted and display-ready data for a single Pokémon.
///
/// All derived values that involve dictionary/string allocation (stat lookup, normalized
/// search haystack, comma-joined names) are computed on first access and cached on a
/// reference-typed `Derived` companion. Copying the struct copies the cache pointer, so
/// callers that copy the value reuse work done by their siblings.
struct PokemonViewModel {
    private(set) var pokemon: Pokemon
    let id: Int
    let name: String
    let frontSprite: String

    var isBookmarked: Bool

    private let derived: Derived

    init(pokemon: Pokemon) {
        self.pokemon = pokemon
        self.id = pokemon.id
        self.name = pokemon.name.capitalized
        self.frontSprite = pokemon.sprite.front
        self.isBookmarked = pokemon.isBookmarked
        self.derived = Derived()
    }

    /// Stat name → base value. Used by sorting + the battle engine.
    var statLookup: [String: Int] {
        derived.statLookup(stats: pokemon.stats)
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
        derived.joined(\.cachedTypes) {
            pokemon.types.map { $0.type }.joinedCapitalizedNames
        }
    }
    var abilities: String {
        derived.joined(\.cachedAbilities) {
            pokemon.abilities.map { $0.ability }.joinedCapitalizedNames
        }
    }
    var moves: String {
        derived.joined(\.cachedMoves) {
            pokemon.moves.map { $0.move }.joinedCapitalizedNames
        }
    }
    var searchHaystack: String {
        derived.searchHaystack(rawName: pokemon.name, types: pokemon.types)
    }
    var habitat: String? {
        pokemon.habitat?.capitalized
    }
    var flavorText: String? {
        pokemon.flavorText
    }
    var genus: String? { pokemon.genus }
    var generationName: String? { pokemon.generationName }
    var genderRate: Int { pokemon.genderRate }
    var captureRate: Int { pokemon.captureRate }
    var hatchSteps: Int { (pokemon.hatchCounter + 1) * 255 }
    var eggGroups: [String] {
        pokemon.eggGroups.map { $0.replacingOccurrences(of: "-", with: " ").capitalized }
    }
    var evolutionChainId: String? { pokemon.evolutionChainId }
    var baseStatTotal: Int { pokemon.stats.map(\.baseStat).reduce(0, +) }
    var typeNames: [String] { pokemon.types.map { $0.type.name } }
    var isLegendary: Bool { pokemon.isLegendary }
    var isMythical: Bool { pokemon.isMythical }
}

// MARK: - Lazy cache companion
/// Reference-typed cache for derived display strings + lookups. Lives behind the
/// struct so each `PokemonViewModel` instance gets its own memoization box without
/// turning the viewmodel itself into a class.
private final class Derived {
    var cachedStatLookup: [String: Int]?
    var cachedSearchHaystack: String?
    var cachedTypes: String?
    var cachedAbilities: String?
    var cachedMoves: String?

    func statLookup(stats: [Stat]) -> [String: Int] {
        if let cached = cachedStatLookup { return cached }
        let map = Dictionary(uniqueKeysWithValues: stats.map { ($0.stat.name, $0.baseStat) })
        cachedStatLookup = map
        return map
    }

    func searchHaystack(rawName: String, types: [Type]) -> String {
        if let cached = cachedSearchHaystack { return cached }
        let typeNames = types.map { $0.type.name }.joined(separator: " ")
        let result = "\(rawName) \(typeNames)".normalize
        cachedSearchHaystack = result
        return result
    }

    /// Helper: read or compute a cached String slot via key-path.
    func joined(_ keyPath: ReferenceWritableKeyPath<Derived, String?>, build: () -> String) -> String {
        if let cached = self[keyPath: keyPath] { return cached }
        let value = build()
        self[keyPath: keyPath] = value
        return value
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
