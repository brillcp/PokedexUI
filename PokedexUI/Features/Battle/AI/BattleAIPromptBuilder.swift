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

    func flagSuffix(_ snapshot: OpponentCandidateSnapshot) -> String {
        if snapshot.isLegendary { return ", legendary" }
        if snapshot.isMythical { return ", mythical" }
        return ""
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
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
