import Foundation

/// Bulbapedia-faithful damage formula and deterministic estimator for AI.
public enum DamageCalculator {

    /// Full damage computation with all modifiers. Used internally by
    /// `BattleEngine` when resolving a hit.
    ///
    /// Formula per Bulbapedia:
    /// `((2*Level/5+2) * Power * A/D) / 50 + 2`
    /// `* Critical * random(0.85-1.0) * STAB * Type * Burn`
    ///
    /// Super-effective is capped at `superEffectiveCap` (default 1.5) to
    /// prevent runaway one-shots.
    static func computeDamage(
        power: Int,
        move: some BattleMoveData,
        attacker: BattleCombatant,
        defender: BattleCombatant,
        typeChart: some TypeEffectivenessProviding,
        superEffectiveCap: Double = 1.5
    ) -> (damage: Int, effectiveness: Double, crit: Bool) {
        let level = 50.0
        let isSpecial = move.damageClassKind == .special

        let atkStatName = isSpecial ? "special-attack" : "attack"
        let defStatName = isSpecial ? "special-defense" : "defense"
        let atkBase = isSpecial ? attacker.specialAttack : attacker.attack
        let defBase = isSpecial ? defender.specialDefense : defender.defense
        let atk = Double(atkBase) * statStageMultiplier(attacker.stage(for: atkStatName))
        let def = Double(defBase) * statStageMultiplier(defender.stage(for: defStatName))

        let stab = attacker.typeNames.contains(move.typeName) ? 1.5 : 1.0
        let rawType = typeChart.multiplier(attacking: move.typeName, defenders: defender.typeNames)
        let typeMult: Double
        if rawType == 0 {
            typeMult = 0
        } else if rawType > 1 {
            typeMult = min(rawType, superEffectiveCap)
        } else {
            typeMult = rawType
        }
        let crit = Double.random(in: 0..<1) < (1.0 / 32.0)
        let critMult = crit ? 1.5 : 1.0
        let randVar = Double.random(in: 0.85...1.0)
        let burnPenalty = (attacker.status == .burn && !isSpecial) ? 0.5 : 1.0

        let base = ((2.0 * level / 5.0 + 2.0) * Double(power) * atk / def) / 50.0 + 2.0
        let total = base * stab * typeMult * critMult * randVar * burnPenalty
        let damage = typeMult == 0 ? 0 : max(1, Int(total))
        return (damage, rawType, crit)
    }

    /// Deterministic damage estimate (no randomness, no crit) for AI scoring.
    ///
    /// `typeChart` is the sole input for type effectiveness; callers cannot
    /// pass arbitrary multipliers. Status-class moves and zero-power moves
    /// return 0.
    public static func estimateDamage(
        move: some BattleMoveData,
        attacker: BattleCombatant,
        defender: BattleCombatant,
        typeChart: some TypeEffectivenessProviding,
        superEffectiveCap: Double = 1.5
    ) -> Int {
        guard let power = move.power, power > 0 else { return 0 }
        guard move.damageClassKind != .status else { return 0 }
        let effectiveness = typeChart.multiplier(attacking: move.typeName, defenders: defender.typeNames)
        guard effectiveness > 0 else { return 0 }

        let isSpecial = move.damageClassKind == .special
        let atkStatName = isSpecial ? "special-attack" : "attack"
        let defStatName = isSpecial ? "special-defense" : "defense"
        let atkBase = isSpecial ? attacker.specialAttack : attacker.attack
        let defBase = isSpecial ? defender.specialDefense : defender.defense
        let atk = Double(atkBase) * statStageMultiplier(attacker.stage(for: atkStatName))
        let def = Double(defBase) * statStageMultiplier(defender.stage(for: defStatName))

        let stab = attacker.typeNames.contains(move.typeName) ? 1.5 : 1.0
        let typeMult = effectiveness > 1 ? min(effectiveness, superEffectiveCap) : effectiveness

        let base = ((2.0 * 50.0 / 5.0 + 2.0) * Double(power) * atk / def) / 50.0 + 2.0
        return Int(base * stab * typeMult)
    }

    /// How many hits at `damage` per hit to KO a target with `hp`.
    public static func turnsToKO(_ damage: Int, hp: Int) -> Int {
        guard damage > 0 else { return 99 }
        return Int(ceil(Double(hp) / Double(damage)))
    }

    /// Move that lands a KO this turn, accounting for accuracy.
    ///
    /// Filters to moves whose estimated damage covers the defender's current
    /// HP and whose accuracy is at least 85%. Tiebreaks on accuracy-weighted
    /// expected damage. Returns `nil` when no move qualifies.
    public static func guaranteedKO<Move: BattleMoveData>(
        attacker: BattleCombatant,
        defender: BattleCombatant,
        moves: [Move],
        typeChart: some TypeEffectivenessProviding,
        accuracyFloor: Double = 0.85
    ) -> Move? {
        let target = defender.currentHP
        let killers = moves.compactMap { move -> (Move, Double)? in
            let dmg = estimateDamage(move: move, attacker: attacker, defender: defender, typeChart: typeChart)
            guard dmg >= target else { return nil }
            let accuracy = Double(move.accuracy ?? 100) / 100
            guard accuracy >= accuracyFloor else { return nil }
            return (move, Double(dmg) * accuracy)
        }
        return killers.max { $0.1 < $1.1 }?.0
    }

    /// Move that deals the most damage against `defender`. Returns `nil` if
    /// no damaging move is viable (zero power, status, or fully resisted).
    public static func strongestMove<Move: BattleMoveData>(
        attacker: BattleCombatant,
        defender: BattleCombatant,
        moves: [Move],
        typeChart: some TypeEffectivenessProviding
    ) -> (move: Move, damage: Int)? {
        let scored = moves.compactMap { move -> (Move, Int)? in
            let dmg = estimateDamage(move: move, attacker: attacker, defender: defender, typeChart: typeChart)
            return dmg > 0 ? (move, dmg) : nil
        }
        return scored.max { $0.1 < $1.1 }
    }
}
