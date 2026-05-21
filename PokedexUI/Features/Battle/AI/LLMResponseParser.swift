import Foundation

/// Free-form text parsing for LLM responses. Only concerned with shape;
/// move/opponent semantics live in the per-decision `*Prompt` types.
enum LLMResponseParser {

    /// First integer found anywhere in the response, ignoring punctuation.
    static func firstInt(in text: String) -> Int? {
        guard let match = text.firstMatch(of: /\d+/) else { return nil }
        return Int(match.output)
    }

    /// All integers found in `text`, in order, deduplicated by appearance.
    static func allInts(in text: String) -> [Int] {
        text.matches(of: /\d+/).compactMap { Int($0.output) }
    }

    /// Parse up to `count` move picks. Tries move-name substring match
    /// first, then falls back to integer indices via `indexMap`. Stops at
    /// `count` unique moves.
    static func loadoutIndices(
        _ text: String,
        indexMap: [Int: Int],
        moves: [MoveDetail],
        count: Int
    ) -> [MoveDetail] {
        let byName = Dictionary(uniqueKeysWithValues: moves.map { ($0.name, $0) })
        var picked: [MoveDetail] = []
        var usedNames: Set<String> = []

        func take(_ move: MoveDetail) {
            guard !usedNames.contains(move.name) else { return }
            picked.append(move)
            usedNames.insert(move.name)
        }

        for name in byName.keys where text.contains(name) {
            guard picked.count < count else { break }
            take(byName[name]!)
        }

        if picked.count < count {
            for displayIdx in allInts(in: text) {
                guard picked.count < count,
                      let originalIdx = indexMap[displayIdx],
                      moves.indices.contains(originalIdx) else { continue }
                take(moves[originalIdx])
            }
        }

        return picked
    }
}
