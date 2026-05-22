import BattleKit
import Foundation

/// Deterministic AI for pre-battle loadout construction. The flow is:
/// 1. `shortlist` curates a diverse 50-move pool for the LLM (SE damage
///    first, then generic damage, boost, disrupt, then filler).
/// 2. `heuristicPick` returns the deterministic 4-move fallback when the
///    LLM is unavailable.
/// 3. `fill` pads partial LLM picks to 4.
/// 4. `adjust` runs `enforceComposition` + `handicap` against the final
///    picks so every loadout has at least 1 BOOST + 1 DISRUPT slot and
///    one damage move downgraded for fairness.
enum LoadoutStrategy {

    /// Diversified ranked pool for the LLM: SE damage > damage > boost >
    /// disrupt > the rest, deduped, capped at `limit`.
    static func shortlist(
        fighter: BattleCombatant,
        opponent: BattleCombatant,
        moves: [MoveDetail],
        typeChart: TypeChart,
        limit: Int = 50
    ) -> [MoveDetail] {
        let ranked = moves.sorted { lhs, rhs in
            MoveScoring.score(move: lhs, fighter: fighter, opponent: opponent, typeChart: typeChart)
            > MoveScoring.score(move: rhs, fighter: fighter, opponent: opponent, typeChart: typeChart)
        }
        let buckets: [[MoveDetail]] = [
            ranked.filter { $0.isDamage && typeChart.multiplier(attacking: $0.typeName, defenders: opponent.typeNames) >= 2 },
            ranked.filter { $0.isDamage },
            ranked.filter { $0.isBoost },
            ranked.filter { $0.isDisrupt },
            ranked
        ]
        return collapse(buckets, limit: limit)
    }

    /// Deterministic 4-move loadout: SE damage + lesser damage + self-boost
    /// + disruption. Falls back to highest-scoring move when a slot has no
    /// candidates.
    static func heuristicPick(
        fighter: BattleCombatant,
        opponent: BattleCombatant,
        moves: [MoveDetail],
        typeChart: TypeChart
    ) -> [MoveDetail] {
        let ranked = moves.sorted { lhs, rhs in
            MoveScoring.score(move: lhs, fighter: fighter, opponent: opponent, typeChart: typeChart)
            > MoveScoring.score(move: rhs, fighter: fighter, opponent: opponent, typeChart: typeChart)
        }
        let se = ranked.filter { $0.isDamage && typeChart.multiplier(attacking: $0.typeName, defenders: opponent.typeNames) >= 2 }
        let buckets: [[MoveDetail]] = [
            Array(se.prefix(1)),
            ranked.filter(\.isDamage),
            ranked.filter(\.isBoost),
            ranked.filter(\.isDisrupt),
            ranked
        ]
        return collapse(buckets, limit: 4)
    }

    /// Pad LLM-seeded picks to `count` using deterministic scoring.
    static func fill(
        seed: [MoveDetail],
        fighter: BattleCombatant,
        opponent: BattleCombatant,
        moves: [MoveDetail],
        typeChart: TypeChart,
        count: Int
    ) -> [MoveDetail] {
        guard seed.count < count else { return Array(seed.prefix(count)) }
        let ranked = moves.sorted { lhs, rhs in
            MoveScoring.score(move: lhs, fighter: fighter, opponent: opponent, typeChart: typeChart)
            > MoveScoring.score(move: rhs, fighter: fighter, opponent: opponent, typeChart: typeChart)
        }
        return collapse([seed, ranked], limit: count)
    }

    /// Post-pick correction pipeline applied to every loadout regardless
    /// of source: enforce 2 DMG + 1 BOOST + 1 DISRUPT composition, then
    /// downgrade one damage move to keep matchups fair.
    static func adjust(
        picks: [MoveDetail],
        pool: [MoveDetail],
        fighter: BattleCombatant,
        opponent: BattleCombatant,
        typeChart: TypeChart
    ) -> [MoveDetail] {
        let composed = enforceComposition(picks, pool: pool, fighter: fighter, opponent: opponent, typeChart: typeChart)
        return handicap(composed, pool: pool, fighter: fighter, opponent: opponent, typeChart: typeChart)
    }
}

// MARK: - Private
private extension LoadoutStrategy {

    /// Walks each bucket in order and takes moves not yet seen, stopping
    /// at `limit`. The shared dedupe core for shortlist / heuristicPick /
    /// fill.
    static func collapse(_ buckets: [[MoveDetail]], limit: Int) -> [MoveDetail] {
        var seen: Set<String> = []
        var out: [MoveDetail] = []
        for bucket in buckets {
            for move in bucket where seen.insert(move.name).inserted {
                out.append(move)
                if out.count >= limit { return out }
            }
        }
        return out
    }

    static func enforceComposition(
        _ loadout: [MoveDetail],
        pool: [MoveDetail],
        fighter: BattleCombatant,
        opponent: BattleCombatant,
        typeChart: TypeChart
    ) -> [MoveDetail] {
        let damageMoves = loadout.enumerated().filter { $0.element.isDamage }
        guard damageMoves.count > 2 else { return loadout }

        var result = loadout
        var used = Set(result.map(\.name))
        let hasBoost = result.contains(where: \.isBoost)
        let hasDisrupt = result.contains(where: \.isDisrupt)

        let weakestFirst = damageMoves.sorted {
            DamageCalculator.estimateDamage(move: $0.element, attacker: fighter, defender: opponent, typeChart: typeChart)
            < DamageCalculator.estimateDamage(move: $1.element, attacker: fighter, defender: opponent, typeChart: typeChart)
        }

        var replaced = 0
        for (offset, _) in weakestFirst where replaced < damageMoves.count - 2 {
            let needCategory: String? = !hasBoost && replaced == 0 ? "BOOST" :
                !hasDisrupt ? "DISRUPT" :
                ["BOOST", "DISRUPT"].randomElement()
            guard let category = needCategory else { continue }
            guard let swap = bestFromPool(category: category, pool: pool, exclude: used,
                                          fighter: fighter, opponent: opponent, typeChart: typeChart) else { continue }
            result[offset] = swap
            used.insert(swap.name)
            replaced += 1
        }
        return result
    }

    static func bestFromPool(
        category: String,
        pool: [MoveDetail],
        exclude: Set<String>,
        fighter: BattleCombatant,
        opponent: BattleCombatant,
        typeChart: TypeChart
    ) -> MoveDetail? {
        pool.filter { !exclude.contains($0.name) && $0.loadoutCategory == category }
            .max {
                MoveScoring.score(move: $0, fighter: fighter, opponent: opponent, typeChart: typeChart)
                < MoveScoring.score(move: $1, fighter: fighter, opponent: opponent, typeChart: typeChart)
            }
    }

    /// Downgrade one damage move to a weaker pool alternative for balance.
    static func handicap(
        _ loadout: [MoveDetail],
        pool: [MoveDetail],
        fighter: BattleCombatant,
        opponent: BattleCombatant,
        typeChart: TypeChart
    ) -> [MoveDetail] {
        let damageMoves = loadout.enumerated().filter { $0.element.isDamage }
        guard damageMoves.count >= 2 else { return loadout }

        func dmg(_ move: MoveDetail) -> Int {
            DamageCalculator.estimateDamage(move: move, attacker: fighter, defender: opponent, typeChart: typeChart)
        }

        guard let weakest = damageMoves.min(by: { dmg($0.element) < dmg($1.element) }) else { return loadout }
        let bestDmg = max(1, damageMoves.map { dmg($0.element) }.max() ?? 1)
        let threshold = Int(Double(bestDmg) * 0.55)
        let used = Set(loadout.map(\.name))

        let candidates = pool
            .filter { $0.isDamage && !used.contains($0.name) }
            .filter { typeChart.multiplier(attacking: $0.typeName, defenders: opponent.typeNames) > 0 }
            .filter { dmg($0) > 0 && dmg($0) < threshold }
            .sorted { dmg($0) < dmg($1) }

        let bottomHalf = candidates.prefix(max(1, candidates.count / 2))
        guard let replacement = bottomHalf.randomElement() else { return loadout }

        var result = loadout
        result[weakest.offset] = replacement
        return result
    }
}

// MARK: - MoveDetail loadout classification

extension MoveDetail {
    var isDamage: Bool  { (power ?? 0) > 0 }
    var isBoost: Bool   { (power ?? 0) == 0 && statChangeDeltas.contains { $0 > 0 } }
    var isDisrupt: Bool { (power ?? 0) == 0 && (ailment != "none" || statChangeDeltas.contains { $0 < 0 }) }
}
