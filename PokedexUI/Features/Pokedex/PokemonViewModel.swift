import SwiftUI

// MARK: - Focused protocols (Interface Segregation)

/// Minimum surface needed to render a sprite cell: id, name and the two sprite URLs.
/// Used by grid cells and any view that just needs to identify a pokemon visually.
protocol IdentifiablePokemon {
    /// Unique Pokémon identifier (national dex number).
    var id: Int { get }
    /// Display-ready Pokémon name.
    var name: String { get }
    /// The Pokémon front sprite image URL.
    var frontSprite: String { get }
    /// The Pokémon back sprite image URL.
    var backSprite: String? { get }
}

/// Combat-relevant numbers: read by the battle engine and by sort comparators
/// that key on base stats.
protocol PokemonStatsProviding {
    /// Statistics for the Pokémon.
    var stats: [Stat] { get }
    /// Sum of all six base stats.
    var baseStatTotal: Int { get }
    /// Lowercase type names (e.g. `["fire", "flying"]`) for effectiveness lookup.
    var typeNames: [String] { get }
}

/// Display-formatted strings + species metadata for the detail view, bookmarks,
/// and search. Anything that exists only to be shown to the user lives here.
protocol PokemonDisplayData {
    /// Types as a comma-joined display string.
    var types: String { get }
    /// Abilities as a comma-joined display string.
    var abilities: String { get }
    /// Up to 10 move names joined for the detail view's Moves row.
    var moves: String { get }
    /// Pokémon height, formatted for display.
    var height: String { get }
    /// Pokémon weight, formatted for display.
    var weight: String { get }
    /// The battle cry of the pokemon.
    var latestCry: String? { get }
    /// Whether this Pokémon is currently bookmarked.
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
    /// Evolution chain id (last path component) for lazy fetch.
    var evolutionChainId: String? { get }
    /// `true` when this pokemon is flagged legendary.
    var isLegendary: Bool { get }
    /// `true` when this pokemon is flagged mythical.
    var isMythical: Bool { get }
}

/// Aggregate protocol used where the full Pokémon contract is needed (the
/// detail view, mostly). Smaller surfaces should use the focused protocols.
typealias PokemonViewModelProtocol = IdentifiablePokemon & PokemonStatsProviding & PokemonDisplayData

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
    /// Display-friendly list capped at the first 10 moves; appends an ellipsis
    /// when the underlying movepool is larger. Battles draw from the full list.
    var moves: String {
        derived.joined(\.cachedMoves) {
            let names = pokemon.moves.map { $0.move.name.capitalized }
            let displayed = Array(names.prefix(10))
            let joined = displayed.joined(separator: ", ")
            return names.count > displayed.count ? "\(joined)…" : joined
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
