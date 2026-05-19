import SwiftUI

// MARK: - PokemonViewModel
/// ViewModel providing formatted and display-ready data for a single Pokémon.
///
/// All derived display values (stat lookup, normalized search haystack,
/// comma-joined name lists) are computed once in `init` and stored as `let`
/// properties. With ~1150 pokemon hydrated at app launch the eager cost is
/// well under 50ms total, and the struct stays a pure value type. No
/// reference-typed cache box sneaking inside.
struct PokemonViewModel {
    let id: Int
    let name: String
    let frontSprite: String
    var isBookmarked: Bool

    /// Stat name → base value. Used by sort comparators and the battle
    /// engine's `BattleCombatant` factory.
    let statLookup: [String: Int]
    let typeNames: [String]
    /// Lowercased, diacritic-stripped concatenation of name + type names.
    /// Search compares against this so per-keystroke filtering doesn't
    /// re-run `.normalize` across every row.
    let searchHaystack: String
    let types: String
    let abilities: String
    /// Capped at the first 10 moves; appends "…" when the underlying
    /// movepool is larger. Battles draw from the full list on `pokemon`.
    let moves: String

    private(set) var pokemon: Pokemon

    init(pokemon: Pokemon) {
        self.pokemon = pokemon
        self.id = pokemon.id
        self.name = pokemon.name.capitalized
        self.frontSprite = pokemon.sprite.front
        self.isBookmarked = pokemon.isBookmarked

        self.statLookup = Dictionary(
            uniqueKeysWithValues: pokemon.stats.map { ($0.stat.name, $0.baseStat) }
        )
        let rawTypeNames = pokemon.types.map { $0.type.name }
        self.typeNames = rawTypeNames
        self.searchHaystack = "\(pokemon.name) \(rawTypeNames.joined(separator: " "))".normalize
        self.types = pokemon.types.map { $0.type }.joinedCapitalizedNames
        self.abilities = pokemon.abilities.map { $0.ability }.joinedCapitalizedNames

        let moveNames = pokemon.moves.map { $0.move.name.capitalized }
        let displayed = Array(moveNames.prefix(10))
        let joined = displayed.joined(separator: ", ")
        self.moves = moveNames.count > displayed.count ? "\(joined)…" : joined
    }
}

// MARK: - Computed display properties

extension PokemonViewModel {
    var backSprite: String? { pokemon.sprite.back }
    var height: String { "\(Double(pokemon.height) / 10.0) m" }
    var weight: String { "\(Double(pokemon.weight) / 10.0) kg" }
    var latestCry: String? { pokemon.cries.latest }
    var stats: [Stat] { pokemon.stats }
    var habitat: String? { pokemon.habitat?.capitalized }
    var flavorText: String? { pokemon.flavorText }
    var genus: String? { pokemon.genus }
    var generationName: String? { pokemon.generationName }
    var genderRate: Int { pokemon.genderRate }
    var captureRate: Int { pokemon.captureRate }
    var evolutionChainId: String? { pokemon.evolutionChainId }
    var baseStatTotal: Int { pokemon.stats.map(\.baseStat).reduce(0, +) }
    var isLegendary: Bool { pokemon.isLegendary }
    var isMythical: Bool { pokemon.isMythical }
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
