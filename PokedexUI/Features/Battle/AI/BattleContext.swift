import PokeBattleKit
import Foundation

/// Battle-state prose used in prompts: a one-liner summary of the current
/// state and a tactical hint nudging the LLM toward the right move
/// category.
enum BattleContext {

    /// "Turn N. X 85% HP vs Y 50% HP. You: +2 atk. Opponent is paralyzed."
    static func compact(
        attacker: BattleCombatant,
        defender: BattleCombatant,
        turnNumber: Int
    ) -> String {
        let atkHP = Int(Double(attacker.currentHP) / Double(max(1, attacker.maxHP)) * 100)
        let defHP = Int(Double(defender.currentHP) / Double(max(1, defender.maxHP)) * 100)
        var parts = ["Turn \(turnNumber). \(attacker.name) \(atkHP)% HP vs \(defender.name) \(defHP)% HP."]
        let boosts = attacker.statStages.filter { $0.value != 0 }
            .map { "\($0.value > 0 ? "+" : "")\($0.value) \(shortStat($0.key))" }
        if !boosts.isEmpty { parts.append("You: \(boosts.joined(separator: ", ")).") }
        if attacker.status != .none { parts.append("You are \(attacker.status.label).") }
        if defender.status != .none { parts.append("Opponent is \(defender.status.label).") }
        return parts.joined(separator: " ")
    }

    /// One-line tactical directive based on HP, boosts, and available
    /// move shapes.
    static func tacticalHint(
        attacker: BattleCombatant,
        defender: BattleCombatant,
        moves: [MoveDetail]
    ) -> String {
        let hpFrac = Double(attacker.currentHP) / Double(max(1, attacker.maxHP))
        let defHpFrac = Double(defender.currentHP) / Double(max(1, defender.maxHP))

        if defHpFrac <= 0.30 { return "Opponent is low. Pick the move that KOs." }
        if hpFrac <= 0.30 { return "Low HP. Pick highest damage." }
        if !attacker.isBoosted, hpFrac >= 0.70,
           moves.contains(where: { ($0.power ?? 0) == 0 && $0.statChangeDeltas.contains { $0 > 0 } }) {
            return "Consider a boost move to set up."
        }
        if attacker.isBoosted { return "You are boosted. Pick highest damage." }
        return "Pick highest damage."
    }

    /// Three-letter stat abbreviation for compact prompt rows.
    static func shortStat(_ stat: String) -> String {
        switch stat {
        case "attack":          return "atk"
        case "defense":         return "def"
        case "special-attack":  return "spa"
        case "special-defense": return "spd"
        case "speed":           return "spe"
        default:                return stat
        }
    }
}

// MARK: - MoveRow

/// Renders one prompt row for a move. Used by both `MovePrompt`
/// (verbose: full damage prose, status-worthiness tags) and
/// `LoadoutPrompt` (compact: abbreviated tags, no worthiness).
enum MoveRow {
    enum Style { case compact, verbose }

    static func describe(
        _ move: MoveDetail,
        index: Int,
        attacker: BattleCombatant,
        defender: BattleCombatant,
        typeChart: TypeChart,
        style: Style
    ) -> String {
        let header = "\(index): \(move.name) (\(move.typeName))"
        let tags = (move.power ?? 0) > 0
            ? damageTags(move, attacker: attacker, defender: defender, typeChart: typeChart, style: style)
            : supportTags(move, attacker: attacker, defender: defender, style: style)
        return tags.isEmpty ? header : "\(header) - \(tags.joined(separator: ", "))"
    }
}

// MARK: - Private
private extension MoveRow {

    static func damageTags(
        _ move: MoveDetail,
        attacker: BattleCombatant,
        defender: BattleCombatant,
        typeChart: TypeChart,
        style: Style
    ) -> [String] {
        let eff = typeChart.multiplier(attacking: move.typeName, defenders: defender.typeNames)
        let dmg = DamageCalculator.estimateDamage(move: move, attacker: attacker, defender: defender, typeChart: typeChart)
        let koTurns = DamageCalculator.turnsToKO(dmg, hp: defender.currentHP)
        var tags = ["\(dmg) dmg"]

        switch (style, koTurns) {
        case (.verbose, 1): tags.append("KOs this turn")
        case (.verbose, 2): tags.append("2-hit KO")
        case (.verbose, 3): tags.append("3-hit KO")
        case (.compact, let n) where n <= 2: tags.append("\(n)-hit KO")
        default: break
        }

        let acc = move.accuracy ?? 100
        if acc < 100 { tags.append("\(acc)% acc") }
        if attacker.typeNames.contains(move.typeName) { tags.append("STAB") }
        if eff >= 2 { tags.append(style == .verbose ? "super effective" : "SE") }
        else if eff > 0, eff < 1 { tags.append("resisted") }
        else if eff == 0 { tags.append("IMMUNE") }
        if move.hasSelfDebuff { tags.append(style == .verbose ? "lowers your stats" : "self-debuff") }
        if move.isRechargeMove { tags.append(style == .verbose ? "must recharge next turn" : "recharge") }
        if move.priority > 0 { tags.append("priority") }
        return tags
    }

    static func supportTags(
        _ move: MoveDetail,
        attacker: BattleCombatant,
        defender: BattleCombatant,
        style: Style
    ) -> [String] {
        var tags: [String] = []
        if move.ailment != "none" {
            if style == .verbose {
                let chance = move.ailmentChance > 0 ? " (\(move.ailmentChance)%)" : ""
                var line = "inflicts \(move.ailment)\(chance)"
                if let worth = statusWorthiness(ailment: move.ailment, attacker: attacker, defender: defender) {
                    line += " [\(worth)]"
                }
                tags.append(line)
            } else {
                tags.append(move.ailment)
            }
        }
        for (i, stat) in move.statChangeNames.enumerated() where i < move.statChangeDeltas.count {
            let delta = move.statChangeDeltas[i]
            tags.append("\(delta > 0 ? "+" : "")\(delta) \(BattleContext.shortStat(stat))")
        }
        if move.healing > 0 {
            tags.append(style == .verbose ? "heals \(move.healing)%" : "heal \(move.healing)%")
        }
        if move.name == "rest" {
            tags.append(style == .verbose ? "full heal, sleeps 2 turns" : "full heal")
        }
        return tags
    }

    /// Qualitative tag mirroring `MoveScoring.statusScore` weighting so
    /// the LLM understands why a status move is or isn't recommended.
    static func statusWorthiness(
        ailment: String,
        attacker: BattleCombatant,
        defender: BattleCombatant
    ) -> String? {
        guard defender.status == .none else { return "wasted, target already statused" }
        switch ailment {
        case "paralysis":
            return defender.effectiveSpeed > attacker.effectiveSpeed
                ? "high value, target is faster"
                : "low value, target already slower"
        case "burn":
            return defender.attack >= defender.specialAttack
                ? "high value, target is physical"
                : "low value, target is special"
        case "poison":
            return defender.maxHP >= attacker.maxHP
                ? "high value, target is bulky"
                : "low value, target is frail"
        case "sleep":
            return "high value, sleep cripples any target"
        default:
            return nil
        }
    }
}
