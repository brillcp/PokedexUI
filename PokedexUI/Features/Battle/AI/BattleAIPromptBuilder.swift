import Foundation

/// Builds the per-call prompt strings for `BattleAIService`. Pulled into its
/// own type so the service stays focused on session handling and the prompt
/// shape is easy to tweak / inspect in isolation.
struct BattleAIPromptBuilder {

    /// Builds the move-selection prompt with shuffled move order. Returns
    /// the prompt string and a mapping from shuffled index back to original
    /// index so the caller can resolve the model's pick.
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
            return describe(move, index: displayIdx, effectiveness: effectiveness[safe: originalIdx] ?? 1.0, annotation: annotations[originalIdx])
        }.joined(separator: "\n")
        let historyLine = recentMoves.isEmpty
            ? ""
            : "\n        Your last move was \(recentMoves.last!). Pick a different one.\n"
        let prompt = """
        Pick a move. Do not repeat your last move.

        Attacker: \(attacker.name) (\(attacker.typeNames.joined(separator: "/")), \(hpPct(attacker))% HP, \(statusDescription(attacker.status)))
        Defender: \(defender.name) (\(defender.typeNames.joined(separator: "/")), \(hpPct(defender))% HP, \(statusDescription(defender.status)))
        \(historyLine)
        Moves:
        \(movesBlock)

        Return ONLY the index number.
        """
        return (prompt, indexMap)
    }

    /// Loadout selection: fighter + opponent context + full movepool with
    /// pre-computed effectiveness numbers. AI returns 4 indices from the
    /// movepool. Used by `BattleAIService.chooseLoadout` at battle start so
    /// the opponent goes in with a hand-picked 4-move set, just like the
    /// player.
    func buildLoadoutPrompt(
        fighter: BattleCombatant,
        opponent: BattleCombatant,
        moves: [MoveDetail],
        effectiveness: [Double],
        loadoutSize: Int
    ) -> String {
        let movesBlock = moves.enumerated().map { idx, move in
            describe(move, index: idx, effectiveness: effectiveness[safe: idx] ?? 1.0)
        }.joined(separator: "\n")
        return """
        Pick \(loadoutSize) moves for \(fighter.name) to bring into a 1v1 battle.

        Fighter: \(fighter.name)
        - Types: \(fighter.typeNames.joined(separator: ", "))

        Opponent: \(opponent.name)
        - Types: \(opponent.typeNames.joined(separator: ", "))

        Full movepool (index: name. details):
        \(movesBlock)

        Return ONLY a comma-separated list of exactly \(loadoutSize) distinct indices (e.g. "0, 3, 7, 12"). No other text.
        Prefer a balanced set: at least one super-effective damaging move when possible, no duplicate types, mix damaging and utility if it helps.
        """
    }

    /// Player + roster summary for opponent selection. Player types are passed
    /// in explicitly (the picker view forwards them) so the model can match a
    /// challenger to the actual matchup, not just recall the player's typing
    /// from training. Candidate roster is capped at 60 to stay under the
    /// input token budget.
    func buildOpponentPrompt(
        player: Pokemon,
        playerTypes: [String],
        candidates: [Pokemon]
    ) -> String {
        let capped = candidates.prefix(60)
        let roster = capped.map { "- \($0.id): \($0.name)" }.joined(separator: "\n")
        let typeLine = playerTypes.isEmpty
            ? ""
            : " (types: \(playerTypes.joined(separator: ", ")))"
        return """
        Pick a worthy opponent for \(player.name) (id \(player.id))\(typeLine) from this list.

        Candidates:
        \(roster)

        Return ONLY the exact pokedex id (integer) from the list above.
        """
    }

}

// MARK: - Private

private extension BattleAIPromptBuilder {
    func describe(_ move: MoveDetail, index: Int, effectiveness: Double, annotation: String? = nil) -> String {
        let power = move.power.map { "\($0)" } ?? "-"
        let accuracy = move.accuracy.map { "\($0)%" } ?? "100%"
        let effectivenessText: String
        if move.power == nil || (move.power ?? 0) == 0 {
            effectivenessText = "status"
        } else {
            effectivenessText = "×\(format(effectiveness)) vs defender"
        }
        let tag = annotation.map { " [\($0)]" } ?? ""
        return "\(index): \(move.name). \(move.typeName) \(move.damageClass), power \(power), acc \(accuracy), \(effectivenessText)\(tag)"
    }

    /// Annotates moves with recent usage info so the model naturally
    /// gravitates toward variety.
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

    func format(_ multiplier: Double) -> String {
        if multiplier == multiplier.rounded() {
            return String(Int(multiplier))
        }
        return String(format: "%.2f", multiplier)
    }

    func statusDescription(_ status: BattleStatus) -> String {
        switch status {
        case .none: return "healthy"
        case .paralysis: return "paralyzed (speed halved, 25% skip)"
        case .burn: return "burned (-1/16 HP/turn, physical halved)"
        case .poison: return "poisoned (-1/8 HP/turn)"
        }
    }
}

private extension Array {
    /// Out-of-bounds-safe lookup. Used as a defensive guard when iterating
    /// the moves array next to a parallel `effectiveness` array: if the
    /// caller ever passes mismatched lengths we degrade to neutral instead
    /// of crashing.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
