import PokeBattleKit

// MARK: - OpponentStrategy

/// Deterministic AI for opponent selection. Owns the pool filter, the
/// matchup-scoring function, and the heuristic fallback used when the
/// LLM is unavailable.
enum OpponentStrategy {

    /// Filter candidates within BST tolerance, reject hard counters,
    /// score-rank survivors, then shuffle a top slice. Falls back to the
    /// unfiltered pool if filtering leaves too few candidates.
    static func balancedPool(
        from snapshots: [OpponentCandidate],
        playerBST: Int,
        playerTypes: [String],
        chart: TypeChart?,
        limit: Int = 50
    ) -> [OpponentCandidate] {
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

    /// Best opponent id by full matchup scoring; nil if pool is empty.
    static func heuristicPick(
        player: OpponentCandidate,
        candidates: [OpponentCandidate],
        typeChart: TypeChart?
    ) -> Int? {
        let tiered = candidates.filter { candidate in
            let delta = candidate.baseStatTotal - player.baseStatTotal
            return delta >= -90 && delta <= 160
        }
        let pool = tiered.isEmpty ? candidates : tiered
        return pool.max { lhs, rhs in
            matchupScore(player: player, candidate: lhs, typeChart: typeChart)
                < matchupScore(player: player, candidate: rhs, typeChart: typeChart)
        }?.id
    }
}

// MARK: - Private
private extension OpponentStrategy {

    /// Composite matchup score: BST closeness, type pressure, legendary
    /// and mega caveats. Used by `heuristicPick` for final ranking.
    static func matchupScore(
        player: OpponentCandidate,
        candidate: OpponentCandidate,
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

    static func poolScore(
        _ candidate: OpponentCandidate,
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

// MARK: - OpponentPrompt

/// Builds the prompt asking the LLM to pick a fair opponent from a
/// pre-filtered candidate pool, and parses the model's index reply.
enum OpponentPrompt {

    struct Output {
        let prompt: String
        let indexMap: [Int: Int]
    }

    static func build(
        player: OpponentCandidate,
        candidates: [OpponentCandidate],
        typeChart: TypeChart?
    ) -> Output {
        var indexMap: [Int: Int] = [:]
        let playerBST = player.baseStatTotal
        let roster = Array(candidates.indices).shuffled().enumerated().map { displayIdx, originalIdx in
            let idx = displayIdx + 1
            indexMap[idx] = candidates[originalIdx].id
            return describe(candidates[originalIdx], index: idx, player: player, playerBST: playerBST, typeChart: typeChart)
        }.joined(separator: "\n")

        let prompt = """
        Pick a fair opponent for \(player.name) (\(player.typeNames.joined(separator: "/")), BST \(playerBST)).

        \(roster)

        If "mutual threat", prefer it. If "stronger", avoid it. Return ONLY the number.
        """
        return Output(prompt: prompt, indexMap: indexMap)
    }

    static func parsePick(raw: String, indexMap: [Int: Int]) -> Int? {
        guard let displayIdx = firstInt(in: raw) else { return nil }
        return indexMap[displayIdx]
    }
}

// MARK: - Private
private extension OpponentPrompt {

    static func describe(
        _ candidate: OpponentCandidate,
        index: Int,
        player: OpponentCandidate,
        playerBST: Int,
        typeChart: TypeChart?
    ) -> String {
        let types = candidate.typeNames.joined(separator: "/")
        let bstDelta = candidate.baseStatTotal - playerBST
        let bstNote = bstDelta > 20 ? "stronger" : bstDelta < -20 ? "weaker" : "similar"
        var line = "\(index). \(candidate.name) (\(types), BST \(candidate.baseStatTotal), \(bstNote))"

        if let chart = typeChart, !player.typeNames.isEmpty, !candidate.typeNames.isEmpty {
            line += matchupTag(chart: chart, candidate: candidate, player: player)
        }
        if candidate.isLegendary { line += " [legendary]" }
        if candidate.isMythical { line += " [mythical]" }
        return line
    }

    static func matchupTag(
        chart: TypeChart,
        candidate: OpponentCandidate,
        player: OpponentCandidate
    ) -> String {
        let cPressure = chart.bestSTABMultiplier(attackerTypes: candidate.typeNames, defenderTypes: player.typeNames)
        let pPressure = chart.bestSTABMultiplier(attackerTypes: player.typeNames, defenderTypes: candidate.typeNames)
        var matchup: [String] = []
        if cPressure >= 2 { matchup.append("SE STAB vs you") }
        else if cPressure < 1, cPressure > 0 { matchup.append("resisted vs you") }
        else if cPressure == 0 { matchup.append("immune to their STAB") }
        if pPressure >= 2 { matchup.append("you hit SE") }
        else if pPressure < 1, pPressure > 0 { matchup.append("you resisted") }
        else if pPressure == 0 { matchup.append("they immune to you") }
        if cPressure >= 1.5, pPressure >= 1.5 { matchup.append("mutual threat") }
        return matchup.isEmpty ? "" : " [\(matchup.joined(separator: ", "))]"
    }
}
