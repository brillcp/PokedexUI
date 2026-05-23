import PokeBattleKit

// MARK: - MovePrompt

/// Builds the per-turn move-pick prompt and parses the model's index
/// reply. The prompt opens with a one-line battle context, optionally
/// lists the defender's observed moves with damage-back-at-you tags,
/// then enumerates the attacker's options in a randomised order.
enum MovePrompt {

    struct Output {
        let prompt: String
        let indexMap: [Int: Int]
    }

    static func build(
        attacker: Combatant,
        defender: Combatant,
        moves: [Move],
        defenderSeenMoves: [Move],
        typeChart: TypeChart,
        turnNumber: Int
    ) -> Output {
        var indexMap: [Int: Int] = [:]
        let movesBlock = Array(moves.indices).shuffled().enumerated().map { displayIdx, originalIdx in
            indexMap[displayIdx] = originalIdx
            return describeMove(moves[originalIdx], index: displayIdx)
        }.joined(separator: "\n")

        var sections = [BattleContext.compact(attacker: attacker, defender: defender, turnNumber: turnNumber)]
        if !defenderSeenMoves.isEmpty {
            let names = defenderSeenMoves.map(\.name).joined(separator: ", ")
            sections.append("Defender used: \(names)")
        }
        sections.append(movesBlock)
        sections.append("\(BattleContext.tacticalHint(attacker: attacker, defender: defender, moves: moves)) Return ONLY the index.")
        return Output(prompt: sections.joined(separator: "\n\n"), indexMap: indexMap)
    }

    static func parsePick(raw: String, indexMap: [Int: Int], moves: [Move]) -> Move? {
        guard let shuffledIdx = firstInt(in: raw),
              let originalIdx = indexMap[shuffledIdx],
              moves.indices.contains(originalIdx)
        else { return nil }
        return moves[originalIdx]
    }
}


// MARK: - Helpers

/// Move description for structured prompts: `"thunderbolt (electric) 90/100"`.
func describeMove(_ move: Move) -> String {
    let pwr = move.power.map(String.init) ?? "-"
    let acc = move.accuracy.map(String.init) ?? "-"
    return "\(move.name) (\(move.typeName)) \(pwr)/\(acc)"
}

/// Indexed move description for index-based prompts: `"0: thunderbolt (electric) 90/100"`.
func describeMove(_ move: Move, index: Int) -> String {
    "\(index): \(describeMove(move))"
}

/// First integer found anywhere in `text`, ignoring punctuation.
func firstInt(in text: String) -> Int? {
    guard let match = text.firstMatch(of: /\d+/) else { return nil }
    return Int(match.output)
}
