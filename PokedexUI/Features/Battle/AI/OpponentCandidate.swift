import Foundation

/// Sendable DTO carrying just the fields the AI needs to evaluate an
/// opponent. Pure data; heuristics live in ``OpponentStrategy``.
struct OpponentCandidate: Sendable {
    let id: Int
    let name: String
    let typeNames: [String]
    let baseStatTotal: Int
    let isLegendary: Bool
    let isMythical: Bool
}

extension OpponentCandidate {
    /// Build a candidate from a `Pokemon` SwiftData model. The only
    /// place this DTO touches the persistence model. `fallbackTypes` is
    /// applied when the pokemon has no types of its own (rare; used by
    /// the player snapshot to inherit the chosen lead's types).
    @MainActor
    init(pokemon: Pokemon, fallbackTypes: [String] = []) {
        let types = pokemon.types.map(\.type.name)
        self.init(
            id: pokemon.id,
            name: pokemon.name,
            typeNames: types.isEmpty ? fallbackTypes : types,
            baseStatTotal: pokemon.stats.map(\.baseStat).reduce(0, +),
            isLegendary: pokemon.isLegendary,
            isMythical: pokemon.isMythical
        )
    }
}
