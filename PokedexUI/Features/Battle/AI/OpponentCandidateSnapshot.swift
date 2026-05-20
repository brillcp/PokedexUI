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
    /// Filter snapshots to opponents within `±120` BST of the player and roughly fair type matchup,
    /// then return up to `limit` randomly sampled candidates. Falls back to the full snapshot list
    /// when the filter yields fewer than `limit` matches.
    static func balancedPool(
        from snapshots: [OpponentCandidateSnapshot],
        playerBST: Int,
        playerTypes: [String],
        chart: TypeChart?,
        limit: Int = 40
    ) -> [OpponentCandidateSnapshot] {
        let filtered = snapshots.filter { candidate in
            guard abs(candidate.baseStatTotal - playerBST) <= 120 else { return false }
            guard let chart, !playerTypes.isEmpty else { return true }
            guard !candidate.typeNames.isEmpty else { return true }
            let candidatePressure = candidate.typeNames
                .map { chart.multiplier(attacking: $0, defenders: playerTypes) }
                .max() ?? 1
            let playerPressure = playerTypes
                .map { chart.multiplier(attacking: $0, defenders: candidate.typeNames) }
                .max() ?? 1
            if candidatePressure >= 2, playerPressure < 1.5 { return false }
            if playerPressure == 0 { return false }
            return true
        }
        let pool = filtered.count >= limit ? filtered : snapshots
        return Array(pool.shuffled().prefix(limit))
    }

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
