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
            let row = describeLoadoutMove(
                move,
                index: displayIdx,
                fighter: attacker,
                opponent: defender,
                effectiveness: effectiveness[safe: originalIdx] ?? 1.0
            )
            guard let annotation = annotations[originalIdx] else { return row }
            return "\(row) [\(annotation)]"
        }.joined(separator: "\n")
        let historyLine = recentMoves.isEmpty
            ? ""
            : "\n        Your last move was \(recentMoves.last!). Prefer a different one only if it is still strong.\n"
        let prompt = """
        Pick a move. Prefer variety, but repeat the best move if it is clearly strongest.

        Attacker: \(attacker.name) (\(attacker.typeNames.joined(separator: "/")), \(hpPct(attacker))% HP, \(statusDescription(attacker.status)), stats ATK \(attacker.attack)/SPA \(attacker.specialAttack)/SPE \(attacker.speed), stages \(stageSummary(attacker)))
        Defender: \(defender.name) (\(defender.typeNames.joined(separator: "/")), \(hpPct(defender))% HP, \(statusDescription(defender.status)), stats DEF \(defender.defense)/SPD \(defender.specialDefense)/SPE \(defender.speed), stages \(stageSummary(defender)))
        \(historyLine)
        Moves:
        \(movesBlock)

        Return ONLY the index number.
        Pick the highest-impact move this turn. Do not choose low-power filler when a much higher damage score is available.
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
            describeLoadoutMove(
                move,
                index: idx,
                fighter: fighter,
                opponent: opponent,
                effectiveness: effectiveness[safe: idx] ?? 1.0
            )
        }.joined(separator: "\n")
        return """
        Pick \(loadoutSize) moves for \(fighter.name) to bring into a 1v1 battle.

        Fighter: \(fighter.name)
        - Types: \(fighter.typeNames.joined(separator: ", "))
        - Stats: HP \(fighter.maxHP)/ATK \(fighter.attack)/DEF \(fighter.defense)/SPA \(fighter.specialAttack)/SPD \(fighter.specialDefense)/SPE \(fighter.speed)

        Opponent: \(opponent.name)
        - Types: \(opponent.typeNames.joined(separator: ", "))
        - Stats: HP \(opponent.maxHP)/ATK \(opponent.attack)/DEF \(opponent.defense)/SPA \(opponent.specialAttack)/SPD \(opponent.specialDefense)/SPE \(opponent.speed)

        Full movepool (index: name. details and matchup notes):
        \(movesBlock)

        Return ONLY a comma-separated list of exactly \(loadoutSize) distinct indices (e.g. "0, 3, 7, 12"). No other text.
        Pick the best 4 moves for this exact 1v1. Prioritise high expected damage, STAB, super-effective coverage, accuracy, and moves that use the fighter's stronger attacking stat.
        Utility is only worth a slot when it clearly helps this matchup. Avoid speed boosts if the fighter is already faster. Avoid attack/special boosts when the fighter lacks good matching damaging moves.
        """
    }

    /// Player + roster summary for opponent selection. Operates on Sendable
    /// snapshots, never SwiftData `@Model` rows, so the AI actor can build
    /// the prompt off-main without crossing isolation into the main-bound
    /// `Pokemon` store. The caller builds the snapshots on main before the
    /// actor call.
    func buildOpponentPrompt(
        player: OpponentCandidateSnapshot,
        candidates: [OpponentCandidateSnapshot],
        typeChart: TypeChart?
    ) -> String {
        let roster = candidates.map { candidate in
            let types = candidate.typeNames.joined(separator: "/")
            let matchup = opponentMatchupSummary(player: player, candidate: candidate, typeChart: typeChart)
            return "- \(candidate.id): \(candidate.name) (\(types), BST \(candidate.baseStatTotal), \(matchup)\(flagSuffix(candidate)))"
        }.joined(separator: "\n")
        return """
        Pick a competitive, exciting opponent for \(player.name). Prioritise matchups where BOTH sides can threaten each other. Avoid hard counters (4x STAB advantage) and avoid opponents the player completely walls. The best fight is one where either side could win.

        Player: \(player.name) (id \(player.id))
        - Types: \(player.typeNames.joined(separator: "/"))
        - Generation: \(generationLabel(player))\(flagSuffix(player))
        - Base stat total: \(player.baseStatTotal)
        - Stats: \(compactStats(player))

        Candidates (id: name (types, BST, matchup, flags)):
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
            effectivenessText = "x\(format(effectiveness)) vs defender"
        }
        let tag = annotation.map { " [\($0)]" } ?? ""
        return "\(index): \(move.name). \(move.typeName) \(move.damageClass), power \(power), acc \(accuracy), \(effectivenessText)\(tag)"
    }

    func describeLoadoutMove(
        _ move: MoveDetail,
        index: Int,
        fighter: BattleCombatant,
        opponent: BattleCombatant,
        effectiveness: Double
    ) -> String {
        let base = describe(move, index: index, effectiveness: effectiveness)
        let notes = loadoutNotes(move, fighter: fighter, opponent: opponent, effectiveness: effectiveness)
        guard !notes.isEmpty else { return base }
        return "\(base) [\(notes.joined(separator: ", "))]"
    }

    func loadoutNotes(
        _ move: MoveDetail,
        fighter: BattleCombatant,
        opponent: BattleCombatant,
        effectiveness: Double
    ) -> [String] {
        var notes: [String] = []
        if fighter.typeNames.contains(move.typeName) { notes.append("STAB") }
        if effectiveness >= 2 { notes.append("super-effective") }
        if effectiveness == 0 { notes.append("no-effect") }
        if effectiveness > 0 && effectiveness < 1 { notes.append("resisted") }

        switch move.damageClassKind {
        case .physical:
            notes.append(fighter.attack >= fighter.specialAttack ? "uses stronger ATK" : "uses weaker ATK")
            if opponent.defense > opponent.specialDefense + 15 { notes.append("targets high DEF") }
        case .special:
            notes.append(fighter.specialAttack >= fighter.attack ? "uses stronger SPA" : "uses weaker SPA")
            if opponent.specialDefense > opponent.defense + 15 { notes.append("targets high SPD") }
        case .status:
            notes.append(contentsOf: statusMoveNotes(move, fighter: fighter, opponent: opponent))
        }

        if let power = move.power, power > 0 {
            let expected = expectedDamageSignal(move, fighter: fighter, opponent: opponent, effectiveness: effectiveness)
            notes.append("damage score \(Int(expected.rounded()))")
            if expected >= Double(opponent.currentHP) { notes.append("likely KO") }
            if power < 60 { notes.append("low power") }
        }
        if move.accuracy ?? 100 < 85 { notes.append("risky accuracy") }
        if move.hasSelfDebuff { notes.append("self-debuff") }
        if move.isRechargeMove { notes.append("SKIPS NEXT TURN after use") }
        return notes
    }

    func statusMoveNotes(_ move: MoveDetail, fighter: BattleCombatant, opponent: BattleCombatant) -> [String] {
        var notes: [String] = []
        for (index, stat) in move.statChangeNames.enumerated() where index < move.statChangeDeltas.count {
            let delta = move.statChangeDeltas[index]
            if stat == "speed", delta > 0, fighter.effectiveSpeed > opponent.effectiveSpeed {
                notes.append("speed boost low value")
            } else if stat == "attack", delta > 0, fighter.attack < fighter.specialAttack {
                notes.append("attack boost low value")
            } else if stat == "special-attack", delta > 0, fighter.specialAttack < fighter.attack {
                notes.append("special boost low value")
            } else {
                notes.append("\(stat) \(signed(delta))")
            }
        }
        if move.ailment != "none" {
            notes.append("\(move.ailment) \(move.ailmentChance)%")
        }
        if move.healing > 0 || move.name == "rest" {
            notes.append("healing")
        }
        return notes
    }

    func expectedDamageSignal(
        _ move: MoveDetail,
        fighter: BattleCombatant,
        opponent: BattleCombatant,
        effectiveness: Double
    ) -> Double {
        guard let power = move.power, power > 0, move.damageClassKind != .status else { return 0 }
        let attackStat: Int
        let defenseStat: Int
        switch move.damageClassKind {
        case .physical:
            attackStat = fighter.attack
            defenseStat = max(1, opponent.defense)
        case .special:
            attackStat = fighter.specialAttack
            defenseStat = max(1, opponent.specialDefense)
        case .status:
            return 0
        }
        let stab = fighter.typeNames.contains(move.typeName) ? 1.5 : 1.0
        let accuracy = Double(move.accuracy ?? 100) / 100
        let levelFactor = 22.0
        let base = (((levelFactor * Double(power) * Double(attackStat) / Double(defenseStat)) / 50.0) + 2.0)
        return base * stab * effectiveness * accuracy
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

    func compactStats(_ snapshot: OpponentCandidateSnapshot) -> String {
        let order: [(String, String)] = [
            ("HP", "hp"),
            ("ATK", "attack"),
            ("DEF", "defense"),
            ("SPA", "special-attack"),
            ("SPD", "special-defense"),
            ("SPE", "speed")
        ]
        return order.map { label, key in "\(label) \(snapshot.stats[key] ?? 0)" }.joined(separator: "/")
    }

    func flagSuffix(_ snapshot: OpponentCandidateSnapshot) -> String {
        if snapshot.isLegendary { return ", legendary" }
        if snapshot.isMythical { return ", mythical" }
        return ""
    }

    func generationLabel(_ snapshot: OpponentCandidateSnapshot) -> String {
        snapshot.generationName?
            .replacingOccurrences(of: "generation-", with: "Gen ")
            .uppercased() ?? "?"
    }

    func opponentMatchupSummary(
        player: OpponentCandidateSnapshot,
        candidate: OpponentCandidateSnapshot,
        typeChart: TypeChart?
    ) -> String {
        let delta = candidate.baseStatTotal - player.baseStatTotal
        guard let typeChart else {
            return "BST delta \(signed(delta))"
        }
        let candidatePressure = bestSTABMultiplier(attackerTypes: candidate.typeNames, defenderTypes: player.typeNames, typeChart: typeChart)
        let playerPressure = bestSTABMultiplier(attackerTypes: player.typeNames, defenderTypes: candidate.typeNames, typeChart: typeChart)
        return "BST delta \(signed(delta)), candidate STAB x\(format(candidatePressure)) vs player, player STAB x\(format(playerPressure)) vs candidate"
    }

    func bestSTABMultiplier(attackerTypes: [String], defenderTypes: [String], typeChart: TypeChart) -> Double {
        attackerTypes
            .map { typeChart.multiplier(attacking: $0, defenders: defenderTypes) }
            .max() ?? 1.0
    }

    func signed(_ value: Int) -> String {
        value >= 0 ? "+\(value)" : "\(value)"
    }

    func statusDescription(_ status: BattleStatus) -> String {
        switch status {
        case .none: return "healthy"
        case .paralysis: return "paralyzed (speed halved, 25% skip)"
        case .burn: return "burned (-1/16 HP/turn, physical halved)"
        case .poison: return "poisoned (-1/8 HP/turn)"
        case .sleep: return "asleep (skips turns, wakes in 1-3 turns)"
        }
    }

    func stageSummary(_ combatant: BattleCombatant) -> String {
        let active = combatant.statStages
            .filter { $0.value != 0 }
            .sorted { $0.key < $1.key }
            .map { "\($0.key) \(signed($0.value))" }
        return active.isEmpty ? "none" : active.joined(separator: ", ")
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
