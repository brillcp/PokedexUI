import BattleKit
import Foundation

/// LLM prompt + response parsing for picking a 4-move loadout. Rows are
/// grouped by `loadoutCategory` (DMG/BOOST/DISRUPT) so the model is steered
/// toward composition rather than four damage moves. The threat summary
/// reminds the model what the opposing fighter can hit it with.
enum LoadoutPrompt {

    struct Output {
        let prompt: String
        let indexMap: [Int: Int]
    }

    static func build(
        fighter: BattleCombatant,
        opponent: BattleCombatant,
        moves: [MoveDetail],
        playerMoves: [MoveDetail],
        typeChart: TypeChart
    ) -> Output {
        let biggestThreat = threatSummary(playerMoves: playerMoves, fighter: fighter, opponent: opponent, typeChart: typeChart)
        let shuffled = Array(moves.indices).shuffled()
        var indexMap: [Int: Int] = [:]

        var dmgRows: [String] = []
        var boostRows: [String] = []
        var disruptRows: [String] = []
        for (displayIdx, originalIdx) in shuffled.enumerated() {
            indexMap[displayIdx] = originalIdx
            let move = moves[originalIdx]
            let row = describe(move, index: displayIdx, fighter: fighter, opponent: opponent, typeChart: typeChart)
            switch move.loadoutCategory {
            case "BOOST": boostRows.append(row)
            case "DISRUPT": disruptRows.append(row)
            default: dmgRows.append(row)
            }
        }

        let prompt = """
        Pick 4 moves for \(fighter.name) (\(fighter.typeNames.joined(separator: "/"))) vs \(opponent.name) (\(opponent.typeNames.joined(separator: "/"))). \(biggestThreat)

        DMG (pick 2):
        \(dmgRows.joined(separator: "\n"))

        BOOST (pick 1):
        \(boostRows.joined(separator: "\n"))

        DISRUPT (pick 1):
        \(disruptRows.joined(separator: "\n"))

        Pick highest dmg for DMG. Never pick IMMUNE. Return ONLY 4 index numbers.
        """
        return Output(prompt: prompt, indexMap: indexMap)
    }

    /// Resolve the LLM's reply (move names or 4 integers) to up to 4
    /// unique moves; missing slots are returned empty for the caller to
    /// pad via `LoadoutStrategy.fill`.
    static func parsePicks(raw: String, indexMap: [Int: Int], moves: [MoveDetail]) -> [MoveDetail] {
        LLMResponseParser.loadoutIndices(raw, indexMap: indexMap, moves: moves, count: 4)
    }
}

// MARK: - Private
private extension LoadoutPrompt {

    static func threatSummary(
        playerMoves: [MoveDetail],
        fighter: BattleCombatant,
        opponent: BattleCombatant,
        typeChart: TypeChart
    ) -> String {
        guard let best = DamageCalculator.strongestMove(
            attacker: opponent, defender: fighter, moves: playerMoves, typeChart: typeChart
        ) else { return "" }
        let ko = DamageCalculator.turnsToKO(best.damage, hp: fighter.maxHP)
        return "Player's strongest: \(best.move.displayName) (\(best.damage) dmg, \(ko)-hit KO vs you)."
    }

    static func describe(
        _ move: MoveDetail,
        index: Int,
        fighter: BattleCombatant,
        opponent: BattleCombatant,
        typeChart: TypeChart
    ) -> String {
        var parts: [String] = []
        parts.append("\(index): \(move.name) (\(move.typeName))")

        if let power = move.power, power > 0 {
            let effectiveness = typeChart.multiplier(attacking: move.typeName, defenders: opponent.typeNames)
            let dmg = DamageCalculator.estimateDamage(move: move, attacker: fighter, defender: opponent, typeChart: typeChart)
            let koTurns = DamageCalculator.turnsToKO(dmg, hp: opponent.maxHP)
            var tags: [String] = []
            tags.append("\(dmg) dmg")
            if koTurns <= 2 { tags.append("\(koTurns)-hit KO") }
            if fighter.typeNames.contains(move.typeName) { tags.append("STAB") }
            if effectiveness >= 2 { tags.append("SE") }
            else if effectiveness > 0, effectiveness < 1 { tags.append("resisted") }
            else if effectiveness == 0 { tags.append("IMMUNE") }
            let acc = move.accuracy ?? 100
            if acc < 100 { tags.append("\(acc)% acc") }
            if move.hasSelfDebuff { tags.append("self-debuff") }
            if move.isRechargeMove { tags.append("recharge") }
            if move.priority > 0 { tags.append("priority") }
            parts.append(tags.joined(separator: ", "))
        } else {
            var effects: [String] = []
            if move.ailment != "none" { effects.append(move.ailment) }
            for (i, stat) in move.statChangeNames.enumerated() where i < move.statChangeDeltas.count {
                let d = move.statChangeDeltas[i]
                effects.append("\(d > 0 ? "+" : "")\(d) \(BattleContext.shortStat(stat))")
            }
            if move.healing > 0 { effects.append("heal \(move.healing)%") }
            if move.name == "rest" { effects.append("full heal") }
            parts.append(effects.joined(separator: ", "))
        }

        return parts.joined(separator: " - ")
    }
}
