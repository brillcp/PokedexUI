import BattleKit
import Foundation

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

    static func parsePicks(raw: String, indexMap: [Int: Int], moves: [MoveDetail]) -> [MoveDetail] {
        LLMResponseParser.loadoutIndices(raw, indexMap: indexMap, moves: moves, count: 4)
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
