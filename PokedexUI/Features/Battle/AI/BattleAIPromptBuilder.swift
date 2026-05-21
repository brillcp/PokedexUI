import Foundation

/// Builds prompt strings for each `BattleAIService` call.
struct BattleAIPromptBuilder {

    func buildMovePrompt(
        attacker: BattleCombatant,
        defender: BattleCombatant,
        moves: [MoveDetail],
        effectiveness: [Double],
        recentMoves: [String],
        turnNumber: Int
    ) -> (prompt: String, indexMap: [Int: Int]) {
        let annotations = moveAnnotations(moves: moves, recentMoves: recentMoves, attacker: attacker, defender: defender)
        let shuffled = Array(moves.indices).shuffled()
        var indexMap: [Int: Int] = [:]
        let movesBlock = shuffled.enumerated().map { displayIdx, originalIdx in
            indexMap[displayIdx] = originalIdx
            let move = moves[originalIdx]
            let eff = effectiveness[safe: originalIdx] ?? 1.0
            var row = richMoveDescription(move, index: displayIdx, attacker: attacker, defender: defender, effectiveness: eff)
            if let annotation = annotations[originalIdx] {
                row += " [AVOID]"
            }
            return row
        }.joined(separator: "\n")
        let situation = compactBattleContext(attacker: attacker, defender: defender, turnNumber: turnNumber)
        let hint = tacticalHint(attacker: attacker, defender: defender, moves: moves)
        let prompt = """
        \(situation)

        \(movesBlock)

        \(hint) Never pick AVOID. Return ONLY the index.
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
        effectiveness: [Double],
        playerMoves: [MoveDetail],
        playerEffectiveness: [Double]
    ) -> (prompt: String, indexMap: [Int: Int]) {
        let biggestThreat = playerBiggestThreat(
            playerMoves: playerMoves, playerEffectiveness: playerEffectiveness,
            fighter: fighter, opponent: opponent
        )

        let shuffled = Array(moves.indices).shuffled()
        var indexMap: [Int: Int] = [:]

        var dmgRows: [String] = []
        var boostRows: [String] = []
        var disruptRows: [String] = []
        for (displayIdx, originalIdx) in shuffled.enumerated() {
            indexMap[displayIdx] = originalIdx
            let move = moves[originalIdx]
            let eff = effectiveness[safe: originalIdx] ?? 1.0
            let row = richLoadoutMoveDescription(move, index: displayIdx, fighter: fighter, opponent: opponent, effectiveness: eff)
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

        Pick highest ~dmg for DMG. Never pick IMMUNE. Return ONLY 4 index numbers.
        """
        return (prompt, indexMap)
    }

}

// MARK: - Private
private extension BattleAIPromptBuilder {

    // MARK: Damage estimation

    func estimateDamage(
        move: MoveDetail,
        attacker: BattleCombatant,
        defender: BattleCombatant,
        effectiveness: Double
    ) -> Int {
        guard let power = move.power, power > 0, effectiveness > 0 else { return 0 }
        let atkStat: Int
        let defStat: Int
        switch move.damageClassKind {
        case .physical:
            let atkStage = statStageMultiplier(attacker.stage(for: "attack"))
            let defStage = statStageMultiplier(defender.stage(for: "defense"))
            atkStat = Int(Double(attacker.attack) * atkStage)
            defStat = Int(Double(defender.defense) * defStage)
        case .special:
            let atkStage = statStageMultiplier(attacker.stage(for: "special-attack"))
            let defStage = statStageMultiplier(defender.stage(for: "special-defense"))
            atkStat = Int(Double(attacker.specialAttack) * atkStage)
            defStat = Int(Double(defender.specialDefense) * defStage)
        case .status:
            return 0
        }
        let stab = attacker.typeNames.contains(move.typeName) ? 1.5 : 1.0
        let base = ((22.0 * Double(power) * Double(atkStat) / Double(max(1, defStat))) / 50.0 + 2.0)
        return Int(base * stab * effectiveness)
    }

    func turnsToKO(_ damage: Int, hp: Int) -> Int {
        guard damage > 0 else { return 99 }
        return Int(ceil(Double(hp) / Double(damage)))
    }

    // MARK: Move prompt helpers

    func richMoveDescription(
        _ move: MoveDetail,
        index: Int,
        attacker: BattleCombatant,
        defender: BattleCombatant,
        effectiveness: Double
    ) -> String {
        var parts: [String] = []
        parts.append("\(index): \(move.name) (\(move.typeName))")

        if let power = move.power, power > 0 {
            let dmg = estimateDamage(move: move, attacker: attacker, defender: defender, effectiveness: effectiveness)
            let acc = move.accuracy ?? 100
            let koTurns = turnsToKO(dmg, hp: defender.currentHP)
            var dmgStr = "~\(dmg) dmg"
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

    func moveAnnotations(
        moves: [MoveDetail],
        recentMoves: [String],
        attacker: BattleCombatant,
        defender: BattleCombatant
    ) -> [String?] {
        var counts: [String: Int] = [:]
        for name in recentMoves { counts[name, default: 0] += 1 }
        return moves.map { move in
            var warnings: [String] = []
            let count = counts[move.name] ?? 0
            if count >= 2 { warnings.append("used \(count)x recently") }
            else if move.name == recentMoves.last { warnings.append("used last turn") }
            if (move.power ?? 0) == 0,
               move.statChangeDeltas.contains(where: { $0 > 0 }),
               attacker.isBoosted { warnings.append("already boosted") }
            if move.ailment != "none", defender.status != .none {
                warnings.append("opponent already statused")
            }
            return warnings.isEmpty ? nil : warnings.joined(separator: ", ")
        }
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
            let cPressure = candidate.typeNames
                .map { chart.multiplier(attacking: $0, defenders: player.typeNames) }.max() ?? 1
            let pPressure = player.typeNames
                .map { chart.multiplier(attacking: $0, defenders: candidate.typeNames) }.max() ?? 1

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
        effectiveness: Double
    ) -> String {
        var parts: [String] = []
        parts.append("\(index): \(move.name) (\(move.typeName))")

        if let power = move.power, power > 0 {
            let dmg = estimateDamage(move: move, attacker: fighter, defender: opponent, effectiveness: effectiveness)
            let koTurns = turnsToKO(dmg, hp: opponent.maxHP)
            var tags: [String] = []
            tags.append("~\(dmg) dmg")
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
        playerEffectiveness: [Double],
        fighter: BattleCombatant,
        opponent: BattleCombatant
    ) -> String {
        var bestDmg = 0
        var bestName = ""
        for (idx, move) in playerMoves.enumerated() {
            let eff = playerEffectiveness[safe: idx] ?? 1
            let dmg = estimateDamage(move: move, attacker: opponent, defender: fighter, effectiveness: eff)
            if dmg > bestDmg { bestDmg = dmg; bestName = move.displayName }
        }
        if bestDmg > 0 {
            let ko = turnsToKO(bestDmg, hp: fighter.maxHP)
            return "Player's strongest: \(bestName) (~\(bestDmg) dmg, \(ko)-hit KO vs you)."
        }
        return ""
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
