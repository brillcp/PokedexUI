import Foundation

/// Provides type-effectiveness multipliers for damage calculation.
public protocol TypeEffectivenessProviding: Sendable {
    /// Combined multiplier for `attacking` type against all `defenders` types.
    func multiplier(attacking: String, defenders: [String]) -> Double
}

public extension TypeEffectivenessProviding {
    /// Highest multiplier any of `attackerTypes` achieves against `defenderTypes`.
    /// Used to gauge offensive pressure on a type matchup. Returns 1.0 when
    /// either list is empty.
    func bestSTABMultiplier(attackerTypes: [String], defenderTypes: [String]) -> Double {
        attackerTypes
            .map { multiplier(attacking: $0, defenders: defenderTypes) }
            .max() ?? 1.0
    }
}
