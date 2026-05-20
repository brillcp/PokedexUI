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
    /// Filter to opponents within +/-120 BST, reject hard counters, score-rank survivors,
    /// then return a shuffled shortlist of top candidates for the LLM.
    static func balancedPool(
        from snapshots: [OpponentCandidateSnapshot],
        playerBST: Int,
        playerTypes: [String],
        chart: TypeChart?,
        limit: Int = 8
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
        let ranked = pool.sorted { a, b in
            poolScore(a, playerBST: playerBST, playerTypes: playerTypes, chart: chart)
            > poolScore(b, playerBST: playerBST, playerTypes: playerTypes, chart: chart)
        }
        let shortlist = Array(ranked.prefix(limit + limit / 2))
        return Array(shortlist.shuffled().prefix(limit))
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

private extension OpponentCandidateSnapshot {
    /// BST closeness + mutual type threat, used to rank filtered pool before truncation.
    static func poolScore(
        _ candidate: OpponentCandidateSnapshot,
        playerBST: Int,
        playerTypes: [String],
        chart: TypeChart?
    ) -> Double {
        var score = max(0, 120.0 - Double(abs(candidate.baseStatTotal - playerBST)))
        guard let chart, !playerTypes.isEmpty, !candidate.typeNames.isEmpty else { return score }
        let cPressure = candidate.typeNames
            .map { chart.multiplier(attacking: $0, defenders: playerTypes) }.max() ?? 1
        let pPressure = playerTypes
            .map { chart.multiplier(attacking: $0, defenders: candidate.typeNames) }.max() ?? 1
        if cPressure >= 1.5, pPressure >= 1.5 { score += 20 }
        if cPressure >= 1, pPressure >= 1 { score += 10 }
        return score
    }
}
