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
            var row = compactMoveDescription(move, index: displayIdx, fighter: attacker, effectiveness: eff)
            if let annotation = annotations[originalIdx] {
                row += " [\(annotation)]"
            }
            return row
        }.joined(separator: "\n")
        let situation = battleContext(attacker: attacker, defender: defender, recentMoves: recentMoves, turnNumber: turnNumber)
        let hint = tacticalHint(attacker: attacker, defender: defender, moves: moves)
        let prompt = """
        \(situation)

        \(movesBlock)

        \(hint)
        Return ONLY the index number.
        """
        return (prompt, indexMap)
    }

    func buildOpponentPrompt(
        player: OpponentCandidateSnapshot,
        candidates: [OpponentCandidateSnapshot],
        typeChart: TypeChart?
    ) -> (prompt: String, indexMap: [Int: Int]) {
        var indexMap: [Int: Int] = [:]
        let roster = candidates.enumerated().map { displayIdx, candidate in
            let idx = displayIdx + 1
            indexMap[idx] = candidate.id
            let types = candidate.typeNames.joined(separator: "/")
            return "\(idx). \(candidate.name) (\(types), BST \(candidate.baseStatTotal)\(candidate.flagSuffix))"
        }.joined(separator: "\n")
        let prompt = """
        Pick the most exciting opponent for \(player.name) (\(player.typeNames.joined(separator: "/"))).

        \(roster)

        Return ONLY the number.
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
        let playerBlock = playerMoves.enumerated().map { idx, move in
            playerMoveTag(move, effectiveness: playerEffectiveness[safe: idx] ?? 1, against: fighter)
        }.joined(separator: "\n")

        let shuffled = Array(moves.indices).shuffled()
        var indexMap: [Int: Int] = [:]

        var dmgRows: [String] = []
        var boostRows: [String] = []
        var disruptRows: [String] = []
        for (displayIdx, originalIdx) in shuffled.enumerated() {
            indexMap[displayIdx] = originalIdx
            let move = moves[originalIdx]
            let eff = effectiveness[safe: originalIdx] ?? 1.0
            let row = compactMoveDescription(move, index: displayIdx, fighter: fighter, effectiveness: eff)
            switch move.loadoutCategory {
            case "BOOST": boostRows.append(row)
            case "DISRUPT": disruptRows.append(row)
            default: dmgRows.append(row)
            }
        }

        let prompt = """
        You are \(fighter.name) (\(fighter.typeNames.joined(separator: "/"))). Pick 4 moves to fight \(opponent.name) (\(opponent.typeNames.joined(separator: "/"))).

        Player's moves:
        \(playerBlock)

        DMG (pick 2):
        \(dmgRows.joined(separator: "\n"))

        BOOST (pick 1):
        \(boostRows.joined(separator: "\n"))

        DISRUPT (pick 1):
        \(disruptRows.joined(separator: "\n"))

        Return ONLY 4 index numbers.
        """
        return (prompt, indexMap)
    }

}

// MARK: - Private
private extension BattleAIPromptBuilder {
    func compactMoveDescription(
        _ move: MoveDetail,
        index: Int,
        fighter: BattleCombatant,
        effectiveness: Double
    ) -> String {
        let power = move.power.map { "\($0) pow" } ?? "status"
        var tags: [String] = []
        if fighter.typeNames.contains(move.typeName) { tags.append("STAB") }
        if effectiveness >= 2 { tags.append("SE") }
        if effectiveness == 0 { tags.append("immune") }
        if move.ailment != "none" { tags.append(move.ailment) }
        if move.healing > 0 || move.name == "rest" { tags.append("heal") }
        let tagStr = tags.isEmpty ? "" : " [\(tags.joined(separator: ", "))]"
        return "\(index): \(move.name) (\(move.typeName), \(power))\(tagStr)"
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
            if count >= 2 { warnings.append("AVOID: used \(count)x recently") }
            else if move.name == recentMoves.last { warnings.append("used last turn") }
            if (move.power ?? 0) == 0,
               move.statChangeDeltas.contains(where: { $0 > 0 }),
               attacker.isBoosted { warnings.append("AVOID: already boosted") }
            if move.ailment != "none", defender.status != .none {
                warnings.append("AVOID: opponent already statused")
            }
            return warnings.isEmpty ? nil : warnings.joined(separator: ", ")
        }
    }

    func battleContext(
        attacker: BattleCombatant,
        defender: BattleCombatant,
        recentMoves: [String],
        turnNumber: Int
    ) -> String {
        let hpPct: (BattleCombatant) -> Int = { Int(Double($0.currentHP) / Double(max(1, $0.maxHP)) * 100) }
        var lines: [String] = []
        lines.append("Turn \(turnNumber). \(attacker.name) \(hpPct(attacker))% HP vs \(defender.name) \(hpPct(defender))% HP.")

        var atkTraits: [String] = []
        if attacker.status != .none { atkTraits.append(attacker.status.label) }
        let boosts = attacker.statStages.filter { $0.value > 0 }.map { "+\($0.value) \(shortStat($0.key))" }
        if !boosts.isEmpty { atkTraits.append(boosts.joined(separator: ", ")) }
        if !atkTraits.isEmpty { lines.append("You: \(atkTraits.joined(separator: ", ")).") }

        var defTraits: [String] = []
        if defender.status != .none { defTraits.append(defender.status.label) }
        let defBoosts = defender.statStages.filter { $0.value > 0 }.map { "+\($0.value) \(shortStat($0.key))" }
        if !defBoosts.isEmpty { defTraits.append(defBoosts.joined(separator: ", ")) }
        if !defTraits.isEmpty { lines.append("Opponent: \(defTraits.joined(separator: ", ")).") }

        if attacker.effectiveSpeed > defender.effectiveSpeed {
            lines.append("You are faster.")
        } else if defender.effectiveSpeed > attacker.effectiveSpeed {
            lines.append("Opponent is faster.")
        }

        if let last = recentMoves.last {
            lines.append("Your last move: \(last).")
        }

        return lines.joined(separator: " ")
    }

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

    func playerMoveTag(_ move: MoveDetail, effectiveness: Double, against fighter: BattleCombatant) -> String {
        var tags: [String] = []
        if let p = move.power, p > 0 {
            if effectiveness >= 2 { tags.append("SE against you") }
            else if effectiveness > 0, effectiveness < 1 { tags.append("resisted") }
            else if effectiveness == 0 { tags.append("immune") }
            else { tags.append("damage") }
        }
        if move.ailment != "none" { tags.append("disrupts you") }
        if move.healing > 0 || move.name == "rest" { tags.append("heals") }
        if move.statChangeDeltas.contains(where: { $0 > 0 }) { tags.append("powers up") }
        if move.statChangeDeltas.contains(where: { $0 < 0 }), (move.power ?? 0) == 0 {
            tags.append("debuffs you")
        }
        let tagStr = tags.isEmpty ? "" : " (\(tags.joined(separator: ", ")))"
        return "- \(move.displayName)\(tagStr)"
    }

    /// Phase-based tactical hint that steers the model toward setup/disrupt/attack.
    func tacticalHint(
        attacker: BattleCombatant,
        defender: BattleCombatant,
        moves: [MoveDetail]
    ) -> String {
        let hpFrac = Double(attacker.currentHP) / Double(max(1, attacker.maxHP))
        let defHpFrac = Double(defender.currentHP) / Double(max(1, defender.maxHP))
        let defStatused = defender.status != .none
        let hasBoost = moves.contains { ($0.power ?? 0) == 0 && $0.statChangeDeltas.contains(where: { $0 > 0 }) }
        let hasDisrupt = moves.contains {
            ($0.power ?? 0) == 0 && ($0.ailment != "none" || $0.statChangeDeltas.contains(where: { $0 < 0 }))
        }

        if hpFrac <= 0.30 { return "Low HP. Go for damage." }
        if defHpFrac <= 0.30 { return "Opponent is low. Finish it." }
        if !attacker.isBoosted, hpFrac >= 0.70, hasBoost { return "Set up with a boost move." }
        if attacker.isBoosted, !defStatused, hasDisrupt { return "You are boosted. Disrupt the opponent." }
        if attacker.isBoosted { return "You are boosted. Hit hard." }
        return "Pick your strongest move."
    }
}

// MARK: - Private
private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
