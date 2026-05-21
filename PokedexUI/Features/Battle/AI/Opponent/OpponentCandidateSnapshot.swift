import Foundation

/// Sendable DTO carrying just the fields the AI needs to evaluate an
/// opponent. Pure data; heuristics live in ``OpponentStrategy`` and
/// Pokemon-model adapters in `OpponentCandidateSnapshot+Pokemon.swift`.
struct OpponentCandidateSnapshot: Sendable {
    let id: Int
    let name: String
    let typeNames: [String]
    let baseStatTotal: Int
    let stats: [String: Int]
    let generationName: String?
    let isLegendary: Bool
    let isMythical: Bool

    var flagSuffix: String {
        if isLegendary { return ", legendary" }
        if isMythical { return ", mythical" }
        return ""
    }
}

/// @MainActor adapters that convert a `Pokemon` SwiftData model into the
/// Sendable AI snapshot. Kept in a separate file so the pure DTO has no
/// dependency on the persistence model.
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
