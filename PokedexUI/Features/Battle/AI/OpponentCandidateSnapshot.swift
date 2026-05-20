import Foundation

/// Sendable snapshot of Pokemon data for the opponent-picker AI prompt.
struct OpponentCandidateSnapshot: Sendable {
    let id: Int
    let name: String
    let typeNames: [String]
    let baseStatTotal: Int
    let stats: [String: Int]
    let generationName: String?
    let isLegendary: Bool
    let isMythical: Bool
}

extension OpponentCandidateSnapshot {
    @MainActor
    static func player(_ pokemon: Pokemon, fallbackTypes: [String] = []) -> OpponentCandidateSnapshot {
        let statLookup = Dictionary(uniqueKeysWithValues: pokemon.stats.map { ($0.stat.name, $0.baseStat) })
        let types = pokemon.types.map(\.type.name)
        return OpponentCandidateSnapshot(
            id: pokemon.id,
            name: pokemon.name,
            typeNames: types.isEmpty ? fallbackTypes : types,
            baseStatTotal: statLookup.values.reduce(0, +),
            stats: statLookup,
            generationName: pokemon.generationName,
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
            stats: [:],
            generationName: pokemon.generationName,
            isLegendary: pokemon.isLegendary,
            isMythical: pokemon.isMythical
        )
    }
}
