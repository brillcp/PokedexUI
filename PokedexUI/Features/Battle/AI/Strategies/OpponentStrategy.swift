import BattleKit
import Foundation

/// Deterministic AI logic for opponent selection: matchup scoring, pool
/// filtering, and the heuristic fallback used when the LLM is unavailable
/// or returns an unusable response.
enum OpponentStrategy {

    /// Filter candidates within ±BST tolerance, reject hard counters,
    /// score-rank survivors, then shuffle a top slice. Falls back to the
    /// unfiltered pool if filtering leaves too few candidates.
    static func balancedPool(
        from snapshots: [OpponentCandidateSnapshot],
        playerBST: Int,
        playerTypes: [String],
        chart: TypeChart?,
        limit: Int = 50
    ) -> [OpponentCandidateSnapshot] {
        let filtered = snapshots.filter { candidate in
            let delta = candidate.baseStatTotal - playerBST
            guard delta >= -120 && delta <= 70 else { return false }
            guard let chart, !playerTypes.isEmpty, !candidate.typeNames.isEmpty else { return true }
            let candidatePressure = chart.bestSTABMultiplier(attackerTypes: candidate.typeNames, defenderTypes: playerTypes)
            let playerPressure = chart.bestSTABMultiplier(attackerTypes: playerTypes, defenderTypes: candidate.typeNames)
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

    /// Best opponent id by full matchup scoring; nil if the candidate pool is empty.
    static func heuristicPick(
        player: OpponentCandidateSnapshot,
        candidates: [OpponentCandidateSnapshot],
        typeChart: TypeChart?
    ) -> Int? {
        bestOpponent(player: player, candidates: candidates, typeChart: typeChart)?.id
    }

    /// Composite matchup score: BST closeness, type pressure, legendary/mega
    /// caveats. Used by both `balancedPool` (filtering pre-LLM) and
    /// `heuristicPick` (fallback selection). Single source of truth.
    static func score(
        player: OpponentCandidateSnapshot,
        candidate: OpponentCandidateSnapshot,
        typeChart: TypeChart?
    ) -> Double {
        let delta = candidate.baseStatTotal - player.baseStatTotal
        let absDelta = abs(delta)
        var score = 0.0

        if absDelta <= 70 {
            score += 35 - Double(absDelta) * 0.20
        } else if delta < -90 {
            score -= 70 + Double(abs(delta + 90)) * 0.35
        } else if delta > 160 {
            score -= 45 + Double(delta - 160) * 0.20
        } else {
            score += max(0, 20 - Double(absDelta - 70) * 0.15)
        }

        if delta < 0, delta >= -50 { score += 12 }

        if let typeChart {
            let candidatePressure = typeChart.bestSTABMultiplier(attackerTypes: candidate.typeNames, defenderTypes: player.typeNames)
            let playerPressure = typeChart.bestSTABMultiplier(attackerTypes: player.typeNames, defenderTypes: candidate.typeNames)

            score += pressureScore(candidatePressure)
            score -= vulnerabilityPenalty(playerPressure)

            if candidatePressure >= 1.5, playerPressure >= 1.5 { score += 18 }
            if candidatePressure >= 4, playerPressure <= 1 { score -= 25 }
            if candidatePressure < 1, playerPressure >= 2 { score -= 18 }
        }

        if candidate.isLegendary || candidate.isMythical {
            score += player.baseStatTotal >= 500 ? 10 : -8
        }
        if candidate.name.localizedCaseInsensitiveContains("mega") {
            score += player.baseStatTotal >= 540 ? 4 : -20
        }

        return score
    }
}

// MARK: - Private
private extension OpponentStrategy {

    static func bestOpponent(
        player: OpponentCandidateSnapshot,
        candidates: [OpponentCandidateSnapshot],
        typeChart: TypeChart?
    ) -> OpponentCandidateSnapshot? {
        let tiered = candidates.filter { candidate in
            let delta = candidate.baseStatTotal - player.baseStatTotal
            return delta >= -90 && delta <= 160
        }
        let pool = tiered.isEmpty ? candidates : tiered
        return pool.max { lhs, rhs in
            score(player: player, candidate: lhs, typeChart: typeChart)
                < score(player: player, candidate: rhs, typeChart: typeChart)
        }
    }

    /// Lightweight filter-time score used while shortening the pool, before
    /// full `score(player:candidate:typeChart:)` ranks survivors. Coarser
    /// by design.
    static func poolScore(
        _ candidate: OpponentCandidateSnapshot,
        playerBST: Int,
        playerTypes: [String],
        chart: TypeChart?
    ) -> Double {
        let delta = candidate.baseStatTotal - playerBST
        var score = max(0, 120.0 - Double(abs(delta)))
        if delta < 0, delta >= -60 { score += 15 }
        guard let chart, !playerTypes.isEmpty, !candidate.typeNames.isEmpty else { return score }
        let cPressure = chart.bestSTABMultiplier(attackerTypes: candidate.typeNames, defenderTypes: playerTypes)
        let pPressure = chart.bestSTABMultiplier(attackerTypes: playerTypes, defenderTypes: candidate.typeNames)
        if cPressure >= 1.5, pPressure >= 1.5 { score += 20 }
        if cPressure >= 1, pPressure >= 1 { score += 10 }
        return score
    }

    static func pressureScore(_ multiplier: Double) -> Double {
        if multiplier >= 4 { return 8 }
        if multiplier >= 2 { return 30 }
        if multiplier >= 1 { return 10 }
        if multiplier > 0 { return -4 }
        return -12
    }

    static func vulnerabilityPenalty(_ multiplier: Double) -> Double {
        if multiplier >= 4 { return 32 }
        if multiplier >= 2 { return 14 }
        if multiplier >= 1 { return 0 }
        return -8
    }
}
