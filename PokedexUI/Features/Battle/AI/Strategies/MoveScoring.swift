import BattleKit
import Foundation

/// Move-evaluation primitive used by both move-pick and loadout-pick AI
/// strategies. Mixes BattleKit damage estimates with heuristic weights for
/// status effects, stat changes, and move quirks (self-debuff, recharge,
/// priority). Returns a unitless score where higher = better for the
/// fighter.
enum MoveScoring {

    static func score(
        move: MoveDetail,
        fighter: BattleCombatant,
        opponent: BattleCombatant,
        typeChart: TypeChart
    ) -> Double {
        if (move.power ?? 0) > 0, move.damageClassKind != .status {
            return damageScore(move: move, fighter: fighter, opponent: opponent, typeChart: typeChart)
        }
        return supportScore(move: move, fighter: fighter, opponent: opponent)
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
        guard effectiveness > 0 else { return -100 }
        let accuracy = Double(move.accuracy ?? 100) / 100
        let estimated = Double(DamageCalculator.estimateDamage(
            move: move, attacker: fighter, defender: opponent, typeChart: typeChart
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

    static func supportScore(
        move: MoveDetail,
        fighter: BattleCombatant,
        opponent: BattleCombatant
    ) -> Double {
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

    static func statusScore(
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

    static func statChangeScore(
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
