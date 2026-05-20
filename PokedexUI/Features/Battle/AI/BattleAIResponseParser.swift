import Foundation

/// Parses raw LLM responses into battle decisions with deterministic fallbacks.
enum BattleAIResponseParser {

    static func firstInt(in text: String) -> Int? {
        guard let match = text.firstMatch(of: /\d+/) else { return nil }
        return Int(match.output)
    }

    static func intsOnLastLine(of text: String) -> [Int] {
        let lastLine = text
            .components(separatedBy: .newlines)
            .last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
            ?? text
        return lastLine.matches(of: /\d+/).compactMap { Int($0.output) }
    }

    static func heuristicLoadout(from moves: [MoveDetail], count: Int) -> [MoveDetail] {
        Array(
            moves.sorted { lhs, rhs in
                let lDamaging = (lhs.power ?? 0) > 0
                let rDamaging = (rhs.power ?? 0) > 0
                if lDamaging != rDamaging { return lDamaging }
                if lhs.power != rhs.power { return (lhs.power ?? 0) > (rhs.power ?? 0) }
                return (lhs.accuracy ?? 100) > (rhs.accuracy ?? 100)
            }
            .prefix(count)
        )
    }

    static func heuristicLoadout(
        for fighter: BattleCombatant,
        against opponent: BattleCombatant,
        moves: [MoveDetail],
        effectiveness: [Double],
        count: Int
    ) -> [MoveDetail] {
        let ranked = moves.enumerated().sorted { lhs, rhs in
            loadoutScore(
                move: lhs.element,
                fighter: fighter,
                opponent: opponent,
                effectiveness: effectiveness[safe: lhs.offset] ?? 1
            ) > loadoutScore(
                move: rhs.element,
                fighter: fighter,
                opponent: opponent,
                effectiveness: effectiveness[safe: rhs.offset] ?? 1
            )
        }

        var picked: [MoveDetail] = []
        var usedTypes: Set<String> = []
        for item in ranked {
            guard picked.count < count else { break }
            let move = item.element
            let score = loadoutScore(
                move: move,
                fighter: fighter,
                opponent: opponent,
                effectiveness: effectiveness[safe: item.offset] ?? 1
            )
            if picked.count >= 2, usedTypes.contains(move.typeName), (move.power ?? 0) > 0 {
                continue
            }
            if score <= 0, picked.count < count - 1 {
                continue
            }
            picked.append(move)
            if (move.power ?? 0) > 0 { usedTypes.insert(move.typeName) }
        }

        guard picked.count < count else { return Array(picked.prefix(count)) }
        let usedNames = Set(picked.map(\.name))
        let padded = picked + heuristicLoadout(from: moves, count: count)
            .filter { !usedNames.contains($0.name) }
            .prefix(count - picked.count)
        return Array(padded.prefix(count))
    }

    static func heuristicMove(
        attacker: BattleCombatant,
        defender: BattleCombatant,
        moves: [MoveDetail],
        effectiveness: [Double],
        recentMoves: [String]
    ) -> MoveDetail? {
        moves.enumerated().max { lhs, rhs in
            moveScore(
                move: lhs.element,
                attacker: attacker,
                defender: defender,
                effectiveness: effectiveness[safe: lhs.offset] ?? 1,
                recentMoves: recentMoves
            ) < moveScore(
                move: rhs.element,
                attacker: attacker,
                defender: defender,
                effectiveness: effectiveness[safe: rhs.offset] ?? 1,
                recentMoves: recentMoves
            )
        }?.element
    }

    static func heuristicOpponent(
        player: OpponentCandidateSnapshot,
        candidates: [OpponentCandidateSnapshot],
        typeChart: TypeChart?
    ) -> Int? {
        bestOpponent(player: player, candidates: candidates, typeChart: typeChart)?.id
    }

    static func rankedMoveSample(
        for fighter: BattleCombatant,
        against opponent: BattleCombatant,
        moves: [MoveDetail],
        effectiveness: [Double],
        count: Int
    ) -> [MoveDetail] {
        guard moves.count > count else { return moves }
        // Pre-filter: drop damaging moves that are resisted or immune.
        let filtered = moves.enumerated().filter { idx, move in
            let eff = effectiveness[safe: idx] ?? 1
            if (move.power ?? 0) > 0, eff > 0, eff < 1 { return false }
            if eff == 0 { return false }
            return true
        }
        // Fall back to full pool if filtering removed too many options.
        let pool = filtered.count >= count ? filtered : moves.enumerated().map { ($0, $1) }
        let ranked = pool.sorted {
            loadoutScore(
                move: $0.element,
                fighter: fighter,
                opponent: opponent,
                effectiveness: effectiveness[safe: $0.offset] ?? 1
            ) > loadoutScore(
                move: $1.element,
                fighter: fighter,
                opponent: opponent,
                effectiveness: effectiveness[safe: $1.offset] ?? 1
            )
        }

        var picked: [MoveDetail] = []
        var usedNames: Set<String> = []

        func append(where predicate: (MoveDetail, Int) -> Bool) {
            for item in ranked where picked.count < count {
                let move = item.element
                guard !usedNames.contains(move.name), predicate(move, item.offset) else { continue }
                picked.append(move)
                usedNames.insert(move.name)
            }
        }

        append { move, offset in
            (effectiveness[safe: offset] ?? 1) >= 2 && (move.power ?? 0) > 0
        }
        append { move, _ in
            fighter.typeNames.contains(move.typeName) && (move.power ?? 0) > 0
        }
        append { move, _ in
            move.priority > 0 && (move.power ?? 0) > 0
        }
        append { move, _ in
            move.ailment != "none" || !move.statChangeNames.isEmpty || move.healing > 0 || move.name == "rest"
        }
        append { _, _ in true }

        return Array(picked.prefix(count))
    }

    private static func bestOpponent(
        player: OpponentCandidateSnapshot,
        candidates: [OpponentCandidateSnapshot],
        typeChart: TypeChart?
    ) -> OpponentCandidateSnapshot? {
        let tiered = candidates.filter { candidate in
            let delta = candidate.baseStatTotal - player.baseStatTotal
            return delta >= -90 && delta <= 160
        }
        let pool = tiered.isEmpty ? candidates : tiered
        return pool.max { lhs, rhs in
            opponentScore(player: player, candidate: lhs, typeChart: typeChart)
                < opponentScore(player: player, candidate: rhs, typeChart: typeChart)
        }
    }

    static func assembleLoadout(
        indices: [Int],
        from moves: [MoveDetail],
        size: Int
    ) -> [MoveDetail] {
        let fallback = heuristicLoadout(from: moves, count: size)
        let valid = Array(Set(indices.filter { moves.indices.contains($0) })).map { moves[$0] }
        guard valid.count < size else { return Array(valid.prefix(size)) }
        let usedNames = Set(valid.map(\.name))
        let padded = valid + fallback.filter { !usedNames.contains($0.name) }.prefix(size - valid.count)
        return Array(padded.prefix(size))
    }

    static func repairedLoadout(
        indices: [Int],
        from moves: [MoveDetail],
        fighter: BattleCombatant,
        opponent: BattleCombatant,
        effectiveness: [Double],
        size: Int
    ) -> [MoveDetail] {
        let heuristic = heuristicLoadout(
            for: fighter,
            against: opponent,
            moves: moves,
            effectiveness: effectiveness,
            count: size
        )
        let ranked = moves.enumerated().sorted {
            loadoutScore(
                move: $0.element,
                fighter: fighter,
                opponent: opponent,
                effectiveness: effectiveness[safe: $0.offset] ?? 1
            ) > loadoutScore(
                move: $1.element,
                fighter: fighter,
                opponent: opponent,
                effectiveness: effectiveness[safe: $1.offset] ?? 1
            )
        }
        let bestScore = ranked.first.map {
            loadoutScore(
                move: $0.element,
                fighter: fighter,
                opponent: opponent,
                effectiveness: effectiveness[safe: $0.offset] ?? 1
            )
        } ?? 0

        var picked: [MoveDetail] = []
        var usedNames: Set<String> = []
        var rechargeCount = 0
        var typeCount: [String: Int] = [:]
        for index in indices where moves.indices.contains(index) {
            let move = moves[index]
            guard !usedNames.contains(move.name) else { continue }
            let eff = effectiveness[safe: index] ?? 1
            // Reject heavily resisted damaging moves when better options exist.
            if (move.power ?? 0) > 0, eff > 0, eff < 1, bestScore > 20 { continue }
            // Cap recharge moves at 1 in the loadout.
            if move.isRechargeMove { guard rechargeCount == 0 else { continue }; rechargeCount += 1 }
            // Cap same-type damaging moves at 2 for coverage diversity.
            if (move.power ?? 0) > 0, (typeCount[move.typeName] ?? 0) >= 2 { continue }
            let score = loadoutScore(
                move: move,
                fighter: fighter,
                opponent: opponent,
                effectiveness: eff
            )
            let isUsefulUtility = (move.power ?? 0) == 0 && score >= 16
            let isGoodEnough = score >= 12 && score >= bestScore * 0.35
            if isGoodEnough || isUsefulUtility {
                picked.append(move)
                usedNames.insert(move.name)
                if (move.power ?? 0) > 0 { typeCount[move.typeName, default: 0] += 1 }
            }
            if picked.count == size { break }
        }

        for move in heuristic where picked.count < size && !usedNames.contains(move.name) {
            picked.append(move)
            usedNames.insert(move.name)
        }

        if picked.count < size {
            for item in ranked where picked.count < size && !usedNames.contains(item.element.name) {
                picked.append(item.element)
                usedNames.insert(item.element.name)
            }
        }

        return Array(picked.prefix(size))
    }

    private static func opponentScore(
        player: OpponentCandidateSnapshot,
        candidate: OpponentCandidateSnapshot,
        typeChart: TypeChart?
    ) -> Double {
        let delta = candidate.baseStatTotal - player.baseStatTotal
        let absDelta = abs(delta)
        var score = 0.0

        if absDelta <= 70 {
            score += 35 - Double(absDelta) * 0.20
        } else if delta < -90 {
            score -= 70 + Double(abs(delta + 90)) * 0.35
        } else if delta > 160 {
            score -= 45 + Double(delta - 160) * 0.20
        } else {
            score += max(0, 20 - Double(absDelta - 70) * 0.15)
        }

        if let typeChart {
            let candidatePressure = bestSTABMultiplier(
                attackerTypes: candidate.typeNames,
                defenderTypes: player.typeNames,
                typeChart: typeChart
            )
            let playerPressure = bestSTABMultiplier(
                attackerTypes: player.typeNames,
                defenderTypes: candidate.typeNames,
                typeChart: typeChart
            )

            score += pressureScore(candidatePressure)
            score -= vulnerabilityPenalty(playerPressure)

            // Mutual threat bonus
            if candidatePressure >= 1.5, playerPressure >= 1.5 {
                score += 18
            }
            // One-sided dominance penalty
            if candidatePressure >= 4, playerPressure <= 1 {
                score -= 25
            }
            if candidatePressure < 1, playerPressure >= 2 {
                score -= 18
            }
        }

        if candidate.isLegendary || candidate.isMythical {
            score += player.baseStatTotal >= 500 ? 10 : -8
        }
        // Megas punch above weight; only allow when player can keep up.
        if candidate.name.localizedCaseInsensitiveContains("mega") {
            score += player.baseStatTotal >= 540 ? 4 : -20
        }

        return score
    }

    private static func bestSTABMultiplier(
        attackerTypes: [String],
        defenderTypes: [String],
        typeChart: TypeChart
    ) -> Double {
        attackerTypes
            .map { typeChart.multiplier(attacking: $0, defenders: defenderTypes) }
            .max() ?? 1.0
    }

    private static func pressureScore(_ multiplier: Double) -> Double {
        if multiplier >= 4 { return 8 }
        if multiplier >= 2 { return 30 }
        if multiplier >= 1 { return 10 }
        if multiplier > 0 { return -4 }
        return -12
    }

    private static func vulnerabilityPenalty(_ multiplier: Double) -> Double {
        if multiplier >= 4 { return 32 }
        if multiplier >= 2 { return 14 }
        if multiplier >= 1 { return 0 }
        return -8
    }

    private static func loadoutScore(
        move: MoveDetail,
        fighter: BattleCombatant,
        opponent: BattleCombatant,
        effectiveness: Double
    ) -> Double {
        if let power = move.power, power > 0, move.damageClassKind != .status {
            guard effectiveness > 0 else { return -100 }
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
            let estimated = estimatedDamage(power: power, attack: attackStat, defense: defenseStat, stab: stab, effectiveness: effectiveness)
            var score = estimated * accuracy
            if estimated >= Double(opponent.currentHP) { score += 55 }
            if estimated >= Double(opponent.currentHP) * 0.65 { score += 18 }
            if effectiveness < 1 && effectiveness > 0 { score *= 0.4 }
            if move.hasSelfDebuff { score -= 18 }
            if move.priority > 0 { score += 8 }
            if move.isRechargeMove { score *= 0.45 }
            return score
        }

        var score = 0.0
        if move.ailment != "none" {
            score += statusScore(move.ailment, chance: move.ailmentChance, fighter: fighter, opponent: opponent)
        }
        if move.healing > 0 || move.name == "rest" {
            score += opponent.maxHP > fighter.maxHP ? 16 : 8
        }
        for (index, stat) in move.statChangeNames.enumerated() where index < move.statChangeDeltas.count {
            score += statChangeScore(
                stat: stat,
                delta: move.statChangeDeltas[index],
                fighter: fighter,
                opponent: opponent
            )
        }
        return score
    }

    private static func moveScore(
        move: MoveDetail,
        attacker: BattleCombatant,
        defender: BattleCombatant,
        effectiveness: Double,
        recentMoves: [String]
    ) -> Double {
        var score = loadoutScore(
            move: move,
            fighter: attacker,
            opponent: defender,
            effectiveness: effectiveness
        )

        if recentMoves.last == move.name {
            score -= 18
        } else if recentMoves.contains(move.name) {
            score -= 8
        }

        if (move.power ?? 0) == 0 {
            for (index, stat) in move.statChangeNames.enumerated() where index < move.statChangeDeltas.count {
                let delta = move.statChangeDeltas[index]
                if delta > 0, attacker.stage(for: stat) >= 2 {
                    score -= 18
                }
            }
        }

        // Avoid trying to re-status a target that already has one.
        if defender.status != .none, move.ailment != "none" {
            score -= 25
        }

        // Low HP: prefer recovery, deprioritize chip damage.
        let hpFraction = Double(attacker.currentHP) / Double(max(1, attacker.maxHP))
        if hpFraction <= 0.30 {
            if move.healing > 0 || move.name == "rest" {
                score += 35
            } else if (move.power ?? 0) > 0, move.priority <= 0 {
                score -= 8
            }
            if move.priority > 0, (move.power ?? 0) > 0 {
                score += 6
            }
        }

        return score
    }

    private static func estimatedDamage(
        power: Int,
        attack: Int,
        defense: Int,
        stab: Double,
        effectiveness: Double
    ) -> Double {
        let levelFactor = 22.0
        let base = (((levelFactor * Double(power) * Double(attack) / Double(max(1, defense))) / 50.0) + 2.0)
        return base * stab * effectiveness
    }

    /// Estimated damage a single move deals, used by the brain for KO overrides.
    static func estimatedDamage(
        move: MoveDetail,
        attacker: BattleCombatant,
        defender: BattleCombatant,
        typeChart: TypeChart
    ) -> Double {
        guard let power = move.power, power > 0, move.damageClassKind != .status else { return 0 }
        let effectiveness = typeChart.multiplier(attacking: move.typeName, defenders: defender.typeNames)
        guard effectiveness > 0 else { return 0 }
        let attackStat: Int
        let defenseStat: Int
        switch move.damageClassKind {
        case .physical:
            attackStat = attacker.attack
            defenseStat = max(1, defender.defense)
        case .special:
            attackStat = attacker.specialAttack
            defenseStat = max(1, defender.specialDefense)
        case .status:
            return 0
        }
        let stab = attacker.typeNames.contains(move.typeName) ? 1.5 : 1.0
        let cappedEff = effectiveness > 1 ? min(effectiveness, 1.5) : effectiveness
        return estimatedDamage(
            power: power,
            attack: attackStat,
            defense: defenseStat,
            stab: stab,
            effectiveness: cappedEff
        )
    }

    /// Move that lands a KO this turn, accounting for accuracy. Tiebreak: highest expected damage.
    static func guaranteedKO(
        attacker: BattleCombatant,
        defender: BattleCombatant,
        moves: [MoveDetail],
        typeChart: TypeChart
    ) -> MoveDetail? {
        let target = Double(defender.currentHP)
        let killers = moves.compactMap { move -> (MoveDetail, Double)? in
            let dmg = estimatedDamage(move: move, attacker: attacker, defender: defender, typeChart: typeChart)
            guard dmg >= target else { return nil }
            let accuracy = Double(move.accuracy ?? 100) / 100
            guard accuracy >= 0.85 else { return nil }
            return (move, dmg * accuracy)
        }
        return killers.max { $0.1 < $1.1 }?.0
    }

    private static func statusScore(
        _ ailment: String,
        chance: Int,
        fighter: BattleCombatant,
        opponent: BattleCombatant
    ) -> Double {
        let chanceFactor = Double(max(chance, 60)) / 100
        switch ailment {
        case "paralysis":
            return opponent.effectiveSpeed > fighter.effectiveSpeed ? 28 * chanceFactor : 12 * chanceFactor
        case "burn":
            return opponent.attack >= opponent.specialAttack ? 24 * chanceFactor : 10 * chanceFactor
        case "poison":
            return opponent.maxHP >= fighter.maxHP ? 18 * chanceFactor : 8 * chanceFactor
        case "sleep":
            return 22 * chanceFactor
        default:
            return 4 * chanceFactor
        }
    }

    private static func statChangeScore(
        stat: String,
        delta: Int,
        fighter: BattleCombatant,
        opponent: BattleCombatant
    ) -> Double {
        guard delta != 0 else { return 0 }
        if delta > 0 {
            switch stat {
            case "speed":
                return fighter.effectiveSpeed > opponent.effectiveSpeed ? 2 : 16
            case "attack":
                return fighter.attack >= fighter.specialAttack ? Double(delta) * 10 : Double(delta) * 2
            case "special-attack":
                return fighter.specialAttack >= fighter.attack ? Double(delta) * 10 : Double(delta) * 2
            case "defense", "special-defense":
                return opponent.maxHP >= fighter.maxHP ? Double(delta) * 7 : Double(delta) * 4
            default:
                return Double(delta) * 4
            }
        } else {
            switch stat {
            case "defense":
                return fighter.attack >= fighter.specialAttack ? Double(abs(delta)) * 8 : Double(abs(delta)) * 3
            case "special-defense":
                return fighter.specialAttack >= fighter.attack ? Double(abs(delta)) * 8 : Double(abs(delta)) * 3
            case "speed":
                return opponent.effectiveSpeed > fighter.effectiveSpeed ? Double(abs(delta)) * 8 : Double(abs(delta)) * 3
            default:
                return Double(abs(delta)) * 4
            }
        }
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
