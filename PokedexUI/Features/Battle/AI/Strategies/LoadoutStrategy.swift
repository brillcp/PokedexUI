import BattleKit
import Foundation

/// Deterministic AI logic for picking a 4-move loadout: pool diversification,
/// slot-based assembly, post-LLM composition enforcement, and a handicap
/// downgrade step to keep matchups fair.
enum LoadoutStrategy {

    /// Diverse 24-move shortlist for the LLM: prioritises SE damage then
    /// generic damage then setup/disruption, padded by raw score.
    static func shortlist(
        fighter: BattleCombatant,
        opponent: BattleCombatant,
        moves: [MoveDetail],
        typeChart: TypeChart,
        limit: Int = 24
    ) -> [MoveDetail] {
        let candidates = moves.map { move -> (move: MoveDetail, eff: Double, score: Double) in
            let eff = typeChart.multiplier(attacking: move.typeName, defenders: opponent.typeNames)
            return (move, eff, MoveScoring.score(move: move, fighter: fighter, opponent: opponent, typeChart: typeChart))
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

    /// Deterministic 4-move loadout: 1 SE damage + 1 lesser damage + 1
    /// self-boost + 1 disruption. Falls back to best available when a slot
    /// category has no candidates.
    static func assemble(
        fighter: BattleCombatant,
        opponent: BattleCombatant,
        moves: [MoveDetail],
        typeChart: TypeChart
    ) -> [MoveDetail] {
        var picked: [MoveDetail] = []
        var usedNames: Set<String> = []

        let candidates = moves.map { move -> (move: MoveDetail, eff: Double) in
            (move, typeChart.multiplier(attacking: move.typeName, defenders: opponent.typeNames))
        }

        func score(_ m: MoveDetail) -> Double {
            MoveScoring.score(move: m, fighter: fighter, opponent: opponent, typeChart: typeChart)
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

        take(best { move, eff in (move.power ?? 0) > 0 && eff >= 2 })
        take(best { move, _ in (move.power ?? 0) > 0 })
        take(best { move, _ in (move.power ?? 0) == 0 && move.statChangeDeltas.contains(where: { $0 > 0 }) })
        take(best { move, _ in (move.power ?? 0) == 0 && (move.ailment != "none" || move.statChangeDeltas.contains(where: { $0 < 0 })) })

        while picked.count < 4 {
            guard let filler = best(where: { _, _ in true }) else { break }
            take(filler)
        }

        return picked
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
        var picked = seed
        var usedNames = Set(seed.map(\.name))
        while picked.count < count {
            guard let best = moves
                .filter({ !usedNames.contains($0.name) })
                .max(by: { MoveScoring.score(move: $0, fighter: fighter, opponent: opponent, typeChart: typeChart)
                    < MoveScoring.score(move: $1, fighter: fighter, opponent: opponent, typeChart: typeChart) })
            else { break }
            picked.append(best)
            usedNames.insert(best.name)
        }
        return picked
    }

    /// Enforce 2 DMG + 1 BOOST + 1 DISRUPT composition by swapping excess
    /// damage moves for boost or disrupt picks from the pool.
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
                    MoveScoring.score(move: $0, fighter: fighter, opponent: opponent, typeChart: typeChart)
                    < MoveScoring.score(move: $1, fighter: fighter, opponent: opponent, typeChart: typeChart)
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
        }
        return result
    }

    /// Downgrade one damage move to a weak alternative for balance.
    static func handicap(
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
        return result
    }
}
