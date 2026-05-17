import SwiftUI

// MARK: - PokemonViewModel
/// ViewModel providing formatted and display-ready data for a single Pokémon.
///
/// All derived values that involve dictionary/string allocation (stat lookup, normalized
/// search haystack, comma-joined names) are computed on first access and cached on a
/// reference-typed `Derived` companion. Copying the struct copies the cache pointer, so
/// callers that copy the value reuse work done by their siblings.
struct PokemonViewModel {
    private let derived: Derived

    let id: Int
    let name: String
    let frontSprite: String
    var isBookmarked: Bool

    private(set) var pokemon: Pokemon

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

// MARK: - Computed display properties
extension PokemonViewModel {
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

/// Internal helper: anything name-bearing that can be joined into a comma
/// separated capitalized list (abilities, moves, types). Keeps the joining
/// logic in one place rather than scattering `.map(\.name).joined(...)`.
private protocol NameProvidable {
    var name: String { get }
}

private extension Array where Element: NameProvidable {
    var joinedCapitalizedNames: String {
        map { $0.name.capitalized }.joined(separator: ", ")
    }
}

extension APIItem: NameProvidable {}
