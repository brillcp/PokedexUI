import BattleKit
import Foundation

/// LLM prompt + response parsing for picking the next move in battle.
///
/// `build(...)` shuffles move indices so the model can't rely on order,
/// then assembles a context line, per-move description block, and a
/// tactical directive. `parsePick(...)` resolves the LLM's reply (a
/// single integer) back to the original move via the returned index map.
enum MovePrompt {

    struct Output {
        let prompt: String
        let indexMap: [Int: Int]
    }

    static func build(
        attacker: BattleCombatant,
        defender: BattleCombatant,
        moves: [MoveDetail],
        typeChart: TypeChart,
        turnNumber: Int
    ) -> Output {
        let shuffled = Array(moves.indices).shuffled()
        var indexMap: [Int: Int] = [:]
        let movesBlock = shuffled.enumerated().map { displayIdx, originalIdx in
            indexMap[displayIdx] = originalIdx
            let move = moves[originalIdx]
            return describe(move, index: displayIdx, attacker: attacker, defender: defender, typeChart: typeChart)
        }.joined(separator: "\n")
        let situation = BattleContext.compact(attacker: attacker, defender: defender, turnNumber: turnNumber)
        let hint = BattleContext.tacticalHint(attacker: attacker, defender: defender, moves: moves)
        let prompt = """
        \(situation)

        \(movesBlock)

        \(hint) Return ONLY the index.
        """
        return Output(prompt: prompt, indexMap: indexMap)
    }

    /// Resolve the LLM's first-integer reply to the original move, or nil
    /// if no valid index is present.
    static func parsePick(raw: String, indexMap: [Int: Int], moves: [MoveDetail]) -> MoveDetail? {
        guard let shuffledIdx = LLMResponseParser.firstInt(in: raw),
              let originalIdx = indexMap[shuffledIdx],
              moves.indices.contains(originalIdx)
        else { return nil }
        return moves[originalIdx]
    }
}

// MARK: - Private
private extension MovePrompt {

    static func describe(
        _ move: MoveDetail,
        index: Int,
        attacker: BattleCombatant,
        defender: BattleCombatant,
        typeChart: TypeChart
    ) -> String {
        var parts: [String] = []
        parts.append("\(index): \(move.name) (\(move.typeName))")

        if let power = move.power, power > 0 {
            let effectiveness = typeChart.multiplier(attacking: move.typeName, defenders: defender.typeNames)
            let dmg = DamageCalculator.estimateDamage(move: move, attacker: attacker, defender: defender, typeChart: typeChart)
            let acc = move.accuracy ?? 100
            let koTurns = DamageCalculator.turnsToKO(dmg, hp: defender.currentHP)
            var dmgStr = "\(dmg) dmg"
            if koTurns == 1 { dmgStr += ", KOs this turn" }
            else if koTurns == 2 { dmgStr += ", 2-hit KO" }
            else if koTurns == 3 { dmgStr += ", 3-hit KO" }
            if acc < 100 { dmgStr += ", \(acc)% acc" }
            if attacker.typeNames.contains(move.typeName) { dmgStr += ", STAB" }
            if effectiveness >= 2 { dmgStr += ", super effective" }
            else if effectiveness > 0, effectiveness < 1 { dmgStr += ", resisted" }
            else if effectiveness == 0 { dmgStr += ", IMMUNE" }
            if move.hasSelfDebuff { dmgStr += ", lowers your stats" }
            if move.isRechargeMove { dmgStr += ", must recharge next turn" }
            if move.priority > 0 { dmgStr += ", priority" }
            parts.append(dmgStr)
        } else {
            var effects: [String] = []
            if move.ailment != "none" {
                let chance = move.ailmentChance > 0 ? " (\(move.ailmentChance)%)" : ""
                effects.append("inflicts \(move.ailment)\(chance)")
            }
            for (i, stat) in move.statChangeNames.enumerated() where i < move.statChangeDeltas.count {
                let delta = move.statChangeDeltas[i]
                let sign = delta > 0 ? "+" : ""
                effects.append("\(sign)\(delta) \(BattleContext.shortStat(stat))")
            }
            if move.healing > 0 { effects.append("heals \(move.healing)%") }
            if move.name == "rest" { effects.append("full heal, sleeps 2 turns") }
            parts.append(effects.joined(separator: ", "))
        }

        return parts.joined(separator: " - ")
    }
}
