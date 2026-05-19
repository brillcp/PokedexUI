import Foundation

/// Parses raw LLM string responses into typed battle decisions, and provides
/// deterministic fallbacks for when the model is unavailable or returns garbage.
///
/// Kept separate from `BattleAIService` (session/network) and
/// `BattleAIPromptBuilder` (prompt formatting) so each type has one reason to
/// change (SRP).
enum BattleAIResponseParser {

    // MARK: - Response parsing

    /// Returns the first non-negative integer found in `text`, or nil.
    /// Used for single-value responses (move index, opponent id).
    static func firstInt(in text: String) -> Int? {
        guard let match = text.firstMatch(of: /\d+/) else { return nil }
        return Int(match.output)
    }

    /// Returns all integers found on the last non-empty line of `text`.
    /// Scanning only the final line prevents power/accuracy numbers that the
    /// model sometimes echoes in its reasoning from polluting the result.
    static func intsOnLastLine(of text: String) -> [Int] {
        let lastLine = text
            .components(separatedBy: .newlines)
            .last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
            ?? text
        return lastLine.matches(of: /\d+/).compactMap { Int($0.output) }
    }

    // MARK: - Deterministic fallback

    /// Top-N moves by combat impact: damaging first, then highest power,
    /// then highest accuracy. Used when the model is unavailable or returns
    /// fewer valid indices than needed.
    static func heuristicLoadout(from moves: [MoveDetail], count: Int) -> [MoveDetail] {
        Array(
            moves.sorted { lhs, rhs in
                let lDamaging = (lhs.power ?? 0) > 0
                let rDamaging = (rhs.power ?? 0) > 0
                if lDamaging != rDamaging { return lDamaging }
                if lhs.power != rhs.power { return (lhs.power ?? 0) > (rhs.power ?? 0) }
                return (lhs.accuracy ?? 100) > (rhs.accuracy ?? 100)
            }
            .prefix(count)
        )
    }

    // MARK: - Loadout assembly

    /// Resolves model-returned indices into a full loadout, padding with the
    /// heuristic fallback if the model returned fewer valid indices than needed.
    static func assembleLoadout(
        indices: [Int],
        from moves: [MoveDetail],
        size: Int
    ) -> [MoveDetail] {
        let fallback = heuristicLoadout(from: moves, count: size)
        let valid = Array(Set(indices.filter { moves.indices.contains($0) })).map { moves[$0] }
        guard valid.count < size else { return Array(valid.prefix(size)) }
        let usedNames = Set(valid.map(\.name))
        let padded = valid + fallback.filter { !usedNames.contains($0.name) }.prefix(size - valid.count)
        return Array(padded.prefix(size))
    }
}
