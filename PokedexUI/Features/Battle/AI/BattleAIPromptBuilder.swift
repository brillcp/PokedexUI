import Foundation

/// Builds prompt strings for each `BattleAIService` call.
struct BattleAIPromptBuilder {

    func buildMovePrompt(
        attacker: BattleCombatant,
        defender: BattleCombatant,
        moves: [MoveDetail],
        effectiveness: [Double],
        recentMoves: [String]
    ) -> (prompt: String, indexMap: [Int: Int]) {
        let hpPct: (BattleCombatant) -> Int = { Int(Double($0.currentHP) / Double($0.maxHP) * 100) }
        let annotations = moveAnnotations(moves: moves, recentMoves: recentMoves)
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
        let historyLine = recentMoves.isEmpty
            ? ""
            : "\nLast move: \(recentMoves.last!). Vary if possible.\n"
        let hint = tacticalHint(attacker: attacker, defender: defender, moves: moves)
        let prompt = """
        Pick a move for \(attacker.name) (\(attacker.typeNames.joined(separator: "/")), \(hpPct(attacker))% HP, \(statusLabel(attacker.status))\(boostLabel(attacker))) vs \(defender.name) (\(defender.typeNames.joined(separator: "/")), \(hpPct(defender))% HP, \(statusLabel(defender.status))).
        \(historyLine)
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
            return "\(idx). \(candidate.name) (\(types), BST \(candidate.baseStatTotal)\(flagSuffix(candidate)))"
        }.joined(separator: "\n")
        let prompt = """
        Pick the most exciting opponent for \(player.name) (\(player.typeNames.joined(separator: "/"))).

        \(roster)

        Return ONLY the number.
        """
        return (prompt, indexMap)
    }

}

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

    func moveAnnotations(moves: [MoveDetail], recentMoves: [String]) -> [String?] {
        guard !recentMoves.isEmpty else { return Array(repeating: nil, count: moves.count) }
        let last = recentMoves.last
        var counts: [String: Int] = [:]
        for name in recentMoves { counts[name, default: 0] += 1 }
        return moves.map { move in
            let count = counts[move.name] ?? 0
            if count >= 2 { return "used \(count) of last \(recentMoves.count) turns" }
            if move.name == last { return "used last turn" }
            return nil
        }
    }

    func flagSuffix(_ snapshot: OpponentCandidateSnapshot) -> String {
        if snapshot.isLegendary { return ", legendary" }
        if snapshot.isMythical { return ", mythical" }
        return ""
    }

    func statusLabel(_ status: BattleStatus) -> String {
        switch status {
        case .none: return "healthy"
        case .paralysis: return "paralyzed"
        case .burn: return "burned"
        case .poison: return "poisoned"
        case .sleep: return "asleep"
        }
    }

    func boostLabel(_ combatant: BattleCombatant) -> String {
        combatant.statStages.values.contains(where: { $0 > 0 }) ? ", boosted" : ""
    }

    /// Phase-based tactical hint that steers the model toward setup/disrupt/attack.
    func tacticalHint(
        attacker: BattleCombatant,
        defender: BattleCombatant,
        moves: [MoveDetail]
    ) -> String {
        let hpFrac = Double(attacker.currentHP) / Double(max(1, attacker.maxHP))
        let defHpFrac = Double(defender.currentHP) / Double(max(1, defender.maxHP))
        let isBoosted = attacker.statStages.values.contains(where: { $0 > 0 })
        let defStatused = defender.status != .none
        let hasBoost = moves.contains { ($0.power ?? 0) == 0 && $0.statChangeDeltas.contains(where: { $0 > 0 }) }
        let hasDisrupt = moves.contains {
            ($0.power ?? 0) == 0 && ($0.ailment != "none" || $0.statChangeDeltas.contains(where: { $0 < 0 }))
        }

        if hpFrac <= 0.30 { return "Low HP. Go for damage." }
        if defHpFrac <= 0.30 { return "Opponent is low. Finish it." }
        if !isBoosted, hpFrac >= 0.70, hasBoost { return "Set up with a boost move." }
        if isBoosted, !defStatused, hasDisrupt { return "You are boosted. Disrupt the opponent." }
        if isBoosted { return "You are boosted. Hit hard." }
        return "Pick your strongest move."
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
