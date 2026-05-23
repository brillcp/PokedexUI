import PokeBattleKit

// MARK: - LoadoutPrompt

/// Builds the pre-battle loadout prompt and parses the model's
/// index reply.
enum LoadoutPrompt {

    struct Output {
        let prompt: String
        let indexMap: [Int: Int]
    }

    static func build(
        fighter: Combatant,
        opponent: Combatant,
        moves: [Move],
        playerMoves: [Move],
        typeChart: TypeChart
    ) -> Output {
        var indexMap: [Int: Int] = [:]
        let movesBlock = Array(moves.indices).shuffled().enumerated().map { displayIdx, originalIdx in
            indexMap[displayIdx] = originalIdx
            return describeMove(moves[originalIdx], index: displayIdx)
        }.joined(separator: "\n")

        let prompt = """
        Pick 4 moves for \(fighter.name) (\(fighter.typeNames.joined(separator: "/"))) vs \(opponent.name) (\(opponent.typeNames.joined(separator: "/"))).

        \(movesBlock)

        Return ONLY 4 index numbers.
        """
        return Output(prompt: prompt, indexMap: indexMap)
    }

    /// Tries move-name substring match first, then falls back to integer
    /// indices via `indexMap`. Stops at 4 unique moves.
    static func parsePicks(raw: String, indexMap: [Int: Int], moves: [Move]) -> [Move] {
        let byName = Dictionary(moves.map { ($0.name, $0) }, uniquingKeysWith: { _, last in last })
        var picked: [Move] = []
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
