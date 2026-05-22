import BattleKit
import Foundation

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

    /// Tunable weights for heuristic scoring. All numbers live here so the
    /// scoring function reads as descriptions, not magic constants.
    enum Weights {
        static let disallowed: Double      = -100
        static let koBonus: Double         = 55     // estimated dmg >= target HP
        static let nearKOBonus: Double     = 18     // estimated dmg >= 65% target HP
        static let resistedMult: Double    = 0.4    // multiply on resisted (eff < 1)
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

        static let statBoostMatching: Double  = 10   // attack/spa boost matching offense
        static let statBoostMismatch: Double  = 2
        static let statBoostSpeedSlow: Double = 16
        static let statBoostSpeedFast: Double = 2
        static let statBoostDefVsTank: Double = 7
        static let statBoostDefVsFrail: Double = 4
        static let statBoostDefault: Double   = 4

        static let statDebuffMatching: Double  = 8
        static let statDebuffMismatch: Double  = 3
        static let statDebuffDefault: Double   = 4
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
