import Foundation

/// Builds the per-call prompt strings for `BattleAIService`. Pulled into its
/// own type so the service stays focused on session handling and the prompt
/// shape is easy to tweak / inspect in isolation.
struct BattleAIPromptBuilder {

    /// Compact battle snapshot + move list. The model only sees what's needed
    /// to make a tactical call — no flavor text, no extraneous IDs.
    func buildMovePrompt(
        attacker: BattleCombatant,
        defender: BattleCombatant,
        moves: [MoveDetail]
    ) -> String {
        let hpPct: (BattleCombatant) -> Int = { Int(Double($0.currentHP) / Double($0.maxHP) * 100) }
        let movesBlock = moves.map { describe($0) }.joined(separator: "\n")
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

        Available moves: 
        \(movesBlock)

        Return ONLY the exact move name (kebab-case) from the list above.
        """
    }

    /// Player + roster summary for opponent selection. Roster is capped at 60
    /// candidates so the prompt stays under the model's input budget — the
    /// caller samples randomly from the full pokedex before passing in.
    func buildOpponentPrompt(
        player: PokemonSummary,
        candidates: [PokemonSummary]
    ) -> String {
        let capped = candidates.prefix(60)
        let roster = capped.map { "- \($0.id): \($0.name)" }.joined(separator: "\n")
        return """
        Pick a worthy opponent for \(player.name) (id \(player.id)) from this list.

        Candidates:
        \(roster)

        Return ONLY the exact pokedex id (integer) from the list above.
        """
    }

    // MARK: - Helpers

    private func describe(_ move: MoveDetail) -> String {
        let power = move.power.map { "\($0)" } ?? "—"
        let accuracy = move.accuracy.map { "\($0)%" } ?? "100%"
        return "- \(move.name): \(move.typeName) \(move.damageClass), power \(power), acc \(accuracy)"
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
