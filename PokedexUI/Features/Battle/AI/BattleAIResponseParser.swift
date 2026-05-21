import BattleKit
import Foundation

/// Parses raw LLM responses into battle decisions with deterministic fallbacks.
enum BattleAIResponseParser {

    static func firstInt(in text: String) -> Int? {
        guard let match = text.firstMatch(of: /\d+/) else { return nil }
        return Int(match.output)
    }

    static func parseLoadoutIndices(_ text: String, indexMap: [Int: Int], moves: [MoveDetail], count: Int) -> [MoveDetail] {
        let byName = Dictionary(uniqueKeysWithValues: moves.map { ($0.name, $0) })
        var picked: [MoveDetail] = []
        var usedNames: Set<String> = []

        func take(_ move: MoveDetail) {
            guard !usedNames.contains(move.name) else { return }
            picked.append(move)
            usedNames.insert(move.name)
        }

        for name in byName.keys where text.contains(name) {
            guard picked.count < count else { break }
            take(byName[name]!)
        }

        if picked.count < count {
            let ints = text.matches(of: /\d+/).compactMap { Int($0.output) }
            for displayIdx in ints {
                guard picked.count < count,
                      let originalIdx = indexMap[displayIdx],
                      moves.indices.contains(originalIdx) else { continue }
                take(moves[originalIdx])
            }
        }

        return picked
    }

    static func heuristicMove(
        attacker: BattleCombatant,
        defender: BattleCombatant,
        moves: [MoveDetail],
        typeChart: TypeChart,
        recentMoves: [String]
    ) -> MoveDetail? {
        moves.max { lhs, rhs in
            moveScore(
                move: lhs,
                attacker: attacker,
                defender: defender,
                typeChart: typeChart,
                recentMoves: recentMoves
            ) < moveScore(
                move: rhs,
                attacker: attacker,
                defender: defender,
                typeChart: typeChart,
                recentMoves: recentMoves
            )
        }
    }

    /// Override boost/status picks when game state makes them wasteful.
    static func phaseAdjustedMove(
        _ chosen: MoveDetail,
        attacker: BattleCombatant,
        defender: BattleCombatant,
        moves: [MoveDetail],
        typeChart: TypeChart
    ) -> MoveDetail {
        // Don't re-boost when already set up
        if (chosen.power ?? 0) == 0,
           chosen.statChangeDeltas.contains(where: { $0 > 0 }),
           attacker.statStages.values.contains(where: { $0 >= 2 }) {
            return fallbackDamageMove(from: moves, defender: defender, typeChart: typeChart) ?? chosen
        }
        // Don't re-status a target that already has one
        if chosen.ailment != "none", defender.status != .none {
            return fallbackDamageMove(from: moves, defender: defender, typeChart: typeChart) ?? chosen
        }
        return chosen
    }

    static func heuristicOpponent(
        player: OpponentCandidateSnapshot,
        candidates: [OpponentCandidateSnapshot],
        typeChart: TypeChart?
    ) -> Int? {
        bestOpponent(player: player, candidates: candidates, typeChart: typeChart)?.id
    }

    /// Shrink a full move pool to a diverse shortlist for the LLM.
    static func loadoutShortlist(
        fighter: BattleCombatant,
        opponent: BattleCombatant,
        moves: [MoveDetail],
        typeChart: TypeChart,
        limit: Int = 24
    ) -> [MoveDetail] {
        let candidates = moves.map { move -> (move: MoveDetail, eff: Double, score: Double) in
            let eff = typeChart.multiplier(attacking: move.typeName, defenders: opponent.typeNames)
            return (move, eff, loadoutScore(move: move, fighter: fighter, opponent: opponent, typeChart: typeChart))
        }
        var picked: [MoveDetail] = []
        var usedNames: Set<String> = []

        func take(_ items: [(move: MoveDetail, eff: Double, score: Double)], cap: Int) {
            for item in items.sorted(by: { $0.score > $1.score }) {
                guard picked.count < limit, !usedNames.contains(item.move.name) else { return }
                picked.append(item.move)
                usedNames.insert(item.move.name)
                if picked.count >= cap { return }
            }
        }

        let seDamage = candidates.filter { ($0.move.power ?? 0) > 0 && $0.eff >= 2 }
        let damage = candidates.filter { ($0.move.power ?? 0) > 0 }
        let boosts = candidates.filter { ($0.move.power ?? 0) == 0 && $0.move.statChangeDeltas.contains { $0 > 0 } }
        let disrupts = candidates.filter { ($0.move.power ?? 0) == 0 && ($0.move.ailment != "none" || $0.move.statChangeDeltas.contains { $0 < 0 }) }

        take(seDamage, cap: picked.count + 6)
        take(damage, cap: picked.count + 8)
        take(boosts, cap: picked.count + 4)
        take(disrupts, cap: picked.count + 4)

        let remaining = candidates
            .filter { !usedNames.contains($0.move.name) }
            .sorted { $0.score > $1.score }
        for item in remaining where picked.count < limit {
            picked.append(item.move)
            usedNames.insert(item.move.name)
        }

        return picked
    }

    /// Deterministic loadout: 1 SE damage + 1 lesser damage + 1 self-boost + 1 disruption.
    /// Falls back to best available when a slot category has no candidates.
    static func assembleOpponentLoadout(
        for fighter: BattleCombatant,
        against opponent: BattleCombatant,
        moves: [MoveDetail],
        typeChart: TypeChart
    ) -> [MoveDetail] {
        var picked: [MoveDetail] = []
        var usedNames: Set<String> = []

        let candidates = moves.map { move -> (move: MoveDetail, eff: Double) in
            (move, typeChart.multiplier(attacking: move.typeName, defenders: opponent.typeNames))
        }

        func score(_ m: MoveDetail) -> Double {
            loadoutScore(move: m, fighter: fighter, opponent: opponent, typeChart: typeChart)
        }

        func best(where predicate: (MoveDetail, Double) -> Bool) -> MoveDetail? {
            candidates
                .filter { !usedNames.contains($0.move.name) && predicate($0.move, $0.eff) }
                .max { score($0.move) < score($1.move) }?
                .move
        }

        func take(_ move: MoveDetail?) {
            guard let move, !usedNames.contains(move.name) else { return }
            picked.append(move)
            usedNames.insert(move.name)
        }

        // Slot 1: Best super-effective damage move
        take(best { move, eff in (move.power ?? 0) > 0 && eff >= 2 })
        // Slot 2: Best remaining damage move
        take(best { move, _ in (move.power ?? 0) > 0 })
        // Slot 3: Best self-boost (status move with positive stat changes)
        take(best { move, _ in (move.power ?? 0) == 0 && move.statChangeDeltas.contains(where: { $0 > 0 }) })
        // Slot 4: Best disruption (ailment or opponent debuff)
        take(best { move, _ in (move.power ?? 0) == 0 && (move.ailment != "none" || move.statChangeDeltas.contains(where: { $0 < 0 })) })

        // Pad remaining slots with highest-scored unused moves
        while picked.count < 4 {
            guard let filler = best(where: { _, _ in true }) else { break }
            take(filler)
        }

        return picked
    }

    /// Pad LLM-seeded picks to `count` using deterministic scoring.
    static func fillLoadout(
        seed: [MoveDetail],
        fighter: BattleCombatant,
        opponent: BattleCombatant,
        moves: [MoveDetail],
        typeChart: TypeChart,
        count: Int
    ) -> [MoveDetail] {
        guard seed.count < count else { return Array(seed.prefix(count)) }
        var picked = seed
        var usedNames = Set(seed.map(\.name))
        while picked.count < count {
            guard let best = moves
                .filter({ !usedNames.contains($0.name) })
                .max(by: { loadoutScore(move: $0, fighter: fighter, opponent: opponent, typeChart: typeChart)
                    < loadoutScore(move: $1, fighter: fighter, opponent: opponent, typeChart: typeChart) })
            else { break }
            picked.append(best)
            usedNames.insert(best.name)
        }
        return picked
    }

    /// Enforce 2 DMG + 1 BOOST + 1 DISRUPT composition, replacing excess damage moves.
    static func enforceComposition(
        _ loadout: [MoveDetail],
        pool: [MoveDetail],
        fighter: BattleCombatant,
        opponent: BattleCombatant,
        typeChart: TypeChart
    ) -> [MoveDetail] {
        var result = loadout
        var usedNames = Set(result.map(\.name))
        let hasBoost = result.contains { $0.loadoutCategory == "BOOST" }
        let hasDisrupt = result.contains { $0.loadoutCategory == "DISRUPT" }
        let damageMoves = result.enumerated().filter { ($0.element.power ?? 0) > 0 }

        guard damageMoves.count > 2 else { return result }

        let sorted = damageMoves.sorted {
            DamageCalculator.estimateDamage(move: $0.element, attacker: fighter, defender: opponent, typeChart: typeChart)
            < DamageCalculator.estimateDamage(move: $1.element, attacker: fighter, defender: opponent, typeChart: typeChart)
        }

        func bestFromPool(category: String) -> MoveDetail? {
            pool.filter { !usedNames.contains($0.name) && $0.loadoutCategory == category }
                .max {
                    loadoutScore(move: $0, fighter: fighter, opponent: opponent, typeChart: typeChart)
                    < loadoutScore(move: $1, fighter: fighter, opponent: opponent, typeChart: typeChart)
                }
        }

        var replaced = 0
        for item in sorted {
            guard replaced < damageMoves.count - 2 else { break }
            let needed: String? = !hasBoost && replaced == 0 ? "BOOST" :
                !hasDisrupt ? "DISRUPT" :
                ["BOOST", "DISRUPT"].randomElement()
            guard let category = needed, let swap = bestFromPool(category: category) else { continue }
            result[item.offset] = swap
            usedNames.insert(swap.name)
            replaced += 1
            print("[ai] composition: replaced \(item.element.name) with \(swap.name) (\(category))")
        }
        return result
    }

    /// Downgrade one damage move to a weak alternative for balance.
    static func handicapLoadout(
        _ loadout: [MoveDetail],
        pool: [MoveDetail],
        fighter: BattleCombatant,
        opponent: BattleCombatant,
        typeChart: TypeChart
    ) -> [MoveDetail] {
        let damageMoves = loadout.enumerated().filter { ($0.element.power ?? 0) > 0 }
        guard damageMoves.count >= 2 else { return loadout }
        let weakest = damageMoves.min { lhs, rhs in
            DamageCalculator.estimateDamage(move: lhs.element, attacker: fighter, defender: opponent, typeChart: typeChart)
            < DamageCalculator.estimateDamage(move: rhs.element, attacker: fighter, defender: opponent, typeChart: typeChart)
        }
        guard let weakest else { return loadout }
        let usedNames = Set(loadout.map(\.name))
        let bestDmg = max(1, damageMoves.compactMap {
            DamageCalculator.estimateDamage(move: $0.element, attacker: fighter, defender: opponent, typeChart: typeChart)
        }.max() ?? 1)
        let threshold = Int(Double(bestDmg) * 0.55)
        let candidates = pool
            .filter { ($0.power ?? 0) > 0 && !usedNames.contains($0.name) }
            .filter { typeChart.multiplier(attacking: $0.typeName, defenders: opponent.typeNames) > 0 }
            .filter {
                let dmg = DamageCalculator.estimateDamage(move: $0, attacker: fighter, defender: opponent, typeChart: typeChart)
                return dmg > 0 && dmg < threshold
            }
            .sorted {
                DamageCalculator.estimateDamage(move: $0, attacker: fighter, defender: opponent, typeChart: typeChart)
                < DamageCalculator.estimateDamage(move: $1, attacker: fighter, defender: opponent, typeChart: typeChart)
            }
        let bottomHalf = candidates.prefix(max(1, candidates.count / 2))
        guard let replacement = bottomHalf.randomElement() else { return loadout }
        var result = loadout
        result[weakest.offset] = replacement
        print("[ai] handicap: swapped \(weakest.element.name) -> \(replacement.name)")
        return result
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

        if delta < 0, delta >= -50 { score += 12 }

        if let typeChart {
            let candidatePressure = typeChart.bestSTABMultiplier(
                attackerTypes: candidate.typeNames,
                defenderTypes: player.typeNames
            )
            let playerPressure = typeChart.bestSTABMultiplier(
                attackerTypes: player.typeNames,
                defenderTypes: candidate.typeNames
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

    private static func fallbackDamageMove(
        from moves: [MoveDetail],
        defender: BattleCombatant,
        typeChart: TypeChart
    ) -> MoveDetail? {
        let scored: [(move: MoveDetail, weight: Double)] = moves.compactMap { move in
            guard let power = move.power, power > 0 else { return nil }
            let eff = typeChart.multiplier(attacking: move.typeName, defenders: defender.typeNames)
            guard eff > 0 else { return nil }
            return (move, Double(power) * eff)
        }
        return scored.max { $0.weight < $1.weight }?.move
    }

    private static func loadoutScore(
        move: MoveDetail,
        fighter: BattleCombatant,
        opponent: BattleCombatant,
        typeChart: TypeChart
    ) -> Double {
        if (move.power ?? 0) > 0, move.damageClassKind != .status {
            let effectiveness = typeChart.multiplier(attacking: move.typeName, defenders: opponent.typeNames)
            guard effectiveness > 0 else { return -100 }
            let accuracy = Double(move.accuracy ?? 100) / 100
            let estimated = Double(DamageCalculator.estimateDamage(
                move: move,
                attacker: fighter,
                defender: opponent,
                typeChart: typeChart
            ))
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
        typeChart: TypeChart,
        recentMoves: [String]
    ) -> Double {
        var score = loadoutScore(
            move: move,
            fighter: attacker,
            opponent: defender,
            typeChart: typeChart
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

// MARK: - Private
private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
