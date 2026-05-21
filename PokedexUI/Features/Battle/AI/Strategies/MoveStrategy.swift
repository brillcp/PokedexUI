import BattleKit
import Foundation

/// Deterministic AI logic for in-battle move selection: heuristic fallback
/// when the LLM is unavailable, post-pick adjustments for wasted boosts and
/// re-statusing, and immune-move repair.
enum MoveStrategy {

    /// Highest-scoring move accounting for damage, recency, low-HP bias.
    static func heuristicPick(
        attacker: BattleCombatant,
        defender: BattleCombatant,
        moves: [MoveDetail],
        typeChart: TypeChart,
        recentMoves: [String]
    ) -> MoveDetail? {
        moves.max { lhs, rhs in
            inBattleScore(move: lhs, attacker: attacker, defender: defender, typeChart: typeChart, recentMoves: recentMoves)
            < inBattleScore(move: rhs, attacker: attacker, defender: defender, typeChart: typeChart, recentMoves: recentMoves)
        }
    }

    /// Override boost/status picks when game state makes them wasteful.
    static func phaseAdjust(
        pick: MoveDetail,
        attacker: BattleCombatant,
        defender: BattleCombatant,
        moves: [MoveDetail],
        typeChart: TypeChart
    ) -> MoveDetail {
        if (pick.power ?? 0) == 0,
           pick.statChangeDeltas.contains(where: { $0 > 0 }),
           attacker.statStages.values.contains(where: { $0 >= 2 }) {
            return fallbackDamageMove(from: moves, defender: defender, typeChart: typeChart) ?? pick
        }
        if pick.ailment != "none", defender.status != .none {
            return fallbackDamageMove(from: moves, defender: defender, typeChart: typeChart) ?? pick
        }
        return pick
    }

    /// Swap an immune pick for the heuristic fallback when possible.
    static func immuneRepair(
        pick: MoveDetail,
        defender: BattleCombatant,
        typeChart: TypeChart,
        fallback: MoveDetail
    ) -> MoveDetail {
        let eff = typeChart.multiplier(attacking: pick.typeName, defenders: defender.typeNames)
        if eff == 0, fallback.name != pick.name {
            return fallback
        }
        return pick
    }
}

// MARK: - Private
private extension MoveStrategy {

    static func inBattleScore(
        move: MoveDetail,
        attacker: BattleCombatant,
        defender: BattleCombatant,
        typeChart: TypeChart,
        recentMoves: [String]
    ) -> Double {
        var score = MoveScoring.score(move: move, fighter: attacker, opponent: defender, typeChart: typeChart)

        if recentMoves.last == move.name {
            score -= 18
        } else if recentMoves.contains(move.name) {
            score -= 8
        }

        if (move.power ?? 0) == 0 {
            for (index, stat) in move.statChangeNames.enumerated() where index < move.statChangeDeltas.count {
                let delta = move.statChangeDeltas[index]
                if delta > 0, attacker.stage(for: stat) >= 2 {
                    score -= 18
                }
            }
        }

        if defender.status != .none, move.ailment != "none" {
            score -= 25
        }

        let hpFraction = Double(attacker.currentHP) / Double(max(1, attacker.maxHP))
        if hpFraction <= 0.30 {
            if move.healing > 0 || move.name == "rest" {
                score += 35
            } else if (move.power ?? 0) > 0, move.priority <= 0 {
                score -= 8
            }
            if move.priority > 0, (move.power ?? 0) > 0 {
                score += 6
            }
        }

        return score
    }

    static func fallbackDamageMove(
        from moves: [MoveDetail],
        defender: BattleCombatant,
        typeChart: TypeChart
    ) -> MoveDetail? {
        let scored: [(move: MoveDetail, weight: Double)] = moves.compactMap { move in
            guard let power = move.power, power > 0 else { return nil }
            let eff = typeChart.multiplier(attacking: move.typeName, defenders: defender.typeNames)
            guard eff > 0 else { return nil }
            return (move, Double(power) * eff)
        }
        return scored.max { $0.weight < $1.weight }?.move
    }
}
