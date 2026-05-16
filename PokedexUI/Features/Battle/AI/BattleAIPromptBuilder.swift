import Foundation

/// Builds the per-call prompt strings for `BattleAIService`. Pulled into its
/// own type so the service stays focused on session handling and the prompt
/// shape is easy to tweak / inspect in isolation.
struct BattleAIPromptBuilder {

    /// Compact battle snapshot + indexed move list. Each move row carries the
    /// pre-computed type effectiveness multiplier against the defender so the
    /// model doesn't need to recall the type chart from training; it just
    /// compares numbers. `effectiveness` is parallel to `moves`.
    func buildMovePrompt(
        attacker: BattleCombatant,
        defender: BattleCombatant,
        moves: [MoveDetail],
        effectiveness: [Double]
    ) -> String {
        let hpPct: (BattleCombatant) -> Int = { Int(Double($0.currentHP) / Double($0.maxHP) * 100) }
        let movesBlock = moves.enumerated().map { idx, move in
            describe(move, index: idx, effectiveness: effectiveness[safe: idx] ?? 1.0)
        }.joined(separator: "\n")
        return """
        Pick the best move for the attacker this turn.

        Attacker: \(attacker.name)
        - Types: \(attacker.typeNames.joined(separator: ", "))
        - HP: \(hpPct(attacker))%
        - Status: \(statusDescription(attacker.status))

        Defender: \(defender.name)
        - Types: \(defender.typeNames.joined(separator: ", "))
        - HP: \(hpPct(defender))%
        - Status: \(statusDescription(defender.status))

        Available moves (index: name. details):
        \(movesBlock)

        Return ONLY the index (integer) of the chosen move from the list above.
        """
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
        player: PokemonSummary,
        playerTypes: [String],
        candidates: [PokemonSummary]
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

    // MARK: - Helpers

    /// Render one move row. Damaging moves include the pre-computed
    /// effectiveness multiplier vs the defender's typing.
    private func describe(_ move: MoveDetail, index: Int, effectiveness: Double) -> String {
        let power = move.power.map { "\($0)" } ?? "-"
        let accuracy = move.accuracy.map { "\($0)%" } ?? "100%"
        let effectivenessText: String
        if move.power == nil || (move.power ?? 0) == 0 {
            // Status / non-damaging move: no useful effectiveness number to print.
            effectivenessText = "status"
        } else {
            effectivenessText = "×\(format(effectiveness)) vs defender"
        }
        return "\(index): \(move.name). \(move.typeName) \(move.damageClass), power \(power), acc \(accuracy), \(effectivenessText)"
    }

    private func format(_ multiplier: Double) -> String {
        if multiplier == multiplier.rounded() {
            return String(Int(multiplier))
        }
        return String(format: "%.2f", multiplier)
    }

    private func statusDescription(_ status: BattleStatus) -> String {
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
