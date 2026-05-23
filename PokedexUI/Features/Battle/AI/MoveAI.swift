import PokeBattleKit

// MARK: - Helpers

/// Move description for structured prompts: `"thunderbolt (electric) 90/100"`.
func describeMove(_ move: Move) -> String {
    let pwr = move.power.map(String.init) ?? "-"
    let acc = move.accuracy.map(String.init) ?? "-"
    return "\(move.name) (\(move.typeName)) \(pwr)/\(acc)"
}

/// First integer found anywhere in `text`, ignoring punctuation.
func firstInt(in text: String) -> Int? {
    guard let match = text.firstMatch(of: /\d+/) else { return nil }
    return Int(match.output)
}
