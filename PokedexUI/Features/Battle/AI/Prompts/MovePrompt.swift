import BattleKit
import Foundation

/// Builds the per-turn move-pick prompt and parses the model's index
/// reply. The prompt opens with a one-line battle context, optionally
/// lists the defender's observed moves with damage-back-at-you tags,
/// then enumerates the attacker's options in a randomised order.
enum MovePrompt {

    struct Output {
        let prompt: String
        let indexMap: [Int: Int]
    }

    static func build(
        attacker: BattleCombatant,
        defender: BattleCombatant,
        moves: [MoveDetail],
        defenderSeenMoves: [MoveDetail],
        typeChart: TypeChart,
        turnNumber: Int
    ) -> Output {
        var indexMap: [Int: Int] = [:]
        let movesBlock = Array(moves.indices).shuffled().enumerated().map { displayIdx, originalIdx in
            indexMap[displayIdx] = originalIdx
            return MoveRow.describe(
                moves[originalIdx],
                index: displayIdx,
                attacker: attacker, defender: defender, typeChart: typeChart,
                style: .verbose
            )
        }.joined(separator: "\n")

        var sections = [BattleContext.compact(attacker: attacker, defender: defender, turnNumber: turnNumber)]
        let threat = threatSection(seenMoves: defenderSeenMoves, attacker: defender, defender: attacker, typeChart: typeChart)
        if !threat.isEmpty { sections.append(threat) }
        sections.append(movesBlock)
        sections.append("\(BattleContext.tacticalHint(attacker: attacker, defender: defender, moves: moves)) Return ONLY the index.")
        return Output(prompt: sections.joined(separator: "\n\n"), indexMap: indexMap)
    }

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

    /// Defender's observed moves rendered with their damage threat back
    /// at us. Caller swaps attacker/defender so the damage estimate is
    /// the defender's hit against the attacker.
    static func threatSection(
        seenMoves: [MoveDetail],
        attacker: BattleCombatant,
        defender: BattleCombatant,
        typeChart: TypeChart
    ) -> String {
        guard !seenMoves.isEmpty else { return "" }
        let rows = seenMoves.map { move -> String in
            if (move.power ?? 0) > 0 {
                let dmg = DamageCalculator.estimateDamage(move: move, attacker: attacker, defender: defender, typeChart: typeChart)
                let eff = typeChart.multiplier(attacking: move.typeName, defenders: defender.typeNames)
                let suffix: String
                if eff >= 2 { suffix = ", SE" }
                else if eff > 0, eff < 1 { suffix = ", resisted" }
                else if eff == 0 { suffix = ", immune" }
                else { suffix = "" }
                return "- \(move.name) (\(move.typeName)) \(dmg) dmg\(suffix)"
            }
            var tags: [String] = []
            if move.ailment != "none" { tags.append(move.ailment) }
            if move.statChangeDeltas.contains(where: { $0 > 0 }) { tags.append("boost") }
            if move.statChangeDeltas.contains(where: { $0 < 0 }) { tags.append("debuff") }
            return "- \(move.name) (\(move.typeName)) \(tags.joined(separator: ", "))"
        }
        return "Defender has used:\n" + rows.joined(separator: "\n")
    }
}
