import PokeBattleKit
import Foundation

// MARK: - LoadoutStrategy

/// Deterministic AI for pre-battle loadout construction. Flow:
/// 1. `shortlist` curates a diverse 50-move pool for the LLM.
/// 2. `heuristicPick` returns the 4-move fallback when the LLM is
///    unavailable or returns junk.
/// 3. `fill` pads partial LLM picks up to 4.
/// 4. `adjust` enforces 2 DMG + 1 BOOST + 1 DISRUPT composition and
///    downgrades one damage move for fairness.
enum LoadoutStrategy {

    static func shortlist(
        fighter: BattleCombatant,
        opponent: BattleCombatant,
        moves: [MoveDetail],
        typeChart: TypeChart,
        limit: Int = 50
    ) -> [MoveDetail] {
        let ranked = rankedByScore(moves, fighter: fighter, opponent: opponent, typeChart: typeChart)
        let buckets: [[MoveDetail]] = [
            ranked.filter { $0.isDamage && typeChart.multiplier(attacking: $0.typeName, defenders: opponent.typeNames) >= 2 },
            ranked.filter(\.isDamage),
            ranked.filter(\.isBoost),
            ranked.filter(\.isDisrupt),
            ranked
        ]
        return collapse(buckets, limit: limit)
    }

    static func heuristicPick(
        fighter: BattleCombatant,
        opponent: BattleCombatant,
        moves: [MoveDetail],
        typeChart: TypeChart
    ) -> [MoveDetail] {
        let ranked = rankedByScore(moves, fighter: fighter, opponent: opponent, typeChart: typeChart)
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

    static func fill(
        seed: [MoveDetail],
        fighter: BattleCombatant,
        opponent: BattleCombatant,
        moves: [MoveDetail],
        typeChart: TypeChart,
        count: Int
    ) -> [MoveDetail] {
        guard seed.count < count else { return Array(seed.prefix(count)) }
        let ranked = rankedByScore(moves, fighter: fighter, opponent: opponent, typeChart: typeChart)
        return collapse([seed, ranked], limit: count)
    }

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

    static func rankedByScore(
        _ moves: [MoveDetail],
        fighter: BattleCombatant,
        opponent: BattleCombatant,
        typeChart: TypeChart
    ) -> [MoveDetail] {
        moves.sorted { lhs, rhs in
            MoveScoring.score(move: lhs, fighter: fighter, opponent: opponent, typeChart: typeChart)
            > MoveScoring.score(move: rhs, fighter: fighter, opponent: opponent, typeChart: typeChart)
        }
    }

    /// Walks each bucket in order, taking unseen moves until `limit`.
    /// Shared dedupe core for shortlist / heuristicPick / fill.
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

        let weakestFirst = damageMoves.sorted { lhs, rhs in
            DamageCalculator.estimateDamage(move: lhs.element, attacker: fighter, defender: opponent, typeChart: typeChart)
            < DamageCalculator.estimateDamage(move: rhs.element, attacker: fighter, defender: opponent, typeChart: typeChart)
        }

        var replaced = 0
        for (offset, _) in weakestFirst where replaced < damageMoves.count - 2 {
            let needCategory: String? = !hasBoost && replaced == 0 ? "BOOST" :
                !hasDisrupt ? "DISRUPT" :
                ["BOOST", "DISRUPT"].randomElement()
            guard let category = needCategory,
                  let swap = bestFromPool(category: category, pool: pool, exclude: used,
                                          fighter: fighter, opponent: opponent, typeChart: typeChart)
            else { continue }
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

// MARK: - LoadoutPrompt

/// Builds the pre-battle loadout prompt: candidates are grouped by
/// `loadoutCategory` so the model is steered toward composition rather
/// than four damage moves. Player's biggest threat is summarised at the
/// top so the model knows what it's planning around.
enum LoadoutPrompt {

    struct Output {
        let prompt: String
        let indexMap: [Int: Int]
    }

    static func build(
        fighter: BattleCombatant,
        opponent: BattleCombatant,
        moves: [MoveDetail],
        playerMoves: [MoveDetail],
        typeChart: TypeChart
    ) -> Output {
        var indexMap: [Int: Int] = [:]
        var dmgRows: [String] = []
        var boostRows: [String] = []
        var disruptRows: [String] = []

        for (displayIdx, originalIdx) in Array(moves.indices).shuffled().enumerated() {
            indexMap[displayIdx] = originalIdx
            let move = moves[originalIdx]
            let row = MoveRow.describe(
                move, index: displayIdx,
                attacker: fighter, defender: opponent, typeChart: typeChart,
                style: .compact
            )
            switch move.loadoutCategory {
            case "BOOST":   boostRows.append(row)
            case "DISRUPT": disruptRows.append(row)
            default:        dmgRows.append(row)
            }
        }

        let prompt = """
        Pick 4 moves for \(fighter.name) (\(fighter.typeNames.joined(separator: "/"))) vs \(opponent.name) (\(opponent.typeNames.joined(separator: "/"))). \(threatSummary(playerMoves: playerMoves, fighter: fighter, opponent: opponent, typeChart: typeChart))

        DMG (pick 2):
        \(dmgRows.joined(separator: "\n"))

        BOOST (pick 1):
        \(boostRows.joined(separator: "\n"))

        DISRUPT (pick 1):
        \(disruptRows.joined(separator: "\n"))

        Pick highest dmg for DMG. Never pick IMMUNE. Return ONLY 4 index numbers.
        """
        return Output(prompt: prompt, indexMap: indexMap)
    }

    /// Tries move-name substring match first, then falls back to integer
    /// indices via `indexMap`. Stops at 4 unique moves.
    static func parsePicks(raw: String, indexMap: [Int: Int], moves: [MoveDetail]) -> [MoveDetail] {
        let byName = Dictionary(uniqueKeysWithValues: moves.map { ($0.name, $0) })
        var picked: [MoveDetail] = []
        var used: Set<String> = []

        for name in byName.keys where raw.contains(name) && picked.count < 4 {
            let move = byName[name]!
            if used.insert(move.name).inserted { picked.append(move) }
        }
        if picked.count < 4 {
            for displayIdx in raw.matches(of: /\d+/).compactMap({ Int($0.output) }) where picked.count < 4 {
                guard let originalIdx = indexMap[displayIdx], moves.indices.contains(originalIdx) else { continue }
                let move = moves[originalIdx]
                if used.insert(move.name).inserted { picked.append(move) }
            }
        }
        return picked
    }
}

// MARK: - Private
private extension LoadoutPrompt {

    static func threatSummary(
        playerMoves: [MoveDetail],
        fighter: BattleCombatant,
        opponent: BattleCombatant,
        typeChart: TypeChart
    ) -> String {
        guard let best = DamageCalculator.strongestMove(
            attacker: opponent, defender: fighter, moves: playerMoves, typeChart: typeChart
        ) else { return "" }
        let ko = DamageCalculator.turnsToKO(best.damage, hp: fighter.maxHP)
        return "Player's strongest: \(best.move.displayName) (\(best.damage) dmg, \(ko)-hit KO vs you)."
    }
}

// MARK: - MoveDetail loadout classification

extension MoveDetail {
    var isDamage: Bool  { (power ?? 0) > 0 }
    var isBoost: Bool   { (power ?? 0) == 0 && statChangeDeltas.contains { $0 > 0 } }
    var isDisrupt: Bool { (power ?? 0) == 0 && (ailment != "none" || statChangeDeltas.contains { $0 < 0 }) }
}
