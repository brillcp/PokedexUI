import BattleKit
import Foundation

// MARK: - MoveStrategy

/// Deterministic AI for in-battle move selection. Owns the heuristic
/// fallback used when the LLM is unavailable and the post-pick correction
/// pipeline applied to every chosen move regardless of source.
enum MoveStrategy {

    /// Highest-scoring move accounting for damage, recency, and low-HP bias.
    static func heuristicPick(
        attacker: BattleCombatant,
        defender: BattleCombatant,
        moves: [MoveDetail],
        typeChart: TypeChart,
        recentMoves: [String]
    ) -> MoveDetail? {
        moves.max { lhs, rhs in
            inBattleScore(move: lhs, attacker: attacker, defender: defender, typeChart: typeChart, recentMoves: recentMoves)
            < inBattleScore(move: rhs, attacker: attacker, defender: defender, typeChart: typeChart, recentMoves: recentMoves)
        }
    }

    /// Post-pick correction pipeline. Order: immune repair → wasted boost
    /// / re-status override → guaranteed-KO upgrade → redundant-status
    /// downgrade. Each step is a no-op when its precondition isn't met.
    static func adjust(
        pick: MoveDetail,
        attacker: BattleCombatant,
        defender: BattleCombatant,
        moves: [MoveDetail],
        typeChart: TypeChart,
        fallback: MoveDetail
    ) -> MoveDetail {
        var current = pick
        current = immuneRepair(pick: current, defender: defender, typeChart: typeChart, fallback: fallback)
        current = phaseAdjust(pick: current, attacker: attacker, defender: defender, moves: moves, typeChart: typeChart)
        current = koOverride(pick: current, attacker: attacker, defender: defender, moves: moves, typeChart: typeChart)
        current = statusRedundancyOverride(pick: current, attacker: attacker, defender: defender, moves: moves, typeChart: typeChart)
        return current
    }
}

// MARK: - Private
private extension MoveStrategy {

    static func immuneRepair(
        pick: MoveDetail,
        defender: BattleCombatant,
        typeChart: TypeChart,
        fallback: MoveDetail
    ) -> MoveDetail {
        let eff = typeChart.multiplier(attacking: pick.typeName, defenders: defender.typeNames)
        return (eff == 0 && fallback.name != pick.name) ? fallback : pick
    }

    static func phaseAdjust(
        pick: MoveDetail,
        attacker: BattleCombatant,
        defender: BattleCombatant,
        moves: [MoveDetail],
        typeChart: TypeChart
    ) -> MoveDetail {
        let alreadyBoosted = attacker.statStages.values.contains { $0 >= 2 }
        let wastedBoost = (pick.power ?? 0) == 0 && pick.statChangeDeltas.contains { $0 > 0 } && alreadyBoosted
        let wastedStatus = pick.ailment != "none" && defender.status != .none
        guard wastedBoost || wastedStatus else { return pick }
        return fallbackDamageMove(from: moves, defender: defender, typeChart: typeChart) ?? pick
    }

    static func koOverride(
        pick: MoveDetail,
        attacker: BattleCombatant,
        defender: BattleCombatant,
        moves: [MoveDetail],
        typeChart: TypeChart
    ) -> MoveDetail {
        let pickDamage = DamageCalculator.estimateDamage(move: pick, attacker: attacker, defender: defender, typeChart: typeChart)
        guard pickDamage < defender.currentHP else { return pick }
        guard let killer = DamageCalculator.guaranteedKO(
            attacker: attacker, defender: defender, moves: moves, typeChart: typeChart
        ), killer.name != pick.name else { return pick }
        return killer
    }

    static func statusRedundancyOverride(
        pick: MoveDetail,
        attacker: BattleCombatant,
        defender: BattleCombatant,
        moves: [MoveDetail],
        typeChart: TypeChart
    ) -> MoveDetail {
        guard pick.ailment != "none", (pick.power ?? 0) == 0, defender.status != .none else { return pick }
        let alternatives = moves.filter { $0.name != pick.name }
        return DamageCalculator.strongestMove(
            attacker: attacker, defender: defender, moves: alternatives, typeChart: typeChart
        )?.move ?? pick
    }

    static func inBattleScore(
        move: MoveDetail,
        attacker: BattleCombatant,
        defender: BattleCombatant,
        typeChart: TypeChart,
        recentMoves: [String]
    ) -> Double {
        var score = MoveScoring.score(move: move, fighter: attacker, opponent: defender, typeChart: typeChart)

        if recentMoves.last == move.name { score -= 18 }
        else if recentMoves.contains(move.name) { score -= 8 }

        if move.isRechargeMove,
           recentMoves.contains(where: { MoveClassification.rechargeMoves.contains($0) }) {
            score *= 0.2
        }

        if (move.power ?? 0) == 0 {
            for (index, stat) in move.statChangeNames.enumerated() where index < move.statChangeDeltas.count {
                if move.statChangeDeltas[index] > 0, attacker.stage(for: stat) >= 2 {
                    score -= 18
                }
            }
        }

        if defender.status != .none, move.ailment != "none" { score -= 25 }

        let hpFraction = Double(attacker.currentHP) / Double(max(1, attacker.maxHP))
        if hpFraction <= 0.30 {
            if move.healing > 0 || move.name == "rest" { score += 35 }
            else if (move.power ?? 0) > 0, move.priority <= 0 { score -= 8 }
            if move.priority > 0, (move.power ?? 0) > 0 { score += 6 }
        }

        return score
    }

    static func fallbackDamageMove(
        from moves: [MoveDetail],
        defender: BattleCombatant,
        typeChart: TypeChart
    ) -> MoveDetail? {
        moves.compactMap { move -> (MoveDetail, Double)? in
            guard let power = move.power, power > 0 else { return nil }
            let eff = typeChart.multiplier(attacking: move.typeName, defenders: defender.typeNames)
            guard eff > 0 else { return nil }
            return (move, Double(power) * eff)
        }
        .max { $0.1 < $1.1 }?.0
    }
}

// MARK: - MoveScoring

/// Move-evaluation primitive used by both move-pick and loadout-pick AI
/// strategies. Mixes BattleKit's damage estimate with heuristic weights
/// for status effects, stat changes, and move quirks (self-debuff,
/// recharge, priority). Higher score = better for the fighter.
enum MoveScoring {

    static func score(
        move: MoveDetail,
        fighter: BattleCombatant,
        opponent: BattleCombatant,
        typeChart: TypeChart
    ) -> Double {
        if MoveClassification.requiresPoisonedTarget.contains(move.name),
           opponent.status != .poison {
            return Weights.disallowed
        }
        if move.isDamage, move.damageClassKind != .status {
            return damageScore(move: move, fighter: fighter, opponent: opponent, typeChart: typeChart)
        }
        return supportScore(move: move, fighter: fighter, opponent: opponent)
    }

    /// Tunable weights collected in one block so the scoring functions
    /// read as descriptions, not magic constants.
    enum Weights {
        static let disallowed: Double      = -100
        static let koBonus: Double         = 55
        static let nearKOBonus: Double     = 18
        static let resistedMult: Double    = 0.4
        static let selfDebuffPenalty: Double = 18
        static let priorityBonus: Double   = 8
        static let rechargeMult: Double    = 0.45

        static let healingVsBulky: Double  = 16
        static let healingDefault: Double  = 8

        static let statusMinChance: Int    = 60
        static let paralysisFaster: Double = 28
        static let paralysisSlower: Double = 12
        static let burnPhysical: Double    = 24
        static let burnSpecial: Double     = 10
        static let poisonBulky: Double     = 18
        static let poisonFrail: Double     = 8
        static let sleep: Double           = 22
        static let statusOther: Double     = 4

        static let statBoostMatching: Double   = 10
        static let statBoostMismatch: Double   = 2
        static let statBoostSpeedSlow: Double  = 16
        static let statBoostSpeedFast: Double  = 2
        static let statBoostDefVsTank: Double  = 7
        static let statBoostDefVsFrail: Double = 4
        static let statBoostDefault: Double    = 4

        static let statDebuffMatching: Double = 8
        static let statDebuffMismatch: Double = 3
        static let statDebuffDefault: Double  = 4
    }
}

// MARK: - Private
private extension MoveScoring {

    static func damageScore(
        move: MoveDetail,
        fighter: BattleCombatant,
        opponent: BattleCombatant,
        typeChart: TypeChart
    ) -> Double {
        let effectiveness = typeChart.multiplier(attacking: move.typeName, defenders: opponent.typeNames)
        guard effectiveness > 0 else { return Weights.disallowed }
        let accuracy = Double(move.accuracy ?? 100) / 100
        let estimated = Double(DamageCalculator.estimateDamage(
            move: move, attacker: fighter, defender: opponent, typeChart: typeChart
        ))
        var score = estimated * accuracy
        if estimated >= Double(opponent.currentHP) { score += Weights.koBonus }
        if estimated >= Double(opponent.currentHP) * 0.65 { score += Weights.nearKOBonus }
        if effectiveness < 1, effectiveness > 0 { score *= Weights.resistedMult }
        if move.hasSelfDebuff { score -= Weights.selfDebuffPenalty }
        if move.priority > 0 { score += Weights.priorityBonus }
        if move.isRechargeMove { score *= Weights.rechargeMult }
        return score
    }

    static func supportScore(
        move: MoveDetail,
        fighter: BattleCombatant,
        opponent: BattleCombatant
    ) -> Double {
        var score = 0.0
        if move.ailment != "none" {
            score += statusScore(ailment: move.ailment, chance: move.ailmentChance, fighter: fighter, opponent: opponent)
        }
        if move.healing > 0 || move.name == "rest" {
            score += opponent.maxHP > fighter.maxHP ? Weights.healingVsBulky : Weights.healingDefault
        }
        for (index, stat) in move.statChangeNames.enumerated() where index < move.statChangeDeltas.count {
            score += statChangeScore(stat: stat, delta: move.statChangeDeltas[index], fighter: fighter, opponent: opponent)
        }
        return score
    }

    static func statusScore(
        ailment: String,
        chance: Int,
        fighter: BattleCombatant,
        opponent: BattleCombatant
    ) -> Double {
        let factor = Double(max(chance, Weights.statusMinChance)) / 100
        switch ailment {
        case "paralysis":
            return (opponent.effectiveSpeed > fighter.effectiveSpeed ? Weights.paralysisFaster : Weights.paralysisSlower) * factor
        case "burn":
            return (opponent.attack >= opponent.specialAttack ? Weights.burnPhysical : Weights.burnSpecial) * factor
        case "poison":
            return (opponent.maxHP >= fighter.maxHP ? Weights.poisonBulky : Weights.poisonFrail) * factor
        case "sleep":
            return Weights.sleep * factor
        default:
            return Weights.statusOther * factor
        }
    }

    static func statChangeScore(
        stat: String,
        delta: Int,
        fighter: BattleCombatant,
        opponent: BattleCombatant
    ) -> Double {
        guard delta != 0 else { return 0 }
        let magnitude = Double(abs(delta))
        if delta > 0 {
            switch stat {
            case "speed":
                return fighter.effectiveSpeed > opponent.effectiveSpeed ? Weights.statBoostSpeedFast : Weights.statBoostSpeedSlow
            case "attack":
                return fighter.attack >= fighter.specialAttack ? magnitude * Weights.statBoostMatching : magnitude * Weights.statBoostMismatch
            case "special-attack":
                return fighter.specialAttack >= fighter.attack ? magnitude * Weights.statBoostMatching : magnitude * Weights.statBoostMismatch
            case "defense", "special-defense":
                return opponent.maxHP >= fighter.maxHP ? magnitude * Weights.statBoostDefVsTank : magnitude * Weights.statBoostDefVsFrail
            default:
                return magnitude * Weights.statBoostDefault
            }
        }
        switch stat {
        case "defense":
            return fighter.attack >= fighter.specialAttack ? magnitude * Weights.statDebuffMatching : magnitude * Weights.statDebuffMismatch
        case "special-defense":
            return fighter.specialAttack >= fighter.attack ? magnitude * Weights.statDebuffMatching : magnitude * Weights.statDebuffMismatch
        case "speed":
            return opponent.effectiveSpeed > fighter.effectiveSpeed ? magnitude * Weights.statDebuffMatching : magnitude * Weights.statDebuffMismatch
        default:
            return magnitude * Weights.statDebuffDefault
        }
    }
}

// MARK: - MovePrompt

/// Builds the per-turn move-pick prompt and parses the model's index
/// reply. The prompt opens with a one-line battle context, optionally
/// lists the defender's observed moves with damage-back-at-you tags,
/// then enumerates the attacker's options in a randomised order.
enum MovePrompt {

    struct Output {
        let prompt: String
        let indexMap: [Int: Int]
    }

    static func build(
        attacker: BattleCombatant,
        defender: BattleCombatant,
        moves: [MoveDetail],
        defenderSeenMoves: [MoveDetail],
        typeChart: TypeChart,
        turnNumber: Int
    ) -> Output {
        var indexMap: [Int: Int] = [:]
        let movesBlock = Array(moves.indices).shuffled().enumerated().map { displayIdx, originalIdx in
            indexMap[displayIdx] = originalIdx
            return MoveRow.describe(
                moves[originalIdx],
                index: displayIdx,
                attacker: attacker, defender: defender, typeChart: typeChart,
                style: .verbose
            )
        }.joined(separator: "\n")

        var sections = [BattleContext.compact(attacker: attacker, defender: defender, turnNumber: turnNumber)]
        let threat = threatSection(seenMoves: defenderSeenMoves, attacker: defender, defender: attacker, typeChart: typeChart)
        if !threat.isEmpty { sections.append(threat) }
        sections.append(movesBlock)
        sections.append("\(BattleContext.tacticalHint(attacker: attacker, defender: defender, moves: moves)) Return ONLY the index.")
        return Output(prompt: sections.joined(separator: "\n\n"), indexMap: indexMap)
    }

    static func parsePick(raw: String, indexMap: [Int: Int], moves: [MoveDetail]) -> MoveDetail? {
        guard let shuffledIdx = firstInt(in: raw),
              let originalIdx = indexMap[shuffledIdx],
              moves.indices.contains(originalIdx)
        else { return nil }
        return moves[originalIdx]
    }
}

// MARK: - Private
private extension MovePrompt {

    static func threatSection(
        seenMoves: [MoveDetail],
        attacker: BattleCombatant,
        defender: BattleCombatant,
        typeChart: TypeChart
    ) -> String {
        guard !seenMoves.isEmpty else { return "" }
        let rows = seenMoves.map { move -> String in
            if move.isDamage {
                let dmg = DamageCalculator.estimateDamage(move: move, attacker: attacker, defender: defender, typeChart: typeChart)
                let eff = typeChart.multiplier(attacking: move.typeName, defenders: defender.typeNames)
                let suffix: String
                if eff >= 2 { suffix = ", SE" }
                else if eff > 0, eff < 1 { suffix = ", resisted" }
                else if eff == 0 { suffix = ", immune" }
                else { suffix = "" }
                return "- \(move.name) (\(move.typeName)) \(dmg) dmg\(suffix)"
            }
            var tags: [String] = []
            if move.ailment != "none" { tags.append(move.ailment) }
            if move.statChangeDeltas.contains(where: { $0 > 0 }) { tags.append("boost") }
            if move.statChangeDeltas.contains(where: { $0 < 0 }) { tags.append("debuff") }
            return "- \(move.name) (\(move.typeName)) \(tags.joined(separator: ", "))"
        }
        return "Defender has used:\n" + rows.joined(separator: "\n")
    }
}

// MARK: - Response parsing

/// First integer found anywhere in `text`, ignoring punctuation. Shared
/// by `MovePrompt` and `OpponentPrompt`.
func firstInt(in text: String) -> Int? {
    guard let match = text.firstMatch(of: /\d+/) else { return nil }
    return Int(match.output)
}
