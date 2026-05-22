import SwiftUI
import PokeBattleKit

/// Display-ready data for a single Pokemon, computed eagerly on init.
struct PokemonViewModel {
    let id: Int
    let name: String
    let frontSprite: String
    var isBookmarked: Bool

    let statLookup: [String: Int]
    let typeNames: [String]
    let searchHaystack: String
    let types: String
    let abilities: String
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

        let capitalized = pokemon.moveNames.map { $0.capitalized }
        let displayed = Array(capitalized.prefix(10))
        let joined = displayed.joined(separator: ", ")
        self.moves = capitalized.count > displayed.count ? "\(joined)…" : joined
    }
}

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

extension PokemonViewModel: PokemonData {}

extension PokemonViewModel: Hashable {
    static func == (lhs: PokemonViewModel, rhs: PokemonViewModel) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

private protocol NameProvidable {
    var name: String { get }
}

// MARK: - Private
private extension Array where Element: NameProvidable {
    var joinedCapitalizedNames: String {
        map { $0.name.capitalized }.joined(separator: ", ")
    }
}

extension APIItem: NameProvidable {}
