import BattleKit
import Foundation

/// Deterministic AI logic for in-battle move selection.
///
/// ``heuristicPick`` produces a fallback used when the LLM is unavailable
/// or returns an invalid pick. ``adjust`` runs the post-pick correction
/// pipeline applied to every chosen move regardless of source (heuristic
/// or LLM): immune-move repair, wasted-boost / re-status overrides,
/// guaranteed-KO upgrade, and redundant-status downgrade.
enum MoveStrategy {

    /// Highest-scoring move accounting for damage, recency, and low-HP bias.
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

    /// Run the full post-pick correction pipeline against `pick`. Pipeline
    /// order: immune repair → phase adjust → KO override → redundant-status
    /// override. Each step is a no-op when its precondition isn't met.
    static func adjust(
        pick: MoveDetail,
        attacker: BattleCombatant,
        defender: BattleCombatant,
        moves: [MoveDetail],
        typeChart: TypeChart,
        fallback: MoveDetail
    ) -> MoveDetail {
        var current = pick
        current = immuneRepair(pick: current, defender: defender, typeChart: typeChart, fallback: fallback)
        current = phaseAdjust(pick: current, attacker: attacker, defender: defender, moves: moves, typeChart: typeChart)
        current = koOverride(pick: current, attacker: attacker, defender: defender, moves: moves, typeChart: typeChart)
        current = statusRedundancyOverride(pick: current, attacker: attacker, defender: defender, moves: moves, typeChart: typeChart)
        return current
    }
}

// MARK: - Private
private extension MoveStrategy {

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

    /// Upgrade `pick` to a guaranteed-KO move when one exists and `pick`
    /// can't finish the defender this turn.
    static func koOverride(
        pick: MoveDetail,
        attacker: BattleCombatant,
        defender: BattleCombatant,
        moves: [MoveDetail],
        typeChart: TypeChart
    ) -> MoveDetail {
        let pickDamage = DamageCalculator.estimateDamage(
            move: pick, attacker: attacker, defender: defender, typeChart: typeChart
        )
        guard pickDamage < defender.currentHP else { return pick }
        guard let killer = DamageCalculator.guaranteedKO(
            attacker: attacker, defender: defender, moves: moves, typeChart: typeChart
        ), killer.name != pick.name else { return pick }
        return killer
    }

    /// Swap a redundant pure-status move for the strongest damage move when
    /// the defender already has a non-`none` status.
    static func statusRedundancyOverride(
        pick: MoveDetail,
        attacker: BattleCombatant,
        defender: BattleCombatant,
        moves: [MoveDetail],
        typeChart: TypeChart
    ) -> MoveDetail {
        guard pick.ailment != "none", (pick.power ?? 0) == 0, defender.status != .none else { return pick }
        let alternatives = moves.filter { $0.name != pick.name }
        guard let best = DamageCalculator.strongestMove(
            attacker: attacker, defender: defender, moves: alternatives, typeChart: typeChart
        ) else { return pick }
        return best.move
    }

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
