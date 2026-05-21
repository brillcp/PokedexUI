import Foundation
import BattleKit

/// Builds prompt strings for each `BattleAIService` call.
struct BattleAIPromptBuilder {

    func buildMovePrompt(
        attacker: BattleCombatant,
        defender: BattleCombatant,
        moves: [MoveDetail],
        typeChart: TypeChart,
        recentMoves: [String],
        turnNumber: Int
    ) -> (prompt: String, indexMap: [Int: Int]) {
        let shuffled = Array(moves.indices).shuffled()
        var indexMap: [Int: Int] = [:]
        let movesBlock = shuffled.enumerated().map { displayIdx, originalIdx in
            indexMap[displayIdx] = originalIdx
            let move = moves[originalIdx]
            return richMoveDescription(move, index: displayIdx, attacker: attacker, defender: defender, typeChart: typeChart)
        }.joined(separator: "\n")
        let situation = compactBattleContext(attacker: attacker, defender: defender, turnNumber: turnNumber)
        let hint = tacticalHint(attacker: attacker, defender: defender, moves: moves)
        let prompt = """
        \(situation)

        \(movesBlock)

        \(hint) Return ONLY the index.
        """
        return (prompt, indexMap)
    }

    func buildOpponentPrompt(
        player: OpponentCandidateSnapshot,
        candidates: [OpponentCandidateSnapshot],
        typeChart: TypeChart?
    ) -> (prompt: String, indexMap: [Int: Int]) {
        var indexMap: [Int: Int] = [:]
        let playerBST = player.baseStatTotal
        let shuffled = Array(candidates.indices).shuffled()
        let roster = shuffled.enumerated().map { displayIdx, originalIdx in
            let idx = displayIdx + 1
            indexMap[idx] = candidates[originalIdx].id
            return richCandidateDescription(
                candidates[originalIdx], index: idx, player: player, playerBST: playerBST, typeChart: typeChart
            )
        }.joined(separator: "\n")

        let prompt = """
        Pick a fair opponent for \(player.name) (\(player.typeNames.joined(separator: "/")), BST \(playerBST)).

        \(roster)

        If "mutual threat", prefer it. If "stronger", avoid it. Return ONLY the number.
        """
        return (prompt, indexMap)
    }

    func buildLoadoutPrompt(
        fighter: BattleCombatant,
        opponent: BattleCombatant,
        moves: [MoveDetail],
        playerMoves: [MoveDetail],
        typeChart: TypeChart
    ) -> (prompt: String, indexMap: [Int: Int]) {
        let biggestThreat = playerBiggestThreat(
            playerMoves: playerMoves, fighter: fighter, opponent: opponent, typeChart: typeChart
        )

        let shuffled = Array(moves.indices).shuffled()
        var indexMap: [Int: Int] = [:]

        var dmgRows: [String] = []
        var boostRows: [String] = []
        var disruptRows: [String] = []
        for (displayIdx, originalIdx) in shuffled.enumerated() {
            indexMap[displayIdx] = originalIdx
            let move = moves[originalIdx]
            let row = richLoadoutMoveDescription(move, index: displayIdx, fighter: fighter, opponent: opponent, typeChart: typeChart)
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
        return (prompt, indexMap)
    }

}

// MARK: - Private
private extension BattleAIPromptBuilder {

    // MARK: Move prompt helpers

    func richMoveDescription(
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
                effects.append("\(sign)\(delta) \(shortStat(stat))")
            }
            if move.healing > 0 { effects.append("heals \(move.healing)%") }
            if move.name == "rest" { effects.append("full heal, sleeps 2 turns") }
            parts.append(effects.joined(separator: ", "))
        }

        return parts.joined(separator: " - ")
    }

    func compactBattleContext(
        attacker: BattleCombatant,
        defender: BattleCombatant,
        turnNumber: Int
    ) -> String {
        let atkHP = Int(Double(attacker.currentHP) / Double(max(1, attacker.maxHP)) * 100)
        let defHP = Int(Double(defender.currentHP) / Double(max(1, defender.maxHP)) * 100)
        var parts = ["Turn \(turnNumber). \(attacker.name) \(atkHP)% HP vs \(defender.name) \(defHP)% HP."]
        let boosts = attacker.statStages.filter { $0.value != 0 }
            .map { "\($0.value > 0 ? "+" : "")\($0.value) \(shortStat($0.key))" }
        if !boosts.isEmpty { parts.append("You: \(boosts.joined(separator: ", ")).") }
        if attacker.status != .none { parts.append("You are \(attacker.status.label).") }
        if defender.status != .none { parts.append("Opponent is \(defender.status.label).") }
        return parts.joined(separator: " ")
    }

    func richCandidateDescription(
        _ candidate: OpponentCandidateSnapshot,
        index: Int,
        player: OpponentCandidateSnapshot,
        playerBST: Int,
        typeChart: TypeChart?
    ) -> String {
        let types = candidate.typeNames.joined(separator: "/")
        let bstDelta = candidate.baseStatTotal - playerBST
        let bstNote = bstDelta > 20 ? "stronger" : bstDelta < -20 ? "weaker" : "similar"

        var line = "\(index). \(candidate.name) (\(types), BST \(candidate.baseStatTotal), \(bstNote))"

        if let chart = typeChart, !player.typeNames.isEmpty, !candidate.typeNames.isEmpty {
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
            if !matchup.isEmpty { line += " [\(matchup.joined(separator: ", "))]" }
        }

        if candidate.isLegendary { line += " [legendary]" }
        if candidate.isMythical { line += " [mythical]" }
        return line
    }

    // MARK: Loadout prompt helpers

    func richLoadoutMoveDescription(
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
                effects.append("\(d > 0 ? "+" : "")\(d) \(shortStat(stat))")
            }
            if move.healing > 0 { effects.append("heal \(move.healing)%") }
            if move.name == "rest" { effects.append("full heal") }
            parts.append(effects.joined(separator: ", "))
        }

        return parts.joined(separator: " - ")
    }

    func playerBiggestThreat(
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

    // MARK: Shared

    func shortStat(_ stat: String) -> String {
        switch stat {
        case "attack": return "atk"
        case "defense": return "def"
        case "special-attack": return "spa"
        case "special-defense": return "spd"
        case "speed": return "spe"
        default: return stat
        }
    }

    /// One-line tactical directive based on game state.
    func tacticalHint(
        attacker: BattleCombatant,
        defender: BattleCombatant,
        moves: [MoveDetail]
    ) -> String {
        let hpFrac = Double(attacker.currentHP) / Double(max(1, attacker.maxHP))
        let defHpFrac = Double(defender.currentHP) / Double(max(1, defender.maxHP))

        if defHpFrac <= 0.30 { return "Opponent is low. Pick the move that KOs." }
        if hpFrac <= 0.30 { return "Low HP. Pick highest damage." }
        if !attacker.isBoosted, hpFrac >= 0.70,
           moves.contains(where: { ($0.power ?? 0) == 0 && $0.statChangeDeltas.contains { $0 > 0 } }) {
            return "Consider a boost move to set up."
        }
        if attacker.isBoosted { return "You are boosted. Pick highest damage." }
        return "Pick highest damage."
    }
}

// MARK: - Private
private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
