import Foundation

/// Sendable snapshot of the fields the opponent-picker AI prompt cares about.
/// Built on the main actor from a SwiftData `Pokemon` row so the AI service
/// (an actor) can format the prompt off-main without crossing isolation into
/// the model store; reading `@Model` properties from the actor's thread is
/// what produced the multi-second hang + crash on tap.
///
/// Scope is the picker only. Once a battle starts, in-round state lives on
/// `BattleCombatant`, which is unrelated — different lifecycle, different
/// fields (HP / status / moves vs. legendary / generation flags).
struct OpponentCandidateSnapshot: Sendable {
    let id: Int
    let name: String
    let typeNames: [String]
    let baseStatTotal: Int
    /// 6-stat lookup keyed by `Stat.stat.name` (e.g. `"hp"`, `"attack"`).
    /// Only populated for the player snapshot; candidate snapshots leave
    /// this empty since the prompt only needs the aggregate BST per candidate.
    let stats: [String: Int]
    let generationName: String?
    let isLegendary: Bool
    let isMythical: Bool
}

extension OpponentCandidateSnapshot {
    /// Full snapshot for the player: includes the 6-stat breakdown.
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

    /// Compact snapshot for each candidate: skips the stat-breakdown dict
    /// (prompt only renders BST).
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
