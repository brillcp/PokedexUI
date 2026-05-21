import Foundation

/// Sendable DTO carrying just the fields the AI needs to evaluate an
/// opponent. Pure data; heuristics live in ``OpponentStrategy`` and the
/// `Pokemon`-model adapters below.
struct OpponentCandidateSnapshot: Sendable {
    let id: Int
    let name: String
    let typeNames: [String]
    let baseStatTotal: Int
    let isLegendary: Bool
    let isMythical: Bool
}

/// @MainActor adapters that convert a `Pokemon` SwiftData model into the
/// Sendable AI snapshot. Kept in the same file as the DTO; the adapter
/// methods are the only place the DTO touches the persistence model.
extension OpponentCandidateSnapshot {

    @MainActor
    static func player(_ pokemon: Pokemon, fallbackTypes: [String] = []) -> OpponentCandidateSnapshot {
        let types = pokemon.types.map(\.type.name)
        return OpponentCandidateSnapshot(
            id: pokemon.id,
            name: pokemon.name,
            typeNames: types.isEmpty ? fallbackTypes : types,
            baseStatTotal: pokemon.stats.map(\.baseStat).reduce(0, +),
            isLegendary: pokemon.isLegendary,
            isMythical: pokemon.isMythical
        )
    }

    @MainActor
    static func candidate(_ pokemon: Pokemon) -> OpponentCandidateSnapshot {
        OpponentCandidateSnapshot(
            id: pokemon.id,
            name: pokemon.name,
            typeNames: pokemon.types.map(\.type.name),
            baseStatTotal: pokemon.stats.map(\.baseStat).reduce(0, +),
            isLegendary: pokemon.isLegendary,
            isMythical: pokemon.isMythical
        )
    }
}
