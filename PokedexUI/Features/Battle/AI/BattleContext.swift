import PokeBattleKit

/// Battle-state prose used in prompts: a one-liner summary of the current
/// state and a tactical hint nudging the LLM toward the right move
/// category.
enum BattleContext {

    /// "Turn N. X 85% HP vs Y 50% HP. You: +2 atk. Opponent is paralyzed."
    static func compact(
        attacker: Combatant,
        defender: Combatant,
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
        attacker: Combatant,
        defender: Combatant,
        moves: [Move]
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
