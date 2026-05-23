import PokeBattleKit
import FoundationModels

// MARK: - Generable Results

@Generable(description: "The chosen move for this turn")
struct MovePickResult {
    @Guide(description: "Exact move name from the available list, e.g. 'thunderbolt'")
    var moveName: String
}

@Generable(description: "Four moves for the battle loadout")
struct LoadoutPickResult {
    @Guide(description: "Exactly 4 move names from the available list")
    var moveNames: [String]
}

@Generable(description: "The chosen opponent for this battle")
struct OpponentPickResult {
    @Guide(description: "The number of the chosen opponent from the list")
    var index: Int
}

// MARK: - Tools

/// Lets the model query type effectiveness before deciding.
struct CheckTypeTool: Tool {
    let typeChart: TypeChart

    var description: String {
        "Check type effectiveness. Returns multiplier: 0=immune, 0.5=not very effective, 1=neutral, 2=super effective."
    }

    @Generable
    struct Arguments {
        @Guide(description: "Attacking type, e.g. 'fire'")
        var attackingType: String
        @Guide(description: "Defending types, e.g. ['water', 'ground']")
        var defendingTypes: [String]
    }

    @Generable
    struct Output {
        var multiplier: Double
    }

    func call(arguments: Arguments) async throws -> Output {
        let mult = typeChart.multiplier(attacking: arguments.attackingType, defenders: arguments.defendingTypes)
        aiLog("  TOOL checkType: \(arguments.attackingType) vs \(arguments.defendingTypes) = \(mult)x")
        return Output(multiplier: mult)
    }
}

/// Lets the model estimate damage a specific move would deal.
struct EstimateDamageTool: Tool {
    let attacker: Combatant
    let defender: Combatant
    let typeChart: TypeChart
    let movesByName: [String: Move]

    var description: String {
        "Estimate damage a move deals. Returns HP damage and whether it KOs."
    }

    @Generable
    struct Arguments {
        @Guide(description: "Name of the move to estimate")
        var moveName: String
    }

    @Generable
    struct Output {
        var estimatedDamage: Int
        var defenderCurrentHP: Int
        var wouldKO: Bool
    }

    func call(arguments: Arguments) async throws -> Output {
        guard let move = movesByName[arguments.moveName] else {
            aiLog("  TOOL estimateDmg: '\(arguments.moveName)' not found")
            return Output(estimatedDamage: 0, defenderCurrentHP: defender.currentHP, wouldKO: false)
        }
        let dmg = DamageCalculator.estimateDamage(move: move, attacker: attacker, defender: defender, typeChart: typeChart)
        aiLog("  TOOL estimateDmg: \(arguments.moveName) = \(dmg) dmg (defender \(defender.currentHP) HP, KO: \(dmg >= defender.currentHP))")
        return Output(estimatedDamage: dmg, defenderCurrentHP: defender.currentHP, wouldKO: dmg >= defender.currentHP)
    }
}
